import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_scope.dart';
import '../../data/db/database.dart';
import '../../data/models.dart';
import '../../data/stats.dart';
import '../diary/diary_page.dart';

const _months = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  int? _year = DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final db = AppScope.of(context).db;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stats'),
        actions: [
          IconButton(
            tooltip: 'Diary',
            icon: const Icon(Icons.event_note_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DiaryPage()),
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<MediaItem>>(
        stream: db.watchAll(),
        builder: (context, snap) => StreamBuilder<List<WatchEvent>>(
          stream: db.watchAllEvents(),
          builder: (context, eventSnap) => _body(
            context,
            snap.data ?? const <MediaItem>[],
            eventSnap.data,
          ),
        ),
      ),
    );
  }

  Widget _body(
      BuildContext context, List<MediaItem> items, List<WatchEvent>? events) {
    final stats = LibraryStats.from(items, year: _year, events: events);
    final years = {DateTime.now().year, ...stats.years}.toList()
      ..sort((a, b) => b.compareTo(a));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final y in <int?>[...years, null])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(y == null ? 'All time' : '$y'),
                    selected: _year == y,
                    onSelected: (_) => setState(() => _year = y),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Headline(stats: stats),
        if (stats.year != null) ...[
          const SizedBox(height: 12),
          _Goals(year: stats.year!, stats: stats),
        ],
        const SizedBox(height: 12),
        _CategoryCounts(stats: stats),
        if (stats.year != null) ...[
          const SizedBox(height: 12),
          _MonthBars(months: stats.finishedByMonth),
        ],
        if (stats.topGenres.isNotEmpty) ...[
          const SizedBox(height: 12),
          _TopGenres(stats: stats),
        ],
        if (stats.year == null && stats.finishedByYear.isNotEmpty) ...[
          const SizedBox(height: 12),
          _PerYear(stats: stats),
        ],
      ],
    );
  }
}

/// Yearly goals per category ("24 books in 2027").
class _Goals extends StatefulWidget {
  const _Goals({required this.year, required this.stats});
  final int year;
  final LibraryStats stats;

  @override
  State<_Goals> createState() => _GoalsState();
}

class _GoalsState extends State<_Goals> {
  Map<MediaCategory, int>? _goals;
  int? _loadedFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(_Goals old) {
    super.didUpdateWidget(old);
    if (old.year != widget.year) _load();
  }

  Future<void> _load() async {
    final year = widget.year;
    if (_loadedFor == year && _goals != null) return;
    _loadedFor = year;
    final goals = await AppScope.of(context).db.goalsFor(year);
    if (mounted && widget.year == year) setState(() => _goals = goals);
  }

  Future<void> _edit() async {
    final db = AppScope.of(context).db;
    final result = await showDialog<Map<MediaCategory, int?>>(
      context: context,
      builder: (_) => _GoalDialog(year: widget.year, goals: _goals ?? {}),
    );
    if (result == null) return;
    for (final e in result.entries) {
      await db.setGoal(e.key, widget.year, e.value);
    }
    _loadedFor = null;
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final goals = _goals ?? const {};
    return _Section(
      title: 'Goals for ${widget.year}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (goals.isEmpty)
            Text('Set a goal, like "24 books this year".',
                style: theme.textTheme.bodyMedium),
          for (final e in goals.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.stats.finishedByCategory[e.key]} of ${e.value} '
                    '${e.key.tabLabel.toLowerCase()}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: (widget.stats.finishedByCategory[e.key]! / e.value)
                        .clamp(0.0, 1.0),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.flag_outlined),
              label: Text(goals.isEmpty ? 'Set goals' : 'Change goals'),
              onPressed: _edit,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalDialog extends StatefulWidget {
  const _GoalDialog({required this.year, required this.goals});
  final int year;
  final Map<MediaCategory, int> goals;

  @override
  State<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_GoalDialog> {
  late final Map<MediaCategory, TextEditingController> _fields = {
    for (final c in MediaCategory.values)
      c: TextEditingController(text: widget.goals[c]?.toString() ?? ''),
  };

  @override
  void dispose() {
    for (final f in _fields.values) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Goals for ${widget.year}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in MediaCategory.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: TextField(
                  controller: _fields[c],
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: InputDecoration(
                    labelText: c.tabLabel,
                    hintText: 'No goal',
                    prefixIcon: Icon(c.icon),
                    border: const OutlineInputBorder(),
                  ),
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
          onPressed: () => Navigator.pop(context, {
            for (final e in _fields.entries) e.key: int.tryParse(e.value.text),
          }),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.stats});
  final LibraryStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget figure(String value, String label) => Expanded(
          child: Column(
            children: [
              Text(value, style: theme.textTheme.headlineMedium),
              Text(label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall),
            ],
          ),
        );
    final hours = stats.minutesWatched / 60;
    return _Section(
      title: stats.year == null ? 'All time' : 'In ${stats.year}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          figure('${stats.totalFinished}', 'finished'),
          figure(
            stats.averageRating == null
                ? '–'
                : '${stats.averageRating!.toStringAsFixed(1)} ★',
            'average rating',
          ),
          if (stats.pagesRead > 0) figure('${stats.pagesRead}', 'pages read'),
          if (stats.minutesWatched > 0)
            figure(hours >= 10 ? '${hours.round()}' : hours.toStringAsFixed(1),
                'hours of movies & audiobooks'),
        ],
      ),
    );
  }
}

class _CategoryCounts extends StatelessWidget {
  const _CategoryCounts({required this.stats});
  final LibraryStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Section(
      title: 'By category',
      child: Column(
        children: [
          for (final c in MediaCategory.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(c.icon, size: 20),
                  const SizedBox(width: 12),
                  Expanded(child: Text(c.tabLabel)),
                  Text('${stats.finishedByCategory[c]} ${c.doneLabel.toLowerCase()}',
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 96,
                    child: Text(
                      '${stats.toDoByCategory[c]} ${c.todoLabel.toLowerCase()}',
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MonthBars extends StatelessWidget {
  const _MonthBars({required this.months});
  final List<int> months;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final most = months.fold<int>(0, (a, b) => b > a ? b : a);
    return _Section(
      title: 'Finished each month',
      child: SizedBox(
        height: 140,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var m = 0; m < 12; m++)
              Expanded(
                child: Semantics(
                  label: '${months[m]} in month ${m + 1}',
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (months[m] > 0)
                        Text('${months[m]}', style: theme.textTheme.labelSmall),
                      const SizedBox(height: 2),
                      Container(
                        height: most == 0 ? 0 : 96.0 * months[m] / most,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3)),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(_months[m], style: theme.textTheme.labelSmall),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TopGenres extends StatelessWidget {
  const _TopGenres({required this.stats});
  final LibraryStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final most = stats.topGenres.first.value;
    return _Section(
      title: 'Top genres',
      child: Column(
        children: [
          for (final g in stats.topGenres)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(width: 130, child: Text(g.key, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: g.value / most,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text('${g.value}',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodySmall),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PerYear extends StatelessWidget {
  const _PerYear({required this.stats});
  final LibraryStats stats;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Finished per year',
      child: Column(
        children: [
          for (final e in stats.finishedByYear)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(child: Text('${e.key}')),
                  Text('${e.value}'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
