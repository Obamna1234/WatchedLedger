import '../core/sanitise.dart';
import 'models.dart';

/// What we could read from text shared into the app from another app.
class SharedTitle {
  const SharedTitle(this.title, {this.category, this.year});
  final String title;
  final MediaCategory? category;
  final int? year;

  /// "Heat 1995" so the lookup picks the right version.
  String get query => year == null ? title : '$title $year';

  @override
  String toString() => 'SharedTitle($title, $category, $year)';
}

final RegExp _url = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);
final RegExp _yearSuffix =
    RegExp(r'\s*\(((?:18|19|20)\d{2})(?:[–-]\s*(?:\d{4})?)?\)\s*$');
final RegExp _tvYears = RegExp(
    r'\((?:TV Series|TV Mini Series)\s+((?:19|20)\d{2})[^)]*\)',
    caseSensitive: false);

// Phrases apps wrap around the title when sharing.
final List<RegExp> _noise = [
  RegExp(r'^(?:check out|watch|i(?:\x27|’)m (?:watching|reading|listening to)|'
      r'listen to|look at|have you seen|i want to (?:read|watch))\s+',
      caseSensitive: false),
  RegExp(r'\s+(?:on|at|via) (?:netflix|prime video|disney\+|hbo max|max|'
      r'apple tv\+?|hulu|imdb|goodreads|spotify|apple podcasts|pocket casts|'
      r'overcast|audible|letterboxd|youtube)\b.*$', caseSensitive: false),
  RegExp(r'\s*[-|–—:]\s*(?:imdb|goodreads|netflix|letterboxd|audible\.?\w*|'
      r'apple podcasts|spotify|wikipedia|rotten tomatoes)\s*$',
      caseSensitive: false),
  RegExp(r'\s*[⭐★]\s*[\d.]+(?:/10)?.*$'),
];
final RegExp _byAuthor =
    RegExp(r'\s+by\s+([^,|–—]+?)\s*$', caseSensitive: false);

MediaCategory? _categoryFromHost(Uri u) {
  final host = u.host.toLowerCase();
  final path = u.path.toLowerCase();
  bool on(String d) => host == d || host.endsWith('.$d');
  if (on('goodreads.com') || on('openlibrary.org') || on('storygraph.com') ||
      on('thestorygraph.com')) {
    return MediaCategory.book;
  }
  if (on('audible.com') || on('audible.co.uk') || on('libro.fm')) {
    return MediaCategory.audiobook;
  }
  if (on('podcasts.apple.com') || on('pca.st') || on('overcast.fm') ||
      on('pocketcasts.com') || (on('spotify.com') && path.contains('/show')) ||
      (on('spotify.com') && path.contains('/episode'))) {
    return MediaCategory.podcast;
  }
  if (on('store.steampowered.com') || on('steamcommunity.com') ||
      on('playstation.com') || on('xbox.com') || on('nintendo.com') ||
      on('epicgames.com') || on('gog.com') || on('itch.io')) {
    return MediaCategory.game;
  }
  if (on('letterboxd.com') || on('boxd.it')) return MediaCategory.movie;
  if (on('tvmaze.com') || on('trakt.tv') && path.startsWith('/shows')) {
    return MediaCategory.series;
  }
  if (on('trakt.tv') && path.startsWith('/movies')) return MediaCategory.movie;
  return null;
}

/// Title-ish text from a link's path, e.g.
/// goodreads.com/book/show/44767458-dune → "dune".
String? _slugTitle(Uri u) {
  final segments = [
    for (final s in u.pathSegments)
      if (s.isNotEmpty) s,
  ];
  for (final s in segments.reversed) {
    final cleaned = s
        .replaceFirst(RegExp(r'^\d+[-._]'), '')
        .replaceFirst(RegExp(r'\.\w{2,4}$'), '');
    if (RegExp(r'^(?:tt|id)?\d+$').hasMatch(cleaned)) continue;
    if (!cleaned.contains(RegExp(r'[a-zA-Z]{3}'))) continue;
    if (const {'show', 'book', 'title', 'film', 'shows', 'movies', 'podcast',
        'episode', 'pd', 'en', 'us', 'gb'}.contains(cleaned.toLowerCase())) {
      continue;
    }
    return cleaned.replaceAll(RegExp(r'[-_+]+'), ' ');
  }
  return null;
}

/// Reads a title (and category, if obvious) from shared text such as
/// "Heat (1995) - IMDb https://www.imdb.com/title/tt0113277/" or
/// "Check out Dune by Frank Herbert https://www.goodreads.com/book/show/...".
/// Nothing is fetched; returns null if no title can be found.
SharedTitle? parseShared(String raw) {
  final text = raw.length > 4000 ? raw.substring(0, 4000) : raw;
  MediaCategory? category;
  Uri? firstUrl;
  for (final m in _url.allMatches(text)) {
    final u = Uri.tryParse(m.group(0)!);
    if (u == null) continue;
    firstUrl ??= u;
    category ??= _categoryFromHost(u);
  }
  if (_tvYears.hasMatch(text)) category ??= MediaCategory.series;

  final lines = [
    for (final l in text.replaceAll(_url, '\n').split('\n'))
      if (cleanText(l).isNotEmpty) cleanText(l),
  ];
  String? title;
  int? year = int.tryParse(_tvYears.firstMatch(text)?.group(1) ?? '');
  for (final line in lines) {
    var t = line.replaceAll(_tvYears, '');
    t = t.replaceAll(RegExp(r'^["“”]+|["“”]+$'), '');
    for (final n in _noise) {
      t = t.replaceFirst(n, '');
    }
    final y = _yearSuffix.firstMatch(t);
    if (y != null) {
      year ??= int.tryParse(y.group(1)!);
      t = t.substring(0, y.start);
    }
    if (category == MediaCategory.book || category == MediaCategory.audiobook) {
      t = t.replaceFirst(_byAuthor, '');
    }
    t = cleanTitle(t.replaceAll(RegExp(r'^["“”]+|["“”]+$'), ''));
    if (t.length >= 2) {
      title = t;
      break;
    }
  }
  if (title == null && firstUrl != null) {
    final slug = _slugTitle(firstUrl);
    if (slug != null) title = cleanTitle(slug);
  }
  if (title == null || title.isEmpty) return null;
  return SharedTitle(title, category: category, year: year);
}
