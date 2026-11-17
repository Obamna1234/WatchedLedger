import '../../core/net/net_client.dart';
import 'json_read.dart';

/// One episode from TVmaze.
class Episode {
  const Episode({
    required this.season,
    required this.number,
    required this.name,
    this.airstamp,
    this.runtime,
  });

  final int season;
  final int number;
  final String name;

  /// When it airs (UTC), if announced.
  final DateTime? airstamp;
  final int? runtime;

  String get code =>
      'S${season.toString().padLeft(2, '0')}E${number.toString().padLeft(2, '0')}';
}

/// TVmaze episode lists. Only the show's TVmaze ID is sent.
class EpisodeService {
  EpisodeService(this.net);
  final NetClient net;

  static final RegExp _id = RegExp(r'^\d{1,9}$');

  Future<List<Episode>> episodes(String showId) async {
    if (!_id.hasMatch(showId)) return const [];
    final json = await net.getJson(
      Uri.https('api.tvmaze.com', '/shows/$showId/episodes'),
      maxBytes: 3 * 1024 * 1024,
    );
    final out = <Episode>[];
    for (final raw in asList(json)) {
      final e = asMap(raw);
      final season = e?['season'], number = e?['number'];
      // Specials have no number; they're left out.
      if (season is! int || number is! int) continue;
      if (season < 0 || season > 999 || number < 0 || number > 9999) continue;
      final stamp = e?['airstamp'];
      final runtime = e?['runtime'];
      out.add(Episode(
        season: season,
        number: number,
        name: str(e, 'name') ?? 'Episode $number',
        airstamp: stamp is String ? DateTime.tryParse(stamp)?.toUtc() : null,
        runtime: runtime is int && runtime > 0 && runtime < 1000 ? runtime : null,
      ));
    }
    out.sort((a, b) {
      final s = a.season.compareTo(b.season);
      return s != 0 ? s : a.number.compareTo(b.number);
    });
    return out;
  }
}
