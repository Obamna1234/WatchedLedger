import 'dart:math';

import 'db/database.dart';
import 'models.dart';

/// "Pick something for me". Runs only on your own list, on the phone.

enum PickLength { any, short, medium, long }

enum PickMood { any, light, gripping, thoughtful, escape }

extension PickLengthInfo on PickLength {
  String get label => switch (this) {
        PickLength.any => 'Any length',
        PickLength.short => 'Short',
        PickLength.medium => 'Medium',
        PickLength.long => 'Long',
      };
}

extension PickMoodInfo on PickMood {
  String get label => switch (this) {
        PickMood.any => 'Any mood',
        PickMood.light => 'Light & fun',
        PickMood.gripping => 'Gripping',
        PickMood.thoughtful => 'Thoughtful',
        PickMood.escape => 'Escape',
      };

  /// Genres (lower-case) that fit this mood, across all categories.
  Set<String> get genres => switch (this) {
        PickMood.any => const {},
        PickMood.light => const {
            'comedy', 'animation', 'family', 'romance', 'music', 'kids',
            'kids & family', 'leisure', "children's", 'comics & graphic novels',
            'reality', 'talk', 'tv & film', 'sports',
            'party', 'platformer', 'puzzle', 'racing',
          },
        PickMood.gripping => const {
            'action', 'adventure', 'crime', 'horror', 'mystery', 'thriller',
            'mystery & crime', 'true crime', 'western', 'war',
            'shooter', 'fighting', 'survival', 'action-adventure',
          },
        PickMood.thoughtful => const {
            'drama', 'documentary', 'history', 'biography & memoir',
            'literary fiction', 'historical fiction', 'non-fiction',
            'philosophy', 'poetry', 'science', 'self-help', 'news',
            'society & culture', 'education', 'religion & spirituality',
            'business', 'health & fitness', 'technology',
            'strategy', 'simulation',
          },
        PickMood.escape => const {
            'fantasy', 'science fiction', 'young adult', 'fiction', 'travel',
            'arts', 'role-playing', 'sandbox',
          },
      };
}

/// Length bucket for an item, or null if its length isn't known.
PickLength? lengthOf(MediaItem i) {
  switch (i.category) {
    case MediaCategory.book:
      final p = i.pages;
      if (p == null || p <= 0) return null;
      return p < 250
          ? PickLength.short
          : (p <= 450 ? PickLength.medium : PickLength.long);
    case MediaCategory.audiobook:
      final m = i.runtimeMinutes;
      if (m == null || m <= 0) return null;
      return m < 6 * 60
          ? PickLength.short
          : (m <= 12 * 60 ? PickLength.medium : PickLength.long);
    case MediaCategory.movie:
      final m = i.runtimeMinutes;
      if (m == null || m <= 0) return null;
      return m < 100
          ? PickLength.short
          : (m <= 140 ? PickLength.medium : PickLength.long);
    case MediaCategory.series:
    case MediaCategory.podcast:
    case MediaCategory.game:
      return null;
  }
}

class PickFilter {
  const PickFilter({
    required this.categories,
    this.genre,
    this.length = PickLength.any,
    this.mood = PickMood.any,
    this.includeUnknownLength = true,
  });

  final Set<MediaCategory> categories;
  final String? genre;
  final PickLength length;
  final PickMood mood;

  /// When a length is chosen, also allow items whose length isn't known.
  final bool includeUnknownLength;

  bool matches(MediaItem i) {
    if (i.status != ListStatus.todo) return false;
    if (!categories.contains(i.category)) return false;
    if (genre != null && i.genre != genre) return false;
    if (mood != PickMood.any &&
        !mood.genres.contains(i.genre.toLowerCase())) {
      return false;
    }
    if (length != PickLength.any) {
      final l = lengthOf(i);
      if (l == null) return includeUnknownLength;
      if (l != length) return false;
    }
    return true;
  }
}

/// Picks one item at random. Things that have waited longer are a bit more
/// likely, and recently shown picks ([avoid]) are skipped when possible.
MediaItem? pickOne(
  List<MediaItem> items,
  PickFilter filter, {
  Set<int> avoid = const {},
  Random? random,
  DateTime? now,
}) {
  final rnd = random ?? Random();
  final all = items.where(filter.matches).toList();
  if (all.isEmpty) return null;
  final fresh = all.where((i) => !avoid.contains(i.id)).toList();
  final pool = fresh.isEmpty ? all : fresh;
  final today = now ?? DateTime.now();
  // Weight 1 + months waiting (capped), so old items surface more often
  // without new ones being shut out.
  int weight(MediaItem i) {
    final months = today.difference(i.addedAt).inDays ~/ 30;
    return 1 + (months < 0 ? 0 : (months > 24 ? 24 : months));
  }

  final weights = <int>[for (final i in pool) weight(i)];
  final total = weights.fold<int>(0, (a, b) => a + b);
  var r = rnd.nextInt(total);
  for (var k = 0; k < pool.length; k++) {
    r -= weights[k];
    if (r < 0) return pool[k];
  }
  return pool.last;
}
