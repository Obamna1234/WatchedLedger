import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/open_link.dart';
import '../../core/share_out.dart';
import '../../data/db/database.dart';
import '../../data/models.dart';
import '../../data/tags.dart';
import '../../data/transfer/folder_share.dart';
import '../edit/edit_item_page.dart';
import '../lookup/remote_thumb.dart';

/// Folders (tags) across every tab, each one shareable.
class FoldersPage extends StatelessWidget {
  const FoldersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final db = AppScope.of(context).db;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Folders')),
      body: StreamBuilder<List<MediaItem>>(
        stream: db.watchAll(),
        builder: (context, snap) {
          final items = snap.data ?? const <MediaItem>[];
          final folders = <String, List<MediaItem>>{};
          final names = <String, String>{};
          for (final i in items) {
            for (final t in itemTags(i)) {
              final key = t.toLowerCase();
              names.putIfAbsent(key, () => t);
              folders.putIfAbsent(key, () => []).add(i);
            }
          }
          final keys = folders.keys.toList()..sort();
          if (keys.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No folders yet. Open any item and add it to a folder '
                  '(e.g. "Funny reels" or "For Sofia") under "Tags & '
                  'folders". Folders can hold anything from any tab, and '
                  'you can share one with someone.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            );
          }
          return ListView(
            children: [
              for (final k in keys)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(names[k]!),
                  subtitle: Text('${folders[k]!.length} '
                      '${folders[k]!.length == 1 ? 'item' : 'items'}'),
                  trailing: IconButton(
                    tooltip: 'Share this folder',
                    icon: const Icon(Icons.share_outlined),
                    onPressed: () => _share(context, names[k]!, folders[k]!),
                  ),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => FolderPage(folder: names[k]!))),
                ),
            ],
          );
        },
      ),
    );
  }
}

Future<void> _share(
    BuildContext context, String folder, List<MediaItem> items) async {
  final visible = [for (final i in items) if (!i.isPrivate) i];
  final shared = await shareText(folderShareText(folder, visible));
  if (!shared && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Copied. Paste it into a message to share.')));
  }
}

/// One folder: everything in it, with links to watch and a share button.
class FolderPage extends StatelessWidget {
  const FolderPage({super.key, required this.folder});
  final String folder;

  @override
  Widget build(BuildContext context) {
    final db = AppScope.of(context).db;
    return StreamBuilder<List<MediaItem>>(
      stream: db.watchAll(),
      builder: (context, snap) {
        final items = [
          for (final i in snap.data ?? const <MediaItem>[])
            if (itemTags(i).any((t) => t.toLowerCase() == folder.toLowerCase()))
              i,
        ];
        return Scaffold(
          appBar: AppBar(
            title: Text(folder),
            actions: [
              IconButton(
                tooltip: 'Share this folder',
                icon: const Icon(Icons.share_outlined),
                onPressed:
                    items.isEmpty ? null : () => _share(context, folder, items),
              ),
            ],
          ),
          body: ListView(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  'Sharing sends a message with each title and its link '
                  '(no app needed to open them). Private items are left out.',
                ),
              ),
              for (final i in items)
                ListTile(
                  leading: ItemCover(item: i),
                  title: Text(i.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text([
                    i.category.tabLabel,
                    i.category.labelFor(i.status),
                    if (i.whereToWatch != null) 'on ${i.whereToWatch}',
                  ].join(' · ')),
                  trailing: i.link == null
                      ? null
                      : IconButton(
                          tooltip: 'Open link',
                          icon: const Icon(Icons.play_circle_outline),
                          onPressed: () => openLink(context, i.link!),
                        ),
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => EditItemPage(item: i))),
                ),
            ],
          ),
        );
      },
    );
  }
}
