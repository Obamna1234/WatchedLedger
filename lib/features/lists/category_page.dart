import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../data/db/database.dart';
import '../../data/models.dart';
import '../../data/tags.dart';
import '../edit/edit_item_page.dart';
import '../search/list_search.dart';
import 'fast_scroll_bar.dart';
import 'item_tile.dart';
import 'list_layout.dart';
import 'list_options_sheets.dart';

/// One tab: the To Watch / Watched switch, sort & filter controls and the
/// list (grouped by genre by default) with a fast-scroll index.
class CategoryPage extends StatefulWidget {
  const CategoryPage({
    super.key,
    required this.category,
    required this.status,
    this.isActive = true,
  });

  final MediaCategory category;

  /// Which list is showing. Owned by the home screen so search can switch
  /// lists ("also in Watched").
  final ValueNotifier<ListStatus> status;

  /// Only the visible tab answers search (counts matches and scrolls).
  final bool isActive;

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage>
    with AutomaticKeepAliveClientMixin<CategoryPage> {
  ListStatus get _status => widget.status.value;
  ListOptions _options = const ListOptions();
  Stream<List<MediaItem>>? _stream;
  List<MediaItem> _latest = const [];
  final _scroll = ScrollController();
  String? _bubble;

  int _handledJump = -1;

  /// Items swiped away but not yet gone from the database stream. Hiding
  /// them immediately keeps Flutter's Dismissible happy.
  final Set<int> _hidden = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.status.addListener(_onStatusChanged);
  }

  @override
  void didUpdateWidget(CategoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      oldWidget.status.removeListener(_onStatusChanged);
      widget.status.addListener(_onStatusChanged);
      _onStatusChanged();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream ??= _watch();
  }

  Stream<List<MediaItem>> _watch() =>
      AppScope.of(context).db.watchList(widget.category, _status);

  @override
  void dispose() {
    widget.status.removeListener(_onStatusChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _setStatus(ListStatus status) => widget.status.value = status;

  void _onStatusChanged() {
    if (!mounted) return;
    setState(() {
      _hidden.clear();
      _selected.clear();
      // Year filters for "finished in" make no sense on the other list.
      _options = _options.withFilters(
        genres: _options.genres,
        tags: _options.tags,
        where: _options.where,
        people: _options.people,
        minRating: _options.minRating,
        yearFrom: _options.yearFrom,
        yearTo: _options.yearTo,
        addedYear: _options.addedYear,
      );
      _stream = _watch();
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  // ------------------------------------------------------------ actions

  void _showUndo(String message, MediaItem previous) {
    final db = AppScope.of(context).db;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 5),
        persist: false,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            if (mounted) setState(() => _hidden.remove(previous.id));
            db.restoreItem(previous);
          },
        ),
      ));
  }

  Future<void> _toggle(MediaItem item, {bool fromSwipe = false}) async {
    final target =
        item.status == ListStatus.todo ? ListStatus.done : ListStatus.todo;
    if (fromSwipe) setState(() => _hidden.add(item.id));
    await AppScope.of(context).db.setStatus(item.id, target);
    if (!mounted) return;
    _showUndo('Moved to ${widget.category.labelFor(target)}', item);
  }

  // ---------------------------------------------------- select several

  final Set<int> _selected = {};
  List<MediaItem> _shown = const [];

  void _toggleSelected(int id) => setState(() {
        if (!_selected.remove(id)) _selected.add(id);
      });

  List<MediaItem> get _selectedItems =>
      [for (final i in _shown) if (_selected.contains(i.id)) i];

  void _doneSelecting(String message, List<MediaItem> before) {
    setState(_selected.clear);
    final db = AppScope.of(context).db;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        persist: false,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            for (final i in before) {
              await db.restoreItem(i);
            }
          },
        ),
      ));
  }

  Future<void> _bulkMove() async {
    final items = _selectedItems;
    final to = _status == ListStatus.todo ? ListStatus.done : ListStatus.todo;
    final db = AppScope.of(context).db;
    for (final i in items) {
      await db.setStatus(i.id, to);
    }
    if (!mounted) return;
    _doneSelecting(
        'Moved ${items.length} to ${widget.category.labelFor(to)}', items);
  }

  Future<void> _bulkDelete() async {
    final items = _selectedItems;
    final db = AppScope.of(context).db;
    for (final i in items) {
      await db.deleteItem(i.id);
    }
    if (!mounted) return;
    _doneSelecting('Deleted ${items.length} (in Recently deleted for 30 days)',
        items);
  }

  Future<void> _bulkCategory() async {
    final picked = await showModalBottomSheet<MediaCategory>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in MediaCategory.values)
              if (c != widget.category)
                ListTile(
                  leading: Icon(c.icon),
                  title: Text('Move to ${c.tabLabel}'),
                  onTap: () => Navigator.pop(context, c),
                ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final items = _selectedItems;
    final db = AppScope.of(context).db;
    final now = DateTime.now();
    for (final i in items) {
      await db.updateItem(i.copyWith(category: picked, updatedAt: now));
    }
    if (!mounted) return;
    _doneSelecting('Moved ${items.length} to ${picked.tabLabel}', items);
  }

  Future<void> _bulkFolder() async {
    final db = AppScope.of(context).db;
    final existing = await db.tagsInUse();
    if (!mounted) return;
    final folder = await showDialog<String>(
      context: context,
      builder: (_) => _FolderDialog(existing: existing),
    );
    if (folder == null || cleanTag(folder).isEmpty || !mounted) return;
    final items = _selectedItems;
    final now = DateTime.now();
    for (final i in items) {
      await db.updateItem(i.copyWith(
          tags: Value(encodeTags([...itemTags(i), folder])), updatedAt: now));
    }
    if (!mounted) return;
    _doneSelecting('Added ${items.length} to "${cleanTag(folder)}"', items);
  }

  Widget _selectionBar(BuildContext context) {
    final n = _selected.length;
    final other = widget.category.labelFor(
        _status == ListStatus.todo ? ListStatus.done : ListStatus.todo);
    return Material(
      elevation: 6,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Cancel',
                icon: const Icon(Icons.close),
                onPressed: () => setState(_selected.clear),
              ),
              Expanded(child: Text('$n selected')),
              IconButton(
                tooltip: 'Select all',
                icon: const Icon(Icons.select_all),
                onPressed: () => setState(
                    () => _selected.addAll([for (final i in _shown) i.id])),
              ),
              IconButton(
                tooltip: 'Move to $other',
                icon: Icon(_status == ListStatus.todo
                    ? Icons.check_circle_outline
                    : Icons.undo),
                onPressed: _bulkMove,
              ),
              IconButton(
                tooltip: 'Add to a folder',
                icon: const Icon(Icons.create_new_folder_outlined),
                onPressed: _bulkFolder,
              ),
              IconButton(
                tooltip: 'Change category',
                icon: const Icon(Icons.drive_file_move_outline),
                onPressed: _bulkCategory,
              ),
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: _bulkDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _delete(MediaItem item) async {
    setState(() => _hidden.add(item.id));
    await AppScope.of(context).db.deleteItem(item.id);
    if (!mounted) return;
    _showUndo('Deleted "${item.title}"', item);
  }

  Future<void> _edit(MediaItem item) async {
    final outcome = await Navigator.of(context).push<EditOutcome>(
      MaterialPageRoute(builder: (_) => EditItemPage(item: item)),
    );
    if (!mounted || outcome == null) return;
    switch (outcome) {
      case EditSaved(:final previous, :final updated):
        final moved = previous.category != updated.category ||
            previous.status != updated.status;
        _showUndo(
          moved
              ? 'Moved to ${updated.category.tabLabel} › '
                  '${updated.category.labelFor(updated.status)}'
              : 'Saved',
          previous,
        );
      case EditDeleteRequested():
        await _delete(item);
    }
  }

  Future<void> _openSort() => showSortSheet(
        context,
        options: _options,
        onChanged: (o) => setState(() => _options = o),
      );

  Future<void> _openFilter() async {
    final items = _latest;
    final result = await showFilterSheet(
      context,
      options: _options,
      category: widget.category,
      status: _status,
      genresInList: {for (final i in items) i.genre},
      tagsInList: {
        for (final i in items) ...itemTags(i),
      },
      whereInList: {
        for (final i in items)
          if (i.whereToWatch != null) i.whereToWatch!,
      },
      peopleInList: {
        for (final i in items) ...[
          if (i.recommendedBy != null) i.recommendedBy!,
          ...decodeTags(i.watchWith),
        ],
      },
      addedYears: {for (final i in items) i.addedAt.year},
      completedYears: {
        for (final i in items)
          if (i.completedAt != null) i.completedAt!.year,
      },
    );
    if (result != null && mounted) setState(() => _options = result);
  }

  // ------------------------------------------------------------- layout

  void _jumpTo(ListSection section, List<double> offsets) {
    if (!_scroll.hasClients) return;
    final target = offsets[section.startRow];
    _scroll.jumpTo(math.min(target, _scroll.position.maxScrollExtent));
  }

  /// After the frame: tell search how many matches this list has, and
  /// scroll to the current one when the search bar asked for a jump.
  void _syncSearch(
    ListSearch? search,
    List<int> matchRows,
    List<double> offsets,
    double itemExtent,
  ) {
    if (search == null || !widget.isActive) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      search.reportTotal(matchRows.length);
      if (_handledJump == search.jumpRequest) return;
      _handledJump = search.jumpRequest;
      if (matchRows.isEmpty || !_scroll.hasClients) return;
      final row = matchRows[math.min(search.current, matchRows.length - 1)];
      final position = _scroll.position;
      final target = offsets[row] - (position.viewportDimension - itemExtent) / 2;
      _scroll.animateTo(
        target.clamp(0.0, position.maxScrollExtent),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final search = SearchScope.maybeOf(context);
    final query = search?.query ?? '';
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final headerExtent = (22 + 22 * scale).roundToDouble();
    final itemExtent = math.max(72.0, (28 + 48 * scale).roundToDouble());

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<ListStatus>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: ListStatus.todo,
                      label: Text(widget.category.todoLabel),
                    ),
                    ButtonSegment(
                      value: ListStatus.done,
                      label: Text(widget.category.doneLabel),
                    ),
                  ],
                  selected: {_status},
                  onSelectionChanged: (s) => _setStatus(s.first),
                ),
              ),
              IconButton(
                tooltip: 'Sort & group',
                icon: const Icon(Icons.sort),
                onPressed: _openSort,
              ),
              IconButton(
                tooltip: 'Filter',
                icon: Badge(
                  isLabelVisible: _options.isFiltered,
                  child: const Icon(Icons.filter_list),
                ),
                onPressed: _openFilter,
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<MediaItem>>(
            stream: _stream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              final raw = snapshot.data;
              if (raw == null) {
                return const Center(child: CircularProgressIndicator());
              }
              final scope = AppScope.of(context);
              final all = [
                for (final i in raw)
                  if (scope.isVisible(i)) i,
              ];
              final ids = {for (final i in all) i.id};
              _hidden.removeWhere((id) => !ids.contains(id));
              final visible = [
                for (final i in all)
                  if (!_hidden.contains(i.id)) i,
              ];
              _latest = visible;
              _shown = visible;
              _selected.removeWhere((id) => !ids.contains(id));
              if (visible.isEmpty) {
                _syncSearch(search, const [], const [], itemExtent);
                return _EmptyState(category: widget.category, status: _status);
              }

              final layout = buildListLayout(visible, _options);
              final rows = layout.rows;
              final offsets = <double>[];
              var y = 0.0;
              for (final r in rows) {
                offsets.add(y);
                y += r is HeaderRow ? headerExtent : itemExtent;
              }
              final showIndex =
                  layout.sections.length >= 2 && rows.length > 12;

              final matchRows = <int>[
                if (query.isNotEmpty)
                  for (var i = 0; i < rows.length; i++)
                    if (rows[i] case ItemRow(:final item)
                        when itemMatches(item, query))
                      i,
              ];
              final currentRow = matchRows.isEmpty || search == null
                  ? null
                  : matchRows[math.min(search.current, matchRows.length - 1)];
              _syncSearch(search, matchRows, offsets, itemExtent);

              return Column(
                children: [
                  if (_options.isFiltered)
                    _FilterBanner(
                      shown: layout.itemCount,
                      total: layout.totalBeforeFilter,
                      onClear: () => setState(
                        () => _options = _options.withFilters(),
                      ),
                    ),
                  Expanded(
                    child: layout.rows.isEmpty
                        ? const Center(child: Text('Nothing matches the filter'))
                        : Stack(
                            children: [
                              Scrollbar(
                                controller: _scroll,
                                child: ListView.builder(
                                  controller: _scroll,
                                  padding: EdgeInsets.only(
                                    bottom: 80,
                                    right: showIndex ? 28 : 0,
                                  ),
                                  itemCount: rows.length,
                                  itemExtentBuilder: (index, _) {
                                    if (index >= rows.length) return null;
                                    return rows[index] is HeaderRow
                                        ? headerExtent
                                        : itemExtent;
                                  },
                                  itemBuilder: (context, index) =>
                                      switch (rows[index]) {
                                    final HeaderRow h => _GenreHeader(
                                        label: h.label,
                                        count: h.count,
                                        theme: theme,
                                      ),
                                    final ItemRow r => ItemTile(
                                        key: ValueKey(r.item.id),
                                        item: r.item,
                                        onToggle: () => _toggle(r.item),
                                        onSwipeToggle: () =>
                                            _toggle(r.item, fromSwipe: true),
                                        onEdit: () => _edit(r.item),
                                        onSwipeDelete: () => _delete(r.item),
                                        query: query,
                                        isCurrentMatch: widget.isActive &&
                                            index == currentRow,
                                        selecting: _selected.isNotEmpty,
                                        selected:
                                            _selected.contains(r.item.id),
                                        onSelect: () =>
                                            _toggleSelected(r.item.id),
                                      ),
                                  },
                                ),
                              ),
                              if (showIndex)
                                Positioned(
                                  top: 4,
                                  bottom: 4,
                                  right: 0,
                                  child: FastScrollBar(
                                    sections: layout.sections,
                                    onJump: (s) => _jumpTo(s, offsets),
                                    onActiveLabel: (l) =>
                                        setState(() => _bubble = l),
                                  ),
                                ),
                              if (_bubble != null)
                                Center(child: FastScrollBubble(label: _bubble!)),
                            ],
                          ),
                  ),
                ],
              );
            },
          ),
        ),
        if (_selected.isNotEmpty) _selectionBar(context),
      ],
    );
  }
}

/// Asks which folder to add the selected items to.
class _FolderDialog extends StatefulWidget {
  const _FolderDialog({required this.existing});
  final List<String> existing;

  @override
  State<_FolderDialog> createState() => _FolderDialogState();
}

class _FolderDialogState extends State<_FolderDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add to a folder'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: widget.existing.isEmpty,
              maxLength: kMaxTagLength,
              decoration: const InputDecoration(
                labelText: 'New folder name',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
            if (widget.existing.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final t in widget.existing)
                    ActionChip(
                      label: Text(t),
                      onPressed: () => Navigator.pop(context, t),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _name.text),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _GenreHeader extends StatelessWidget {
  const _GenreHeader({
    required this.label,
    required this.count,
    required this.theme,
  });

  final String label;
  final int count;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Text(
          '$label  ·  $count',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall
              ?.copyWith(color: theme.colorScheme.primary),
        ),
      ),
    );
  }
}

class _FilterBanner extends StatelessWidget {
  const _FilterBanner({
    required this.shown,
    required this.total,
    required this.onClear,
  });

  final int shown;
  final int total;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.only(left: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Filtered: showing $shown of $total',
                style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
              ),
            ),
            TextButton(onPressed: onClear, child: const Text('Clear')),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.category, required this.status});

  final MediaCategory category;
  final ListStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(category.icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              'Nothing in ${category.labelFor(status)} yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Type a title in the box above to add one.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
