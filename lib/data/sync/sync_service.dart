import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../../core/net/net_client.dart';
import '../db/database.dart';
import '../transfer/backup.dart';
import 'sync_merge.dart';

/// One-time sync codes: 8 characters without look-alikes (no 0/O, 1/I/L).
class SyncCode {
  static const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  static String generate([Random? random]) {
    final rnd = random ?? Random.secure();
    final chars = List.generate(8, (_) => _alphabet[rnd.nextInt(_alphabet.length)]);
    return '${chars.take(4).join()}-${chars.skip(4).join()}';
  }

  /// "k7q2 9xmf" -> "K7Q2-9XMF"; null if it isn't a valid code.
  static String? normalise(String raw) {
    final s = raw.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    if (s.length != 8 || s.split('').any((c) => !_alphabet.contains(c))) {
      return null;
    }
    return '${s.substring(0, 4)}-${s.substring(4)}';
  }
}

/// Reads "192.168.1.23:41234" (as shown on the other phone).
Uri? parseSyncAddress(String raw) {
  final m = RegExp(r'^\s*(\d{1,3}(?:\.\d{1,3}){3})\s*:\s*(\d{2,5})\s*$')
      .firstMatch(raw);
  if (m == null) return null;
  final port = int.parse(m.group(2)!);
  if (port < 1024 || port > 65535) return null;
  final uri = Uri(scheme: 'http', host: m.group(1), port: port, path: '/sync');
  return NetClient.isLocalSyncAddress(uri) ? uri : null;
}

class SyncException implements Exception {
  const SyncException(this.message);
  final String message;
  @override
  String toString() => message;
}

// Key settings both phones use; anything else is refused so a stranger on
// the network can't make the phone do a huge amount of work.
const int _kdfMemoryKiB = defaultKdfMemoryKiB;
const int _kdfIterations = defaultKdfIterations;

Future<Uint8List> _seal(Map<String, Object?> snapshot, String code) =>
    encryptBackup(snapshot, code,
        kdfMemoryKiB: _kdfMemoryKiB, kdfIterations: _kdfIterations);

Future<Map<String, Object?>> _open(Uint8List bytes, String code) async {
  final data = await decryptBackup(bytes, code,
      maxMemoryKiB: _kdfMemoryKiB, maxIterations: _kdfIterations);
  if (data['kind'] != 'sync') throw const BackupFormatException('not a sync');
  return data;
}

/// The phone that shows the code. Waits (up to [lifetime]) for the other
/// phone, syncs once, then stops listening.
class SyncHost {
  SyncHost._(this._server, this.address, this.code, this._db);

  final HttpServer _server;
  final String address;
  final String code;
  final AppDatabase _db;
  final Completer<SyncResult> _done = Completer();
  Timer? _timer;
  int _badTries = 0;
  bool _busy = false;

  static const Duration lifetime = Duration(minutes: 5);
  static const int maxBadTries = 5;

  /// Result of the sync; completes with an error if it times out or is
  /// stopped.
  Future<SyncResult> get done => _done.future;

  /// Starts listening on this phone's home-network address.
  static Future<SyncHost> start(AppDatabase db,
      {required bool offline, String? code}) async {
    if (offline) throw const SyncException('Offline mode is on.');
    final ip = await localAddress();
    if (ip == null) {
      throw const SyncException(
          'Connect this phone to your home Wi-Fi first.');
    }
    final server = await HttpServer.bind(ip, 0);
    server.idleTimeout = const Duration(seconds: 30);
    final host = SyncHost._(server, '${ip.address}:${server.port}',
        code ?? SyncCode.generate(), db);
    host._timer = Timer(lifetime, () => host.stop('Timed out.'));
    server.listen(host._handle, onError: (_) {});
    return host;
  }

  /// This phone's address on the home network, or null.
  static Future<InternetAddress?> localAddress() async {
    final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLoopback: false);
    InternetAddress? fallback;
    for (final i in interfaces) {
      for (final a in i.addresses) {
        final uri = Uri(scheme: 'http', host: a.address, path: '/sync');
        if (!NetClient.isLocalSyncAddress(uri)) continue;
        final name = i.name.toLowerCase();
        if (name.startsWith('wlan') || name.startsWith('en') ||
            name.startsWith('wifi')) {
          return a;
        }
        fallback ??= a;
      }
    }
    return fallback;
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    var claimed = false;
    try {
      if (req.method != 'POST' || req.uri.path != '/sync') {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      if (_busy || _done.isCompleted) {
        res.statusCode = HttpStatus.conflict;
        return;
      }
      _busy = true;
      claimed = true;
      final body = BytesBuilder(copy: false);
      await for (final chunk in req.timeout(const Duration(seconds: 60))) {
        body.add(chunk);
        if (body.length > NetClient.maxLocalBytes) {
          res.statusCode = HttpStatus.requestEntityTooLarge;
          return;
        }
      }
      final Map<String, Object?> remote;
      try {
        remote = await _open(body.takeBytes(), code);
      } on Object {
        // Wrong code, or not from WatchedLedger.
        res.statusCode = HttpStatus.forbidden;
        if (++_badTries >= maxBadTries) {
          scheduleMicrotask(() => stop('Too many wrong codes.'));
        }
        return;
      }
      final result = await mergeSync(_db, remote);
      final reply = await _seal(await buildSyncSnapshot(_db), code);
      res
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.binary
        ..contentLength = reply.length
        ..add(reply);
      if (!_done.isCompleted) _done.complete(result);
      scheduleMicrotask(() => stop());
    } catch (_) {
      try {
        res.statusCode = HttpStatus.internalServerError;
      } on StateError {
        // Reply already started.
      }
    } finally {
      if (claimed) _busy = false;
      try {
        await res.close();
      } catch (_) {}
    }
  }

  Future<void> stop([String? why]) async {
    _timer?.cancel();
    if (!_done.isCompleted) {
      _done.completeError(SyncException(why ?? 'Stopped.'));
    }
    await _server.close(force: true);
  }
}

/// The phone that types the code: sends its library, gets the merged one
/// back and merges that too, so both phones end up the same.
Future<SyncResult> syncWith({
  required AppDatabase db,
  required NetClient net,
  required Uri address,
  required String code,
}) async {
  final request = await _seal(await buildSyncSnapshot(db), code);
  final Uint8List reply;
  try {
    reply = await net.postLocal(address, request);
  } on OfflineException {
    rethrow;
  } on TimeoutException {
    throw const SyncException(
        "The other phone didn't answer. Check both are on the same Wi-Fi.");
  } on SocketException {
    throw const SyncException(
        "Couldn't reach the other phone. Check the address and that both "
        'are on the same Wi-Fi.');
  } on Exception catch (e) {
    if ('$e'.contains('HTTP 403')) {
      throw const SyncException('Wrong code. Check it and try again.');
    }
    throw const SyncException("Couldn't sync. Try again.");
  }
  final Map<String, Object?> remote;
  try {
    remote = await _open(reply, code);
  } on Object {
    throw const SyncException('The reply could not be read.');
  }
  return mergeSync(db, remote);
}
