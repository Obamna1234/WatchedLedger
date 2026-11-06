import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_scope.dart';
import '../../data/db/database.dart';
import '../../data/models.dart';
import '../add/quick_add_bar.dart';
import '../lists/category_page.dart';
import '../search/list_search.dart';
import '../settings/settings_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: MediaCategory.values.length, vsync: this)
        ..addListener(_onTabChanged);

  /// Which list (To Watch / Watched) each tab is showing.
  final Map<MediaCategory, ValueNotifier<ListStatus>> _statuses = {
    for (final c in MediaCategory.values) c: ValueNotifier(ListStatus.todo),
  };

  final ListSearch _search = ListSearch();
  final TextEditingController _searchText = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  MediaCategory get _current => MediaCategory.values[_tabs.index];

  @override
  void initState() {
    super.initState();
    for (final n in _statuses.values) {
      n.addListener(_onListSwitched);
    }
  }

  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;
    setState(() {});
    if (_search.active) _search.restart();
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

  /// "Also in…" chip tapped: switch tab and list, keep the search.
  void _showList(MediaCategory category, ListStatus status) {
    _statuses[category]!.value = status;
    if (category != _current) _tabs.animateTo(category.index);
    _search.restart();
  }

  @override
  void dispose() {
    for (final n in _statuses.values) {
      n.dispose();
    }
    _tabs.dispose();
    _search.dispose();
    _searchText.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  PreferredSizeWidget _appBar(BuildContext context) {
    final tabBar = TabBar(
      controller: _tabs,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      tabs: [
        for (final c in MediaCategory.values)
          Tab(icon: Icon(c.icon), text: c.tabLabel),
      ],
    );

    if (!_search.active) {
      return AppBar(
        title: const Text('WatchedLedger'),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: _openSearch,
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
            ),
          ),
        ],
        bottom: tabBar,
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
        decoration: const InputDecoration(
          hintText: 'Search this list',
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
      bottom: tabBar,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // The Back button closes search first.
      canPop: !_search.active,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeSearch();
      },
      child: SearchScope(
        search: _search,
        child: Scaffold(
          appBar: _appBar(context),
          body: Column(
            children: [
              if (_search.active)
                _ElsewhereBar(
                  category: _current,
                  status: _statuses[_current]!,
                  onShow: _showList,
                )
              else
                QuickAddBar(category: _current),
              const Divider(height: 1),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    for (final c in MediaCategory.values)
                      CategoryPage(
                        key: PageStorageKey(c),
                        category: c,
                        status: _statuses[c]!,
                        isActive: c == _current,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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
