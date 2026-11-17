import 'package:drift/drift.dart' show Value;

import '../db/database.dart';
import '../transfer/backup.dart';

/// What a sync changed on this phone.
class SyncResult {
  const SyncResult({
    this.added = 0,
    this.updated = 0,
    this.deleted = 0,
    this.diaryEntries = 0,
  });
  final int added;
  final int updated;
  final int deleted;
  final int diaryEntries;

  bool get nothingChanged =>
      added == 0 && updated == 0 && deleted == 0 && diaryEntries == 0;

  @override
  String toString() =>
      'SyncResult(added: $added, updated: $updated, deleted: $deleted, '
      'diary: $diaryEntries)';
}

/// Everything the other phone needs: items, diary, episode ticks and
/// deletions. Settings and the app lock are not synced.
Future<Map<String, Object?>> buildSyncSnapshot(AppDatabase db) async {
  final snapshot = await buildSnapshot(db);
  snapshot.remove('settings');
  snapshot['kind'] = 'sync';
  snapshot['tombstones'] = [
    for (final t in await db.select(db.tombstones).get()) t.toJson(),
  ];
  return snapshot;
}

/// Merges the other phone's snapshot into this one.
///
/// - Same item (same ID) on both: the most recent edit wins.
/// - Deleted on one phone: deleted on the other too, unless it was edited
///   there after the deletion.
/// - The same title added separately on both phones becomes one item.
/// - Diary entries and episode ticks are combined.
Future<SyncResult> mergeSync(
    AppDatabase db, Map<String, Object?> remote) async {
  final rawItems = remote['items'];
  final remoteItems = <MediaItem>[];
  final remoteUidById = <int, String>{};
  for (final raw in rawItems is List ? rawItems : const <Object?>[]) {
    final item = cleanSnapshotItem(raw);
    final uid = item?.uid;
    if (item == null || uid == null) continue;
    remoteItems.add(item);
    remoteUidById[item.id] = uid;
  }
  final remoteEvents = snapshotList(remote['watchEvents'], WatchEvent.fromJson);
  final remoteMarks = snapshotList(remote['episodeMarks'], EpisodeMark.fromJson);
  final remoteTombs = snapshotList(remote['tombstones'], Tombstone.fromJson);

  return db.transaction(() async {
    var added = 0, updated = 0, deleted = 0, diary = 0;

    final local = await db.select(db.items).get();
    final byUid = {
      for (final i in local)
        if (i.uid != null) i.uid!: i,
    };
    final tombs = {
      for (final t in await db.select(db.tombstones).get()) t.uid: t.deletedAt,
    };

    // 1. Deletions from the other phone.
    for (final t in remoteTombs) {
      final mine = byUid[t.uid];
      if (mine != null && !mine.updatedAt.isAfter(t.deletedAt)) {
        await db.deleteItem(mine.id);
        byUid.remove(t.uid);
        deleted++;
      }
      final known = tombs[t.uid];
      if (known == null || t.deletedAt.isAfter(known)) {
        tombs[t.uid] = t.deletedAt;
        await db.into(db.tombstones).insertOnConflictUpdate(t);
      }
    }

    // 2. Items.
    final byKey = {
      for (final i in byUid.values) '${i.category.index}|${i.matchKey}': i,
    };
    for (final r in remoteItems) {
      final uid = r.uid!;
      final gone = tombs[uid];
      if (gone != null && !r.updatedAt.isAfter(gone)) continue;

      var mine = byUid[uid];
      if (mine == null) {
        // Same title added on both phones: keep one, under the smaller ID,
        // so both phones agree on it.
        final twin = byKey['${r.category.index}|${r.matchKey}'];
        if (twin != null && twin.uid != null) {
          if (uid.compareTo(twin.uid!) < 0) {
            final renamed = twin.copyWith(uid: Value(uid));
            await db.update(db.items).replace(renamed);
            byUid
              ..remove(twin.uid)
              ..[uid] = renamed;
            mine = renamed;
          } else {
            continue; // the other phone will adopt our ID
          }
        }
      }

      if (mine != null) {
        if (r.updatedAt.isAfter(mine.updatedAt)) {
          final keepCover = r.coverUrl == mine.coverUrl ? mine.coverFile : null;
          await db.update(db.items).replace(
              r.copyWith(id: mine.id, coverFile: Value(keepCover)));
          updated++;
        }
        continue;
      }

      final id = await db.into(db.items)
          .insert(r.toCompanion(true).copyWith(id: const Value.absent()));
      final inserted = r.copyWith(id: id);
      byUid[uid] = inserted;
      byKey['${r.category.index}|${r.matchKey}'] = inserted;
      added++;
    }

    // 3. Diary entries (combined, never duplicated).
    final localEvents = await db.select(db.watchEvents).get();
    final eventUids = {
      for (final e in localEvents)
        if (e.uid != null) e.uid!,
    };
    final eventKeys = {for (final e in localEvents) '${e.itemId}|${e.date}'};
    for (final e in remoteEvents) {
      final itemUid = remoteUidById[e.itemId];
      final mine = itemUid == null ? null : byUid[itemUid];
      if (mine == null) continue;
      if (e.uid != null && eventUids.contains(e.uid)) continue;
      if (eventKeys.contains('${mine.id}|${e.date}')) continue;
      await db.into(db.watchEvents).insert(WatchEventsCompanion.insert(
            itemId: mine.id,
            date: e.date,
            rating: Value(e.rating == null ? null : e.rating!.clamp(1, 5)),
            note: Value(e.note),
            uid: Value(e.uid ?? newUid()),
          ));
      if (e.uid != null) eventUids.add(e.uid!);
      eventKeys.add('${mine.id}|${e.date}');
      diary++;
    }

    // 4. Episode ticks (combined).
    for (final m in remoteMarks) {
      final itemUid = remoteUidById[m.itemId];
      final mine = itemUid == null ? null : byUid[itemUid];
      if (mine == null) continue;
      await db.into(db.episodeMarks)
          .insertOnConflictUpdate(m.copyWith(itemId: mine.id));
    }

    return SyncResult(
        added: added, updated: updated, deleted: deleted, diaryEntries: diary);
  });
}
