import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchedledger/data/db/database.dart';
import 'package:watchedledger/data/models.dart';
import 'package:watchedledger/data/stats.dart';
import 'package:watchedledger/data/tags.dart';
import 'package:watchedledger/features/edit/edit_sections.dart';
import 'package:watchedledger/features/lists/list_layout.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<List<WatchEvent>> events(int id) =>
      (db.select(db.watchEvents)..where((e) => e.itemId.equals(id))).get();

  group('diary', () {
    test('ticking adds an entry; unticking removes that one only', () async {
      final id = await db.addItem(
          category: MediaCategory.movie,
          status: ListStatus.todo,
          title: 'Heat');
      expect(await events(id), isEmpty);
      await db.setStatus(id, ListStatus.done, now: DateTime(2025, 5, 1, 20));
      await db.addRewatch(id, date: DateTime(2026, 2, 3, 12));
      expect(await events(id), hasLength(2));
      expect((await db.itemById(id))!.completedAt, DateTime(2026, 2, 3, 12));

      await db.setStatus(id, ListStatus.todo);
      final left = await events(id);
      expect(left.single.date, DateTime(2025, 5, 1, 20));
    });

    test('adding straight to Watched creates an entry', () async {
      final id = await db.addItem(
          category: MediaCategory.book,
          status: ListStatus.done,
          title: 'Dune',
          now: DateTime(2026, 1, 1, 9));
      expect((await events(id)).single.date, DateTime(2026, 1, 1, 9));
    });

    test('an older rewatch date does not move the finished date', () async {
      final id = await db.addItem(
          category: MediaCategory.movie,
          status: ListStatus.done,
          title: 'Alien',
          now: DateTime(2026, 6, 1));
      await db.addRewatch(id, date: DateTime(2010, 1, 1), rating: 9, note: 'x');
      final item = (await db.itemById(id))!;
      expect(item.completedAt, DateTime(2026, 6, 1));
      final old = (await events(id)).firstWhere((e) => e.date.year == 2010);
      expect(old.rating, 5);
      expect(old.note, 'x');
    });

    test('deleting the latest entry falls back to the previous date',
        () async {
      final id = await db.addItem(
          category: MediaCategory.movie,
          status: ListStatus.done,
          title: 'Up',
          now: DateTime(2024, 1, 1));
      await db.addRewatch(id, date: DateTime(2025, 1, 1));
      final latest =
          (await events(id)).firstWhere((e) => e.date.year == 2025);
      await db.deleteEvent(latest.id);
      expect((await db.itemById(id))!.completedAt, DateTime(2024, 1, 1));
    });

    test('editing the list or finished date keeps the diary in step',
        () async {
      final id = await db.addItem(
          category: MediaCategory.movie,
          status: ListStatus.todo,
          title: 'Jaws');
      var item = (await db.itemById(id))!;
      await db.updateItem(item.copyWith(
          status: ListStatus.done,
          completedAt: Value(DateTime(2026, 3, 3))));
      expect((await events(id)).single.date, DateTime(2026, 3, 3));

      item = (await db.itemById(id))!;
      await db.updateItem(
          item.copyWith(completedAt: Value(DateTime(2026, 4, 4))));
      expect((await events(id)).single.date, DateTime(2026, 4, 4));

      item = (await db.itemById(id))!;
      await db.updateItem(item.copyWith(
          status: ListStatus.todo, completedAt: const Value(null)));
      expect(await events(id), isEmpty);
    });

    test('Undo of a tick or untick keeps the diary right', () async {
      final id = await db.addItem(
          category: MediaCategory.movie,
          status: ListStatus.todo,
          title: 'Fargo');
      final todo = (await db.itemById(id))!;
      await db.setStatus(id, ListStatus.done, now: DateTime(2026, 2, 2));
      expect(await events(id), hasLength(1));
      await db.restoreItem(todo); // Undo the tick
      expect(await events(id), isEmpty);

      await db.setStatus(id, ListStatus.done, now: DateTime(2026, 3, 3));
      final done = (await db.itemById(id))!;
      await db.setStatus(id, ListStatus.todo);
      expect(await events(id), isEmpty);
      await db.restoreItem(done); // Undo the untick
      expect((await events(id)).single.date, DateTime(2026, 3, 3));
    });

    test('backfill gives older finished items one entry, once', () async {
      final id = await db.into(db.items).insert(ItemsCompanion.insert(
            category: MediaCategory.movie,
            status: ListStatus.done,
            title: 'Old',
            sortTitle: 'old',
            matchKey: 'old',
            matchState: MatchState.manual,
            rating: const Value(4),
            addedAt: DateTime(2020),
            updatedAt: DateTime(2020),
            completedAt: Value(DateTime(2020, 7, 7)),
          ));
      expect(await db.backfillDiary(), 1);
      expect(await db.backfillDiary(), 0);
      final e = (await events(id)).single;
      expect(e.date, DateTime(2020, 7, 7));
      expect(e.rating, 4);
    });

    test('diary hides entries of deleted items; undo brings them back',
        () async {
      final id = await db.addItem(
          category: MediaCategory.movie,
          status: ListStatus.done,
          title: 'Gone');
      final item = (await db.itemById(id))!;
      await db.deleteItem(id);
      expect(await db.watchDiary().first, isEmpty);
      expect(await db.select(db.tombstones).get(), hasLength(1));
      await db.restoreItem(item);
      expect(await db.watchDiary().first, hasLength(1));
      expect(await db.select(db.tombstones).get(), isEmpty);
      await db.deleteItem(id);
      await db.tidyOrphans();
      expect(await db.select(db.watchEvents).get(), isEmpty);
    });

    test('stats count every entry, including rewatches', () async {
      final id = await db.addItem(
          category: MediaCategory.movie,
          status: ListStatus.done,
          title: 'Heat',
          now: DateTime(2026, 1, 5));
      await db.addRewatch(id, date: DateTime(2026, 8, 1));
      final items = await db.select(db.items).get();
      final s = LibraryStats.from(items,
          year: 2026, events: await db.allEvents());
      expect(s.totalFinished, 2);
      expect(s.finishedByMonth[0], 1);
      expect(s.finishedByMonth[7], 1);
    });
  });

  group('tags', () {
    test('cleaned, de-duplicated, capped', () {
      final raw = encodeTags(
          ['Halloween', ' halloween ', 'with Sam;', '', '#cosy', 'a' * 60]);
      expect(decodeTags(raw), ['Halloween', 'with Sam', 'cosy', 'a' * 40]);
      expect(encodeTags(const []), isNull);
      expect(decodeTags('not json'), isEmpty);
    });

    test('tags in use and the tag filter', () async {
      await db.into(db.items).insert(ItemsCompanion.insert(
            category: MediaCategory.movie,
            status: ListStatus.todo,
            title: 'Coco',
            sortTitle: 'coco',
            matchKey: 'coco',
            matchState: MatchState.manual,
            tags: Value(encodeTags(['Halloween', 'with Sam'])),
            addedAt: DateTime(2026),
            updatedAt: DateTime(2026),
          ));
      expect(await db.tagsInUse(), ['Halloween', 'with Sam']);
      expect(await db.tagsInUse(MediaCategory.book), isEmpty);
      final item = (await db.select(db.items).get()).single;
      expect(const ListOptions(tags: {'halloween'}).matches(item), isTrue);
      expect(const ListOptions(tags: {'xmas'}).matches(item), isFalse);
      expect(const ListOptions(tags: {'x'}).isFiltered, isTrue);
    });
  });

  group('goals and progress', () {
    test('goals per category and year', () async {
      await db.setGoal(MediaCategory.book, 2027, 24);
      await db.setGoal(MediaCategory.movie, 2027, 0);
      expect(await db.goalsFor(2027), {MediaCategory.book: 24});
      expect(await db.goalsFor(2026), isEmpty);
      await db.setGoal(MediaCategory.book, 2027, null);
      expect(await db.goalsFor(2027), isEmpty);
    });

    test('progress labels and h:mm parsing', () {
      expect(parseMinutes('3:20'), 200);
      expect(parseMinutes('3h05'), 185);
      expect(parseMinutes('45'), 45);
      expect(parseMinutes('3:75'), isNull);
      expect(parseMinutes(''), isNull);
      expect(formatMinutes(605), '10:05');
      expect(progressFraction(ProgressUnit.pages, 150, 300), 0.5);
      expect(progressFraction(ProgressUnit.percent, 30, null), 0.3);
      expect(progressFraction(ProgressUnit.pages, 10, null), isNull);
    });
  });
}
