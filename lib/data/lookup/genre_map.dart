import '../../core/sanitise.dart';
import '../genres.dart';
import '../models.dart';

/// Maps a source's own genre names onto WatchedLedger's curated genres.
///
/// Rules are checked in priority order across all of the source's genres,
/// so specific genres ("Science Fiction") beat broad ones ("Drama").

typedef _Rule = (List<String> keywords, String genre);

const List<_Rule> _screenRules = [
  (['anime', 'animation', 'animated'], 'Animation'),
  (['documentar'], 'Documentary'),
  (['science fiction', 'sci fi', 'scifi'], 'Science Fiction'),
  (['fantasy'], 'Fantasy'),
  (['horror'], 'Horror'),
  (['thriller', 'suspense'], 'Thriller'),
  (['crime'], 'Crime'),
  (['myster'], 'Mystery'),
  (['war'], 'War'),
  (['western'], 'Western'),
  (['romance', 'romantic'], 'Romance'),
  (['comed', 'sitcom'], 'Comedy'),
  (['action'], 'Action'),
  (['adventure'], 'Adventure'),
  (['family'], 'Family'),
  (['music'], 'Music'),
  (['histor'], 'History'),
  (['drama'], 'Drama'),
];

const List<_Rule> _seriesOnlyRules = [
  (['reality'], 'Reality'),
  (['children', 'kids'], 'Kids'),
  (['news'], 'News'),
  (['talk'], 'Talk'),
];

const List<_Rule> _bookRules = [
  (['young adult'], 'Young Adult'),
  (['juvenile', 'children'], "Children's"),
  (['graphic novel', 'comic'], 'Comics & Graphic Novels'),
  (['true crime'], 'True Crime'),
  (['science fiction', 'sci fi'], 'Science Fiction'),
  (['fantasy'], 'Fantasy'),
  (['historical fiction'], 'Historical Fiction'),
  (['horror'], 'Horror'),
  (['thriller', 'suspense'], 'Thriller'),
  (['mystery', 'detective', 'crime'], 'Mystery & Crime'),
  (['romance', 'love stor'], 'Romance'),
  (['biograph', 'autobiograph', 'memoir'], 'Biography & Memoir'),
  (['self help'], 'Self-Help'),
  (['business', 'economics'], 'Business'),
  (['philosoph'], 'Philosophy'),
  (['poetry'], 'Poetry'),
  (['travel'], 'Travel'),
  (['histor'], 'History'),
  (['science'], 'Science'),
  (['literary', 'classics'], 'Literary Fiction'),
  (['non fiction', 'nonfiction'], 'Non-fiction'),
  (['fiction'], 'Fiction'),
];

final RegExp _nonLetters = RegExp(r'[^a-z0-9]+');

String _normalise(String s) =>
    ' ${cleanText(s).toLowerCase().replaceAll(_nonLetters, ' ').trim()} ';

bool _hasKeyword(String normalised, String keyword) =>
    normalised.contains(' $keyword');

/// Returns a curated genre, the first raw genre (where sensible), or
/// [kUncategorised].
String mapGenre(MediaCategory category, Iterable<String> raw) {
  final names = [
    for (final r in raw)
      if (cleanText(r).isNotEmpty && r.toLowerCase() != 'podcasts')
        cleanText(r, maxLength: 40),
  ];
  if (names.isEmpty) return kUncategorised;

  // 1. Keyword rules in priority order.
  final rules = switch (category) {
    MediaCategory.movie => _screenRules,
    MediaCategory.series => [..._seriesOnlyRules, ..._screenRules],
    MediaCategory.book || MediaCategory.audiobook => _bookRules,
    MediaCategory.podcast => const <_Rule>[],
  };
  final normalised = [for (final n in names) _normalise(n)];
  for (final (keywords, genre) in rules) {
    for (final n in normalised) {
      if (keywords.any((k) => _hasKeyword(n, k))) return genre;
    }
  }

  // 2. Exact (case-insensitive) match with a curated name.
  final curated = curatedGenres(category);
  for (final n in names) {
    for (final c in curated) {
      if (c.toLowerCase() == n.toLowerCase()) return c;
    }
  }

  // 3. Book subjects are too messy to show raw; others are usually fine.
  if (category == MediaCategory.book || category == MediaCategory.audiobook) {
    return kUncategorised;
  }
  return names.first;
}
