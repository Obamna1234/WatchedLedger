import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/net/net_client.dart';
import '../../core/sanitise.dart';
import '../../data/models.dart';
import '../../data/transfer/import_parsers.dart';
import '../../data/transfer/import_plan.dart';
import '../lookup/lookup_sheet.dart';
import '../lookup/remote_thumb.dart';

const int _maxImportFileBytes = 10 * 1024 * 1024;

/// Paste or pick a file -> look titles up -> review -> save.
/// Pops with the number of titles added.
class ImportPage extends StatefulWidget {
  const ImportPage({super.key, this.initialText});

  /// Text to start with (e.g. something shared into the app).
  final String? initialText;

  @override
  State<ImportPage> createState() => _ImportPageState();
}

enum _Phase { input, lookingUp, review }

class _ImportPageState extends State<ImportPage> {
  late final TextEditingController _text =
      TextEditingController(text: widget.initialText ?? '');
  MediaCategory _category = MediaCategory.movie;
  _Phase _phase = _Phase.input;
  ImportFormat? _format;
  List<ImportEntry> _entries = [];
  int _done = 0, _total = 0;
  bool _cancel = false;
  bool _onlyToCheck = false;
  bool _saving = false;
  String? _lookupNote;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _toast(String text) => ScaffoldMessenger.of(context)
    ..removeCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _pickFile() async {
    final picked = await FilePicker.pickFile(
        dialogTitle: 'Choose a list (.txt, .csv or .json)');
    if (picked == null || !mounted) return;
    final bytes = await picked.xFile.readAsBytes();
    if (!mounted) return;
    if (bytes.length > _maxImportFileBytes) {
      _toast('That file is too large (10 MB max).');
      return;
    }
    final String text;
    try {
      text = utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      _toast("That file couldn't be read as text.");
      return;
    }
    if (text.contains('\u0000')) {
      _toast("That doesn't look like a text, CSV or JSON file.");
      return;
    }
    await _start(text, fileName: picked.name);
  }

  Future<void> _start(String text, {String? fileName}) async {
    final parsed = parseImport(text, fileName: fileName);
    if (parsed.rows.isEmpty) {
      _toast('No titles found.');
      return;
    }
    final scope = AppScope.of(context);
    final entries = await prepareImport(scope.db, parsed.rows, _category);
    if (!mounted) return;
    setState(() {
      _format = parsed.format;
      _entries = entries;
    });
    await _lookup();
  }

  Future<void> _lookup() async {
    final scope = AppScope.of(context);
    final settings = scope.settings;
    String? note;
    if (settings.offlineMode) {
      note = 'Offline mode is on, so titles are saved as typed and can be '
          'matched later.';
    } else if (!settings.lookupsEnabled) {
      note = 'Lookups are off, so titles are saved as typed.';
    } else if (!scope.net.mayUse(NetPurpose.lookup)) {
      note = "You're on mobile data, so titles are saved as typed and looked "
          'up automatically once you are back on Wi-Fi.';
    }
    if (note != null) {
      setState(() {
        _lookupNote = note;
        _phase = _Phase.review;
      });
      return;
    }
    _cancel = false;
    setState(() => _phase = _Phase.lookingUp);
    await lookupAll(
      scope.lookup,
      _entries,
      cancelled: () => _cancel || !mounted,
      onProgress: (d, t) {
        if (!mounted) return;
        setState(() {
          _done = d;
          _total = t;
        });
      },
    );
    if (!mounted) return;
    await markDuplicates(scope.db, _entries);
    if (!mounted) return;
    final missed = _entries.where((e) => e.include && !e.looked).length;
    setState(() {
      _lookupNote = missed > 0
          ? '$missed titles were not looked up. They are saved as typed and '
              'matched later.'
          : null;
      _phase = _Phase.review;
    });
  }

  Future<void> _fix(ImportEntry e) async {
    final choice = await showLookupSheet(context,
        category: e.category, query: e.row.query);
    if (choice == null || !mounted) return;
    final scope = AppScope.of(context);
    switch (choice) {
      case PickedCandidate(:final candidate):
        e.match = await scope.lookup.details(candidate);
      case SaveAsTyped(:final text):
        final t = cleanTitle(text);
        if (t.isNotEmpty) e.row.title = t;
        e.match = null;
    }
    e
      ..confirmed = true
      ..looked = true
      ..include = true;
    await markDuplicates(scope.db, _entries);
    if (mounted) setState(() {});
  }

  Future<void> _changeCategory(ImportEntry e) async {
    final picked = await showModalBottomSheet<MediaCategory>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in MediaCategory.values)
              ListTile(
                title: Text(c.tabLabel),
                trailing: c == e.category ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, c),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked == e.category || !mounted) return;
    e
      ..category = picked
      ..match = null
      ..looked = false
      ..confirmed = false;
    final db = AppScope.of(context).db;
    await markDuplicates(db, _entries);
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final scope = AppScope.of(context);
    final added = await saveImport(scope.db, _entries);
    final matcher = scope.matcher;
    if (matcher != null) unawaited(matcher.run());
    if (!mounted) return;
    Navigator.of(context).pop(added);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _phase == _Phase.input,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_phase == _Phase.lookingUp) {
          _cancel = true;
        } else {
          setState(() => _phase = _Phase.input);
        }
      },
      child: switch (_phase) {
        _Phase.input => _buildInput(context),
        _Phase.lookingUp => _buildProgress(context),
        _Phase.review => _buildReview(context),
      },
    );
  }

  Widget _buildInput(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Import titles')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text('Paste a list, one title per line',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _text,
            minLines: 6,
            maxLines: 12,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Heat (1995)\n[x] The Wire\n~~Dune~~',
            ),
          ),
          const SizedBox(height: 16),
          Text('Titles without a category are added to',
              style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final c in MediaCategory.values)
                ChoiceChip(
                  label: Text(c.tabLabel),
                  selected: _category == c,
                  onSelected: (_) => setState(() => _category = c),
                ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            icon: const Icon(Icons.playlist_add_check),
            label: const Text('Continue'),
            onPressed: () {
              final text = _text.text;
              if (text.trim().isEmpty) {
                _toast('Paste some titles first, or choose a file.');
                return;
              }
              unawaited(_start(text));
            },
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('Choose a file'),
            onPressed: _pickFile,
          ),
          const SizedBox(height: 20),
          Text(
            'Works with: plain lists, Samsung Notes checklists (ticked or '
            'crossed-out items go to Watched), .txt and .csv files, and the '
            'export files from Letterboxd, Goodreads, IMDb and Trakt.\n\n'
            'Nothing is saved until you check the list on the next screen.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildProgress(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Looking up titles')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
              const SizedBox(height: 16),
              Text('$_done of $_total', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text('Only each title is sent, one at a time.',
                  style: theme.textTheme.bodySmall),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => _cancel = true,
                child: const Text('Skip the rest'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReview(BuildContext context) {
    final theme = Theme.of(context);
    final included = _entries.where((e) => e.include).length;
    final found = _entries.where((e) => e.include && e.match != null).length;
    final toCheck = _entries.where((e) => e.needsAttention).length;
    final dupes = _entries.where((e) => e.duplicate).length;
    final shown = _onlyToCheck
        ? _entries.where((e) => e.needsAttention || e.duplicate).toList()
        : _entries;
    final notLooked = _entries.where((e) => e.include && !e.looked).length;

    return Scaffold(
      appBar: AppBar(
        title: Text('Check ${_entries.length} titles'),
        actions: [
          if (notLooked > 0 && _lookupNote == null)
            IconButton(
              tooltip: 'Look up again',
              icon: const Icon(Icons.refresh),
              onPressed: _lookup,
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_format != null)
                  Text('Read as: ${_format!.label}',
                      style: theme.textTheme.bodySmall),
                if (_lookupNote != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_lookupNote!, style: theme.textTheme.bodySmall),
                  ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    Chip(label: Text('Matched $found')),
                    FilterChip(
                      label: Text('To check $toCheck · Duplicates $dupes'),
                      selected: _onlyToCheck,
                      onSelected: (v) => setState(() => _onlyToCheck = v),
                    ),
                  ],
                ),
                Text(
                  'Tap a title to fix the match. Tap To Watch / Watched to '
                  'switch lists. Long-press to change the category.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: shown.length,
              itemBuilder: (context, i) => _EntryTile(
                entry: shown[i],
                onChanged: () => setState(() {}),
                onFix: () => _fix(shown[i]),
                onLongPress: () => _changeCategory(shown[i]),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: FilledButton(
            onPressed: included == 0 || _saving ? null : _save,
            child: Text(_saving
                ? 'Saving…'
                : 'Add $included ${included == 1 ? 'title' : 'titles'}'),
          ),
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.onChanged,
    required this.onFix,
    required this.onLongPress,
  });

  final ImportEntry entry;
  final VoidCallback onChanged;
  final VoidCallback onFix;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = entry;
    final details = <String>[
      e.category.singular,
      if (e.year != null) '${e.year}',
      if (e.match != null && e.match!.genre != kUncategorised) e.match!.genre,
    ];
    final String state;
    if (e.duplicate) {
      state = 'Already in your list';
    } else if (e.match != null) {
      state = e.confirmed ? 'Chosen by you' : 'Matched';
    } else if (e.confirmed) {
      state = 'Saved as typed';
    } else if (e.looked) {
      state = 'No clear match: tap to choose';
    } else {
      state = 'Not looked up yet';
    }
    final typedDiffers =
        e.match != null && matchKey(e.match!.title) != matchKey(e.row.title);

    return InkWell(
      onTap: onFix,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
        child: Row(
          children: [
            Checkbox(
              value: e.include,
              onChanged: (v) {
                e.include = v ?? false;
                onChanged();
              },
            ),
            RemoteThumb(url: e.match?.coverUrl, category: e.category),
            const SizedBox(width: 12),
            Expanded(
              child: Opacity(
                opacity: e.include ? 1 : 0.5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall),
                    Text(details.join(' · '), style: theme.textTheme.bodySmall),
                    if (typedDiffers)
                      Text('You wrote: ${e.row.title}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall),
                    Text(
                      state,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: e.needsAttention || e.duplicate
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                e.status = e.status == ListStatus.done
                    ? ListStatus.todo
                    : ListStatus.done;
                onChanged();
              },
              child: Text(e.category.labelFor(e.status)),
            ),
          ],
        ),
      ),
    );
  }
}
