import 'package:drift/drift.dart' show Value;

import '../db/database.dart';
import '../models.dart';

/// One possible match returned by a lookup source.
class LookupCandidate {
  const LookupCandidate({
    required this.title,
    required this.source,
    required this.sourceId,
    this.year,
    this.genre = kUncategorised,
    this.creator,
    this.coverUrl,
  });

  final String title;
  final int? year;
  final String genre;
  final String? creator;
  final String? coverUrl;

  /// Short source name, e.g. "itunes", "tvmaze", "openlibrary".
  final String source;
  final String sourceId;

  @override
  String toString() => 'LookupCandidate($title, $year, $source:$sourceId)';
}

/// Applies a chosen match to an existing item (used by "Look up details").
MediaItem applyCandidate(MediaItem item, LookupCandidate c, DateTime now) {
  final coverChanged = c.coverUrl != item.coverUrl;
  return item.copyWith(
    title: c.title,
    year: Value(c.year ?? item.year),
    genre: c.genre == kUncategorised ? item.genre : c.genre,
    creator: Value(c.creator ?? item.creator),
    coverUrl: Value(c.coverUrl ?? item.coverUrl),
    coverFile: coverChanged && c.coverUrl != null
        ? const Value(null)
        : Value(item.coverFile),
    source: Value(c.source),
    sourceId: Value(c.sourceId),
    matchState: MatchState.matched,
    updatedAt: now,
  );
}
