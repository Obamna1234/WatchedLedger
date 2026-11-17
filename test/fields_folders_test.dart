import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchedledger/core/reminders.dart';
import 'package:watchedledger/core/sanitise.dart';
import 'package:watchedledger/data/db/database.dart';
import 'package:watchedledger/data/models.dart';
import 'package:watchedledger/data/tags.dart';
import 'package:watchedledger/data/transfer/folder_share.dart';
import 'package:watchedledger/data/transfer/import_parsers.dart';
import 'package:watchedledger/data/transfer/import_plan.dart';
import 'package:watchedledger/features/lists/list_layout.dart';

MediaItem item(int id, String title,
        {MediaCategory c = MediaCategory.movie,
        String? where,
        String? rec,
        List<String> withWho = const [],
        bool upcoming = false,
        DateTime? release,
        String? link,
        List<String> tags = const []}) =>
    MediaItem(
      id: id,
      category: c,
      status: ListStatus.todo,
      title: title,
      sortTitle: sortKey(title),
      matchKey: matchKey(title),
      genre: kUncategorised,
      matchState: MatchState.manual,
      following: false,
      upcoming: upcoming,
      isPrivate: false,
      whereToWatch: where,
      recommendedBy: rec,
      watchWith: encodeTags(withWho),
      releaseDate: release,
      link: link,
      tags: encodeTags(tags),
      addedAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  test('hints in notes fill the new fields', () {
    ImportRow hint(String note) =>
        readHints(ImportRow(title: 'X', note: note));
    expect(hint('meat canyon recommendation "holy moly"').recommendedBy,
        'Meat Canyon');
    expect(hint('suggested by bobb lee').recommendedBy, 'Bobb Lee');
    expect(hint('watch with sofia').watchWith, ['Sofia']);
    expect(hint('netflix').whereToWatch, 'Netflix');
    expect(hint('on plex').whereToWatch, 'Plex');
    expect(hint('waiting to get released').upcoming, isTrue);
    expect(hint('alien movie').recommendedBy, isNull);
    expect(hint('alien movie').whereToWatch, isNull);
  });

  test('filters: where to watch and people', () {
    final a = item(1, 'A', where: 'Netflix', withWho: ['Sofia']);
    final b = item(2, 'B', where: 'Stan', rec: 'Meat Canyon');
    expect(const ListOptions(where: {'netflix'}).matches(a), isTrue);
    expect(const ListOptions(where: {'netflix'}).matches(b), isFalse);
    expect(const ListOptions(people: {'sofia'}).matches(a), isTrue);
    expect(const ListOptions(people: {'meat canyon'}).matches(b), isTrue);
    expect(const ListOptions(people: {'sofia'}).matches(b), isFalse);
  });

  test('"Not out yet" items are grouped at the top', () {
    final layout = buildListLayout([
      item(1, 'Alpha'),
      item(2, 'Mo season 2', upcoming: true),
    ], const ListOptions());
    final first = layout.rows.first as HeaderRow;
    expect(first.label, 'Not out yet');
    expect((layout.rows[1] as ItemRow).item.title, 'Mo season 2');
  });

  test('release-day reminders', () {
    final now = DateTime.utc(2026, 11, 17);
    final plan = ReminderService.releasePlan([
      item(1, 'Soon', upcoming: true, release: DateTime.utc(2026, 12, 1)),
      item(2, 'Past', upcoming: true, release: DateTime.utc(2026, 1, 1)),
      item(3, 'No date', upcoming: true),
    ], now);
    expect([for (final r in plan) r.title], ['Soon']);
  });

  test('a shared folder reads back as the same items', () async {
    final text = folderShareText('Funny reels', [
      item(1, 'Pumpkin review',
          c: MediaCategory.video, link: 'https://youtu.be/abc'),
      item(2, 'Interstellar', where: 'Netflix'),
    ]);
    expect(text, contains('https://youtu.be/abc'));
    expect(text, startsWith('"Funny reels" (from WatchedLedger)'));

    final r = parseImport(text);
    expect(r.format, ImportFormat.sharedFolder);
    expect([for (final x in r.rows) x.title],
        ['Pumpkin review', 'Interstellar']);
    expect(r.rows[0].category, MediaCategory.video);
    expect(r.rows[0].link, 'https://youtu.be/abc');
    expect(r.rows[1].whereToWatch, 'Netflix');
    expect(r.rows.every((x) => x.tags.contains('Funny reels')), isTrue);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final entries = await prepareImport(db, r.rows, MediaCategory.movie);
    await saveImport(db, entries);
    final saved = await db.select(db.items).get();
    expect(saved.firstWhere((i) => i.title == 'Pumpkin review').link,
        'https://youtu.be/abc');
    expect(await db.tagsInUse(), ['Funny reels']);
  });

  test('names and places in use', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final id = await db.addItem(
        category: MediaCategory.movie, status: ListStatus.todo, title: 'A');
    final a = (await db.itemById(id))!;
    await db.updateItem(a.copyWith(
      recommendedBy: const Value('Meat Canyon'),
      watchWith: Value(encodeTags(['Sofia'])),
      whereToWatch: const Value('Stan'),
    ));
    expect(await db.peopleInUse(), ['Meat Canyon', 'Sofia']);
    expect(await db.placesInUse(), ['Stan']);
  });
}
