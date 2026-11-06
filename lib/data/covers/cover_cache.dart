import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/net/net_client.dart';

/// Downloads cover images once (through [NetClient]) and keeps them in the
/// app's private storage so they show offline.
class CoverCache {
  CoverCache(this._net, this._dir);

  final NetClient _net;
  final Directory _dir;

  /// URLs already attempted this session, so a broken cover isn't retried
  /// on every scroll.
  final Map<String, Future<String?>> _inFlight = {};

  static Future<CoverCache> open(NetClient net) async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'covers'));
    await dir.create(recursive: true);
    return CoverCache(net, dir);
  }

  File fileFor(String name) => File(p.join(_dir.path, p.basename(name)));

  /// File name a URL is stored under (stable 64-bit hash, no extension
  /// guessing needed).
  static String nameFor(String url) {
    var a = 0x811C9DC5;
    var b = 0x01000193 ^ 0x5bd1e995;
    final units = url.codeUnits;
    for (var i = 0; i < units.length; i++) {
      a = ((a ^ units[i]) * 16777619) & 0xFFFFFFFF;
      b = ((b ^ units[units.length - 1 - i]) * 16777619) & 0xFFFFFFFF;
    }
    return '${a.toRadixString(16).padLeft(8, '0')}'
        '${b.toRadixString(16).padLeft(8, '0')}.img';
  }

  /// True if [bytes] start like a JPEG, PNG, GIF or WebP file.
  static bool looksLikeImage(Uint8List bytes) {
    if (bytes.length < 12) return false;
    final jpeg = bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
    final png = bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    final gif = bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46;
    final webp = bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;
    return jpeg || png || gif || webp;
  }

  /// Downloads [url] if needed. Returns the cached file name, or null if the
  /// cover can't be fetched (offline, blocked, not an image, network error).
  Future<String?> ensure(String url) {
    return _inFlight.putIfAbsent(url, () => _download(url));
  }

  Future<String?> _download(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !NetClient.isAllowed(uri)) return null;
    final name = nameFor(url);
    final file = fileFor(name);
    if (await file.exists()) return name;
    try {
      final bytes = await _net.getBytes(
        uri,
        maxBytes: NetClient.maxImageBytes,
        accept: 'image/*',
      );
      if (!looksLikeImage(bytes)) return null;
      final tmp = File('${file.path}.part');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(file.path);
      return name;
    } on OfflineException {
      // Try again later, once Offline mode is switched off.
      _inFlight.remove(url)?.ignore();
      return null;
    } catch (_) {
      return null;
    }
  }
}
