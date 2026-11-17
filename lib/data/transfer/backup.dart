import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' show Value;

import '../../core/sanitise.dart';
import '../db/database.dart';

/// Encrypted backup files (.wlbackup).
///
/// Layout: "WLBACKUP1\n" + header JSON + "\n" + AES-256-GCM ciphertext + tag.
/// The key comes from your password with Argon2id (salt and settings are in
/// the header, which is also authenticated). The content is gzipped JSON of
/// every item, diary entry, episode tick and setting.
class BackupPasswordException implements Exception {
  const BackupPasswordException();
  @override
  String toString() => 'Wrong password, or the file was changed.';
}

class BackupFormatException implements Exception {
  const BackupFormatException(this.reason);
  final String reason;
  @override
  String toString() => 'Not a valid WatchedLedger backup: $reason';
}

const String _magic = 'WLBACKUP1\n';
const int _maxPlainBytes = 200 * 1024 * 1024;
const int defaultKdfMemoryKiB = 19456; // 19 MiB (OWASP recommendation)
const int defaultKdfIterations = 2;

Uint8List _randomBytes(int n) {
  final r = Random.secure();
  return Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
}

Future<SecretKey> _deriveKey(
    String password, List<int> salt, int memory, int iterations) {
  return Argon2id(
    parallelism: 1,
    memory: memory,
    iterations: iterations,
    hashLength: 32,
  ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
}

/// Encrypts [snapshot] (see [buildSnapshot]). Runs off the UI thread.
Future<Uint8List> encryptBackup(
  Map<String, Object?> snapshot,
  String password, {
  int kdfMemoryKiB = defaultKdfMemoryKiB,
  int kdfIterations = defaultKdfIterations,
}) {
  final json = jsonEncode(snapshot);
  return Isolate.run(() async {
    final salt = _randomBytes(16);
    final nonce = _randomBytes(12);
    final header = utf8.encode(jsonEncode({
      'kdf': 'argon2id',
      'm': kdfMemoryKiB,
      't': kdfIterations,
      'p': 1,
      'salt': base64.encode(salt),
      'cipher': 'aes-256-gcm',
      'nonce': base64.encode(nonce),
      'zip': 'gzip',
    }));
    final key = await _deriveKey(password, salt, kdfMemoryKiB, kdfIterations);
    final box = await AesGcm.with256bits().encrypt(
      gzip.encode(utf8.encode(json)),
      secretKey: key,
      nonce: nonce,
      aad: header,
    );
    return Uint8List.fromList([
      ...utf8.encode(_magic),
      ...header,
      0x0A,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  });
}

/// Decrypts a backup file. Throws [BackupPasswordException] for a wrong
/// password (or a modified file) and [BackupFormatException] otherwise.
Future<Map<String, Object?>> decryptBackup(
  Uint8List bytes,
  String password, {
  int maxMemoryKiB = 262144,
  int maxIterations = 10,
}) {
  return Isolate.run(() async {
    final magic = utf8.encode(_magic);
    if (bytes.length < magic.length + 32 ||
        !_startsWith(bytes, magic)) {
      throw const BackupFormatException('missing header');
    }
    final headerEnd = bytes.indexOf(0x0A, magic.length);
    if (headerEnd < 0 || headerEnd - magic.length > 4096) {
      throw const BackupFormatException('bad header');
    }
    final headerBytes = bytes.sublist(magic.length, headerEnd);
    final Object? header;
    try {
      header = jsonDecode(utf8.decode(headerBytes));
    } catch (_) {
      throw const BackupFormatException('bad header');
    }
    if (header is! Map<String, Object?> ||
        header['kdf'] != 'argon2id' ||
        header['cipher'] != 'aes-256-gcm') {
      throw const BackupFormatException('unknown format');
    }
    final m = header['m'], t = header['t'];
    // Refuse absurd settings so a crafted file can't freeze the phone.
    if (m is! int ||
        t is! int ||
        m < 1024 ||
        m > maxMemoryKiB ||
        t < 1 ||
        t > maxIterations) {
      throw const BackupFormatException('bad key settings');
    }
    final List<int> salt, nonce;
    try {
      salt = base64.decode(header['salt']! as String);
      nonce = base64.decode(header['nonce']! as String);
    } catch (_) {
      throw const BackupFormatException('bad header');
    }
    final body = bytes.sublist(headerEnd + 1);
    if (body.length < 16 || nonce.length != 12) {
      throw const BackupFormatException('file is too short');
    }
    final key = await _deriveKey(password, salt, m, t);
    final List<int> zipped;
    try {
      zipped = await AesGcm.with256bits().decrypt(
        SecretBox(
          body.sublist(0, body.length - 16),
          nonce: nonce,
          mac: Mac(body.sublist(body.length - 16)),
        ),
        secretKey: key,
        aad: headerBytes,
      );
    } on SecretBoxAuthenticationError {
      throw const BackupPasswordException();
    }
    final plain = _gunzipCapped(zipped);
    final Object? decoded = jsonDecode(utf8.decode(plain));
    if (decoded is! Map<String, Object?> || decoded['app'] != 'WatchedLedger') {
      throw const BackupFormatException('not a WatchedLedger backup');
    }
    return decoded;
  });
}

bool _startsWith(List<int> bytes, List<int> prefix) {
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}

List<int> _gunzipCapped(List<int> zipped) {
  final out = BytesBuilder(copy: false);
  gzip.decoder.startChunkedConversion(_CappedSink(out, _maxPlainBytes))
    ..add(zipped)
    ..close();
  return out.takeBytes();
}

/// Collects unzipped bytes and stops a "zip bomb" from filling memory.
class _CappedSink implements Sink<List<int>> {
  _CappedSink(this._out, this._cap);
  final BytesBuilder _out;
  final int _cap;

  @override
  void add(List<int> data) {
    _out.add(data);
    if (_out.length > _cap) {
      throw const BackupFormatException('content is too large');
    }
  }

  @override
  void close() {}
}

// ------------------------------------------------------------- content

/// Everything needed to rebuild the library on another phone.
Future<Map<String, Object?>> buildSnapshot(AppDatabase db) async {
  return {
    'app': 'WatchedLedger',
    'backupFormat': 1,
    'schema': db.schemaVersion,
    'created': DateTime.now().toUtc().toIso8601String(),
    'items': [for (final i in await db.select(db.items).get()) i.toJson()],
    'watchEvents': [
      for (final e in await db.select(db.watchEvents).get()) e.toJson(),
    ],
    'episodeMarks': [
      for (final e in await db.select(db.episodeMarks).get()) e.toJson(),
    ],
    'settings': await db.readSettings(),
  };
}

class SnapshotSummary {
  const SnapshotSummary(this.items, this.created);
  final int items;
  final DateTime? created;
}

SnapshotSummary summarise(Map<String, Object?> snapshot) {
  final items = snapshot['items'];
  final created = snapshot['created'];
  return SnapshotSummary(
    items is List ? items.length : 0,
    created is String ? DateTime.tryParse(created)?.toLocal() : null,
  );
}

class RestoreResult {
  const RestoreResult({
    required this.added,
    required this.updated,
    required this.skipped,
  });
  final int added;
  final int updated;
  final int skipped;
}

/// Checks and cleans one item from a backup; null if it is unusable.
MediaItem? cleanSnapshotItem(Object? raw) => _cleanItem(raw);

MediaItem? _cleanItem(Object? raw) {
  if (raw is! Map<String, Object?>) return null;
  final MediaItem item;
  try {
    item = MediaItem.fromJson(raw);
  } catch (_) {
    return null;
  }
  final title = cleanTitle(item.title);
  if (title.isEmpty) return null;
  final rating = item.rating;
  return item.copyWith(
    title: title,
    sortTitle: sortKey(title),
    matchKey: matchKey(title),
    note: Value(item.note == null
        ? null
        : cleanText(item.note!, maxLength: kMaxNoteLength)),
    rating: Value(rating != null && rating >= 1 && rating <= 5 ? rating : null),
    coverFile: const Value(null), // pictures aren't in backups
    uid: Value(item.uid ?? newUid()),
  );
}

/// Reads a list of rows from a snapshot, skipping anything malformed.
List<T> snapshotList<T>(
        Object? raw, T Function(Map<String, Object?>) fromJson) =>
    _list(raw, fromJson);

List<T> _list<T>(Object? raw, T Function(Map<String, Object?>) fromJson) {
  if (raw is! List) return const [];
  final out = <T>[];
  for (final e in raw) {
    if (e is! Map<String, Object?>) continue;
    try {
      out.add(fromJson(e));
    } catch (_) {}
  }
  return out;
}

/// Restores a decrypted backup.
///
/// [replace]: the library becomes exactly the backup.
/// Otherwise (merge): new titles are added, titles that exist in both keep
/// whichever copy was edited last, nothing is deleted.
Future<RestoreResult> restoreSnapshot(
  AppDatabase db,
  Map<String, Object?> snapshot, {
  required bool replace,
}) async {
  final rawItems = snapshot['items'];
  final items = <MediaItem>[];
  var skipped = 0;
  for (final raw in rawItems is List ? rawItems : const <Object?>[]) {
    final item = _cleanItem(raw);
    if (item == null) {
      skipped++;
    } else {
      items.add(item);
    }
  }
  final events = _list(snapshot['watchEvents'], WatchEvent.fromJson);
  final marks = _list(snapshot['episodeMarks'], EpisodeMark.fromJson);

  return db.transaction(() async {
    var added = 0, updated = 0;
    if (replace) {
      await db.delete(db.items).go();
      await db.delete(db.watchEvents).go();
      await db.delete(db.episodeMarks).go();
      await db.delete(db.tombstones).go();
      for (final i in items) {
        await db.into(db.items).insert(i);
      }
      for (final e in events) {
        await db.into(db.watchEvents).insert(e);
      }
      for (final m in marks) {
        await db.into(db.episodeMarks).insertOnConflictUpdate(m);
      }
      final settings = snapshot['settings'];
      if (settings is Map) {
        for (final entry in settings.entries) {
          if (entry.key is String && entry.value is String) {
            await db.writeSetting(entry.key as String, entry.value as String);
          }
        }
      }
      added = items.length;
    } else {
      final existing = await db.select(db.items).get();
      final byUid = {for (final e in existing) if (e.uid != null) e.uid!: e};
      final keys = {for (final e in existing) '${e.category.index}|${e.matchKey}'};
      final newIds = <int, int>{};
      for (final i in items) {
        final local = byUid[i.uid];
        if (local != null) {
          if (i.updatedAt.isAfter(local.updatedAt)) {
            await db.update(db.items).replace(i.copyWith(id: local.id));
            updated++;
          }
          continue;
        }
        if (keys.contains('${i.category.index}|${i.matchKey}')) {
          skipped++;
          continue;
        }
        final id = await db.into(db.items)
            .insert(i.toCompanion(true).copyWith(id: const Value.absent()));
        newIds[i.id] = id;
        added++;
      }
      for (final e in events) {
        final id = newIds[e.itemId];
        if (id == null) continue;
        await db.into(db.watchEvents).insert(WatchEventsCompanion.insert(
              itemId: id,
              date: e.date,
              rating: Value(e.rating),
              note: Value(e.note),
              uid: Value(e.uid),
            ));
      }
      for (final m in marks) {
        final id = newIds[m.itemId];
        if (id == null) continue;
        await db.into(db.episodeMarks)
            .insertOnConflictUpdate(m.copyWith(itemId: id));
      }
    }
    return RestoreResult(added: added, updated: updated, skipped: skipped);
  });
}
