import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../data/db/database.dart';
import '../../data/models.dart';
import 'item_tile.dart';

/// One tab: the To Watch / Watched switch and the list grouped by genre.
class CategoryPage extends StatefulWidget {
  const CategoryPage({super.key, required this.category});

  final MediaCategory category;

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

sealed class _Row {}

class _HeaderRow extends _Row {
  _HeaderRow(this.genre, this.count);
  final String genre;
  final int count;
}

class _ItemRow extends _Row {
  _ItemRow(this.item);
  final MediaItem item;
}

class _CategoryPageState extends State<CategoryPage>
    with AutomaticKeepAliveClientMixin {
  ListStatus _status = ListStatus.todo;
  Stream<List<MediaItem>>? _stream;
  final _scroll = ScrollController();

  /// Items swiped away but not yet gone from the database stream. Hiding
  /// them immediately keeps Flutter's Dismissible happy.
  final Set<int> _hidden = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream ??= _watch();
  }

  Stream<List<MediaItem>> _watch() =>
      AppScope.of(context).db.watchList(widget.category, _status);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _setStatus(ListStatus status) {
    if (status == _status) return;
    setState(() {
      _status = status;
      _hidden.clear();
      _stream = _watch();
    });
  }

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
    _showUndo(
      'Moved to ${widget.category.labelFor(target)}',
      item,
    );
  }

  Future<void> _delete(MediaItem item) async {
    setState(() => _hidden.add(item.id));
    await AppScope.of(context).db.deleteItem(item.id);
    if (!mounted) return;
    _showUndo('Deleted "${item.title}"', item);
  }

  List<_Row> _buildRows(List<MediaItem> items) {
    final rows = <_Row>[];
    String? currentGenre;
    var headerIndex = -1;
    var count = 0;
    for (final item in items) {
      if (item.genre != currentGenre) {
        if (headerIndex >= 0) {
          rows[headerIndex] = _HeaderRow(currentGenre!, count);
        }
        currentGenre = item.genre;
        headerIndex = rows.length;
        rows.add(_HeaderRow(item.genre, 0));
        count = 0;
      }
      rows.add(_ItemRow(item));
      count++;
    }
    if (headerIndex >= 0) rows[headerIndex] = _HeaderRow(currentGenre!, count);
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: SizedBox(
            width: double.infinity,
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
        ),
        Expanded(
          child: StreamBuilder<List<MediaItem>>(
            stream: _stream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              final all = snapshot.data;
              if (all == null) {
                return const Center(child: CircularProgressIndicator());
              }
              final ids = {for (final i in all) i.id};
              _hidden.removeWhere((id) => !ids.contains(id));
              final items = [
                for (final i in all)
                  if (!_hidden.contains(i.id)) i,
              ];
              if (items.isEmpty) {
                return _EmptyState(category: widget.category, status: _status);
              }
              final rows = _buildRows(items);
              return Scrollbar(
                controller: _scroll,
                interactive: true,
                thumbVisibility: rows.length > 30,
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    return switch (rows[index]) {
                      final _HeaderRow h => Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                          child: Text(
                            '${h.genre}  ·  ${h.count}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      final _ItemRow r => ItemTile(
                          key: ValueKey(r.item.id),
                          item: r.item,
                          onToggle: () => _toggle(r.item),
                          onSwipeToggle: () => _toggle(r.item, fromSwipe: true),
                          onSwipeDelete: () => _delete(r.item),
                        ),
                    };
                  },
                ),
              );
            },
          ),
        ),
      ],
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
