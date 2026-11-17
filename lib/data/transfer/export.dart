import 'dart:convert';

import '../db/database.dart';
import '../models.dart';
import 'csv.dart';

enum ExportFormat { txt, csv, json }

extension ExportFormatInfo on ExportFormat {
  String get extension => name;
  String get mimeType => switch (this) {
        ExportFormat.txt => 'text/plain',
        ExportFormat.csv => 'text/csv',
        ExportFormat.json => 'application/json',
      };
  String get label => switch (this) {
        ExportFormat.txt => 'Plain text (.txt): readable checklist',
        ExportFormat.csv => 'Spreadsheet (.csv): Excel, Google Sheets',
        ExportFormat.json => 'JSON (.json): every detail, for other apps',
      };
}

String _date(DateTime? d) => d == null
    ? ''
    : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}'
        '-${d.day.toString().padLeft(2, '0')}';

List<String> itemTags(MediaItem i) {
  final raw = i.tags;
  if (raw == null || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) return [for (final t in decoded) if (t is String) t];
  } catch (_) {}
  return const [];
}

List<MediaItem> _sorted(List<MediaItem> items) => [...items]
  ..sort((a, b) {
    final c = a.category.index.compareTo(b.category.index);
    if (c != 0) return c;
    final s = a.status.index.compareTo(b.status.index);
    if (s != 0) return s;
    return a.sortTitle.compareTo(b.sortTitle);
  });

String exportText(List<MediaItem> items) {
  final b = StringBuffer('WatchedLedger export ${_date(DateTime.now())}\n');
  MediaCategory? cat;
  ListStatus? status;
  for (final i in _sorted(items)) {
    if (i.category != cat || i.status != status) {
      cat = i.category;
      status = i.status;
      b.writeln('\n${i.category.tabLabel.toUpperCase()} - '
          '${i.category.labelFor(i.status)}');
    }
    final parts = <String>[
      if (i.year != null) '(${i.year})',
      if (i.rating != null) '★' * i.rating!,
      if (i.status == ListStatus.done && i.completedAt != null)
        '- ${completedLabel(i.category, i.completedAt!)}',
      if (i.note != null && i.note!.isNotEmpty) '- "${i.note}"',
    ];
    final box = i.status == ListStatus.done ? '[x]' : '[ ]';
    b.writeln('$box ${i.title}${parts.isEmpty ? '' : ' ${parts.join(' ')}'}');
  }
  return b.toString();
}

const List<String> csvHeader = [
  'category', 'list', 'title', 'year', 'genre', 'creator', 'rating', 'note', //
  'season', 'episode', 'tags', 'added', 'finished',
];

String exportCsv(List<MediaItem> items) => toCsv([
      csvHeader,
      for (final i in _sorted(items))
        [
          i.category.name,
          i.status == ListStatus.done ? 'done' : 'todo',
          i.title,
          i.year,
          i.genre,
          i.creator,
          i.rating,
          i.note,
          i.season,
          i.episode,
          itemTags(i).join('; '),
          _date(i.addedAt),
          _date(i.completedAt),
        ],
    ]);

String exportJson(List<MediaItem> items) =>
    const JsonEncoder.withIndent('  ').convert({
      'app': 'WatchedLedger',
      'format': 1,
      'exported': DateTime.now().toUtc().toIso8601String(),
      'items': [
        for (final i in _sorted(items))
          {
            'category': i.category.name,
            'list': i.status == ListStatus.done ? 'done' : 'todo',
            'title': i.title,
            'year': i.year,
            'genre': i.genre,
            'creator': i.creator,
            'rating': i.rating,
            'note': i.note,
            'season': i.season,
            'episode': i.episode,
            'tags': itemTags(i),
            'added': i.addedAt.toUtc().toIso8601String(),
            'finished': i.completedAt?.toUtc().toIso8601String(),
            'source': i.source,
            'sourceId': i.sourceId,
          },
      ],
    });

String exportAs(ExportFormat format, List<MediaItem> items) => switch (format) {
      ExportFormat.txt => exportText(items),
      ExportFormat.csv => exportCsv(items),
      ExportFormat.json => exportJson(items),
    };
