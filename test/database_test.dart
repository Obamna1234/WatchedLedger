import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchedledger/data/db/database.dart';
import 'package:watchedledger/data/models.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('add, tick, untick keeps completion date in sync', () async {
    final id = await db.addItem(
      category: MediaCategory.movie,
      status: ListStatus.todo,
      title: '  Dune ',
    );

    var todo =
        await db.watchList(MediaCategory.movie, ListStatus.todo).first;
    expect(todo.single.title, 'Dune');
    expect(todo.single.completedAt, isNull);
    expect(todo.single.genre, kUncategorised);

    final when = DateTime(2026, 3, 14);
    await db.setStatus(id, ListStatus.done, now: when);
    final done =
        await db.watchList(MediaCategory.movie, ListStatus.done).first;
    expect(done.single.completedAt, when);
    expect(completedLabel(MediaCategory.movie, when), 'Watched March 2026');

    await db.setStatus(id, ListStatus.todo);
    todo = await db.watchList(MediaCategory.movie, ListStatus.todo).first;
    expect(todo.single.completedAt, isNull);
  });

  test('duplicates are found across categories and lists', () async {
    await db.addItem(
      category: MediaCategory.book,
      status: ListStatus.done,
      title: 'The Hobbit',
    );
    final dups = await db.findDuplicates('the hobbit');
    expect(dups, hasLength(1));
    expect(dups.single.category, MediaCategory.book);
  });

  test('undo restores a deleted item exactly', () async {
    final id = await db.addItem(
      category: MediaCategory.podcast,
      status: ListStatus.todo,
      title: 'Hardcore History',
    );
    final before = (await db.findDuplicates('Hardcore History')).single;
    await db.deleteItem(id);
    expect(await db.findDuplicates('Hardcore History'), isEmpty);
    await db.restoreItem(before);
    final after = (await db.findDuplicates('Hardcore History')).single;
    expect(after, before);
  });

  test('settings round-trip', () async {
    await db.writeSetting('theme', 'amoled');
    await db.writeSetting('theme', 'dark');
    expect(await db.readSettings(), {'theme': 'dark'});
  });

  test('empty titles are rejected', () {
    expect(
      () => db.addItem(
        category: MediaCategory.movie,
        status: ListStatus.todo,
        title: ' \u200B ',
      ),
      throwsArgumentError,
    );
  });
}
