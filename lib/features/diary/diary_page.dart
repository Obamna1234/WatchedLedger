import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../data/db/database.dart';
import '../../data/models.dart';
import '../edit/edit_item_page.dart';
import '../lookup/remote_thumb.dart';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', //
  'August', 'September', 'October', 'November', 'December',
];

/// Every time something was finished, newest first, grouped by month.
class DiaryPage extends StatefulWidget {
  const DiaryPage({super.key});

  @override
  State<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends State<DiaryPage> {
  MediaCategory? _category;

  @override
  Widget build(BuildContext context) {
    final db = AppScope.of(context).db;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Diary')),
      body: StreamBuilder<List<DiaryEntry>>(
        stream: db.watchDiary(),
        builder: (context, snap) {
          final all = snap.data ?? const <DiaryEntry>[];
          // Which entries are re-watches: count earlier entries per item.
          final seen = <int, int>{};
          final rewatch = <int>{};
          for (final e in all.reversed) {
            final n = seen[e.item.id] = (seen[e.item.id] ?? 0) + 1;
            if (n > 1) rewatch.add(e.event.id);
          }
          final entries = [
            for (final e in all)
              if (_category == null || e.item.category == _category) e,
          ];
          final rows = <Widget>[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  for (final c in <MediaCategory?>[null, ...MediaCategory.values])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(c?.tabLabel ?? 'All'),
                        selected: _category == c,
                        onSelected: (_) => setState(() => _category = c),
                      ),
                    ),
                ],
              ),
            ),
          ];
          if (entries.isEmpty && snap.hasData) {
            rows.add(Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Nothing here yet. Tick something as finished, or use '
                '"Watched again" on its Edit screen.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
            ));
          }
          String? month;
          for (final e in entries) {
            final d = e.event.date;
            final label = '${_monthNames[d.month - 1]} ${d.year}';
            if (label != month) {
              month = label;
              final count = entries
                  .where((x) =>
                      x.event.date.year == d.year &&
                      x.event.date.month == d.month)
                  .length;
              rows.add(Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('$label · $count',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: theme.colorScheme.primary)),
              ));
            }
            final rating = e.event.rating ?? e.item.rating;
            rows.add(ListTile(
              leading: ItemCover(item: e.item),
              title: Text(e.item.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text([
                '${d.day} ${_monthNames[d.month - 1].substring(0, 3)}',
                e.item.category.singular,
                if (rewatch.contains(e.event.id)) 'again',
                if (rating != null) '★' * rating,
                if (e.event.note != null && e.event.note!.isNotEmpty)
                  '“${e.event.note}”',
              ].join('  ·  ')),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => EditItemPage(item: e.item))),
            ));
          }
          return ListView(children: rows);
        },
      ),
    );
  }
}
