import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../data/db/database.dart';
import '../data/lookup/episodes.dart';
import '../data/models.dart';
import 'net/net_client.dart';
import 'settings.dart';

/// One reminder for the phone to show at [at].
class Reminder {
  const Reminder(this.id, this.at, this.title, this.body);
  final int id;
  final DateTime at;
  final String title;
  final String body;

  Map<String, Object> toMap() => {
        'id': id,
        'at': at.millisecondsSinceEpoch,
        'title': title,
        'body': body,
      };

  static Reminder? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], at = raw['at'], title = raw['title'];
    final body = raw['body'];
    if (id is! int || at is! int || title is! String || body is! String) {
      return null;
    }
    return Reminder(id, DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
        title, body);
  }
}

/// "New episode" reminders. When the app opens (at most about once a day),
/// it asks TVmaze for the episode lists of followed shows only, then has the
/// phone schedule its own notifications. No server, account or push token.
class ReminderService {
  ReminderService({
    required this.db,
    required this.settings,
    required this.net,
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel('watchedledger/reminders');

  final AppDatabase db;
  final SettingsController settings;
  final NetClient net;
  final MethodChannel _channel;

  static const _kCheckedAt = 'reminders_checked_at';
  static const _kEpisodePlan = 'reminders_episode_plan';
  static const Duration checkEvery = Duration(hours: 20);
  static const Duration lookAhead = Duration(days: 45);
  static const int maxReminders = 60;

  bool _running = false;

  /// Asks for notification permission. True if allowed.
  Future<bool> requestPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> cancelAll() async {
    try {
      await _channel.invokeMethod<void>('cancelAll');
    } on MissingPluginException {
      // Tests.
    } on PlatformException {
      // Ignore.
    }
  }

  /// Upcoming episodes of [shows] as reminders, soonest first.
  static List<Reminder> plan(
      Map<MediaItem, List<Episode>> shows, DateTime now) {
    final out = <Reminder>[];
    for (final MapEntry(key: show, value: episodes) in shows.entries) {
      for (final e in episodes) {
        final at = e.airstamp;
        if (at == null || !at.isAfter(now) || at.isAfter(now.add(lookAhead))) {
          continue;
        }
        out.add(Reminder(
          (show.id * 100003 + e.season * 1000 + e.number) & 0x7fffffff,
          at,
          show.title,
          '${e.code} "${e.name}" is out',
        ));
      }
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return out.take(maxReminders).toList();
  }

  /// "Out today" reminders for items marked "Not out yet" with a date
  /// (no internet needed).
  static List<Reminder> releasePlan(List<MediaItem> items, DateTime now) => [
        for (final i in items)
          if (i.upcoming &&
              i.releaseDate != null &&
              i.releaseDate!.isAfter(now))
            Reminder(
              0x40000000 | (i.id & 0x3fffffff),
              i.releaseDate!.toUtc(),
              i.title,
              'Out today: your "Not out yet" ${i.category.singular}',
            ),
      ];

  Future<void> _schedule(List<Reminder> episodes, DateTime now) async {
    final all = [
      ...episodes.where((r) => r.at.isAfter(now)),
      ...releasePlan(await db.select(db.items).get(), now),
    ]..sort((a, b) => a.at.compareTo(b.at));
    try {
      await _channel.invokeMethod<void>(
          'schedule', [for (final r in all.take(maxReminders)) r.toMap()]);
    } on MissingPluginException {
      // Tests.
    } on PlatformException {
      // Ignore; try again next time.
    }
  }

  Future<List<Reminder>> _cachedEpisodes() async {
    final raw = (await db.readSettings())[_kEpisodePlan];
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw);
      return [
        if (list is List)
          for (final r in list) ?Reminder.fromMap(r),
      ];
    } on FormatException {
      return const [];
    }
  }

  /// Safe to call often. Release-date reminders are always refreshed;
  /// TVmaze is only asked about followed shows when due (or [force]).
  Future<void> run({bool force = false, DateTime? now}) async {
    if (_running || !settings.episodeReminders) return;
    final ts = now ?? DateTime.now();
    final values = await db.readSettings();
    final last = DateTime.tryParse(values[_kCheckedAt] ?? '');
    final due = force || last == null || ts.difference(last) >= checkEvery;
    if (!due || settings.offlineMode || !net.mayUse(NetPurpose.lookup)) {
      await _schedule(await _cachedEpisodes(), ts.toUtc());
      return;
    }
    _running = true;
    try {
      final service = EpisodeService(net);
      final shows = <MediaItem, List<Episode>>{};
      for (final show in await db.followedShows()) {
        try {
          shows[show] = await service.episodes(show.sourceId!);
        } on OfflineException {
          return;
        } catch (_) {
          // One show failing doesn't stop the rest.
        }
      }
      final reminders = plan(shows, ts.toUtc());
      await db.writeSetting(
          _kEpisodePlan, jsonEncode([for (final r in reminders) r.toMap()]));
      await _schedule(reminders, ts.toUtc());
      await db.writeSetting(_kCheckedAt, ts.toIso8601String());
    } finally {
      _running = false;
    }
  }
}
