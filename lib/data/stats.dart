import 'db/database.dart';
import 'models.dart';

/// Numbers for the Stats screen. Everything is worked out on the phone.
class LibraryStats {
  LibraryStats._({
    required this.year,
    required this.finishedByCategory,
    required this.toDoByCategory,
    required this.finishedByMonth,
    required this.topGenres,
    required this.averageRating,
    required this.pagesRead,
    required this.minutesWatched,
    required this.finishedByYear,
    required this.years,
  });

  /// The year shown, or null for all time.
  final int? year;
  final Map<MediaCategory, int> finishedByCategory;
  final Map<MediaCategory, int> toDoByCategory;

  /// 12 entries (Jan..Dec); empty for all time.
  final List<int> finishedByMonth;

  /// Most common genres among finished items, most first (max 6).
  final List<MapEntry<String, int>> topGenres;
  final double? averageRating;
  final int pagesRead;
  final int minutesWatched;

  /// Finished items per year, newest first.
  final List<MapEntry<int, int>> finishedByYear;

  /// Every year that has something finished, newest first.
  final List<int> years;

  int get totalFinished =>
      finishedByCategory.values.fold(0, (a, b) => a + b);

  /// Every diary entry counts (a rewatch counts again). Without [events],
  /// each finished item counts once on its finished date.
  factory LibraryStats.from(List<MediaItem> items,
      {int? year, List<WatchEvent>? events}) {
    final byId = {for (final i in items) i.id: i};
    final List<(MediaItem, DateTime)> finishes;
    if (events != null) {
      finishes = [
        for (final e in events)
          if (byId[e.itemId] case final i?) (i, e.date),
      ];
    } else {
      finishes = [
        for (final i in items)
          if (i.status == ListStatus.done && i.completedAt != null)
            (i, i.completedAt!),
      ];
    }
    final inYear = [
      for (final f in finishes)
        if (year == null || f.$2.year == year) f,
    ];

    final byCat = {for (final c in MediaCategory.values) c: 0};
    final todo = {for (final c in MediaCategory.values) c: 0};
    for (final (i, _) in inYear) {
      byCat[i.category] = byCat[i.category]! + 1;
    }
    for (final i in items) {
      if (i.status == ListStatus.todo) todo[i.category] = todo[i.category]! + 1;
    }

    final months = List<int>.filled(year == null ? 0 : 12, 0);
    if (year != null) {
      for (final (_, date) in inYear) {
        months[date.month - 1]++;
      }
    }

    final genres = <String, int>{};
    for (final (i, _) in inYear) {
      if (i.genre == kUncategorised) continue;
      genres[i.genre] = (genres[i.genre] ?? 0) + 1;
    }
    final top = genres.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : a.key.compareTo(b.key);
      });

    final rated = [
      for (final (i, _) in inYear)
        if (i.rating != null) i.rating!,
    ];
    final avg = rated.isEmpty
        ? null
        : rated.fold<int>(0, (a, b) => a + b) / rated.length;

    var pages = 0, minutes = 0;
    for (final (i, _) in inYear) {
      if (i.category == MediaCategory.book) pages += i.pages ?? 0;
      if (i.category == MediaCategory.movie ||
          i.category == MediaCategory.audiobook) {
        minutes += i.runtimeMinutes ?? 0;
      }
    }

    final perYear = <int, int>{};
    for (final (_, date) in finishes) {
      final y = date.year;
      perYear[y] = (perYear[y] ?? 0) + 1;
    }
    final yearsList = perYear.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));

    return LibraryStats._(
      year: year,
      finishedByCategory: byCat,
      toDoByCategory: todo,
      finishedByMonth: months,
      topGenres: top.take(6).toList(),
      averageRating: avg,
      pagesRead: pages,
      minutesWatched: minutes,
      finishedByYear: yearsList,
      years: [for (final e in yearsList) e.key],
    );
  }
}
