import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_scope.dart';
import '../../core/sanitise.dart';
import '../../data/db/database.dart';
import '../../data/models.dart';

/// Text box at the top of the main screen. The category follows the open tab
/// but can be changed for a single add.
class QuickAddBar extends StatefulWidget {
  const QuickAddBar({super.key, required this.category});

  final MediaCategory category;

  @override
  State<QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends State<QuickAddBar> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  late MediaCategory _category = widget.category;
  ListStatus _status = ListStatus.todo;
  bool _busy = false;

  @override
  void didUpdateWidget(QuickAddBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.category != widget.category) {
      _category = widget.category;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = cleanTitle(_controller.text);
    if (title.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final db = AppScope.of(context).db;
      final duplicates = await db.findDuplicates(title);
      if (!mounted) return;
      if (duplicates.isNotEmpty) {
        final addAnyway = await _confirmDuplicate(title, duplicates);
        if (addAnyway != true || !mounted) return;
      }
      final category = _category;
      final status = _status;
      await db.addItem(
        category: category,
        status: status,
        title: title,
        typedTitle: title,
      );
      if (!mounted) return;
      _controller.clear();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(
            'Added to ${category.tabLabel} › ${category.labelFor(status)}',
          ),
          duration: const Duration(seconds: 2),
        ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmDuplicate(String title, List<MediaItem> existing) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Already on your lists'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('"$title" matches:'),
            const SizedBox(height: 8),
            for (final item in existing.take(5))
              Text(
                '• ${item.title}${item.year != null ? ' (${item.year})' : ''}'
                ' — ${item.category.tabLabel} › '
                '${item.category.labelFor(item.status)}',
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add anyway'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        children: [
          PopupMenuButton<MediaCategory>(
            tooltip: 'Category: ${_category.tabLabel}',
            initialValue: _category,
            onSelected: (c) => setState(() => _category = c),
            icon: Icon(_category.icon, color: scheme.primary),
            itemBuilder: (context) => [
              for (final c in MediaCategory.values)
                PopupMenuItem(
                  value: c,
                  child: ListTile(
                    leading: Icon(c.icon),
                    title: Text(c.tabLabel),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
            ],
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.words,
              inputFormatters: [
                LengthLimitingTextInputFormatter(kMaxTitleLength),
              ],
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: 'Add a ${_category.singular}…',
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: () => setState(() {
              _status = _status == ListStatus.todo
                  ? ListStatus.done
                  : ListStatus.todo;
            }),
            child: Text(_category.labelFor(_status)),
          ),
          IconButton.filled(
            tooltip: 'Add',
            onPressed: _busy ? null : _submit,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
