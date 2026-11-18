import 'package:drift/drift.dart' show Value;
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

/// A group of items: a folder you made, or everything you watch with
/// one person ("With Sam").
class Group {
  const Group(this.name, {this.person = false});
  final String name;
  final bool person;

  String get label => person ? 'With $name' : name;

  bool contains(MediaItem i) {
    final key = name.toLowerCase();
    final names = person ? decodeTags(i.watchWith) : itemTags(i);
    return names.any((n) => n.toLowerCase() == key);
  }

  /// The item with this group added or removed.
  MediaItem toggled(MediaItem i, bool on) {
    final key = name.toLowerCase();
    final names = person ? decodeTags(i.watchWith) : itemTags(i);
    final kept = [for (final n in names) if (n.toLowerCase() != key) n];
    final next = encodeTags(on ? [...kept, name] : kept);
    return person
        ? i.copyWith(watchWith: Value(next), updatedAt: DateTime.now())
        : i.copyWith(tags: Value(next), updatedAt: DateTime.now());
  }
}

/// Folders and people, across every category. Each one can be shared.
class FoldersPage extends StatelessWidget {
  const FoldersPage({super.key});

  Future<void> _newGroup(BuildContext context, {required bool person}) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(person: person),
    );
    final clean = name == null ? '' : cleanTag(name);
    if (clean.isEmpty || !context.mounted) return;
    final group = Group(clean, person: person);
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PickItemsPage(group: group)));
    if (!context.mounted) return;
    await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => FolderPage(group: group)));
  }

  @override
  Widget build(BuildContext context) {
    final db = AppScope.of(context).db;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Folders')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-folder',
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('New folder'),
        onPressed: () => _newGroup(context, person: false),
      ),
      body: StreamBuilder<List<MediaItem>>(
        stream: db.watchAll(),
        builder: (context, snap) {
          final scope = AppScope.of(context);
          final items = [
            for (final i in snap.data ?? const <MediaItem>[])
              if (scope.isVisible(i)) i,
          ];
          final folders = <String, String>{};
          final people = <String, String>{};
          for (final i in items) {
            for (final t in itemTags(i)) {
              folders.putIfAbsent(t.toLowerCase(), () => t);
            }
            for (final p in decodeTags(i.watchWith)) {
              people.putIfAbsent(p.toLowerCase(), () => p);
            }
          }
          List<Group> sorted(Map<String, String> m, bool person) => [
                for (final k in (m.keys.toList()..sort()))
                  Group(m[k]!, person: person),
              ];

          Widget tile(Group g) {
            final inIt = items.where(g.contains).toList();
            return ListTile(
              leading: Icon(g.person
                  ? Icons.people_outline
                  : Icons.folder_outlined),
              title: Text(g.label),
              subtitle: Text('${inIt.length} '
                  '${inIt.length == 1 ? 'item' : 'items'}'),
              trailing: IconButton(
                tooltip: 'Share',
                icon: const Icon(Icons.share_outlined),
                onPressed: () => _share(context, g.label, inIt),
              ),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => FolderPage(group: g))),
            );
          }

          final folderGroups = sorted(folders, false);
          final peopleGroups = sorted(people, true);
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  'Group anything from any category, e.g. "Funny reels" or '
                  '"Movie night", and share it as a simple message. The '
                  "other person doesn't need the app.",
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              const _Header('My folders'),
              if (folderGroups.isEmpty)
                const ListTile(
                  leading: Icon(Icons.folder_open_outlined),
                  title: Text('No folders yet'),
                  subtitle: Text('Tap "New folder" to make one.'),
                ),
              for (final g in folderGroups) tile(g),
              const _Header('Watching with'),
              for (final g in peopleGroups) tile(g),
              ListTile(
                leading: const Icon(Icons.person_add_alt),
                title: const Text('Add someone'),
                subtitle: const Text(
                    'Keep a list of what to watch together. Anything without '
                    'a name is just for you.'),
                onTap: () => _newGroup(context, person: true),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.person});
  final bool person;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.person ? 'Who do you watch with?' : 'New folder'),
      content: TextField(
        controller: _name,
        autofocus: true,
        maxLength: kMaxTagLength,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          labelText: widget.person ? 'Their name' : 'Folder name',
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _name.text),
          child: const Text('Next'),
        ),
      ],
    );
  }
}

Future<void> _share(
    BuildContext context, String title, List<MediaItem> items) async {
  final visible = [for (final i in items) if (!i.isPrivate) i];
  final shared = await shareText(folderShareText(title, visible));
  if (!shared && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Copied. Paste it into a message to share.')));
  }
}

/// Tick the items that belong in [group].
class PickItemsPage extends StatefulWidget {
  const PickItemsPage({super.key, required this.group});
  final Group group;

  @override
  State<PickItemsPage> createState() => _PickItemsPageState();
}

class _PickItemsPageState extends State<PickItemsPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final db = AppScope.of(context).db;
    final g = widget.group;
    return Scaffold(
      appBar: AppBar(
        title: Text('Add to ${g.label}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
      body: StreamBuilder<List<MediaItem>>(
        stream: db.watchAll(),
        builder: (context, snap) {
          final scope = AppScope.of(context);
          final q = _query.toLowerCase();
          final items = [
            for (final i in snap.data ?? const <MediaItem>[])
              if (scope.isVisible(i) &&
                  (q.isEmpty || i.title.toLowerCase().contains(q)))
                i,
          ]..sort((a, b) => a.sortTitle.compareTo(b.sortTitle));
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search your lists',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? const Center(child: Text('Nothing on your lists yet.'))
                    : ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, k) {
                          final i = items[k];
                          final on = g.contains(i);
                          return CheckboxListTile(
                            value: on,
                            secondary: ItemCover(item: i),
                            title: Text(i.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                                '${i.category.tabLabel} · '
                                '${i.category.labelFor(i.status)}'),
                            onChanged: (v) =>
                                db.updateItem(g.toggled(i, v ?? false)),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One folder or person: everything in it, with links and a share button.
class FolderPage extends StatelessWidget {
  const FolderPage({super.key, required this.group});
  final Group group;

  @override
  Widget build(BuildContext context) {
    final db = AppScope.of(context).db;
    return StreamBuilder<List<MediaItem>>(
      stream: db.watchAll(),
      builder: (context, snap) {
        final items = [
          for (final i in snap.data ?? const <MediaItem>[])
            if (AppScope.of(context).isVisible(i) && group.contains(i)) i,
        ];
        return Scaffold(
          appBar: AppBar(
            title: Text(group.label),
            actions: [
              IconButton(
                tooltip: 'Share',
                icon: const Icon(Icons.share_outlined),
                onPressed: items.isEmpty
                    ? null
                    : () => _share(context, group.label, items),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'add-to-folder',
            icon: const Icon(Icons.add),
            label: const Text('Add items'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => PickItemsPage(group: group))),
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  'Share sends a message with each title and its link '
                  '(no app needed to open them). Private items are left out.',
                ),
              ),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Empty. Tap "Add items" to fill it.',
                      textAlign: TextAlign.center),
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
