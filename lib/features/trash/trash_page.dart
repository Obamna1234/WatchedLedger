import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../data/db/database.dart';
import '../../data/models.dart';

/// "Recently deleted": everything deleted in the last 30 days.
class TrashPage extends StatelessWidget {
  const TrashPage({super.key});

  Future<void> _emptyAll(BuildContext context) async {
    final db = AppScope.of(context).db;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Empty Recently deleted?'),
        content: const Text(
            'These items will be gone for good (your backups are not affected).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Empty'),
          ),
        ],
      ),
    );
    if (ok == true) await db.emptyTrash();
  }

  @override
  Widget build(BuildContext context) {
    final db = AppScope.of(context).db;
    final theme = Theme.of(context);
    return StreamBuilder<List<TrashEntry>>(
      stream: db.watchTrash(),
      builder: (context, snap) {
        final entries = snap.data ?? const <TrashEntry>[];
        final now = DateTime.now();
        return Scaffold(
          appBar: AppBar(
            title: const Text('Recently deleted'),
            actions: [
              if (entries.isNotEmpty)
                TextButton(
                  onPressed: () => _emptyAll(context),
                  child: const Text('Empty'),
                ),
            ],
          ),
          body: entries.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Nothing here. Deleted items stay here for 30 days '
                      'so you can bring them back.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                )
              : ListView(
                  children: [
                    for (final e in entries)
                      ListTile(
                        leading: Icon(e.category.icon),
                        title: Text(e.title),
                        subtitle: Text(
                            '${e.category.tabLabel} · deleted '
                            '${_ago(now.difference(e.deletedAt))}, '
                            'kept ${_left(e.deletedAt, now)} more'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Delete for good',
                              icon: const Icon(Icons.delete_forever_outlined),
                              onPressed: () => db.deleteFromTrash(e.id),
                            ),
                            FilledButton.tonal(
                              onPressed: () async {
                                final item = await db.restoreFromTrash(e.id);
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(item == null
                                            ? "Couldn't restore that one."
                                            : 'Restored "${item.title}"')));
                              },
                              child: const Text('Restore'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }
}

String _ago(Duration d) {
  if (d.inDays >= 1) return '${d.inDays} day${d.inDays == 1 ? '' : 's'} ago';
  if (d.inHours >= 1) return '${d.inHours} h ago';
  return 'just now';
}

String _left(DateTime deleted, DateTime now) {
  final left = deleted.add(AppDatabase.keepDeleted).difference(now).inDays;
  return left <= 0 ? 'until tomorrow' : '$left day${left == 1 ? '' : 's'}';
}
