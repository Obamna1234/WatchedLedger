import 'package:flutter_test/flutter_test.dart';
import 'package:watchedledger/core/home_widget_sync.dart';
import 'package:watchedledger/core/sanitise.dart';
import 'package:watchedledger/data/db/database.dart';
import 'package:watchedledger/data/models.dart';

MediaItem item(int id, String title, MediaCategory c, ListStatus s,
        {int? year}) =>
    MediaItem(
      id: id,
      category: c,
      status: s,
      title: title,
      sortTitle: sortKey(title),
      matchKey: matchKey(title),
      year: year,
      genre: kUncategorised,
      matchState: MatchState.matched,
      following: false,
      upcoming: false,
      isPrivate: false,
      addedAt: DateTime(2026, 1, id),
      updatedAt: DateTime(2026, 1, id),
    );

void main() {
  test('widget shows the newest To Watch items, max 5', () {
    final items = [
      item(1, 'Heat', MediaCategory.movie, ListStatus.todo, year: 1995),
      item(2, 'Dune', MediaCategory.book, ListStatus.todo),
      item(3, 'Alien', MediaCategory.movie, ListStatus.done),
      for (var k = 4; k < 10; k++)
        item(k, 'Show $k', MediaCategory.series, ListStatus.todo),
    ];
    final lines = HomeWidgetSync.linesFor(items);
    expect(lines, hasLength(5));
    expect(lines.first, 'Show 9 · series');
    expect(lines.any((l) => l.startsWith('Alien')), isFalse);
    expect(HomeWidgetSync.linesFor(items.take(2).toList()),
        ['Dune · book', 'Heat (1995) · movie']);
  });
}
