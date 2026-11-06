import 'package:flutter/material.dart';

import '../../data/db/database.dart';
import '../../data/models.dart';
import '../lookup/remote_thumb.dart';
import '../search/list_search.dart';

enum _SwipeAction { edit, delete }

/// A single title row: cover, title, details and tick box.
/// Tap to edit. Swipe right to tick/untick. Swipe left for Edit / Delete.
class ItemTile extends StatelessWidget {
  const ItemTile({
    super.key,
    required this.item,
    required this.onToggle,
    required this.onSwipeToggle,
    required this.onEdit,
    required this.onSwipeDelete,
    this.query = '',
    this.isCurrentMatch = false,
  });

  final MediaItem item;
  final VoidCallback onToggle;
  final VoidCallback onSwipeToggle;
  final VoidCallback onEdit;
  final VoidCallback onSwipeDelete;

  /// Search text to highlight in the title and details ('' for none).
  final String query;

  /// This row is the current search match ("3 of 12").
  final bool isCurrentMatch;

  bool get _done => item.status == ListStatus.done;

  /// The one-line summary under the title.
  static String details(MediaItem item) {
    final parts = <String>[
      if (item.year != null) '${item.year}',
      if (item.creator != null && item.creator!.isNotEmpty) item.creator!,
      if (item.season != null || item.episode != null)
        [
          if (item.season != null) 'S${item.season}',
          if (item.episode != null) 'E${item.episode}',
        ].join(' '),
      if (item.rating != null) '★' * item.rating!,
      if (item.status == ListStatus.done && item.completedAt != null)
        completedLabel(item.category, item.completedAt!),
      if (item.note != null && item.note!.isNotEmpty) '“${item.note}”',
    ];
    return parts.join('  ·  ');
  }

  Future<bool> _confirmSwipe(
      BuildContext context, DismissDirection direction) async {
    if (direction == DismissDirection.startToEnd) return true;
    final action = await showModalBottomSheet<_SwipeAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () => Navigator.pop(context, _SwipeAction.edit),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () => Navigator.pop(context, _SwipeAction.delete),
            ),
          ],
        ),
      ),
    );
    if (action == _SwipeAction.edit) {
      onEdit();
      return false;
    }
    return action == _SwipeAction.delete;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final summary = details(item);
    final highlight = TextStyle(
      backgroundColor: scheme.tertiaryContainer,
      color: scheme.onTertiaryContainer,
      fontWeight: FontWeight.w600,
    );

    final tile = ListTile(
      tileColor: isCurrentMatch ? scheme.secondaryContainer : null,
      leading: ItemCover(item: item),
      title: Text.rich(
        highlightSpan(
          item.title,
          query,
          style: _done
              ? TextStyle(color: scheme.onSurface.withValues(alpha: 0.6))
              : null,
          highlight: highlight,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: summary.isEmpty
          ? null
          : Text.rich(
              highlightSpan(summary, query, highlight: highlight),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: Checkbox(
        value: _done,
        onChanged: (_) => onToggle(),
        semanticLabel: _done ? 'Mark as not done' : 'Mark as done',
      ),
      onTap: onEdit,
    );

    return Dismissible(
      key: ValueKey('dismiss-${item.id}-${item.status.index}'),
      background: _SwipeBackground(
        color: scheme.primaryContainer,
        iconColor: scheme.onPrimaryContainer,
        icon: _done ? Icons.undo : Icons.check,
        label: _done
            ? 'Back to ${item.category.todoLabel}'
            : item.category.doneLabel,
        alignment: Alignment.centerLeft,
      ),
      secondaryBackground: _SwipeBackground(
        color: scheme.secondaryContainer,
        iconColor: scheme.onSecondaryContainer,
        icon: Icons.more_horiz,
        label: 'Edit / Delete',
        alignment: Alignment.centerRight,
      ),
      confirmDismiss: (direction) => _confirmSwipe(context, direction),
      onDismissed: (direction) => direction == DismissDirection.startToEnd
          ? onSwipeToggle()
          : onSwipeDelete(),
      child: tile,
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.color,
    required this.iconColor,
    required this.icon,
    required this.label,
    required this.alignment,
  });

  final Color color;
  final Color iconColor;
  final IconData icon;
  final String label;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final leftSide = alignment == Alignment.centerLeft;
    final children = [
      Icon(icon, color: iconColor),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(color: iconColor)),
    ];
    return Container(
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: alignment,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: leftSide ? children : children.reversed.toList(),
      ),
    );
  }
}
