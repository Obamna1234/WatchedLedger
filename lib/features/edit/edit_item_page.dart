import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_scope.dart';
import '../../core/sanitise.dart';
import '../../data/db/database.dart';
import '../../data/genres.dart';
import '../../data/lookup/candidate.dart';
import '../../data/models.dart';
import '../lookup/lookup_sheet.dart';
import '../lookup/remote_thumb.dart';

/// What happened on the edit screen, so the list can offer Undo.
sealed class EditOutcome {
  const EditOutcome();
}

class EditSaved extends EditOutcome {
  const EditSaved(this.previous, this.updated);
  final MediaItem previous;
  final MediaItem updated;
}

class EditDeleteRequested extends EditOutcome {
  const EditDeleteRequested();
}

const int kMaxGenreLength = 40;

class EditItemPage extends StatefulWidget {
  const EditItemPage({super.key, required this.item});

  final MediaItem item;

  @override
  State<EditItemPage> createState() => _EditItemPageState();
}

class _EditItemPageState extends State<EditItemPage> {
  late final TextEditingController _title =
      TextEditingController(text: widget.item.title);
  late final TextEditingController _year =
      TextEditingController(text: widget.item.year?.toString() ?? '');
  late final TextEditingController _genre =
      TextEditingController(text: widget.item.genre);
  late final TextEditingController _creator =
      TextEditingController(text: widget.item.creator ?? '');
  late final TextEditingController _note =
      TextEditingController(text: widget.item.note ?? '');

  late MediaCategory _category = widget.item.category;
  late ListStatus _status = widget.item.status;
  late int? _rating = widget.item.rating;
  late int? _season = widget.item.season;
  late int? _episode = widget.item.episode;
  late DateTime? _completedAt = widget.item.completedAt;

  // Lookup data; changed by "Look up details".
  late String? _coverUrl = widget.item.coverUrl;
  late String? _coverFile = widget.item.coverFile;
  late String? _source = widget.item.source;
  late String? _sourceId = widget.item.sourceId;
  late MatchState _matchState = widget.item.matchState;

  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _title.dispose();
    _year.dispose();
    _genre.dispose();
    _creator.dispose();
    _note.dispose();
    super.dispose();
  }

  String? _validateYear(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return null;
    final year = int.tryParse(text);
    final max = DateTime.now().year + 10;
    if (year == null || year < 1000 || year > max) {
      return 'Enter a year between 1000 and $max';
    }
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final now = DateTime.now();
    final previous = widget.item;

    final genre = cleanText(_genre.text, maxLength: kMaxGenreLength);
    final creator = cleanText(_creator.text);
    final note = cleanText(_note.text, maxLength: kMaxNoteLength);
    final isSeries = _category == MediaCategory.series;

    DateTime? completedAt;
    if (_status == ListStatus.done) {
      completedAt = _completedAt ?? now;
    }

    final updated = previous.copyWith(
      title: cleanTitle(_title.text),
      category: _category,
      status: _status,
      year: Value(int.tryParse(_year.text.trim())),
      genre: genre.isEmpty ? kUncategorised : genre,
      creator: Value(creator.isEmpty ? null : creator),
      rating: Value(_rating),
      note: Value(note.isEmpty ? null : note),
      season: Value(isSeries ? _season : null),
      episode: Value(isSeries ? _episode : null),
      completedAt: Value(completedAt),
      coverUrl: Value(_coverUrl),
      coverFile: Value(_coverFile),
      source: Value(_source),
      sourceId: Value(_sourceId),
      matchState: _matchState,
      updatedAt: now,
    );

    await AppScope.of(context).db.updateItem(updated);
    if (!mounted) return;
    Navigator.of(context).pop(EditSaved(previous, updated));
  }

  Future<void> _lookUp() async {
    final choice = await showLookupSheet(
      context,
      category: _category,
      query: cleanTitle(_title.text),
    );
    if (choice == null || !mounted) return;
    setState(() {
      switch (choice) {
        case PickedCandidate(:final candidate):
          _applyCandidate(candidate);
        case SaveAsTyped(:final text):
          _title.text = text;
          _matchState = MatchState.manual;
      }
    });
  }

  void _applyCandidate(LookupCandidate c) {
    _title.text = c.title;
    if (c.year != null) _year.text = '${c.year}';
    if (c.genre != kUncategorised) _genre.text = c.genre;
    if (c.creator != null) _creator.text = c.creator!;
    if (c.coverUrl != null && c.coverUrl != _coverUrl) {
      _coverUrl = c.coverUrl;
      _coverFile = null; // the list will download the new cover
    }
    _source = c.source;
    _sourceId = c.sourceId;
    _matchState = MatchState.matched;
  }

  Future<void> _pickGenre() async {
    final inUse = await AppScope.of(context).db.genresInUse(_category);
    if (!mounted) return;
    final options = {...curatedGenres(_category), ...inUse}
        .where((g) => g != kUncategorised)
        .toList()
      ..sort(compareGenres);
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final g in options)
              ListTile(
                title: Text(g),
                trailing: g == _genre.text ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, g),
              ),
            ListTile(
              title: const Text(kUncategorised),
              onTap: () => Navigator.pop(context, kUncategorised),
            ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _genre.text = picked);
  }

  Future<void> _pickCompletedDate() async {
    final now = DateTime.now();
    final current = _completedAt;
    final picked = await showDatePicker(
      context: context,
      initialDate: (current == null || current.isAfter(now)) ? now : current,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null && mounted) setState(() => _completedAt = picked);
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this title?'),
        content: Text('"${widget.item.title}" will be removed. '
            'You can undo straight afterwards.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    Navigator.of(context).pop(const EditDeleteRequested());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const gap = SizedBox(height: 16);
    final creatorLabel = switch (_category) {
      MediaCategory.movie => 'Director',
      MediaCategory.series => 'Creator',
      MediaCategory.book => 'Author',
      MediaCategory.audiobook => 'Author / narrator',
      MediaCategory.podcast => 'Host',
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit'),
        actions: [
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: _confirmDelete,
          ),
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Row(
              children: [
                _coverFile != null
                    ? ItemCover(
                        item: widget.item.copyWith(
                          coverFile: Value(_coverFile),
                          coverUrl: Value(_coverUrl),
                        ),
                        width: 60,
                        height: 84,
                      )
                    : RemoteThumb(
                        key: ValueKey(_coverUrl),
                        url: _coverUrl,
                        category: _category,
                        width: 60,
                        height: 84,
                      ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        switch (_matchState) {
                          MatchState.matched =>
                              'Matched${_source == null ? '' : ' via ${_sourceLabel(_source!)}'}',
                          MatchState.manual => 'Saved as typed',
                          MatchState.unmatched => 'Not looked up yet',
                        },
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      OutlinedButton.icon(
                        onPressed: _lookUp,
                        icon: const Icon(Icons.travel_explore),
                        label: const Text('Look up details'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            gap,
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              inputFormatters: [
                LengthLimitingTextInputFormatter(kMaxTitleLength),
              ],
              validator: (v) =>
                  cleanTitle(v ?? '').isEmpty ? 'Title is required' : null,
            ),
            gap,
            Row(
              children: [
                Expanded(
                  child: DropdownButton<MediaCategory>(
                    isExpanded: true,
                    value: _category,
                    items: [
                      for (final c in MediaCategory.values)
                        DropdownMenuItem(
                          value: c,
                          child: Row(
                            children: [
                              Icon(c.icon, size: 20),
                              const SizedBox(width: 8),
                              Text(c.tabLabel),
                            ],
                          ),
                        ),
                    ],
                    onChanged: (c) {
                      if (c != null) setState(() => _category = c);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 120,
                  child: TextFormField(
                    controller: _year,
                    decoration: const InputDecoration(
                      labelText: 'Year',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    validator: _validateYear,
                  ),
                ),
              ],
            ),
            gap,
            SegmentedButton<ListStatus>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: ListStatus.todo,
                  label: Text(_category.todoLabel),
                ),
                ButtonSegment(
                  value: ListStatus.done,
                  label: Text(_category.doneLabel),
                ),
              ],
              selected: {_status},
              onSelectionChanged: (s) => setState(() => _status = s.first),
            ),
            if (_status == ListStatus.done)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_available_outlined),
                title: Text(completedLabel(_category, _completedAt ?? DateTime.now())),
                subtitle: const Text('Tap to change the date'),
                onTap: _pickCompletedDate,
              ),
            gap,
            TextFormField(
              controller: _genre,
              decoration: InputDecoration(
                labelText: 'Genre',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'Pick a genre',
                  icon: const Icon(Icons.list),
                  onPressed: _pickGenre,
                ),
              ),
              textCapitalization: TextCapitalization.words,
              inputFormatters: [
                LengthLimitingTextInputFormatter(kMaxGenreLength),
              ],
            ),
            gap,
            TextFormField(
              controller: _creator,
              decoration: InputDecoration(
                labelText: '$creatorLabel (optional)',
                border: const OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              inputFormatters: [
                LengthLimitingTextInputFormatter(kMaxTitleLength),
              ],
            ),
            gap,
            Text('Your rating', style: theme.textTheme.titleSmall),
            Row(
              children: [
                for (var star = 1; star <= 5; star++)
                  IconButton(
                    tooltip: '$star star${star == 1 ? '' : 's'}',
                    icon: Icon(
                      (_rating ?? 0) >= star ? Icons.star : Icons.star_border,
                      color: theme.colorScheme.primary,
                    ),
                    // Tapping the current rating again clears it.
                    onPressed: () => setState(
                      () => _rating = _rating == star ? null : star,
                    ),
                  ),
              ],
            ),
            gap,
            TextFormField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'Note (one line, optional)',
                border: OutlineInputBorder(),
              ),
              inputFormatters: [
                LengthLimitingTextInputFormatter(kMaxNoteLength),
              ],
            ),
            if (_category == MediaCategory.series) ...[
              gap,
              Text('Progress', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _Counter(
                      label: 'Season',
                      value: _season,
                      onChanged: (v) => setState(() => _season = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Counter(
                      label: 'Episode',
                      value: _episode,
                      onChanged: (v) => setState(() => _episode = v),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A − value + stepper. Going below 1 clears the value.
class _Counter extends StatelessWidget {
  const _Counter({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = value;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            tooltip: 'Previous $label',
            icon: const Icon(Icons.remove),
            onPressed: v == null ? null : () => onChanged(v <= 1 ? null : v - 1),
          ),
          Text(v?.toString() ?? '–'),
          IconButton(
            tooltip: 'Next $label',
            icon: const Icon(Icons.add),
            onPressed: v != null && v >= 999
                ? null
                : () => onChanged((v ?? 0) + 1),
          ),
        ],
      ),
    );
  }
}

String _sourceLabel(String source) => switch (source) {
      'itunes' => 'iTunes',
      'tvmaze' => 'TVmaze',
      'openlibrary' => 'Open Library',
      'googlebooks' => 'Google Books',
      _ => source,
    };
