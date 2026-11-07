import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_scope.dart';
import '../../core/net/net_client.dart';
import '../../core/sanitise.dart';
import '../../data/db/database.dart';
import '../../data/lookup/candidate.dart';
import '../../data/lookup/lookup_service.dart';
import '../../data/models.dart';
import '../lookup/lookup_sheet.dart';

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

  Future<bool> _duplicateOk(AppDatabase db, String title) async {
    final duplicates = await db.findDuplicates(title);
    if (duplicates.isEmpty) return true;
    if (!mounted) return false;
    return await _confirmDuplicate(title, duplicates) == true;
  }

  /// Add flow: duplicate check → lookup → auto-file if clear, otherwise
  /// "Did you mean…?" (where the user can also keep typing and save as
  /// typed) → save → fetch the cover in the background.
  Future<void> _submit() async {
    final typed = cleanTitle(_controller.text);
    if (typed.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final scope = AppScope.of(context);
      final category = _category;
      final status = _status;
      if (!await _duplicateOk(scope.db, typed) || !mounted) return;

      LookupCandidate? picked;
      String? asTyped;
      var matchState = MatchState.unmatched;
      String? note;

      if (scope.settings.offlineMode) {
        asTyped = typed;
        note = 'Offline mode is on, so it was saved as typed.';
      } else if (!scope.settings.lookupsEnabled) {
        asTyped = typed;
        matchState = MatchState.manual;
      } else {
        LookupResult? result;
        try {
          result = await scope.lookup.search(typed, category);
        } on OfflineException {
          result = null;
        }
        if (!mounted) return;
        if (result == null || result.couldNotReach) {
          asTyped = typed;
          note = "Couldn't reach the lookup service, so it was saved as "
              'typed. You can match it later from Edit.';
        } else {
          picked = LookupService.confidentMatch(typed, result.candidates);
          if (picked == null) {
            final choice = await showLookupSheet(
              context,
              category: category,
              query: typed,
              initial: result,
            );
            // Dismissed: leave the text in the box so nothing is lost.
            if (!mounted || choice == null) return;
            switch (choice) {
              case PickedCandidate(:final candidate):
                picked = candidate;
              case SaveAsTyped(:final text):
                asTyped = text;
                matchState = MatchState.manual;
            }
          }
        }
      }

      final chosen = picked;
      if (chosen != null) {
        picked = await scope.lookup.details(chosen);
        if (!mounted) return;
      }

      final title = picked?.title ?? asTyped ?? typed;
      if (matchKey(title) != matchKey(typed)) {
        if (!await _duplicateOk(scope.db, title) || !mounted) return;
      }

      final id = await scope.db.addItem(
        category: category,
        status: status,
        title: title,
        typedTitle: typed,
        year: picked?.year,
        genre: picked?.genre,
        creator: picked?.creator,
        coverUrl: picked?.coverUrl,
        source: picked?.source,
        sourceId: picked?.sourceId,
        matchState: picked != null ? MatchState.matched : matchState,
      );

      final coverUrl = picked?.coverUrl;
      if (coverUrl != null) {
        unawaited(scope.covers.ensure(coverUrl).then((name) async {
          if (name != null) await scope.db.setCoverFile(id, name);
        }));
      }

      if (!mounted) return;
      _controller.clear();
      final year = picked?.year;
      final label = year == null ? title : '$title ($year)';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(
            'Added "$label" to ${category.tabLabel} › '
            '${category.labelFor(status)}'
            '${note == null ? '' : '\n$note'}',
          ),
          duration: Duration(seconds: note == null ? 4 : 6),
          persist: false,
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => scope.db.deleteItem(id),
          ),
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
            icon: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
