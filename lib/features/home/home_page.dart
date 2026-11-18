import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_scope.dart';
import '../../core/home_widget_sync.dart';
import '../../core/share_receiver.dart';
import '../../data/db/database.dart';
import '../../data/lookup/link_lookup.dart';
import '../../data/models.dart';
import '../../data/share_parser.dart';
import '../../data/transfer/folder_share.dart';
import '../add/add_link.dart';
import '../add/quick_add_bar.dart' show showAddSheet;
import '../data/backup_reminder.dart';
import '../data/data_page.dart';
import '../folders/folders_page.dart';
import '../import/import_page.dart';
import '../lists/category_page.dart';
import '../picker/picker_page.dart';
import '../search/list_search.dart';
import '../settings/settings_page.dart';
import '../stats/stats_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// Which category the list shows.
  MediaCategory _current = MediaCategory.movie;

  /// Bottom bar: 0 Lists, 1 Folders, 2 Pick, 3 Stats, 4 More.
  int _page = 0;

  /// Which list (To Watch / Watched) each category is showing.
  final Map<MediaCategory, ValueNotifier<ListStatus>> _statuses = {
    for (final c in MediaCategory.values) c: ValueNotifier(ListStatus.todo),
  };

  final ListSearch _search = ListSearch();
  final TextEditingController _searchText = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  HomeWidgetSync? _widgetSync;
  bool _backupChecked = false;

  @override
  void initState() {
    super.initState();
    for (final n in _statuses.values) {
      n.addListener(_onListSwitched);
    }
    ShareReceiver.listen(_onShared);
  }

  /// Something was shared into the app: look it up and confirm.
  void _onShared(String text) {
    if (!mounted) return;
    // A folder someone shared from WatchedLedger: check it, then add it.
    if (text.contains(kFolderShareMark)) {
      unawaited(Navigator.of(context).push<int>(MaterialPageRoute(
        builder: (_) => ImportPage(initialText: text, autoStart: true),
      )));
      return;
    }
    // Video and music links (YouTube, NewPipe, TikTok, Spotify...) are added
    // from the link itself, with title, channel and thumbnail.
    for (final m in RegExp(r'https?://[^\s<>"]+').allMatches(text)) {
      final link = LinkLookup.asLink(m.group(0)!);
      if (link != null &&
          (LinkLookup.endpointFor(link) != null ||
              LinkLookup.categoryFor(link) != null)) {
        unawaited(addLinkItem(context, link,
            fallback: _current, status: ListStatus.todo));
        return;
      }
    }
    final shared = parseShared(text);
    if (shared == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Couldn't find a title in what was shared.")));
      return;
    }
    final year = shared.year;
    unawaited(Navigator.of(context)
        .push<int>(MaterialPageRoute(
          builder: (_) => ImportPage(
            initialText:
                year == null ? shared.title : '${shared.title} ($year)',
            initialCategory: shared.category ?? _current,
            autoStart: true,
          ),
        ))
        .then((added) {
      if (added == null || added == 0 || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added "${shared.title}"')));
    }));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = AppScope.of(context);
    // Real app only: screen tests run without the background services.
    if (!_backupChecked && scope.matcher != null) {
      _backupChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(maybeShowBackupReminder(context, scope.db, () {
          Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DataPage()));
        }));
      });
    }
    if (_widgetSync == null && scope.matcher != null) {
      _widgetSync = HomeWidgetSync(scope.db, scope.lock)
        ..start(onQuickAdd: _quickAdd);
    }
  }

  /// The widget's "+" was tapped: open the Add sheet.
  void _quickAdd() {
    if (!mounted) return;
    if (_search.active) _closeSearch();
    setState(() => _page = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_openAdd());
    });
  }

  Future<void> _openAdd() => showAddSheet(
        context,
        category: _current,
        status: _statuses[_current]!.value,
        onImport: _openImport,
      );

  void _openImport() {
    unawaited(Navigator.of(context).push<int>(MaterialPageRoute(
      builder: (_) => ImportPage(initialCategory: _current),
    )));
  }

  void _setCategory(MediaCategory c) {
    if (c == _current) return;
    setState(() => _current = c);
    if (_search.active) _search.restart();
  }

  Future<void> _pickCategory() async {
    final picked = await showModalBottomSheet<MediaCategory>(
      context: context,
      showDragHandle: true,
      builder: (_) => _CategorySheet(current: _current),
    );
    if (picked != null) _setCategory(picked);
  }

  void _onListSwitched() {
    if (_search.active) _search.restart();
  }

  void _openSearch() {
    _search.open();
    setState(() {});
    _searchFocus.requestFocus();
  }

  void _closeSearch() {
    _searchText.clear();
    _search.close();
    _searchFocus.unfocus();
    setState(() {});
  }

  /// "Also in…" chip tapped: switch category and list, keep the search.
  void _showList(MediaCategory category, ListStatus status) {
    _statuses[category]!.value = status;
    if (category != _current) setState(() => _current = category);
    _search.restart();
  }

  @override
  void dispose() {
    for (final n in _statuses.values) {
      n.dispose();
    }
    _search.dispose();
    _searchText.dispose();
    _searchFocus.dispose();
    _widgetSync?.dispose();
    super.dispose();
  }

  PreferredSizeWidget _appBar(BuildContext context) {
    final theme = Theme.of(context);
    if (!_search.active) {
      return AppBar(
        titleSpacing: 8,
        title: TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.onSurface,
            textStyle: theme.textTheme.titleLarge,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          onPressed: _pickCategory,
          icon: Icon(_current.icon, color: theme.colorScheme.primary),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_current.tabLabel),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
      );
    }

    return AppBar(
      leading: IconButton(
        tooltip: 'Close search',
        icon: const Icon(Icons.arrow_back),
        onPressed: _closeSearch,
      ),
      titleSpacing: 0,
      title: TextField(
        controller: _searchText,
        focusNode: _searchFocus,
        textInputAction: TextInputAction.search,
        inputFormatters: [LengthLimitingTextInputFormatter(100)],
        onChanged: _search.setQuery,
        // Enter jumps to the next match and keeps the keyboard open.
        onSubmitted: (_) => _search.next(),
        onEditingComplete: () {},
        decoration: InputDecoration(
          hintText: 'Search ${_current.tabLabel}',
          border: InputBorder.none,
        ),
      ),
      actions: [
        ListenableBuilder(
          listenable: _search,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _search.counterLabel,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              IconButton(
                tooltip: 'Previous match',
                icon: const Icon(Icons.keyboard_arrow_up),
                onPressed: _search.total > 0 ? _search.previous : null,
              ),
              IconButton(
                tooltip: 'Next match',
                icon: const Icon(Icons.keyboard_arrow_down),
                onPressed: _search.total > 0 ? _search.next : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _lists(BuildContext context) {
    return SearchScope(
      search: _search,
      child: Scaffold(
        appBar: _appBar(context),
        floatingActionButton: _search.active
            ? null
            : FloatingActionButton.extended(
                heroTag: 'add',
                onPressed: _openAdd,
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
        body: Column(
          children: [
            if (_search.active)
              _ElsewhereBar(
                category: _current,
                status: _statuses[_current]!,
                onShow: _showList,
              ),
            Expanded(
              child: CategoryPage(
                key: PageStorageKey(_current),
                category: _current,
                status: _statuses[_current]!,
                onSearch: _openSearch,
                onImport: _openImport,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = switch (_page) {
      1 => const FoldersPage(),
      2 => PickerPage(startCategory: _current),
      3 => const StatsPage(),
      4 => const SettingsPage(),
      _ => _lists(context),
    };
    return PopScope(
      // Back closes search first, then returns to the lists.
      canPop: !_search.active && _page == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_search.active) {
          _closeSearch();
        } else {
          setState(() => _page = 0);
        }
      },
      child: Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _page,
          onDestinationSelected: (i) {
            if (_search.active) _closeSearch();
            setState(() => _page = i);
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.checklist_outlined),
              selectedIcon: Icon(Icons.checklist),
              label: 'Lists',
            ),
            NavigationDestination(
              icon: Icon(Icons.folder_outlined),
              selectedIcon: Icon(Icons.folder),
              label: 'Folders',
            ),
            NavigationDestination(
              icon: Icon(Icons.casino_outlined),
              selectedIcon: Icon(Icons.casino),
              label: 'Pick',
            ),
            NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined),
              selectedIcon: Icon(Icons.bar_chart),
              label: 'Stats',
            ),
            NavigationDestination(
              icon: Icon(Icons.more_horiz),
              label: 'More',
            ),
          ],
        ),
      ),
    );
  }
}

/// "Which list?": every category with how much is in it.
class _CategorySheet extends StatelessWidget {
  const _CategorySheet({required this.current});
  final MediaCategory current;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    return StreamBuilder<List<MediaItem>>(
      stream: scope.db.watchAll(),
      builder: (context, snap) {
        final todo = <MediaCategory, int>{};
        final done = <MediaCategory, int>{};
        for (final i in snap.data ?? const <MediaItem>[]) {
          if (!scope.isVisible(i)) continue;
          final m = i.status == ListStatus.done ? done : todo;
          m[i.category] = (m[i.category] ?? 0) + 1;
        }
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final c in MediaCategory.values)
                  ListTile(
                    selected: c == current,
                    leading: Icon(c.icon),
                    title: Text(c.tabLabel),
                    subtitle: Text('${todo[c] ?? 0} ${c.todoLabel.toLowerCase()}'
                        ' · ${done[c] ?? 0} ${c.doneLabel.toLowerCase()}'),
                    trailing:
                        c == current ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.pop(context, c),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Under the search bar: how many matches are in the OTHER lists, as chips
/// that jump there ("Watched · 2", "Books › To Read · 1").
class _ElsewhereBar extends StatefulWidget {
  const _ElsewhereBar({
    required this.category,
    required this.status,
    required this.onShow,
  });

  final MediaCategory category;
  final ValueNotifier<ListStatus> status;
  final void Function(MediaCategory, ListStatus) onShow;

  @override
  State<_ElsewhereBar> createState() => _ElsewhereBarState();
}

class _ElsewhereBarState extends State<_ElsewhereBar> {
  // Created once, so typing doesn't resubscribe on every keystroke.
  Stream<List<MediaItem>>? _all;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _all ??= AppScope.of(context).db.watchAll();
  }

  @override
  Widget build(BuildContext context) {
    final category = widget.category;
    final search = SearchScope.of(context);
    final query = search.query;
    final theme = Theme.of(context);
    if (query.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Text(
          'Type to highlight every match. Use ▲ ▼ or Enter to jump between '
          'them; you can tick items straight from the results.',
          style: theme.textTheme.bodySmall,
        ),
      );
    }
    return ValueListenableBuilder<ListStatus>(
      valueListenable: widget.status,
      builder: (context, currentStatus, _) => StreamBuilder<List<MediaItem>>(
        stream: _all,
        builder: (context, snapshot) {
          final counts = <(MediaCategory, ListStatus), int>{};
          for (final item in snapshot.data ?? const <MediaItem>[]) {
            if (!AppScope.of(context).isVisible(item)) continue;
            if (item.category == category && item.status == currentStatus) {
              continue;
            }
            if (!itemMatches(item, query)) continue;
            final key = (item.category, item.status);
            counts[key] = (counts[key] ?? 0) + 1;
          }
          if (counts.isEmpty) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Text(
                search.total == 0
                    ? 'No matches in any list.'
                    : 'No matches in your other lists.',
                style: theme.textTheme.bodySmall,
              ),
            );
          }
          final keys = counts.keys.toList()
            ..sort((a, b) {
              final byCat = a.$1.index.compareTo(b.$1.index);
              return byCat != 0 ? byCat : a.$2.index.compareTo(b.$2.index);
            });
          return SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                Center(
                  child: Text('Also in: ', style: theme.textTheme.bodySmall),
                ),
                for (final (c, s) in keys)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Center(
                      child: ActionChip(
                        avatar: Icon(c.icon, size: 18),
                        label: Text(
                          c == category
                              ? '${c.labelFor(s)} · ${counts[(c, s)]}'
                              : '${c.tabLabel} › ${c.labelFor(s)} · '
                                  '${counts[(c, s)]}',
                        ),
                        onPressed: () => widget.onShow(c, s),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
