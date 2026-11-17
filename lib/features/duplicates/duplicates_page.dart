import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../data/db/database.dart';
import '../../data/duplicates.dart';
import '../../data/models.dart';
import '../lookup/remote_thumb.dart' show ItemCover;

/// Finds items that were added more than once and merges them.
class DuplicatesPage extends StatefulWidget {
  const DuplicatesPage({super.key});

  @override
  State<DuplicatesPage> createState() => _DuplicatesPageState();
}

class _DuplicatesPageState extends State<DuplicatesPage> {
  /// Which item of each group to keep, by the group's first id.
  final Map<int, int> _keep = {};

  Future<void> _merge(List<MediaItem> group) async {
    final db = AppScope.of(context).db;
    final keepId = _keep[group.first.id] ?? _best(group).id;
    final keep = group.firstWhere((i) => i.id == keepId);
    final others = [for (final i in group) if (i.id != keepId) i];
    await db.updateItem(mergeDuplicates(keep, others));
    for (final o in others) {
      await db.deleteItem(o.id);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Merged into "${keep.title}". '
            'The other ${others.length == 1 ? 'copy is' : 'copies are'} '
            'in Recently deleted.'),
        persist: false,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            for (final i in group) {
              await db.restoreItem(i);
            }
          },
        ),
      ));
  }

  /// The copy with the most filled in: matched, has a cover, ticked.
  MediaItem _best(List<MediaItem> group) {
    int score(MediaItem i) =>
        (i.matchState == MatchState.matched ? 4 : 0) +
        (i.coverUrl != null ? 2 : 0) +
        (i.status == ListStatus.done ? 1 : 0);
    return group.reduce((a, b) => score(b) > score(a) ? b : a);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Find duplicates')),
      body: StreamBuilder<List<MediaItem>>(
        stream: scope.db.watchAll(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final groups = findDuplicateGroups(
              snap.data!.where(scope.isVisible));
          if (groups.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('No duplicates found.',
                    style: theme.textTheme.bodyLarge),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'Pick the copy to keep. Merging keeps its details, adds '
                  'tags, notes and anything missing from the others, and '
                  'moves the others to Recently deleted.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              for (final group in groups) _group(context, group),
            ],
          );
        },
      ),
    );
  }

  Widget _group(BuildContext context, List<MediaItem> group) {
    final keepId = _keep[group.first.id] ?? _best(group).id;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: RadioGroup<int>(
          groupValue: keepId,
          onChanged: (v) {
            if (v != null) setState(() => _keep[group.first.id] = v);
          },
          child: Column(
            children: [
              for (final i in group)
                RadioListTile<int>(
                  value: i.id,
                  secondary: ItemCover(item: i),
                  title: Text(i.year == null ? i.title : '${i.title} (${i.year})'),
                  subtitle: Text([
                    i.category.labelFor(i.status),
                    if (i.genre != kUncategorised) i.genre,
                    'added ${i.addedAt.day}/${i.addedAt.month}/${i.addedAt.year}',
                  ].join(' · ')),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: FilledButton.tonal(
                    onPressed: () => _merge(group),
                    child: Text('Merge ${group.length}'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
