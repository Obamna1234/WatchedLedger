import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_scope.dart';
import '../../data/db/database.dart';
import '../../data/models.dart';
import '../../data/tags.dart';

/// Tag chips with an "add tag" box that suggests tags already in use.
class TagEditor extends StatefulWidget {
  const TagEditor({super.key, required this.tags, required this.onChanged});
  final List<String> tags;
  final ValueChanged<List<String>> onChanged;

  @override
  State<TagEditor> createState() => _TagEditorState();
}

class _TagEditorState extends State<TagEditor> {
  List<String> _known = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    AppScope.of(context).db.tagsInUse().then((t) {
      if (mounted) setState(() => _known = t);
    }).ignore();
  }

  void _add(String raw) {
    final t = cleanTag(raw);
    if (t.isEmpty) return;
    if (widget.tags.any((x) => x.toLowerCase() == t.toLowerCase())) return;
    if (widget.tags.length >= kMaxTagsPerItem) return;
    widget.onChanged([...widget.tags, t]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final have = {for (final t in widget.tags) t.toLowerCase()};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tags', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final t in widget.tags)
              InputChip(
                label: Text(t),
                onDeleted: () => widget
                    .onChanged([for (final x in widget.tags) if (x != t) x]),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Autocomplete<String>(
          optionsBuilder: (value) {
            final q = value.text.trim().toLowerCase();
            return _known.where((t) =>
                !have.contains(t.toLowerCase()) &&
                (q.isEmpty || t.toLowerCase().contains(q)));
          },
          onSelected: (t) => _add(t),
          fieldViewBuilder: (context, controller, focus, onSubmit) =>
              TextField(
            controller: controller,
            focusNode: focus,
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: [
              LengthLimitingTextInputFormatter(kMaxTagLength),
            ],
            decoration: const InputDecoration(
              hintText: 'Add a tag, e.g. Halloween or with Sam',
              prefixIcon: Icon(Icons.sell_outlined),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) {
              _add(v);
              controller.clear();
              focus.requestFocus();
            },
          ),
        ),
      ],
    );
  }
}

/// Reading / listening progress for books and audiobooks.
class ProgressEditor extends StatelessWidget {
  const ProgressEditor({
    super.key,
    required this.category,
    required this.unit,
    required this.current,
    required this.total,
    required this.onChanged,
  });

  final MediaCategory category;
  final ProgressUnit? unit;
  final int? current;
  final int? total;
  final void Function(ProgressUnit? unit, int? current, int? total) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAudio = category == MediaCategory.audiobook;
    final u = isAudio
        ? ProgressUnit.minutes
        : (unit == ProgressUnit.percent ? ProgressUnit.percent : ProgressUnit.pages);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
                child: Text(isAudio ? 'Listening progress' : 'Reading progress',
                    style: theme.textTheme.titleSmall)),
            if (!isAudio)
              SegmentedButton<ProgressUnit>(
                segments: const [
                  ButtonSegment(value: ProgressUnit.pages, label: Text('Pages')),
                  ButtonSegment(value: ProgressUnit.percent, label: Text('%')),
                ],
                selected: {u},
                showSelectedIcon: false,
                onSelectionChanged: (s) => onChanged(s.first, null, null),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (u == ProgressUnit.percent)
          _NumberField(
            key: const ValueKey('pct'),
            label: 'Percent read',
            value: current,
            max: 100,
            onChanged: (v) => onChanged(u, v, 100),
          )
        else
          Row(
            children: [
              Expanded(
                child: isAudio
                    ? _DurationField(
                        key: const ValueKey('listened'),
                        label: 'Listened (h:mm)',
                        minutes: current,
                        onChanged: (v) => onChanged(u, v, total),
                      )
                    : _NumberField(
                        key: const ValueKey('page'),
                        label: 'Page',
                        value: current,
                        max: 99999,
                        onChanged: (v) => onChanged(u, v, total),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: isAudio
                    ? _DurationField(
                        key: const ValueKey('length'),
                        label: 'Length (h:mm)',
                        minutes: total,
                        onChanged: (v) => onChanged(u, current, v),
                      )
                    : _NumberField(
                        key: const ValueKey('pages'),
                        label: 'of',
                        value: total,
                        max: 99999,
                        onChanged: (v) => onChanged(u, current, v),
                      ),
              ),
            ],
          ),
        if (progressFraction(u, current, total) case final f?) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: f,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
        ],
      ],
    );
  }
}

/// 0..1, or null if unknown.
double? progressFraction(ProgressUnit? unit, int? current, int? total) {
  if (current == null) return null;
  if (unit == ProgressUnit.percent) return (current / 100).clamp(0.0, 1.0);
  if (total == null || total <= 0) return null;
  return (current / total).clamp(0.0, 1.0);
}

/// Short label for list rows: "p. 120 of 300", "45%", "3:20 of 10:05".
String? progressLabel(MediaItem i) {
  final c = i.progressCurrent;
  if (c == null) return null;
  final t = i.progressTotal;
  return switch (i.progressUnit) {
    ProgressUnit.percent => '$c%',
    ProgressUnit.minutes =>
      t == null ? formatMinutes(c) : '${formatMinutes(c)} of ${formatMinutes(t)}',
    _ => t == null ? 'p. $c' : 'p. $c of $t',
  };
}

String formatMinutes(int m) => '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';

/// "3:20", "3h20", "200" (minutes) -> minutes.
int? parseMinutes(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.isEmpty) return null;
  final hm = RegExp(r'^(\d{1,3})\s*[:h]\s*(\d{1,2})?\s*m?$').firstMatch(s);
  if (hm != null) {
    final h = int.parse(hm.group(1)!);
    final m = int.tryParse(hm.group(2) ?? '') ?? 0;
    if (m >= 60) return null;
    return h * 60 + m;
  }
  final plain = int.tryParse(s.replaceAll(RegExp(r'\s*m(in)?$'), ''));
  return plain != null && plain >= 0 && plain < 100000 ? plain : null;
}

class _NumberField extends StatefulWidget {
  const _NumberField({
    super.key,
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });
  final String label;
  final int? value;
  final int max;
  final ValueChanged<int?> onChanged;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _c =
      TextEditingController(text: widget.value?.toString() ?? '');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _c,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter('${widget.max}'.length),
        ],
        decoration: InputDecoration(
          labelText: widget.label,
          border: const OutlineInputBorder(),
        ),
        onChanged: (v) {
          final n = int.tryParse(v);
          widget.onChanged(n?.clamp(0, widget.max));
        },
      );
}

class _DurationField extends StatefulWidget {
  const _DurationField({
    super.key,
    required this.label,
    required this.minutes,
    required this.onChanged,
  });
  final String label;
  final int? minutes;
  final ValueChanged<int?> onChanged;

  @override
  State<_DurationField> createState() => _DurationFieldState();
}

class _DurationFieldState extends State<_DurationField> {
  late final TextEditingController _c = TextEditingController(
      text: widget.minutes == null ? '' : formatMinutes(widget.minutes!));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _c,
        keyboardType: TextInputType.datetime,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9:hm ]')),
          LengthLimitingTextInputFormatter(8),
        ],
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: '3:20',
          border: const OutlineInputBorder(),
        ),
        onChanged: (v) => widget.onChanged(parseMinutes(v)),
      );
}

/// This item's diary: every time it was finished, plus "Watched again".
class DiarySection extends StatelessWidget {
  const DiarySection({super.key, required this.item, required this.onRewatch});
  final MediaItem item;

  /// Called after a new entry is added, with its date.
  final ValueChanged<DateTime> onRewatch;

  Future<void> _again(BuildContext context) async {
    final result = await showDialog<(DateTime, int?, String?)>(
      context: context,
      builder: (_) => _RewatchDialog(category: item.category),
    );
    if (result == null || !context.mounted) return;
    final (date, rating, note) = result;
    await AppScope.of(context)
        .db
        .addRewatch(item.id, date: date, rating: rating, note: note);
    onRewatch(date);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final db = AppScope.of(context).db;
    final again = switch (item.category) {
      MediaCategory.movie ||
      MediaCategory.series ||
      MediaCategory.video =>
        'Watched again',
      MediaCategory.book => 'Read again',
      MediaCategory.audiobook || MediaCategory.podcast => 'Listened again',
      MediaCategory.game => 'Played again',
    };
    return StreamBuilder<List<WatchEvent>>(
      stream: db.watchEventsFor(item.id),
      builder: (context, snap) {
        final events = snap.data ?? const <WatchEvent>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    events.length <= 1
                        ? 'Diary'
                        : 'Diary · ${item.category.doneLabel.toLowerCase()} '
                            '${events.length} times',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.replay),
                  label: Text(events.isEmpty
                      ? 'Add a ${item.category.doneLabel.toLowerCase()} date'
                      : again),
                  onPressed: () => _again(context),
                ),
              ],
            ),
            for (final e in events)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_available_outlined),
                title: Text(_formatDate(e.date)),
                subtitle: (e.rating == null && (e.note ?? '').isEmpty)
                    ? null
                    : Text([
                        if (e.rating != null) '★' * e.rating!,
                        if ((e.note ?? '').isNotEmpty) '“${e.note}”',
                      ].join('  ')),
                trailing: IconButton(
                  tooltip: 'Remove this entry',
                  icon: const Icon(Icons.close),
                  onPressed: () => db.deleteEvent(e.id),
                ),
              ),
          ],
        );
      },
    );
  }
}

String _formatDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

class _RewatchDialog extends StatefulWidget {
  const _RewatchDialog({required this.category});
  final MediaCategory category;

  @override
  State<_RewatchDialog> createState() => _RewatchDialogState();
}

class _RewatchDialogState extends State<_RewatchDialog> {
  DateTime _date = DateTime.now();
  int? _rating;
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.category.doneLabel} on'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(_formatDate(_date)),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(1900),
                  lastDate: DateTime.now(),
                );
                if (picked != null && mounted) {
                  setState(() => _date = DateTime(
                      picked.year, picked.month, picked.day, 12));
                }
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var s = 1; s <= 5; s++)
                  IconButton(
                    tooltip: '$s star${s == 1 ? '' : 's'}',
                    icon: Icon((_rating ?? 0) >= s
                        ? Icons.star
                        : Icons.star_border),
                    onPressed: () =>
                        setState(() => _rating = _rating == s ? null : s),
                  ),
              ],
            ),
            TextField(
              controller: _note,
              inputFormatters: [LengthLimitingTextInputFormatter(200)],
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, (_date, _rating, _note.text)),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
