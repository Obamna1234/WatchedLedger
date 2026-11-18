import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_scope.dart';
import '../../core/net/net_client.dart';
import '../../core/sanitise.dart';
import '../../data/db/database.dart';
import '../../data/lookup/candidate.dart';
import '../../data/lookup/link_lookup.dart';
import 'add_link.dart';
import '../../data/lookup/lookup_service.dart';
import '../../data/models.dart';
import '../lookup/lookup_sheet.dart';

/// Opens the "Add" sheet from the big + button. Starts on the category and
/// list you're looking at; both can be changed with one tap.
Future<void> showAddSheet(
  BuildContext context, {
  required MediaCategory category,
  ListStatus status = ListStatus.todo,
  VoidCallback? onImport,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
      child: SafeArea(
        child: QuickAddBar(
          category: category,
          status: status,
          autofocus: true,
          onAdded: () => Navigator.of(sheetContext).pop(),
          onImport: onImport == null
              ? null
              : () {
                  Navigator.of(sheetContext).pop();
                  onImport();
                },
        ),
      ),
    ),
  );
}

/// The add form: what kind of thing, which list, and the title.
class QuickAddBar extends StatefulWidget {
  const QuickAddBar({
    super.key,
    required this.category,
    this.status = ListStatus.todo,
    this.focusNode,
    this.autofocus = false,
    this.onAdded,
    this.onImport,
  });

  final MediaCategory category;
  final ListStatus status;
  final bool autofocus;

  /// Called after something was saved (the sheet closes).
  final VoidCallback? onAdded;

  /// "Paste a list or import a file".
  final VoidCallback? onImport;

  /// Lets the home screen widget's "+" jump straight into typing.
  final FocusNode? focusNode;

  @override
  State<QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends State<QuickAddBar> {
  final _controller = TextEditingController();
  final _ownFocus = FocusNode();
  FocusNode get _focus => widget.focusNode ?? _ownFocus;
  late MediaCategory _category = widget.category;
  late ListStatus _status = widget.status;
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
    _ownFocus.dispose();
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
  Future<void> _addLink(Uri link) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final added = await addLinkItem(context, link,
          fallback: _category, status: _status);
      if (added && mounted) {
        _controller.clear();
        widget.onAdded?.call();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final link = LinkLookup.asLink(_controller.text);
    if (link != null) return _addLink(link);
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
      var fillIn = false;

      if (scope.settings.offlineMode) {
        asTyped = typed;
        note = 'Offline mode is on, so it was saved as typed.';
      } else if (!scope.settings.lookupsEnabled) {
        asTyped = typed;
        matchState = MatchState.manual;
      } else if (!scope.net.mayUse(NetPurpose.lookup)) {
        asTyped = typed;
        note = "You're on mobile data, so it was saved as typed. Details "
            'will be filled in when you are back on Wi-Fi.';
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
              'typed. It will be matched automatically later.';
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
              case SaveAsTyped(:final text, :final fillInDetails):
                asTyped = text;
                matchState = MatchState.manual;
                fillIn = fillInDetails;
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
        pages: picked?.pages,
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
      if (fillIn) {
        final nav = Navigator.of(context);
        widget.onAdded?.call();
        await openNewItemEditor(nav.context, scope.db, id);
        return;
      }
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
      widget.onAdded?.call();
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add to your lists', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in MediaCategory.values)
                ChoiceChip(
                  avatar: Icon(c.icon, size: 18),
                  label: Text(c.tabLabel),
                  showCheckmark: false,
                  selected: c == _category,
                  onSelected: (_) => setState(() => _category = c),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<ListStatus>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                  value: ListStatus.todo, label: Text(_category.todoLabel)),
              ButtonSegment(
                  value: ListStatus.done, label: Text(_category.doneLabel)),
            ],
            selected: {_status},
            onSelectionChanged: (s) => setState(() => _status = s.first),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  autofocus: widget.autofocus,
                  textInputAction: TextInputAction.done,
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(kMaxTitleLength),
                  ],
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: _category == MediaCategory.video
                        ? 'Paste a link or type a title'
                        : 'Type a ${_category.singular} title or paste a link',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Add',
                iconSize: 28,
                onPressed: _busy ? null : _submit,
                icon: _busy
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
              ),
            ],
          ),
          if (widget.onImport != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.playlist_add),
              label: const Text('Have a list? Paste it or import a file'),
              onPressed: widget.onImport,
            ),
          ],
        ],
      ),
    );
  }
}
