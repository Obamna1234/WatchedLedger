import 'dart:convert';
import 'dart:typed_data';

import '../../core/sanitise.dart';
import '../models.dart';
import 'csv.dart';
import 'export.dart' show csvHeader;
import 'samsung_notes.dart' show NoteLine;

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
    this.group,
    this.statusSure = true,
    this.recommendedBy,
    this.whereToWatch,
    this.upcoming = false,
    this.link,
    List<String>? watchWith,
    List<String>? tags,
    Map<int, bool>? seasons,
  })  : tags = tags ?? [],
        seasons = seasons ?? {},
        watchWith = watchWith ?? [];

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

  /// The heading this came under in a note (for the check screen).
  String? group;

  /// False when nothing said whether it was watched (no tick, marker or
  /// heading); the check screen asks the user to confirm those.
  bool statusSure;

  String? recommendedBy;
  String? whereToWatch;
  String? link;
  bool upcoming;
  final List<String> watchWith;

  /// Seasons mentioned for a series ("Mo season 1" ✓) -> watched or not.
  final Map<int, bool> seasons;

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
  samsungNotes,
  sharedFolder,
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
        ImportFormat.samsungNotes => 'Samsung Notes file',
        ImportFormat.sharedFolder => 'Folder shared from WatchedLedger',
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
  final r = _parseImport(text, fileName: fileName);
  return ImportParseResult(
      r.format, mergeSeasons([for (final row in r.rows) readHints(row)]));
}

ImportParseResult _parseImport(String text, {String? fileName}) {
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
  if (v.contains('game')) return MediaCategory.game;
  if (v.startsWith('video') || v.contains('youtube')) {
    return MediaCategory.video;
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
  const done = ['done', 'watched', 'read', 'listened', 'played', 'finished',
    'yes',
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
            statusSure: statusCol.isNotEmpty,
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
    r'podcasts?|(?:video )?games?)\b(?:\s*[-:]\s*(to (?:watch|read|listen|play)|'
    r'watched|read|listened|played))?\s*:?\s*$',
    caseSensitive: false);
// Our own text export: "[x] Heat (1995) ★★★★ - Watched March 2026 - "note""
final RegExp _ourExtras = RegExp(
    r'(\s*\((?:18|19|20)\d{2}\))?(\s*★{1,5})?(\s+-\s+(?:Watched|Read|Listened|Played) \w+ \d{4})?(\s+-\s+"(.*)")?\s*$');

final RegExp _folderHeader =
    RegExp(r'^\s*"(.{1,60})"\s*\(from WatchedLedger\)\s*$');
final RegExp _bareLink = RegExp(r'^https?://\S+$');

/// One line of a shared folder: "• Title (2014) · movie · on Netflix · link".
ImportRow? _folderLine(String line, String folder) {
  final t = line.replaceFirst(RegExp(r'^\s*[\u2022*-]\s*'), '');
  final parts = [for (final p in t.split(' \u00B7 ')) p.trim()];
  if (parts.isEmpty) return null;
  var title = parts.first;
  int? year;
  final ym = _yearInBrackets.firstMatch(title);
  if (ym != null) {
    year = _year(ym.group(1));
    title = title.substring(0, ym.start);
  }
  MediaCategory? category;
  String? where, link;
  for (final p in parts.skip(1)) {
    if (_bareLink.hasMatch(p)) {
      link = cleanLink(p);
    } else if (p.startsWith('on ')) {
      where = cleanText(p.substring(3), maxLength: 60);
    } else {
      category ??= MediaCategory.values
          .where((c) => c.singular == p.toLowerCase())
          .firstOrNull;
    }
  }
  final clean = cleanTitle(title);
  if (clean.isEmpty) return null;
  return ImportRow(
    title: clean,
    category: category,
    year: year,
    whereToWatch: where,
    link: link,
    group: folder,
    tags: [folder],
  );
}

ImportParseResult _fromLines(String text) {
  final rows = <ImportRow>[];
  MediaCategory? category;
  ListStatus? sectionStatus;
  String? group;
  var sawOurHeader = false;
  String? folder;
  for (final rawLine in const LineSplitter().convert(text)) {
    if (rows.length >= maxImportRows) break;
    var line = rawLine.replaceAll('\t', ' ');
    if (line.trim().isEmpty) continue;
    final fh = _folderHeader.firstMatch(line);
    if (fh != null) {
      folder = cleanText(fh.group(1)!, maxLength: 40);
      continue;
    }
    if (line.startsWith('Shared from WatchedLedger')) continue;
    if (folder != null) {
      final row = _folderLine(line, folder);
      if (row != null) rows.add(row);
      continue;
    }
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
      group = cleanText(line);
      continue;
    }
    final sh = statusHeading(line);
    if (sh != null) {
      sectionStatus = sh.status;
      if (sh.category != null) category = sh.category;
      group = cleanText(line);
      continue;
    }

    final boxed = _emptyBox.hasMatch(line);
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
      group: group,
      statusSure: done || boxed || sectionStatus != null || sawOurHeader,
    ));
  }
  return ImportParseResult(
    folder != null
        ? ImportFormat.sharedFolder
        : sawOurHeader
            ? ImportFormat.watchedLedgerText
            : ImportFormat.lines,
    rows,
  );
}


// ------------------------------------------------- headings and seasons

final RegExp _emptyBox = RegExp(
    r'^\s*(?:[-*•]\s*)?(?:\[\s?\]|\(\s?\)|[☐□◻⬜])');

const String _kinds =
    r'(movies?|films?|series|tv(?: shows?)?|shows?|books?|audiobooks?|'
    r'podcasts?|(?:video )?games?)';
final RegExp _doneWords = RegExp(
    r"^(?:already |have |i've |ive )?(?:watched|seen|done|finished|completed|"
    r'read|played|listened(?: to)?|watched list|seen it)$',
    caseSensitive: false);
final RegExp _todoWords = RegExp(
    r'^(?:to[ -]?(?:watch|read|play|listen(?: to)?|see)|watch ?list|'
    r'want to (?:watch|read|play|see|listen to)|not (?:yet )?'
    r'(?:watched|seen|read|played)|unwatched|unread|unplayed|later|'
    r'watch later|backlog|wish ?list|queue|up next|next up|to do|todo|'
    r'plan to (?:watch|read|play))$',
    caseSensitive: false);
final RegExp _statusHeadingShape = RegExp(
    '^\\s*#*\\s*(?:$_kinds\\s*[-:]?\\s*)?(.+?)(?:\\s*[-:]?\\s*$_kinds)?\\s*:?\\s*\$',
    caseSensitive: false);

/// "Watched:", "To watch", "Movies - seen", "Watchlist (games)" and similar
/// headings that say which list the lines below belong to.
({ListStatus status, MediaCategory? category})? statusHeading(String line) {
  final t = cleanText(line).replaceAll(RegExp(r'[()\[\]]'), ' ').trim();
  if (t.isEmpty || t.length > 40) return null;
  final m = _statusHeadingShape.firstMatch(t);
  if (m == null) return null;
  final words = m.group(2)!.trim();
  final kind = m.group(1) ?? m.group(3);
  final category = kind == null ? null : _categoryFrom(kind);
  if (_doneWords.hasMatch(words)) {
    return (status: ListStatus.done, category: category);
  }
  if (_todoWords.hasMatch(words)) {
    return (status: ListStatus.todo, category: category);
  }
  return null;
}

final RegExp _seasonInTitle = RegExp(
    r'^(.{2,}?)[\s,(\-–:]*\bseason\s*(\d{1,2})\b[\s)]*[,;:\-–]?\s*(.*)$',
    caseSensitive: false);

/// "Mo season 1" ✓ + "Mo season 2 (waiting)" -> one series "Mo" with
/// season 1 watched and season 2 not. The show itself stays on the To Watch
/// list (only some seasons are known to be watched).
List<ImportRow> mergeSeasons(List<ImportRow> rows) {
  final out = <ImportRow>[];
  final byKey = <String, ImportRow>{};
  for (final r in rows) {
    final c = r.category;
    final m = c == null ||
            c == MediaCategory.series ||
            c == MediaCategory.movie
        ? _seasonInTitle.firstMatch(r.title)
        : null;
    final base = m == null ? '' : cleanTitle(m.group(1)!);
    if (m == null || base.length < 2) {
      out.add(r);
      continue;
    }
    final season = int.parse(m.group(2)!);
    final rest = cleanText(m.group(3)!
        .replaceAll(RegExp(r'^[\s()]+|[\s()]+$'), ''));
    final key = matchKey(base);
    final existing = byKey[key];
    if (existing != null) {
      existing.seasons[season] =
          (existing.seasons[season] ?? false) || r.status == ListStatus.done;
      existing.statusSure = existing.statusSure && r.statusSure;
      final extra = [if (r.note != null) r.note!, if (rest.isNotEmpty) rest];
      if (extra.isNotEmpty) {
        existing.note = _note(
            [if (existing.note != null) existing.note!, ...extra].join('; '));
      }
      continue;
    }
    final merged = ImportRow(
      title: base,
      category: MediaCategory.series,
      status: ListStatus.todo,
      year: r.year,
      rating: r.rating,
      note: _note([if (r.note != null) r.note!, if (rest.isNotEmpty) rest]
          .join('; ')),
      creator: r.creator,
      group: r.group,
      statusSure: r.statusSure,
      tags: r.tags,
      seasons: {season: r.status == ListStatus.done},
      recommendedBy: r.recommendedBy,
      whereToWatch: r.whereToWatch,
      upcoming: r.upcoming,
      watchWith: [...r.watchWith],
    );
    byKey[key] = merged;
    out.add(merged);
  }
  return out;
}

// ------------------------------------------------------- Samsung Notes

/// The one category a heading names ("Drama Series" -> series), or null
/// if it names none or several ("Movies/Series").
MediaCategory? _categoryInText(String text) {
  final t = text.toLowerCase();
  final hits = <MediaCategory>{
    if (RegExp(r'\b(?:movies?|films?)\b').hasMatch(t)) MediaCategory.movie,
    if (RegExp(r'\b(?:series|tv shows?)\b').hasMatch(t)) MediaCategory.series,
    if (RegExp(r'\baudio ?books?\b').hasMatch(t)) MediaCategory.audiobook,
    if (RegExp(r'(?<!audio ?)\bbooks?\b').hasMatch(t)) MediaCategory.book,
    if (RegExp(r'\bpodcasts?\b').hasMatch(t)) MediaCategory.podcast,
    if (RegExp(r'\bgames?\b').hasMatch(t)) MediaCategory.game,
    if (RegExp(r'\b(?:videos?|youtube)\b(?! ?games?)').hasMatch(t))
      MediaCategory.video,
  };
  return hits.length == 1 ? hits.single : null;
}

final RegExp _bracketNote = RegExp(r'\s*\(([^()]{2,120})\)?\s*$');

/// Turns a Samsung Notes note into import rows.
/// - Tick boxes: ticked = watched, unticked = not yet (certain).
/// - Plain lines: a trailing "@" means watched, a leading "-" means not yet.
/// - Headings ("Action movies", "WATCHED", "To watch") set the category
///   and/or list for the lines below them; "MOVIES"-style headings in
///   capitals start a new section.
/// - Comments in brackets become the item's note, so the lookup gets the
///   plain title.
List<ImportRow> rowsFromNote(List<NoteLine> lines) {
  final rows = <ImportRow>[];
  MediaCategory? section, sub;
  ListStatus? groupStatus;
  String? group;

  int? nextNonEmpty(int i) {
    for (var k = i + 1; k < lines.length; k++) {
      if (lines[k].text.trim().isNotEmpty) return k;
    }
    return null;
  }

  for (var i = 0; i < lines.length && rows.length < maxImportRows; i++) {
    final line = lines[i];
    var t = cleanText(line.text.replaceAll('￼', ' '));
    if (t.isEmpty || RegExp(r'^[_\-=*~.\s]+$').hasMatch(t)) continue;

    var done = line.checkbox ? line.checked : null;
    if (t.endsWith('@')) {
      done = true;
      t = t.substring(0, t.length - 1).trim();
    }
    final dash = t.startsWith('-');
    if (dash) t = t.substring(1).trim();

    if (!line.checkbox && done == null && !dash) {
      if (t.length > 150) continue; // a long comment, not a title
      final next = nextNonEmpty(i);
      final afterBlank = i == 0 || lines[i - 1].text.trim().isEmpty;
      final startsBlock = afterBlank && next != null && lines[next].checkbox;
      final sh = statusHeading(t);
      final kind = _categoryInText(t);
      final isSection = t.length > 2 &&
          t == t.toUpperCase() &&
          RegExp('[A-Z]').hasMatch(t) &&
          !t.contains(' ');
      final firstLine = rows.isEmpty && group == null;
      if (sh != null ||
          isSection ||
          (kind != null && afterBlank) ||
          t.endsWith(':') ||
          startsBlock ||
          firstLine) {
        group = t.replaceAll(RegExp(r':$'), '');
        if (sh != null) {
          groupStatus = sh.status;
          if (sh.category != null) sub = sh.category;
        } else if (isSection) {
          section = kind;
          sub = null;
          groupStatus = null;
        } else {
          sub = kind;
          groupStatus = null;
        }
        continue;
      }
    }

    String? note;
    final b = _bracketNote.firstMatch(t);
    if (b != null && b.start > 1 && _year(b.group(1)) == null) {
      note = b.group(1);
      t = t.substring(0, b.start);
    }
    final title = cleanTitle(t);
    if (title.isEmpty) continue;

    var category = sub ?? section;
    // "... series" / "... season 2" in a mixed list is a series.
    final hint = _categoryInText(title);
    if (category != MediaCategory.book &&
        category != MediaCategory.podcast &&
        category != MediaCategory.game &&
        (hint == MediaCategory.series ||
            RegExp(r'\bseason\s*\d', caseSensitive: false).hasMatch(title))) {
      category = MediaCategory.series;
    }

    final status = done == null
        ? (groupStatus ?? ListStatus.todo)
        : (done ? ListStatus.done : ListStatus.todo);
    rows.add(readHints(ImportRow(
      title: title,
      category: category,
      status: status,
      note: _note(note),
      group: group,
      statusSure: done != null || dash || groupStatus != null,
    )));
  }
  return mergeSeasons(rows);
}

// ------------------------------------------------------------ text files

/// Reads a text file in UTF-8 or UTF-16 (Windows Notepad's "Unicode").
/// Returns null for files that aren't text (images, Word files, PDFs).
String? decodeImportText(Uint8List bytes) {
  if (bytes.isEmpty) return '';
  String text;
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    text = _utf16(bytes, 2, little: true);
  } else if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    text = _utf16(bytes, 2, little: false);
  } else if (_looksUtf16Le(bytes)) {
    text = _utf16(bytes, 0, little: true);
  } else {
    final start = bytes.length >= 3 &&
            bytes[0] == 0xEF &&
            bytes[1] == 0xBB &&
            bytes[2] == 0xBF
        ? 3
        : 0;
    text = utf8.decode(Uint8List.sublistView(bytes, start),
        allowMalformed: true);
  }
  // Text files don't contain NUL; binary files nearly always do.
  if (text.contains('\u0000')) return null;
  // Lots of replacement characters = not really text.
  final bad = '�'.allMatches(text).length;
  if (text.length > 20 && bad > text.length ~/ 20) return null;
  return text;
}

bool _looksUtf16Le(Uint8List b) {
  final n = b.length < 400 ? b.length - b.length % 2 : 400;
  if (n < 4) return false;
  var zeroOdd = 0;
  for (var i = 1; i < n; i += 2) {
    if (b[i] == 0) zeroOdd++;
  }
  return zeroOdd > n ~/ 2 * 0.7;
}

String _utf16(Uint8List b, int start, {required bool little}) {
  final data = ByteData.sublistView(b);
  final units = <int>[
    for (var i = start; i + 1 < b.length; i += 2)
      data.getUint16(i, little ? Endian.little : Endian.big),
  ];
  return String.fromCharCodes(units);
}

// ------------------------------------------------------ hints in notes

final RegExp _recommendation = RegExp(
    r"(?:^|[\s,;(])(?:recommended by|suggested by|rec(?:ommended)?\.? by)\s+([^,;()]{2,40})|"
    r"(?:^|[\s,;(])([A-Za-z][\w' .-]{1,40}?)\s*(?:'s)?\s+(?:recommendation|recommends?|recommended|suggestion)\b",
    caseSensitive: false);
final RegExp _watchWith = RegExp(
    r"\b(?:watch|read|play|listen)(?:ing)? (?:it )?with\s+([A-Za-z][\w'-]{1,30}(?:\s+and\s+[A-Za-z][\w'-]{1,30})?)",
    caseSensitive: false);
final RegExp _upcomingWords = RegExp(
    r'waiting (?:for it )?to (?:get )?(?:be )?release|not (?:out|released) yet|'
    r'coming soon|unreleased|upcoming|comes out|releas(?:es|ing) (?:in|on|next)',
    caseSensitive: false);
const Map<String, String> _services = {
  'netflix': 'Netflix', 'stan': 'Stan', 'plex': 'Plex', 'binge': 'Binge',
  'foxtel': 'Foxtel', 'prime video': 'Prime Video', 'amazon prime': 'Prime Video',
  'disney+': 'Disney+', 'disney plus': 'Disney+', 'youtube': 'YouTube',
  'steam': 'Steam', 'sbs': 'SBS On Demand', 'abc iview': 'ABC iview',
  'iview': 'ABC iview', 'apple tv': 'Apple TV+', 'paramount': 'Paramount+',
  'hbo': 'HBO', 'crunchyroll': 'Crunchyroll', 'shudder': 'Shudder',
  'svt play': 'SVT Play', '9now': '9Now', '10 play': '10 Play',
  '10play': '10 Play', '7plus': '7plus', 'kayo': 'Kayo', 'audible': 'Audible',
  'spotify': 'Spotify', 'kindle': 'Kindle', 'hulu': 'Hulu',
};

String _titleCase(String s) => s
    .trim()
    .split(RegExp(r'\s+'))
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

/// Fills "recommended by", "watch with", "where to watch" and "not out
/// yet" from the item's note, e.g. "(meat canyon recommendation)",
/// "(watch with sofia)", "(on plex)", "(waiting to get released)".
/// The note itself is kept as written.
ImportRow readHints(ImportRow r) {
  final note = r.note;
  if (note == null || note.isEmpty) return r;
  final rec = _recommendation.firstMatch(note);
  final name = rec?.group(1) ?? rec?.group(2);
  if (name != null && r.recommendedBy == null) {
    final cleaned = cleanText(name, maxLength: 40);
    if (cleaned.isNotEmpty) r.recommendedBy = _titleCase(cleaned);
  }
  final ww = _watchWith.firstMatch(note);
  if (ww != null) {
    for (final n in ww.group(1)!.split(RegExp(r'\s+and\s+'))) {
      final c = cleanText(n, maxLength: 40);
      if (c.isNotEmpty && !r.watchWith.contains(_titleCase(c))) {
        r.watchWith.add(_titleCase(c));
      }
    }
  }
  if (r.whereToWatch == null) {
    final lower = ' ${note.toLowerCase()} ';
    for (final MapEntry(key: k, value: v) in _services.entries) {
      if (RegExp('[^a-z0-9]${RegExp.escape(k)}[^a-z0-9]').hasMatch(lower)) {
        r.whereToWatch = v;
        break;
      }
    }
  }
  if (_upcomingWords.hasMatch(note)) r.upcoming = true;
  return r;
}
