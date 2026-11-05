import '../../core/net/net_client.dart';
import '../../core/sanitise.dart';
import '../models.dart';
import 'candidate.dart';
import 'providers.dart';

/// "Dune 2021" / "Dune (2021)" → text "Dune", year 2021.
class ParsedQuery {
  const ParsedQuery(this.text, this.year);
  final String text;
  final int? year;

  static final RegExp _trailingYear =
      RegExp(r'^(.+?)[\s,]*[\(\[]?((?:18|19|20)\d{2})[\)\]]?$');

  factory ParsedQuery.parse(String raw) {
    final clean = cleanText(raw, maxLength: 120);
    final m = _trailingYear.firstMatch(clean);
    if (m != null) {
      final text = m.group(1)!.trim();
      final year = int.parse(m.group(2)!);
      // Keep titles that ARE a year ("1917") or end in one ("Blade Runner 2049")
      // intact when the remainder would be too short to search for.
      if (text.length >= 2 && year <= DateTime.now().year + 5) {
        return ParsedQuery(text, year);
      }
    }
    return ParsedQuery(clean, null);
  }
}

class LookupResult {
  const LookupResult(this.candidates, this.sourcesTried, {this.error});
  final List<LookupCandidate> candidates;
  final List<String> sourcesTried;

  /// Last error from a source, if every source failed or returned nothing.
  final Object? error;

  bool get couldNotReach => candidates.isEmpty && error != null;
}

class LookupService {
  LookupService(this.net);
  final NetClient net;

  List<LookupProvider> chainFor(MediaCategory category) => switch (category) {
        MediaCategory.movie => [ItunesProvider(net, ItunesMedia.movie)],
        MediaCategory.series => [
            TvmazeProvider(net),
            ItunesProvider(net, ItunesMedia.tvShow),
          ],
        MediaCategory.book => [
            OpenLibraryProvider(net),
            GoogleBooksProvider(net),
          ],
        MediaCategory.audiobook => [
            ItunesProvider(net, ItunesMedia.audiobook),
            OpenLibraryProvider(net),
          ],
        MediaCategory.podcast => [ItunesProvider(net, ItunesMedia.podcast)],
      };

  /// Tries each source in turn until one returns results.
  /// Throws [OfflineException] if Offline mode is on.
  Future<LookupResult> search(String raw, MediaCategory category) async {
    final query = ParsedQuery.parse(raw);
    if (query.text.isEmpty) return const LookupResult([], []);
    final tried = <String>[];
    Object? lastError;
    for (final provider in chainFor(category)) {
      tried.add(provider.displayName);
      try {
        final found = await provider.search(query.text, category);
        if (found.isNotEmpty) {
          return LookupResult(rank(query, found), tried);
        }
      } on OfflineException {
        rethrow;
      } catch (e) {
        lastError = e;
      }
    }
    return LookupResult(const [], tried, error: lastError);
  }

  /// Exact title matches first (and the right year first among those);
  /// otherwise the source's own order. Duplicates removed.
  static List<LookupCandidate> rank(
      ParsedQuery query, List<LookupCandidate> found) {
    final key = matchKey(query.text);
    int score(LookupCandidate c) {
      var s = 0;
      if (matchKey(c.title) == key) s += 2;
      if (query.year != null && c.year == query.year) s += 1;
      return s;
    }

    final seen = <String>{};
    final unique = [
      for (final c in found)
        if (seen.add('${matchKey(c.title)}|${c.year}|${c.creator}')) c,
    ];
    final indexed = unique.asMap().entries.toList()
      ..sort((a, b) {
        final byScore = score(b.value).compareTo(score(a.value));
        return byScore != 0 ? byScore : a.key.compareTo(b.key);
      });
    return [for (final e in indexed.take(12)) e.value];
  }

  /// The single result that is clearly what was typed, or null if the user
  /// should choose. Clear = the only exact title match (and the year matches
  /// when a year was typed).
  static LookupCandidate? confidentMatch(
      String raw, List<LookupCandidate> candidates) {
    final query = ParsedQuery.parse(raw);
    final key = matchKey(query.text);
    var exact = [
      for (final c in candidates)
        if (matchKey(c.title) == key) c,
    ];
    if (query.year != null) {
      exact = [
        for (final c in exact)
          if (c.year == query.year) c,
      ];
    }
    return exact.length == 1 ? exact.first : null;
  }
}
