import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchedledger/core/sanitise.dart';
import 'package:watchedledger/data/db/database.dart';
import 'package:watchedledger/data/models.dart';
import 'package:watchedledger/data/picker.dart';
import 'package:watchedledger/data/stats.dart';

int _id = 1;

MediaItem item(
  String title, {
  MediaCategory category = MediaCategory.movie,
  ListStatus status = ListStatus.todo,
  String genre = kUncategorised,
  int? runtime,
  int? pages,
  int? rating,
  DateTime? added,
  DateTime? finished,
}) {
  final t = added ?? DateTime(2026, 11, 1);
  return MediaItem(
    id: _id++,
    category: category,
    status: status,
    title: title,
    sortTitle: sortKey(title),
    matchKey: matchKey(title),
    genre: genre,
    matchState: MatchState.matched,
    following: false,
    upcoming: false,
    isPrivate: false,
    runtimeMinutes: runtime,
    pages: pages,
    rating: rating,
    addedAt: t,
    updatedAt: t,
    completedAt: finished,
  );
}

void main() {
  group('picker', () {
    final heat = item('Heat', genre: 'Crime', runtime: 170);
    final up = item('Up', genre: 'Animation', runtime: 96);
    final dune = item('Dune',
        category: MediaCategory.book, genre: 'Science Fiction', pages: 600);
    final seen = item('Alien', status: ListStatus.done, genre: 'Horror');
    final unknown = item('Mystery Film', genre: 'Drama');
    final all = [heat, up, dune, seen, unknown];

    test('only picks from the To Watch list of chosen categories', () {
      const f = PickFilter(categories: {MediaCategory.movie});
      for (var s = 0; s < 50; s++) {
        final p = pickOne(all, f, random: Random(s))!;
        expect(p.status, ListStatus.todo);
        expect(p.category, MediaCategory.movie);
      }
    });

    test('mood and length filters', () {
      expect(
        pickOne(
            all,
            const PickFilter(
                categories: {MediaCategory.movie}, mood: PickMood.light)),
        up,
      );
      const long = PickFilter(
        categories: {MediaCategory.movie, MediaCategory.book},
        length: PickLength.long,
        includeUnknownLength: false,
      );
      final picks = {
        for (var s = 0; s < 40; s++) pickOne(all, long, random: Random(s)),
      };
      expect(picks, {heat, dune});
      expect(lengthOf(up), PickLength.short);
      expect(lengthOf(unknown), isNull);
    });

    test('nothing fits -> null', () {
      expect(
        pickOne(all, const PickFilter(categories: {MediaCategory.podcast})),
        isNull,
      );
    });

    test('recent picks are avoided until everything has been shown', () {
      const f = PickFilter(categories: {MediaCategory.movie});
      final shown = <int>{};
      for (var k = 0; k < 3; k++) {
        final p = pickOne(all, f, avoid: shown, random: Random(k))!;
        expect(shown.contains(p.id), isFalse);
        shown.add(p.id);
      }
      expect(pickOne(all, f, avoid: shown), isNotNull);
    });

    test('things waiting longer come up more often', () {
      final old = item('Old', added: DateTime(2024, 1, 1));
      final fresh = item('New', added: DateTime(2026, 11, 16));
      const f = PickFilter(categories: {MediaCategory.movie});
      final rnd = Random(7);
      var oldCount = 0;
      for (var k = 0; k < 2000; k++) {
        final p =
            pickOne([old, fresh], f, random: rnd, now: DateTime(2026, 11, 17));
        if (p == old) {
          oldCount++;
        }
      }
      expect(oldCount, greaterThan(1500));
      expect(oldCount, lessThan(2000));
    });
  });

  group('stats', () {
    final items = [
      item('A', status: ListStatus.done, genre: 'Drama', rating: 4,
          runtime: 120, finished: DateTime(2026, 3, 2)),
      item('B', status: ListStatus.done, genre: 'Drama', rating: 2,
          finished: DateTime(2026, 3, 20)),
      item('C', category: MediaCategory.book, status: ListStatus.done,
          genre: 'Fantasy', pages: 300, finished: DateTime(2026, 7, 1)),
      item('D', status: ListStatus.done, genre: 'Comedy',
          finished: DateTime(2025, 1, 1)),
      item('E', category: MediaCategory.book),
    ];

    test('one year', () {
      final s = LibraryStats.from(items, year: 2026);
      expect(s.totalFinished, 3);
      expect(s.finishedByCategory[MediaCategory.movie], 2);
      expect(s.finishedByCategory[MediaCategory.book], 1);
      expect(s.toDoByCategory[MediaCategory.book], 1);
      expect(s.finishedByMonth[2], 2);
      expect(s.finishedByMonth[6], 1);
      expect(s.topGenres.first.key, 'Drama');
      expect(s.topGenres.first.value, 2);
      expect(s.averageRating, 3);
      expect(s.pagesRead, 300);
      expect(s.minutesWatched, 120);
      expect(s.years, [2026, 2025]);
    });

    test('all time', () {
      final s = LibraryStats.from(items);
      expect(s.totalFinished, 4);
      expect(s.finishedByMonth, isEmpty);
      expect(s.finishedByYear.map((e) => (e.key, e.value)).toList(),
          [(2026, 3), (2025, 1)]);
    });

    test('empty library', () {
      final s = LibraryStats.from(const []);
      expect(s.totalFinished, 0);
      expect(s.averageRating, isNull);
      expect(s.topGenres, isEmpty);
    });
  });
}
