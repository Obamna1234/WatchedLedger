import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchedledger/core/lock/app_lock.dart';
import 'package:watchedledger/core/sanitise.dart';
import 'package:watchedledger/data/db/database.dart';
import 'package:watchedledger/data/duplicates.dart';
import 'package:watchedledger/data/models.dart';
import 'package:watchedledger/data/tags.dart';
import 'package:watchedledger/features/data/backup_reminder.dart';

class _NoBiometrics implements Biometrics {
  @override
  Future<bool> available() async => false;
  @override
  Future<bool> authenticate(String reason) async => false;
}

MediaItem item(int id, String title,
        {int? year,
        ListStatus status = ListStatus.todo,
        MediaCategory c = MediaCategory.movie,
        List<String> tags = const [],
        String? note,
        int? season,
        int? episode}) =>
    MediaItem(
      id: id,
      category: c,
      status: status,
      title: title,
      sortTitle: sortKey(title),
      matchKey: matchKey(title),
      year: year,
      genre: kUncategorised,
      matchState: MatchState.manual,
      following: false,
      upcoming: false,
      isPrivate: false,
      tags: encodeTags(tags),
      note: note,
      season: season,
      episode: episode,
      completedAt: status == ListStatus.done ? DateTime(2025, 3) : null,
      addedAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  group('recently deleted', () {
    test('delete keeps a copy that restores with its ticks', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final id = await db.addItem(
          category: MediaCategory.series,
          status: ListStatus.todo,
          title: 'Show');
      await db.setSeasonWatched(id, 1, true);
      await db.deleteItem(id);
      expect(await db.itemById(id), isNull);

      final trash = await db.watchTrash().first;
      expect(trash.map((t) => t.title), ['Show']);

      final back = await db.restoreFromTrash(trash.single.id);
      expect(back?.title, 'Show');
      expect(await db.itemById(id), isNotNull);
      expect(await db.watchTrash().first, isEmpty);
      final marks = await (db.select(db.episodeMarks)
            ..where((m) => m.itemId.equals(id)))
          .get();
      expect(marks, isNotEmpty);
    });

    test('entries older than 30 days are purged', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final old = await db.addItem(
          category: MediaCategory.movie, status: ListStatus.todo, title: 'Old');
      final recent = await db.addItem(
          category: MediaCategory.movie, status: ListStatus.todo, title: 'New');
      await db.deleteItem(old, now: DateTime(2026, 1, 1));
      await db.deleteItem(recent, now: DateTime(2026, 1, 25));
      await db.purgeTrash(now: DateTime(2026, 2, 5));
      final left = await db.watchTrash().first;
      expect(left.map((t) => t.title), ['New']);
    });

    test('undo of a delete also clears it from Recently deleted', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final id = await db.addItem(
          category: MediaCategory.movie, status: ListStatus.todo, title: 'A');
      final a = (await db.itemById(id))!;
      await db.deleteItem(id);
      await db.restoreItem(a);
      expect(await db.watchTrash().first, isEmpty);
    });
  });

  test('private items hide until the PIN is entered, and on lock', () async {
    final lock = AppLock(
      storage: MemoryLockStorage(),
      biometrics: _NoBiometrics(),
      clock: () => DateTime(2026, 11, 17),
      pinIterations: 1000,
    );
    await lock.load();
    expect(lock.privateVisible, isTrue, reason: 'nothing to hide without a PIN');
    await lock.setPin('482913');
    expect(lock.privateVisible, isFalse);
    lock.revealPrivate();
    expect(lock.privateVisible, isTrue);
    lock.lockNow();
    expect(lock.privateVisible, isFalse);
  });

  test('backup reminder: only after a week, 10 titles, 30 days', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final start = DateTime(2026, 1, 1);
    for (var i = 0; i < 10; i++) {
      await db.addItem(
          category: MediaCategory.movie,
          status: ListStatus.todo,
          title: 'T$i');
    }
    expect(await backupDue(db, now: start), isFalse); // first run
    expect(await backupDue(db, now: start.add(const Duration(days: 3))),
        isFalse);
    final later = start.add(const Duration(days: 8));
    expect(await backupDue(db, now: later), isTrue);
    await snoozeBackup(db, now: later);
    expect(await backupDue(db, now: later.add(const Duration(days: 2))),
        isFalse);
    await markBackedUp(db, now: later.add(const Duration(days: 8)));
    expect(await backupDue(db, now: later.add(const Duration(days: 20))),
        isFalse);
    expect(await backupDue(db, now: later.add(const Duration(days: 40))),
        isTrue);
  });

  group('duplicates', () {
    test('groups loose matches but keeps remakes and categories apart', () {
      final groups = findDuplicateGroups([
        item(1, 'Dune', year: 2021),
        item(2, 'Dune (2021)'),
        item(3, 'Dune Part 1', year: 2021),
        item(4, 'Dune', year: 1984),
        item(5, 'Dune', c: MediaCategory.book),
        item(6, 'Arrival'),
        item(7, 'The Office'),
        item(8, 'Office', c: MediaCategory.movie),
      ]);
      expect(groups.map((g) => g.map((i) => i.id).toList()).toList(), [
        [1, 3, 2],
        [7, 8],
      ]);
    });

    test('merging keeps the chosen copy and fills its gaps', () {
      final keep = item(1, 'Dune', tags: ['sci-fi']);
      final merged = mergeDuplicates(keep, [
        item(2, 'Dune (2021)',
            year: 2021,
            status: ListStatus.done,
            tags: ['Cinema', 'sci-fi'],
            note: 'loved it'),
      ]);
      expect(merged.id, 1);
      expect(merged.title, 'Dune');
      expect(merged.year, 2021);
      expect(merged.status, ListStatus.done);
      expect(merged.completedAt, DateTime(2025, 3));
      expect(itemTags(merged), ['sci-fi', 'Cinema']);
      expect(merged.note, 'loved it');
    });

    test('series progress follows the furthest copy', () {
      final merged = mergeDuplicates(
          item(1, 'Show', c: MediaCategory.series, season: 2, episode: 5),
          [item(2, 'Show', c: MediaCategory.series, season: 3, episode: 1)]);
      expect((merged.season, merged.episode), (3, 1));
    });
  });

  test('restoring merged items brings every copy back', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final a = await db.addItem(
        category: MediaCategory.movie, status: ListStatus.todo, title: 'Dune');
    final b = await db.addItem(
        category: MediaCategory.movie,
        status: ListStatus.todo,
        title: 'Dune (2021)');
    final before = [(await db.itemById(a))!, (await db.itemById(b))!];
    await db.updateItem(before[0].copyWith(note: const Value('x')));
    await db.deleteItem(b);
    for (final i in before) {
      await db.restoreItem(i);
    }
    expect((await db.itemById(a))!.note, isNull);
    expect(await db.itemById(b), isNotNull);
    expect(await db.watchTrash().first, isEmpty);
  });
}
