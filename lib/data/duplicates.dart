import 'package:drift/drift.dart' show Value;

import '../core/sanitise.dart';
import 'db/database.dart';
import 'models.dart';
import 'tags.dart';

// Finding and merging items that were added more than once. Pure Dart so
// it can be unit-tested.

final RegExp _brackets = RegExp(r'\([^)]*\)|\[[^\]]*\]');
final RegExp _trailingOne = RegExp(r' (part )?(1|one|i)$');

/// A looser key than [matchKey]: ignores anything in brackets and a
/// trailing "1" / "Part 1", so "Dune (2021)", "Dune [4K]" and "Dune Part 1"
/// all group with "Dune".
String looseKey(String title) {
  var s = sortKey(title.replaceAll(_brackets, ' '));
  s = s.replaceFirst(_trailingOne, '');
  return s.replaceAll(' ', '');
}

/// Groups of two or more items in the same category that look like the
/// same thing. Items with release years more than a year apart are kept
/// apart, so remakes ("Dune" 1984 and 2021) are not treated as duplicates.
List<List<MediaItem>> findDuplicateGroups(Iterable<MediaItem> items) {
  final byKey = <String, List<MediaItem>>{};
  for (final i in items) {
    final key = looseKey(i.title);
    if (key.isEmpty) continue;
    byKey.putIfAbsent('${i.category.index}:$key', () => []).add(i);
  }
  final groups = <List<MediaItem>>[];
  for (final candidates in byKey.values) {
    if (candidates.length < 2) continue;
    // Split by year: items with no year join the first group.
    final split = <List<MediaItem>>[];
    final noYear = <MediaItem>[];
    for (final i in candidates..sort((a, b) => a.id.compareTo(b.id))) {
      final y = i.year;
      if (y == null) {
        noYear.add(i);
        continue;
      }
      final home = split.where((g) => g.any((o) {
            final oy = o.year;
            return oy != null && (oy - y).abs() <= 1;
          }));
      if (home.isEmpty) {
        split.add([i]);
      } else {
        home.first.add(i);
      }
    }
    if (split.isEmpty) {
      split.add(noYear);
    } else {
      split.first.addAll(noYear);
    }
    groups.addAll(split.where((g) => g.length >= 2));
  }
  groups.sort((a, b) => a.first.sortTitle.compareTo(b.first.sortTitle));
  return groups;
}

/// The item [keep] after taking in what only the [others] had: tags,
/// watch-with names and any empty details. A tick on any copy counts.
MediaItem mergeDuplicates(MediaItem keep, List<MediaItem> others,
    {DateTime? now}) {
  T? pick<T>(T? mine, T? Function(MediaItem) of) {
    if (mine != null) return mine;
    for (final o in others) {
      final v = of(o);
      if (v != null) return v;
    }
    return null;
  }

  final tags = encodeTags([
    ...itemTags(keep),
    for (final o in others) ...itemTags(o),
  ]);
  final watchWith = encodeTags([
    ...decodeTags(keep.watchWith),
    for (final o in others) ...decodeTags(o.watchWith),
  ]);
  final done = [keep, ...others].where((i) => i.status == ListStatus.done);
  DateTime? completed;
  for (final i in done) {
    final c = i.completedAt;
    if (c != null && (completed == null || c.isBefore(completed))) {
      completed = c;
    }
  }
  // Series progress: whichever copy is furthest along.
  var furthest = keep;
  for (final o in others) {
    final a = (furthest.season ?? 0, furthest.episode ?? 0);
    final b = (o.season ?? 0, o.episode ?? 0);
    if (b.$1 > a.$1 || (b.$1 == a.$1 && b.$2 > a.$2)) furthest = o;
  }

  final genre = keep.genre != kUncategorised
      ? keep.genre
      : others
          .map((o) => o.genre)
          .firstWhere((g) => g != kUncategorised, orElse: () => keep.genre);

  return keep.copyWith(
    status: done.isEmpty ? keep.status : ListStatus.done,
    completedAt: Value(done.isEmpty ? keep.completedAt : completed),
    tags: Value(tags),
    watchWith: Value(watchWith),
    year: Value(pick(keep.year, (o) => o.year)),
    genre: genre,
    creator: Value(pick(keep.creator, (o) => o.creator)),
    coverUrl: Value(pick(keep.coverUrl, (o) => o.coverUrl)),
    rating: Value(pick(keep.rating, (o) => o.rating)),
    note: Value(pick(keep.note, (o) => o.note)),
    link: Value(pick(keep.link, (o) => o.link)),
    recommendedBy: Value(pick(keep.recommendedBy, (o) => o.recommendedBy)),
    whereToWatch: Value(pick(keep.whereToWatch, (o) => o.whereToWatch)),
    season: Value(furthest.season),
    episode: Value(furthest.episode),
    updatedAt: now ?? DateTime.now(),
  );
}
