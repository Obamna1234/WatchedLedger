import 'package:flutter_test/flutter_test.dart';
import 'package:watchedledger/core/sanitise.dart';
import 'package:watchedledger/data/db/database.dart';
import 'package:watchedledger/data/models.dart';
import 'package:watchedledger/features/lists/item_tile.dart';
import 'package:watchedledger/features/lists/list_layout.dart';

int _nextId = 1;

MediaItem item(
  String title, {
  String genre = kUncategorised,
  int? year,
  int? rating,
  DateTime? added,
  DateTime? completed,
  ListStatus status = ListStatus.todo,
}) {
  final t = added ?? DateTime(2025, 1, 1);
  return MediaItem(
    id: _nextId++,
    category: MediaCategory.movie,
    status: status,
    title: title,
    sortTitle: sortKey(title),
    matchKey: matchKey(title),
    year: year,
    genre: genre,
    matchState: MatchState.unmatched,
    rating: rating,
    addedAt: t,
    completedAt: completed,
    updatedAt: t,
  );
}

List<String> titles(ListLayout l) =>
    [for (final r in l.rows) if (r is ItemRow) r.item.title];

void main() {
  final items = [
    item('The Matrix', genre: 'Science Fiction', year: 1999, rating: 5),
    item('Alien', genre: 'Horror', year: 1979, rating: 4),
    item('Arrival', genre: 'Science Fiction', year: 2016),
    item('Zodiac', year: 2007, rating: 3),
    item('Heat', genre: 'Crime', rating: 5),
  ];

  test('groups by genre A–Z with Uncategorised last', () {
    final l = buildListLayout(items, const ListOptions());
    final headers = [for (final r in l.rows) if (r is HeaderRow) r.label];
    expect(headers,
        ['Crime', 'Horror', 'Science Fiction', kUncategorised]);
    expect(l.sections.map((s) => s.label), headers);
    // "The Matrix" sorts under M, after Arrival.
    expect(titles(l), ['Heat', 'Alien', 'Arrival', 'The Matrix', 'Zodiac']);
    // Each section points at its header row.
    for (final s in l.sections) {
      expect(l.rows[s.startRow], isA<HeaderRow>());
    }
  });

  test('ungrouped A–Z has letter sections', () {
    final l = buildListLayout(
        items, const ListOptions(groupByGenre: false));
    expect(titles(l), ['Alien', 'Arrival', 'Heat', 'The Matrix', 'Zodiac']);
    expect(l.sections.map((s) => s.label), ['A', 'H', 'M', 'Z']);
  });

  test('year sort is newest first with missing years last', () {
    final l = buildListLayout(
        items, const ListOptions(groupByGenre: false, sort: SortMode.year));
    expect(titles(l), ['Arrival', 'Zodiac', 'The Matrix', 'Alien', 'Heat']);
    expect(l.sections.first.label, '2010s');
    expect(l.sections.last.label, 'No year');
  });

  test('reverse keeps missing values last', () {
    final l = buildListLayout(
        items,
        const ListOptions(
            groupByGenre: false, sort: SortMode.rating, reverse: true));
    expect(titles(l).take(3), ['Zodiac', 'Alien', 'Heat']);
    expect(titles(l).last, 'Arrival');
  });

  test('filters combine', () {
    final l = buildListLayout(
      items,
      const ListOptions(minRating: 4, yearFrom: 1990, yearTo: 2010),
    );
    expect(titles(l), ['The Matrix']);
    expect(l.totalBeforeFilter, 5);
    expect(l.itemCount, 1);

    final byGenre = buildListLayout(
        items, const ListOptions(genres: {'Horror', 'Crime'}));
    expect(titles(byGenre), ['Heat', 'Alien']);
  });

  test('withFilters() clears filters but keeps sorting', () {
    const o = ListOptions(sort: SortMode.year, minRating: 3);
    final cleared = o.withFilters();
    expect(cleared.isFiltered, isFalse);
    expect(cleared.sort, SortMode.year);
  });

  test('tile details line', () {
    final done = item('Dune',
        year: 2021,
        rating: 4,
        status: ListStatus.done,
        completed: DateTime(2026, 3, 2));
    expect(ItemTile.details(done), '2021  ·  ★★★★  ·  Watched March 2026');
  });
}
