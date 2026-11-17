import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../data/db/database.dart';
import '../../data/models.dart';
import '../../data/stats.dart';

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
      appBar: AppBar(title: const Text('Stats')),
      body: StreamBuilder<List<MediaItem>>(
        stream: db.watchAll(),
        builder: (context, snap) {
          final items = snap.data ?? const <MediaItem>[];
          final stats = LibraryStats.from(items, year: _year);
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
        },
      ),
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
