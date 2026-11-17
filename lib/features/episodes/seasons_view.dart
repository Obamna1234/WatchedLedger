import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../data/db/database.dart';
import '../../data/models.dart';

/// "Whole show watched" switch, shared by both episode screens.
class WholeShowTile extends StatelessWidget {
  const WholeShowTile({super.key, required this.itemId});
  final int itemId;

  @override
  Widget build(BuildContext context) {
    final db = AppScope.of(context).db;
    return StreamBuilder<MediaItem?>(
      stream: db.watchItem(itemId),
      builder: (context, snap) {
        final item = snap.data;
        return SwitchListTile(
          secondary: const Icon(Icons.task_alt),
          title: const Text('Whole show watched'),
          subtitle: const Text('Moves it to Watched, with the date.'),
          value: item?.status == ListStatus.done,
          onChanged: item == null
              ? null
              : (on) => db.setStatus(
                  itemId, on ? ListStatus.done : ListStatus.todo),
        );
      },
    );
  }
}

/// Seasons and episodes ticked by hand, for shows without an episode list
/// (not matched with TVmaze, or offline). Tick a whole season, or open it
/// and tick single episodes.
class ManualSeasons extends StatefulWidget {
  const ManualSeasons({super.key, required this.item});
  final MediaItem item;

  @override
  State<ManualSeasons> createState() => _ManualSeasonsState();
}

class _ManualSeasonsState extends State<ManualSeasons> {
  int _extraSeasons = 0;
  final Map<int, int> _extraEpisodes = {};

  @override
  Widget build(BuildContext context) {
    final db = AppScope.of(context).db;
    final theme = Theme.of(context);
    return StreamBuilder<List<EpisodeMark>>(
      stream: db.watchMarks(widget.item.id),
      builder: (context, snap) {
        final marks = snap.data ?? const <EpisodeMark>[];
        final whole = {
          for (final m in marks)
            if (m.number == AppDatabase.wholeSeason) m.season,
        };
        final episodes = <int, Set<int>>{};
        for (final m in marks) {
          if (m.number != AppDatabase.wholeSeason) {
            (episodes[m.season] ??= {}).add(m.number);
          }
        }
        var seasons = [
          widget.item.season ?? 0,
          for (final m in marks) m.season,
          1,
        ].reduce((a, b) => a > b ? a : b);
        seasons += _extraSeasons;

        return ListView(
          children: [
            WholeShowTile(itemId: widget.item.id),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Tick a whole season, or open it to tick single episodes.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            for (var s = 1; s <= seasons; s++)
              _seasonTile(context, db, s, whole.contains(s),
                  episodes[s] ?? const {}),
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add a season'),
                onPressed: () => setState(() => _extraSeasons++),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _seasonTile(BuildContext context, AppDatabase db, int season,
      bool wholeDone, Set<int> ticked) {
    final highest = ticked.isEmpty ? 0 : ticked.reduce((a, b) => a > b ? a : b);
    final shown = (highest + 2 > 10 ? highest + 2 : 10) +
        (_extraEpisodes[season] ?? 0);
    final id = widget.item.id;
    return ExpansionTile(
      key: PageStorageKey('season-$season'),
      leading: Checkbox(
        value: wholeDone,
        onChanged: (v) => db.setSeasonWatched(id, season, v ?? false),
      ),
      title: Text('Season $season'),
      subtitle: Text(wholeDone
          ? 'Whole season watched'
          : ticked.isEmpty
              ? 'Not started'
              : '${ticked.length} episode${ticked.length == 1 ? '' : 's'} '
                  'watched'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var e = 1; e <= shown; e++)
              FilterChip(
                label: Text('$e'),
                selected: wholeDone || ticked.contains(e),
                onSelected: (on) async {
                  if (wholeDone && !on) {
                    // Was "whole season": keep the others, drop this one.
                    await db.setSeasonWatched(id, season, false);
                    await db.setEpisodesWatched(id, [
                      for (var x = 1; x <= shown; x++)
                        if (x != e) (season, x),
                    ], true);
                  } else {
                    await db.setEpisodesWatched(id, [(season, e)], on);
                  }
                },
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('More'),
              onPressed: () => setState(() => _extraEpisodes[season] =
                  (_extraEpisodes[season] ?? 0) + 5),
            ),
          ],
        ),
      ],
    );
  }
}
