import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/net/net_client.dart';
import '../../data/db/database.dart';
import '../../data/lookup/episodes.dart';
import 'seasons_view.dart';

/// Tick individual episodes of a series (episode list from TVmaze) and
/// follow it for "new episode" reminders.
class EpisodesPage extends StatefulWidget {
  const EpisodesPage({super.key, required this.item});
  final MediaItem item;

  @override
  State<EpisodesPage> createState() => _EpisodesPageState();
}

class _EpisodesPageState extends State<EpisodesPage> {
  Future<List<Episode>>? _episodes;
  late bool _following = widget.item.following;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _episodes ??= _load();
  }

  Future<List<Episode>> _load() {
    if (!_hasEpisodeList) return Future.value(const <Episode>[]);
    final scope = AppScope.of(context);
    if (!scope.settings.lookupsEnabled) {
      return Future.error(const _LookupsOff());
    }
    return EpisodeService(scope.net).episodes(widget.item.sourceId ?? '');
  }

  Future<void> _toggleFollow(bool on) async {
    final scope = AppScope.of(context);
    await scope.db.setFollowing(widget.item.id, on);
    if (!mounted) return;
    setState(() => _following = on);
    if (on && !scope.settings.episodeReminders) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Following. Turn on "New episode reminders" in '
              'More to get a notification when episodes come out.')));
    } else if (scope.settings.episodeReminders) {
      final reminders = scope.reminders;
      if (reminders != null) await reminders.run(force: true);
    }
  }

  bool get _hasEpisodeList =>
      widget.item.source == 'tvmaze' && widget.item.sourceId != null;

  @override
  Widget build(BuildContext context) {
    if (!_hasEpisodeList) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.item.title)),
        body: ManualSeasons(item: widget.item),
      );
    }
    return _buildTvmaze(context);
  }

  Widget _buildTvmaze(BuildContext context) {
    final db = AppScope.of(context).db;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.item.title)),
      body: StreamBuilder<List<EpisodeMark>>(
        stream: db.watchMarks(widget.item.id),
        builder: (context, marksSnap) {
          final marks = {
            for (final m in marksSnap.data ?? const <EpisodeMark>[])
              (m.season, m.number),
          };
          return FutureBuilder<List<Episode>>(
            future: _episodes,
            builder: (context, snap) {
              final header = SwitchListTile(
                secondary: const Icon(Icons.notifications_outlined),
                title: const Text('Follow this show'),
                subtitle: const Text('Get a reminder when a new episode '
                    'airs. Only the show’s TVmaze number is sent.'),
                value: _following,
                onChanged: _toggleFollow,
              );
              if (snap.connectionState != ConnectionState.done) {
                return ListView(children: [
                  header,
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ]);
              }
              if (snap.hasError) {
                final e = snap.error;
                return ListView(children: [
                  header,
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      e is NotOnWifiException
                          ? "You're on mobile data. The episode list loads "
                              'on Wi-Fi (or allow lookups on mobile data).'
                          : e is OfflineException
                              ? 'Offline mode is on.'
                              : e is _LookupsOff
                                  ? 'Lookups are switched off in More.'
                                  : "Couldn't load the episode list.",
                      textAlign: TextAlign.center,
                    ),
                  ),
                ]);
              }
              final episodes = snap.data ?? const <Episode>[];
              final now = DateTime.now().toUtc();
              final rows = <Widget>[
                WholeShowTile(itemId: widget.item.id),
                header,
              ];
              int? season;
              for (var k = 0; k < episodes.length; k++) {
                final e = episodes[k];
                if (e.season != season) {
                  season = e.season;
                  final inSeason = [
                    for (final x in episodes)
                      if (x.season == e.season) (x.season, x.number),
                  ];
                  final all = inSeason.every(marks.contains);
                  rows.add(ListTile(
                    title: Text('Season ${e.season}',
                        style: theme.textTheme.titleMedium),
                    subtitle: Text(
                        '${inSeason.where(marks.contains).length} of '
                        '${inSeason.length} watched'),
                    trailing: TextButton(
                      onPressed: () =>
                          db.setEpisodesWatched(widget.item.id, inSeason, !all),
                      child: Text(all ? 'Untick season' : 'Tick season'),
                    ),
                  ));
                }
                final key = (e.season, e.number);
                final aired = e.airstamp == null || !e.airstamp!.isAfter(now);
                final upTo = [
                  for (final x in episodes.take(k + 1)) (x.season, x.number),
                ];
                rows.add(CheckboxListTile(
                  dense: true,
                  value: marks.contains(key),
                  onChanged: (v) =>
                      db.setEpisodesWatched(widget.item.id, [key], v ?? false),
                  title: Text('${e.number}. ${e.name}',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text([
                    e.code,
                    if (e.airstamp != null)
                      (aired ? '' : 'Airs ') +
                          _date(e.airstamp!.toLocal()),
                    if (e.runtime != null) '${e.runtime} min',
                  ].join(' · ')),
                  secondary: IconButton(
                    tooltip: 'Tick everything up to here',
                    icon: const Icon(Icons.done_all),
                    onPressed: () =>
                        db.setEpisodesWatched(widget.item.id, upTo, true),
                  ),
                ));
              }
              if (episodes.isEmpty) {
                rows.add(const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('TVmaze has no episodes listed for this show.',
                      textAlign: TextAlign.center),
                ));
              }
              return ListView(children: rows);
            },
          );
        },
      ),
    );
  }
}

String _date(DateTime d) {
  const m = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

class _LookupsOff implements Exception {
  const _LookupsOff();
}
