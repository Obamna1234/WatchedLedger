import '../../core/net/net_client.dart';
import '../../core/settings.dart';
import '../covers/cover_cache.dart';
import '../db/database.dart';
import '../models.dart';
import 'candidate.dart';
import 'lookup_service.dart';

/// "Match later": when the connection allows it (e.g. back on Wi-Fi), looks
/// up titles that were saved as typed and downloads missing covers.
///
/// Only titles saved automatically (offline, mobile data, network error)
/// are retried, never ones the user chose to "save as typed". Each title
/// is retried at most every few days.
class BackgroundMatcher {
  BackgroundMatcher({
    required this.db,
    required this.lookup,
    required this.covers,
    required this.net,
    required this.settings,
  });

  final AppDatabase db;
  final LookupService lookup;
  final CoverCache covers;
  final NetClient net;
  final SettingsController settings;

  static const Duration retryAfter = Duration(days: 3);

  bool _running = false;

  /// Safe to call often; does nothing if already running or not allowed.
  Future<void> run({DateTime? now}) async {
    if (_running || settings.offlineMode) return;
    _running = true;
    try {
      await _matchUnmatched(now ?? DateTime.now());
      await _downloadCovers();
    } finally {
      _running = false;
    }
  }

  Future<void> _matchUnmatched(DateTime now) async {
    if (!settings.lookupsEnabled || !net.mayUse(NetPurpose.lookup)) return;
    final pending = await db.unmatchedToRetry(now.subtract(retryAfter));
    for (final item in pending) {
      if (!net.mayUse(NetPurpose.lookup)) return;
      await db.markLookupAttempt(item.id, now);
      final query = item.typedTitle ?? item.title;
      final LookupResult result;
      try {
        result = await lookup.search(query, item.category);
      } on OfflineException {
        return;
      } catch (_) {
        continue;
      }
      final match = LookupService.confidentMatch(query, result.candidates);
      if (match == null) continue;
      final detailed = await lookup.details(match);
      // Re-read: the user may have edited or matched it meanwhile.
      final fresh = await db.itemById(item.id);
      if (fresh == null || fresh.matchState != MatchState.unmatched) continue;
      await db.updateItem(applyCandidate(fresh, detailed, DateTime.now()));
    }
  }

  Future<void> _downloadCovers() async {
    if (!net.mayUse(NetPurpose.image)) return;
    for (final item in await db.missingCovers()) {
      if (!net.mayUse(NetPurpose.image)) return;
      final name = await covers.ensure(item.coverUrl!);
      if (name != null) await db.setCoverFile(item.id, name);
    }
  }
}
