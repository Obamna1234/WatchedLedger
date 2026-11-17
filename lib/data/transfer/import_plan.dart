import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import '../../core/net/net_client.dart';
import '../../core/sanitise.dart';
import '../db/database.dart';
import '../lookup/candidate.dart';
import '../lookup/lookup_service.dart';
import '../models.dart';
import 'import_parsers.dart';

/// One line on the review screen: what was read, what the lookup found,
/// and whether the user wants it saved.
class ImportEntry {
  ImportEntry(this.row, this.category)
      : status = row.status,
        include = true;

  final ImportRow row;
  MediaCategory category;
  ListStatus status;
  bool include;

  /// Chosen match, or null to save the title as typed.
  LookupCandidate? match;

  /// True once a lookup ran (whether or not it found anything).
  bool looked = false;

  /// The user picked or confirmed this by hand.
  bool confirmed = false;

  /// Already in the library, or earlier in this same import.
  bool duplicate = false;

  String get title => match?.title ?? row.title;
  int? get year => match?.year ?? row.year;

  bool get needsAttention => include && looked && match == null && !confirmed;
}

/// Turns parsed rows into review entries and flags duplicates.
/// Rows without a category get [fallback].
Future<List<ImportEntry>> prepareImport(
  AppDatabase db,
  List<ImportRow> rows,
  MediaCategory fallback,
) async {
  final entries = [
    for (final r in rows) ImportEntry(r, r.category ?? fallback),
  ];
  await markDuplicates(db, entries);
  return entries;
}

/// Re-checks every entry against the library and against earlier entries.
/// Duplicates are left unticked so they're skipped unless the user insists.
Future<void> markDuplicates(AppDatabase db, List<ImportEntry> entries) async {
  final existing = <String>{
    for (final i in await db.select(db.items).get())
      '${i.category.index}|${i.matchKey}',
  };
  final seen = <String>{};
  for (final e in entries) {
    final keys = {
      '${e.category.index}|${matchKey(e.row.title)}',
      '${e.category.index}|${matchKey(e.title)}',
    };
    final wasDuplicate = e.duplicate;
    e.duplicate =
        keys.any(existing.contains) || keys.any(seen.contains);
    if (e.duplicate && !wasDuplicate) e.include = false;
    if (e.include) seen.addAll(keys);
  }
}

/// Looks up every entry that hasn't been looked up yet. Only a single clear
/// match is filled in automatically; everything else is left for review.
/// Stops quietly (leaving the rest unmatched) if the network isn't allowed.
Future<void> lookupAll(
  LookupService lookup,
  List<ImportEntry> entries, {
  void Function(int done, int total)? onProgress,
  bool Function()? cancelled,
}) async {
  final todo = [
    for (final e in entries)
      if (e.include && !e.looked && !e.confirmed) e,
  ];
  var done = 0;
  onProgress?.call(0, todo.length);
  for (final e in todo) {
    if (cancelled?.call() ?? false) return;
    try {
      final result = await lookup.search(e.row.query, e.category);
      final pick = LookupService.confidentMatch(e.row.query, result.candidates);
      if (pick != null) e.match = await lookup.details(pick);
      e.looked = true;
    } on OfflineException {
      return; // offline or not on Wi-Fi: the rest are matched later
    } catch (_) {
      e.looked = true;
    }
    onProgress?.call(++done, todo.length);
  }
}

/// Saves every ticked entry. Returns how many were added.
/// Unmatched titles are saved as typed and matched in the background later.
Future<int> saveImport(AppDatabase db, List<ImportEntry> entries,
    {DateTime? now}) async {
  final ts = now ?? DateTime.now();
  var added = 0;
  await db.transaction(() async {
    for (final e in entries) {
      if (!e.include) continue;
      final title = cleanTitle(e.title);
      if (title.isEmpty) continue;
      final m = e.match;
      final r = e.row;
      final done = e.status == ListStatus.done;
      await db.into(db.items).insert(ItemsCompanion.insert(
            category: e.category,
            status: e.status,
            title: title,
            sortTitle: sortKey(title),
            matchKey: matchKey(title),
            typedTitle: Value(m == null ? null : r.title),
            uid: Value(newUid()),
            year: Value(m?.year ?? r.year),
            genre: m == null || m.genre == kUncategorised
                ? const Value.absent()
                : Value(m.genre),
            creator: Value(m?.creator ?? r.creator),
            coverUrl: Value(m?.coverUrl),
            source: Value(m?.source),
            sourceId: Value(m?.sourceId),
            matchState: m != null
                ? MatchState.matched
                : (e.confirmed ? MatchState.manual : MatchState.unmatched),
            rating: Value(r.rating?.clamp(1, 5)),
            note: Value(r.note),
            season: Value(e.category == MediaCategory.series ? r.season : null),
            episode:
                Value(e.category == MediaCategory.series ? r.episode : null),
            runtimeMinutes: Value(r.runtimeMinutes),
            pages: Value(r.pages ?? m?.pages),
            tags: Value(r.tags.isEmpty ? null : jsonEncode(r.tags)),
            addedAt: ts,
            updatedAt: ts,
            completedAt: Value(done ? (r.finished ?? ts) : null),
          ));
      added++;
    }
  });
  return added;
}
