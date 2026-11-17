import 'dart:convert';

import '../../core/sanitise.dart';
import '../models.dart';
import 'csv.dart';
import 'export.dart' show csvHeader;

/// One title found in pasted text or an imported file, before lookup.
class ImportRow {
  ImportRow({
    required this.title,
    this.category,
    this.status = ListStatus.todo,
    this.year,
    this.rating,
    this.note,
    this.finished,
    this.creator,
    this.runtimeMinutes,
    this.pages,
    this.season,
    this.episode,
    List<String>? tags,
  }) : tags = tags ?? [];

  String title;
  MediaCategory? category;
  ListStatus status;
  int? year;
  int? rating; // 1-5
  String? note;
  DateTime? finished;
  String? creator;
  int? runtimeMinutes;
  int? pages;
  int? season;
  int? episode;
  final List<String> tags;

  /// Text used for the lookup ("Heat 1995" picks the right version).
  String get query => year == null ? title : '$title $year';

  @override
  String toString() => 'ImportRow($title, $category, $status, $year)';
}

enum ImportFormat {
  lines,
  watchedLedgerText,
  watchedLedgerCsv,
  letterboxd,
  goodreads,
  imdb,
  trakt,
  genericCsv,
}

extension ImportFormatLabel on ImportFormat {
  String get label => switch (this) {
        ImportFormat.lines => 'List of titles',
        ImportFormat.watchedLedgerText => 'WatchedLedger text export',
        ImportFormat.watchedLedgerCsv => 'WatchedLedger spreadsheet',
        ImportFormat.letterboxd => 'Letterboxd export',
        ImportFormat.goodreads => 'Goodreads export',
        ImportFormat.imdb => 'IMDb export',
        ImportFormat.trakt => 'Trakt export',
        ImportFormat.genericCsv => 'Spreadsheet (CSV)',
      };
}

class ImportParseResult {
  const ImportParseResult(this.format, this.rows);
  final ImportFormat format;
  final List<ImportRow> rows;
}

const int maxImportRows = 5000;
const int _maxNote = kMaxNoteLength;

/// Works out what kind of text/file this is and reads every title from it.
ImportParseResult parseImport(String text, {String? fileName}) {
  final name = (fileName ?? '').toLowerCase();
  final trimmed = text.trimLeft();
  if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
    final trakt = _tryTrakt(trimmed, name);
    if (trakt != null) return ImportParseResult(ImportFormat.trakt, trakt);
  }
  if (name.endsWith('.csv') || _looksLikeCsv(text)) {
    final rows = parseCsv(text);
    if (rows.length >= 2) {
      final header = [for (final h in rows.first) h.trim().toLowerCase()];
      final body = rows.skip(1).take(maxImportRows).toList();
      final r = _fromCsv(header, body, name);
      if (r != null) return r;
    }
  }
  return _fromLines(text);
}

bool _looksLikeCsv(String text) {
  final first = text.split('\n').first.toLowerCase();
  return first.contains(',') &&
      (first.contains('title') || first.contains('name'));
}

// ------------------------------------------------------------- helpers

int? _int(String? s) {
  if (s == null) return null;
  final m = RegExp(r'-?\d+').firstMatch(s);
  return m == null ? null : int.tryParse(m.group(0)!);
}

int? _year(String? s) {
  final y = _int(s);
  if (y == null || y < 1000 || y > DateTime.now().year + 10) return null;
  return y;
}

/// Converts a rating on a [scale] (5 or 10) to whole stars 1-5.
int? _stars(String? s, int scale) {
  if (s == null || s.trim().isEmpty) return null;
  final v = double.tryParse(s.trim());
  if (v == null || v <= 0) return null;
  final stars = (v * 5 / scale).round();
  return stars.clamp(1, 5);
}

DateTime? _date(String? s) {
  if (s == null) return null;
  final t = s.trim();
  if (t.isEmpty) return null;
  final iso = DateTime.tryParse(t.replaceAll('/', '-'));
  if (iso != null) return iso.toLocal();
  // Goodreads style "2023/05/17" is handled above; try "17 May 2023".
  return null;
}

String? _note(String? s) {
  if (s == null) return null;
  final n = cleanText(s.replaceAll(RegExp(r'<[^>]*>'), ' '),
      maxLength: _maxNote);
  return n.isEmpty ? null : n;
}

String _cell(List<String> row, Map<String, int> cols, String name) {
  final i = cols[name];
  if (i == null || i >= row.length) return '';
  return row[i];
}

MediaCategory? _categoryFrom(String s) {
  final v = s.trim().toLowerCase();
  if (v.isEmpty) return null;
  if (v.startsWith('movie') || v.startsWith('film')) return MediaCategory.movie;
  if (v.startsWith('serie') || v.startsWith('tv') || v.startsWith('show')) {
    return MediaCategory.series;
  }
  if (v.startsWith('audio')) return MediaCategory.audiobook;
  if (v.startsWith('book') || v.startsWith('novel')) return MediaCategory.book;
  if (v.startsWith('podcast')) return MediaCategory.podcast;
  for (final c in MediaCategory.values) {
    if (v == c.name) return c;
  }
  return null;
}

ListStatus _statusFrom(String s, {ListStatus fallback = ListStatus.todo}) {
  final v = s.trim().toLowerCase();
  if (v.isEmpty) return fallback;
  const done = ['done', 'watched', 'read', 'listened', 'finished', 'yes',
    'true', 'x', '1', 'completed'];
  return done.contains(v) ? ListStatus.done : ListStatus.todo;
}

// ------------------------------------------------------------------ CSV

ImportParseResult? _fromCsv(
    List<String> header, List<List<String>> body, String fileName) {
  final cols = {for (var i = 0; i < header.length; i++) header[i]: i};
  bool has(List<String> names) => names.every(cols.containsKey);

  // WatchedLedger's own CSV export.
  if (has(csvHeader)) {
    return ImportParseResult(ImportFormat.watchedLedgerCsv, [
      for (final r in body)
        if (cleanTitle(_cell(r, cols, 'title')).isNotEmpty)
          ImportRow(
            title: cleanTitle(_unformula(_cell(r, cols, 'title'))),
            category: _categoryFrom(_cell(r, cols, 'category')),
            status: _statusFrom(_cell(r, cols, 'list')),
            year: _year(_cell(r, cols, 'year')),
            rating: _stars(_cell(r, cols, 'rating'), 5),
            note: _note(_unformula(_cell(r, cols, 'note'))),
            creator: _nonEmpty(_unformula(_cell(r, cols, 'creator'))),
            season: _int(_cell(r, cols, 'season')),
            episode: _int(_cell(r, cols, 'episode')),
            tags: _tags(_cell(r, cols, 'tags')),
            finished: _date(_cell(r, cols, 'finished')),
          ),
    ]);
  }

  // Letterboxd: watched.csv, diary.csv, ratings.csv, reviews.csv,
  // watchlist.csv all have Name + Letterboxd URI.
  if (has(['name', 'year']) && cols.containsKey('letterboxd uri')) {
    final watchlist = fileName.contains('watchlist');
    return ImportParseResult(ImportFormat.letterboxd, [
      for (final r in body)
        if (cleanTitle(_cell(r, cols, 'name')).isNotEmpty)
          ImportRow(
            title: cleanTitle(_cell(r, cols, 'name')),
            category: MediaCategory.movie,
            status: watchlist ? ListStatus.todo : ListStatus.done,
            year: _year(_cell(r, cols, 'year')),
            rating: _stars(_cell(r, cols, 'rating'), 5),
            note: _note(_cell(r, cols, 'review')),
            tags: _tags(_cell(r, cols, 'tags')),
            finished: watchlist
                ? null
                : _date(_cell(r, cols, 'watched date')) ??
                    _date(_cell(r, cols, 'date')),
          ),
    ]);
  }

  // Goodreads library export.
  if (has(['title', 'author']) && cols.containsKey('exclusive shelf')) {
    return ImportParseResult(ImportFormat.goodreads, [
      for (final r in body)
        if (cleanTitle(_cell(r, cols, 'title')).isNotEmpty)
          _goodreadsRow(r, cols),
    ]);
  }

  // IMDb ratings / watchlist / list export.
  if (has(['const', 'title', 'title type'])) {
    return ImportParseResult(ImportFormat.imdb, [
      for (final r in body)
        if (cleanTitle(_cell(r, cols, 'title')).isNotEmpty)
          _imdbRow(r, cols, fileName),
    ]);
  }

  // Any spreadsheet with a title column.
  final titleCol = ['title', 'name', 'titel', 'titre']
      .firstWhere(cols.containsKey, orElse: () => '');
  if (titleCol.isNotEmpty) {
    final statusCol = ['status', 'list', 'watched', 'done', 'read']
        .firstWhere(cols.containsKey, orElse: () => '');
    final catCol = ['category', 'type', 'kind', 'media']
        .firstWhere(cols.containsKey, orElse: () => '');
    return ImportParseResult(ImportFormat.genericCsv, [
      for (final r in body)
        if (cleanTitle(_cell(r, cols, titleCol)).isNotEmpty)
          ImportRow(
            title: cleanTitle(_unformula(_cell(r, cols, titleCol))),
            category: catCol.isEmpty ? null : _categoryFrom(_cell(r, cols, catCol)),
            status: statusCol.isEmpty
                ? ListStatus.todo
                : _statusFrom(_cell(r, cols, statusCol)),
            year: _year(_cell(r, cols, 'year')),
            rating: _stars(_cell(r, cols, 'rating'), 5),
            note: _note(_cell(r, cols, 'note')),
          ),
    ]);
  }
  return null;
}

String _unformula(String s) => s.startsWith("'=") ||
        s.startsWith("'+") ||
        s.startsWith("'-") ||
        s.startsWith("'@")
    ? s.substring(1)
    : s;

String? _nonEmpty(String s) {
  final c = cleanText(s);
  return c.isEmpty ? null : c;
}

List<String> _tags(String s) => [
      for (final t in s.split(RegExp(r'[;,]')))
        if (cleanText(t, maxLength: 40).isNotEmpty) cleanText(t, maxLength: 40),
    ];

final RegExp _seriesSuffix = RegExp(r'\s*\([^()]*#\s*[\d.]+\)\s*$');

ImportRow _goodreadsRow(List<String> r, Map<String, int> cols) {
  final shelf = _cell(r, cols, 'exclusive shelf').trim().toLowerCase();
  final binding = _cell(r, cols, 'binding').toLowerCase();
  final rawTitle = cleanTitle(_cell(r, cols, 'title'));
  final title = rawTitle.replaceFirst(_seriesSuffix, '').trim();
  return ImportRow(
    title: title.isEmpty ? rawTitle : title,
    category: binding.contains('audio')
        ? MediaCategory.audiobook
        : MediaCategory.book,
    status: shelf == 'read' ? ListStatus.done : ListStatus.todo,
    year: _year(_cell(r, cols, 'original publication year')) ??
        _year(_cell(r, cols, 'year published')),
    rating: _stars(_cell(r, cols, 'my rating'), 5),
    note: _note(_cell(r, cols, 'my review')),
    creator: _nonEmpty(_cell(r, cols, 'author')),
    pages: _int(_cell(r, cols, 'number of pages')),
    finished: shelf == 'read' ? _date(_cell(r, cols, 'date read')) : null,
    tags: [
      if (shelf == 'currently-reading') 'currently reading',
      for (final s in _cell(r, cols, 'bookshelves').split(','))
        if (s.trim().isNotEmpty &&
            !const ['read', 'to-read', 'currently-reading'].contains(s.trim()))
          cleanText(s, maxLength: 40),
    ],
  );
}

ImportRow _imdbRow(List<String> r, Map<String, int> cols, String fileName) {
  final type = _cell(r, cols, 'title type').toLowerCase();
  final rated = _cell(r, cols, 'your rating').trim().isNotEmpty;
  final watchlist = fileName.contains('watchlist');
  final done = rated && !watchlist;
  return ImportRow(
    title: cleanTitle(_cell(r, cols, 'title')),
    category: type.contains('series') || type.contains('episode')
        ? MediaCategory.series
        : MediaCategory.movie,
    status: done ? ListStatus.done : ListStatus.todo,
    year: _year(_cell(r, cols, 'year')),
    rating: _stars(_cell(r, cols, 'your rating'), 10),
    creator: _nonEmpty(_cell(r, cols, 'directors')),
    runtimeMinutes: _int(_cell(r, cols, 'runtime (mins)')),
    finished: done ? _date(_cell(r, cols, 'date rated')) : null,
  );
}

// ---------------------------------------------------------------- Trakt

List<ImportRow>? _tryTrakt(String text, String fileName) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } catch (_) {
    return null;
  }
  if (json is! List || json.isEmpty) return null;
  final rows = <ImportRow>[];
  final watchlist = fileName.contains('watchlist');
  for (final e in json.take(maxImportRows)) {
    if (e is! Map) continue;
    final movie = e['movie'], show = e['show'];
    final media = movie is Map ? movie : (show is Map ? show : null);
    if (media == null) continue;
    final title = media['title'];
    if (title is! String || cleanTitle(title).isEmpty) continue;
    final when = e['last_watched_at'] ?? e['watched_at'] ?? e['rated_at'];
    final listed = e.containsKey('listed_at') || watchlist;
    final done = !listed && (when != null || e['plays'] != null);
    final rating = e['rating'];
    rows.add(ImportRow(
      title: cleanTitle(title),
      category: movie is Map ? MediaCategory.movie : MediaCategory.series,
      status: done ? ListStatus.done : ListStatus.todo,
      year: media['year'] is int ? _year('${media['year']}') : null,
      rating: rating is num ? _stars('$rating', 10) : null,
      finished: done && when is String ? _date(when) : null,
    ));
  }
  return rows.isEmpty ? null : rows;
}

// ---------------------------------------------- plain lines / Samsung Notes

// Markers that mean "already done" at the start of a line.
final RegExp _doneMarker = RegExp(
    r'^\s*(?:[-*•]\s*)?(?:\[[xX✓✔]\]|\([xX]\)|'
    r'[☑☒✅✓✔✖✗✘])\s*');
// Markers that mean "not done yet" (empty boxes, bullets, numbering).
final RegExp _todoMarker = RegExp(
    r'^\s*(?:[-*•◦▪○◯]\s*)?(?:\[\s?\]|\(\s?\)|'
    r'[☐□◻⬜])?\s*(?:\d{1,4}[.)]\s+)?');
final RegExp _strike = RegExp('[\u0335\u0336\u0337\u0338]');
final RegExp _markdownStrike = RegExp(r'^~~(.+)~~$');
final RegExp _trailingDone =
    RegExp(r'\s*(?:[✓✔✅]|\((?:done|watched|read|seen)\))\s*$',
        caseSensitive: false);
final RegExp _yearInBrackets = RegExp(r'\s*\(((?:18|19|20)\d{2})\)\s*$');
final RegExp _heading = RegExp(
    r'^\s*(movies?|films?|series|tv(?: shows?)?|shows?|books?|audiobooks?|'
    r'podcasts?)\b(?:\s*[-:]\s*(to (?:watch|read|listen)|watched|read|listened))?\s*:?\s*$',
    caseSensitive: false);
// Our own text export: "[x] Heat (1995) ★★★★ - Watched March 2026 - "note""
final RegExp _ourExtras = RegExp(
    r'(\s*\((?:18|19|20)\d{2}\))?(\s*★{1,5})?(\s+-\s+(?:Watched|Read|Listened) \w+ \d{4})?(\s+-\s+"(.*)")?\s*$');

ImportParseResult _fromLines(String text) {
  final rows = <ImportRow>[];
  MediaCategory? category;
  ListStatus? sectionStatus;
  var sawOurHeader = false;
  for (final rawLine in const LineSplitter().convert(text)) {
    if (rows.length >= maxImportRows) break;
    var line = rawLine.replaceAll('\t', ' ');
    if (line.trim().isEmpty) continue;
    if (line.startsWith('WatchedLedger export')) {
      sawOurHeader = true;
      continue;
    }

    final h = _heading.firstMatch(line);
    if (h != null) {
      category = _categoryFrom(h.group(1)!);
      final s = h.group(2)?.toLowerCase();
      sectionStatus = s == null
          ? null
          : (s.startsWith('to ') ? ListStatus.todo : ListStatus.done);
      continue;
    }

    var done = false;
    if (_strike.hasMatch(line)) {
      done = true;
      line = line.replaceAll(_strike, '');
    }
    final dm = _doneMarker.firstMatch(line);
    if (dm != null) {
      done = true;
      line = line.substring(dm.end);
    } else {
      final tm = _todoMarker.firstMatch(line);
      if (tm != null) line = line.substring(tm.end);
    }
    final md = _markdownStrike.firstMatch(line.trim());
    if (md != null) {
      done = true;
      line = md.group(1)!;
    }
    if (_trailingDone.hasMatch(line)) {
      done = true;
      line = line.replaceFirst(_trailingDone, '');
    }

    int? year;
    int? rating;
    String? note;
    final extras = _ourExtras.firstMatch(line);
    if (sawOurHeader && extras != null && extras.start > 0) {
      year = _year(extras.group(1));
      rating = extras.group(2)?.trim().length;
      note = _note(extras.group(5));
      line = line.substring(0, extras.start);
    } else {
      final ym = _yearInBrackets.firstMatch(line);
      if (ym != null) {
        year = _year(ym.group(1));
        line = line.substring(0, ym.start);
      }
    }

    final title = cleanTitle(line);
    if (title.isEmpty) continue;
    rows.add(ImportRow(
      title: title,
      category: category,
      status: done ? ListStatus.done : (sectionStatus ?? ListStatus.todo),
      year: year,
      rating: rating,
      note: note,
    ));
  }
  return ImportParseResult(
    sawOurHeader ? ImportFormat.watchedLedgerText : ImportFormat.lines,
    rows,
  );
}
