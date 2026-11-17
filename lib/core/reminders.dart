import 'dart:async';

import 'package:flutter/services.dart';

import '../data/db/database.dart';
import '../data/lookup/episodes.dart';
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

  /// Safe to call often; only checks TVmaze when due (or [force]).
  Future<void> run({bool force = false, DateTime? now}) async {
    if (_running || !settings.episodeReminders) return;
    if (settings.offlineMode || !net.mayUse(NetPurpose.lookup)) return;
    final ts = now ?? DateTime.now();
    final values = await db.readSettings();
    final last = DateTime.tryParse(values[_kCheckedAt] ?? '');
    if (!force && last != null && ts.difference(last) < checkEvery) return;
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
      try {
        await _channel.invokeMethod<void>(
            'schedule', [for (final r in reminders) r.toMap()]);
      } on MissingPluginException {
        // Tests.
      } on PlatformException {
        // Ignore; try again next time.
      }
      await db.writeSetting(_kCheckedAt, ts.toIso8601String());
    } finally {
      _running = false;
    }
  }
}
