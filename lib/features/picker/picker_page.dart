import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../data/db/database.dart';
import '../../data/models.dart';
import '../../data/picker.dart';
import '../edit/edit_item_page.dart';
import '../lookup/remote_thumb.dart';

/// "Pick something for me" from your own To Watch / To Read / To Listen lists.
class PickerPage extends StatefulWidget {
  const PickerPage({super.key, required this.startCategory});
  final MediaCategory startCategory;

  @override
  State<PickerPage> createState() => _PickerPageState();
}

class _PickerPageState extends State<PickerPage> {
  late Set<MediaCategory> _categories = {widget.startCategory};
  String? _genre;
  PickLength _length = PickLength.any;
  PickMood _mood = PickMood.any;
  final Set<int> _shown = {};
  final Random _random = Random();
  MediaItem? _pick;
  bool _picked = false;

  PickFilter get _filter => PickFilter(
        categories: _categories,
        genre: _genre,
        length: _length,
        mood: _mood,
      );

  void _pickFrom(List<MediaItem> items) {
    final p = pickOne(items, _filter, avoid: _shown, random: _random);
    setState(() {
      _pick = p;
      _picked = true;
      if (p != null) _shown.add(p.id);
    });
  }

  void _changed(VoidCallback f) => setState(() {
        f();
        _picked = false;
        _pick = null;
        _shown.clear();
      });

  @override
  Widget build(BuildContext context) {
    final db = AppScope.of(context).db;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Pick something for me')),
      body: StreamBuilder<List<MediaItem>>(
        stream: db.watchAll(),
        builder: (context, snap) {
          final scope = AppScope.of(context);
          final items = [
            for (final i in snap.data ?? const <MediaItem>[])
              if (scope.isVisible(i)) i,
          ];
          final candidates = items.where(_filter.matches).length;
          final genres = {
            for (final i in items)
              if (i.status == ListStatus.todo &&
                  _categories.contains(i.category) &&
                  i.genre != kUncategorised)
                i.genre,
          }.toList()
            ..sort();
          if (_genre != null && !genres.contains(_genre)) genres.add(_genre!);
          final current = _pick == null
              ? null
              : items.where((i) => i.id == _pick!.id).firstOrNull;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final c in MediaCategory.values)
                    FilterChip(
                      avatar: Icon(c.icon, size: 18),
                      label: Text(c.tabLabel),
                      selected: _categories.contains(c),
                      onSelected: (on) => _changed(() {
                        _categories = {..._categories};
                        if (on) {
                          _categories.add(c);
                        } else {
                          _categories.remove(c);
                        }
                        if (_categories.isEmpty) _categories.add(c);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _Choice<PickMood>(
                values: PickMood.values,
                selected: _mood,
                label: (m) => m.label,
                onSelected: (m) => _changed(() => _mood = m),
              ),
              const SizedBox(height: 8),
              _Choice<PickLength>(
                values: PickLength.values,
                selected: _length,
                label: (l) => l.label,
                onSelected: (l) => _changed(() => _length = l),
              ),
              if (genres.isNotEmpty) ...[
                const SizedBox(height: 8),
                _Choice<String?>(
                  values: [null, ...genres],
                  selected: _genre,
                  label: (g) => g ?? 'Any genre',
                  onSelected: (g) => _changed(() => _genre = g),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                _length == PickLength.any
                    ? '$candidates to choose from'
                    : '$candidates to choose from. Length is known for '
                        'movies, books and audiobooks with a runtime or page '
                        'count; others are still included.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              if (_picked && current != null)
                _PickCard(item: current)
              else if (_picked)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Nothing on your list fits those choices.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.casino_outlined),
                label: Text(_picked ? 'Pick again' : 'Pick for me'),
                onPressed: candidates == 0 ? null : () => _pickFrom(items),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
  });
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final v in values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(label(v)),
                selected: v == selected,
                onSelected: (_) => onSelected(v),
              ),
            ),
        ],
      ),
    );
  }
}

class _PickCard extends StatelessWidget {
  const _PickCard({required this.item});
  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final db = AppScope.of(context).db;
    final details = [
      item.category.singular,
      if (item.year != null) '${item.year}',
      if (item.genre != kUncategorised) item.genre,
      if (item.creator != null) item.creator!,
      if (item.runtimeMinutes != null) '${item.runtimeMinutes} min',
      if (item.pages != null) '${item.pages} pages',
    ];
    final done = item.status == ListStatus.done;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ItemCover(item: item, width: 120, height: 170),
            const SizedBox(height: 12),
            Text(item.title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(details.join(' · '),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium),
            if (item.note != null && item.note!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('“${item.note}”', style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  icon: Icon(done ? Icons.undo : Icons.check),
                  label: Text(done
                      ? 'Back to ${item.category.todoLabel}'
                      : 'Mark as ${item.category.doneLabel}'),
                  onPressed: () => db.setStatus(
                      item.id, done ? ListStatus.todo : ListStatus.done),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => EditItemPage(item: item)),
                  ),
                  child: const Text('Details'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
