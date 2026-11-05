import '../../data/db/database.dart';
import '../../data/genres.dart';

/// Pure sorting, filtering and sectioning of a list, kept free of Flutter
/// so it can be unit-tested.

enum SortMode { az, year, added, completed, rating }

extension SortModeLabels on SortMode {
  String get label => switch (this) {
        SortMode.az => 'A–Z',
        SortMode.year => 'Release year (newest first)',
        SortMode.added => 'Date added (newest first)',
        SortMode.completed => 'Date finished (newest first)',
        SortMode.rating => 'Rating (highest first)',
      };
}

class ListOptions {
  const ListOptions({
    this.groupByGenre = true,
    this.sort = SortMode.az,
    this.reverse = false,
    this.genres = const {},
    this.minRating,
    this.yearFrom,
    this.yearTo,
    this.addedYear,
    this.completedYear,
  });

  final bool groupByGenre;
  final SortMode sort;
  final bool reverse;

  final Set<String> genres;
  final int? minRating;
  final int? yearFrom;
  final int? yearTo;
  final int? addedYear;
  final int? completedYear;

  bool get isFiltered =>
      genres.isNotEmpty ||
      minRating != null ||
      yearFrom != null ||
      yearTo != null ||
      addedYear != null ||
      completedYear != null;

  ListOptions withSorting({bool? groupByGenre, SortMode? sort, bool? reverse}) =>
      ListOptions(
        groupByGenre: groupByGenre ?? this.groupByGenre,
        sort: sort ?? this.sort,
        reverse: reverse ?? this.reverse,
        genres: genres,
        minRating: minRating,
        yearFrom: yearFrom,
        yearTo: yearTo,
        addedYear: addedYear,
        completedYear: completedYear,
      );

  /// Same sorting, filters replaced (pass nothing to clear all filters).
  ListOptions withFilters({
    Set<String> genres = const {},
    int? minRating,
    int? yearFrom,
    int? yearTo,
    int? addedYear,
    int? completedYear,
  }) =>
      ListOptions(
        groupByGenre: groupByGenre,
        sort: sort,
        reverse: reverse,
        genres: genres,
        minRating: minRating,
        yearFrom: yearFrom,
        yearTo: yearTo,
        addedYear: addedYear,
        completedYear: completedYear,
      );

  bool matches(MediaItem i) {
    if (genres.isNotEmpty && !genres.contains(i.genre)) return false;
    final min = minRating;
    if (min != null && (i.rating ?? 0) < min) return false;
    final from = yearFrom;
    final year = i.year;
    if (from != null && (year == null || year < from)) return false;
    final to = yearTo;
    if (to != null && (year == null || year > to)) return false;
    final added = addedYear;
    if (added != null && i.addedAt.year != added) return false;
    final completed = completedYear;
    if (completed != null && i.completedAt?.year != completed) return false;
    return true;
  }
}

sealed class ListRow {
  const ListRow();
}

class HeaderRow extends ListRow {
  const HeaderRow(this.label, this.count);
  final String label;
  final int count;
}

class ItemRow extends ListRow {
  const ItemRow(this.item);
  final MediaItem item;
}

/// A jump target for the fast-scroll bar.
class ListSection {
  const ListSection(this.label, this.shortLabel, this.startRow);
  final String label;
  final String shortLabel;
  final int startRow;
}

class ListLayout {
  const ListLayout(this.rows, this.sections, this.totalBeforeFilter);
  final List<ListRow> rows;
  final List<ListSection> sections;
  final int totalBeforeFilter;

  int get itemCount => rows.whereType<ItemRow>().length;
}

int? _nullsLast(Object? a, Object? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return null;
}

int compareItems(MediaItem a, MediaItem b, SortMode mode, bool reverse) {
  int dir(int c) => reverse ? -c : c;
  final int primary;
  switch (mode) {
    case SortMode.az:
      primary = dir(a.sortTitle.compareTo(b.sortTitle));
    case SortMode.year:
      primary = _nullsLast(a.year, b.year) ?? dir(b.year!.compareTo(a.year!));
    case SortMode.added:
      primary = dir(b.addedAt.compareTo(a.addedAt));
    case SortMode.completed:
      primary = _nullsLast(a.completedAt, b.completedAt) ??
          dir(b.completedAt!.compareTo(a.completedAt!));
    case SortMode.rating:
      primary =
          _nullsLast(a.rating, b.rating) ?? dir(b.rating!.compareTo(a.rating!));
  }
  if (primary != 0) return primary;
  final byTitle = a.sortTitle.compareTo(b.sortTitle);
  return byTitle != 0 ? byTitle : a.id.compareTo(b.id);
}

final RegExp _latinLetter = RegExp(r'[a-z]');

String _initial(String sortTitle) {
  if (sortTitle.isEmpty) return '#';
  final first = String.fromCharCode(sortTitle.runes.first);
  return _latinLetter.hasMatch(first) ? first.toUpperCase() : '#';
}

String _twoDigitYear(int year) => "'${(year % 100).toString().padLeft(2, '0')}";

/// (label, shortLabel) of the section an item falls in when not grouped.
(String, String) sectionOf(MediaItem i, SortMode mode) {
  switch (mode) {
    case SortMode.az:
      final l = _initial(i.sortTitle);
      return (l, l);
    case SortMode.year:
      final y = i.year;
      if (y == null) return ('No year', '–');
      final decade = y ~/ 10 * 10;
      return ('${decade}s', _twoDigitYear(decade));
    case SortMode.added:
      final y = i.addedAt.year;
      return ('Added $y', _twoDigitYear(y));
    case SortMode.completed:
      final y = i.completedAt?.year;
      if (y == null) return ('Not finished', '–');
      return ('Finished $y', _twoDigitYear(y));
    case SortMode.rating:
      final r = i.rating;
      if (r == null) return ('Unrated', '–');
      return ('★' * r, '$r★');
  }
}

String _genreShort(String genre) {
  final runes = genre.runes.take(2).toList();
  return String.fromCharCodes(runes);
}

ListLayout buildListLayout(List<MediaItem> all, ListOptions options) {
  final items = all.where(options.matches).toList()
    ..sort((a, b) => compareItems(a, b, options.sort, options.reverse));

  final rows = <ListRow>[];
  final sections = <ListSection>[];

  if (options.groupByGenre) {
    final byGenre = <String, List<MediaItem>>{};
    for (final i in items) {
      byGenre.putIfAbsent(i.genre, () => []).add(i);
    }
    final genres = byGenre.keys.toList()..sort(compareGenres);
    for (final g in genres) {
      final group = byGenre[g]!;
      sections.add(ListSection(g, _genreShort(g), rows.length));
      rows.add(HeaderRow(g, group.length));
      for (final i in group) {
        rows.add(ItemRow(i));
      }
    }
  } else {
    String? current;
    for (final i in items) {
      final (label, short) = sectionOf(i, options.sort);
      if (label != current) {
        sections.add(ListSection(label, short, rows.length));
        current = label;
      }
      rows.add(ItemRow(i));
    }
  }
  return ListLayout(rows, sections, all.length);
}
