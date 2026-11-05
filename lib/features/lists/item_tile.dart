import 'package:flutter/material.dart';

import '../../data/db/database.dart';
import '../../data/models.dart';

/// A single title row: cover, title, year, completion date and tick box.
/// Swipe right to tick/untick, swipe left to delete.
class ItemTile extends StatelessWidget {
  const ItemTile({
    super.key,
    required this.item,
    required this.onToggle,
    required this.onSwipeToggle,
    required this.onSwipeDelete,
  });

  final MediaItem item;
  final VoidCallback onToggle;
  final VoidCallback onSwipeToggle;
  final VoidCallback onSwipeDelete;

  bool get _done => item.status == ListStatus.done;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final details = <String>[
      if (item.year != null) '${item.year}',
      if (item.creator != null && item.creator!.isNotEmpty) item.creator!,
      if (_done && item.completedAt != null)
        completedLabel(item.category, item.completedAt!),
    ];

    final tile = ListTile(
      leading: _CoverThumb(item: item),
      title: Text(
        item.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: _done
            ? TextStyle(color: scheme.onSurface.withValues(alpha: 0.6))
            : null,
      ),
      subtitle: details.isEmpty ? null : Text(details.join('  ·  ')),
      trailing: Checkbox(
        value: _done,
        onChanged: (_) => onToggle(),
        semanticLabel: _done ? 'Mark as not done' : 'Mark as done',
      ),
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
        color: scheme.errorContainer,
        iconColor: scheme.onErrorContainer,
        icon: Icons.delete_outline,
        label: 'Delete',
        alignment: Alignment.centerRight,
      ),
      onDismissed: (direction) => direction == DismissDirection.startToEnd
          ? onSwipeToggle()
          : onSwipeDelete(),
      child: tile,
    );
  }
}

class _CoverThumb extends StatelessWidget {
  const _CoverThumb({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Real cover images arrive with the lookup feature; until then a
    // category icon keeps the layout stable.
    return Container(
      width: 40,
      height: 56,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(item.category.icon, color: scheme.onSurfaceVariant),
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
