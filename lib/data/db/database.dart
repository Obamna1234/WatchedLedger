import 'dart:math';

import 'package:drift/drift.dart';

import '../../core/sanitise.dart';
import '../models.dart';

part 'database.g.dart';

/// One tracked title. The schema already holds everything later phases need
/// (lookup metadata, cover cache, rating, note, series progress) so that
/// upgrades don't require risky migrations of your data.
@DataClassName('MediaItem')
@TableIndex(name: 'idx_items_category_status', columns: {#category, #status})
@TableIndex(name: 'idx_items_match_key', columns: {#matchKey})
class Items extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get category => intEnum<MediaCategory>()();
  IntColumn get status => intEnum<ListStatus>()();

  TextColumn get title => text().withLength(min: 1, max: 300)();
  TextColumn get sortTitle => text()();
  TextColumn get matchKey => text()();

  /// Exactly what was typed/imported, before any lookup corrected it.
  TextColumn get typedTitle => text().nullable()();

  IntColumn get year => integer().nullable()();
  TextColumn get genre => text().withDefault(const Constant(kUncategorised))();
  TextColumn get extraGenres => text().nullable()();

  /// Director / author / narrator / host.
  TextColumn get creator => text().nullable()();

  TextColumn get coverUrl => text().nullable()();
  TextColumn get coverFile => text().nullable()();

  /// Lookup source ("tmdb", "openlibrary", ...) and that source's id.
  TextColumn get source => text().nullable()();
  TextColumn get sourceId => text().nullable()();
  IntColumn get matchState => intEnum<MatchState>()();

  /// 1–5 stars, validated in Dart.
  IntColumn get rating => integer().nullable()();
  TextColumn get note => text().nullable()();

  IntColumn get season => integer().nullable()();
  IntColumn get episode => integer().nullable()();

  DateTimeColumn get addedAt => dateTime()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  // ------------------------------------------------ added in schema v2

  /// Stable random id, used by phone-to-phone sync.
  TextColumn get uid => text().nullable()();

  /// When an automatic "match later" lookup was last tried.
  DateTimeColumn get lookupAttemptedAt => dateTime().nullable()();

  /// Running time (films, episodes, audiobooks) in minutes.
  IntColumn get runtimeMinutes => integer().nullable()();

  /// Page count (books).
  IntColumn get pages => integer().nullable()();

  /// Reading / listening progress, e.g. 120 of 310 pages.
  IntColumn get progressCurrent => integer().nullable()();
  IntColumn get progressTotal => integer().nullable()();
  IntColumn get progressUnit => intEnum<ProgressUnit>().nullable()();

  /// Custom tags as a JSON array of strings.
  TextColumn get tags => text().nullable()();

  /// Series followed for "new episode" reminders.
  BoolColumn get following => boolean().withDefault(const Constant(false))();
}

/// One "finished" entry in the diary (rewatches/rereads add more). v2.
@DataClassName('WatchEvent')
class WatchEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get itemId => integer()();
  DateTimeColumn get date => dateTime()();
  IntColumn get rating => integer().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get uid => text().nullable()();
}

/// Episodes ticked off for a series. v2.
@DataClassName('EpisodeMark')
class EpisodeMarks extends Table {
  IntColumn get itemId => integer()();
  IntColumn get season => integer()();
  IntColumn get number => integer()();
  DateTimeColumn get watchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {itemId, season, number};
}

/// Remembers deleted items so sync can delete them on the other phone. v2.
@DataClassName('Tombstone')
class Tombstones extends Table {
  TextColumn get uid => text()();
  DateTimeColumn get deletedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {uid};
}

String newUid() {
  final rnd = Random.secure();
  return List<int>.generate(16, (_) => rnd.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
}

@DataClassName('SettingEntry')
class SettingsEntries extends Table {
  TextColumn get settingKey => text()();
  TextColumn get settingValue => text()();

  @override
  Set<Column<Object>> get primaryKey => {settingKey};
}

@DriftDatabase(
    tables: [Items, SettingsEntries, WatchEvents, EpisodeMarks, Tombstones])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(items, items.uid);
            await m.addColumn(items, items.lookupAttemptedAt);
            await m.addColumn(items, items.runtimeMinutes);
            await m.addColumn(items, items.pages);
            await m.addColumn(items, items.progressCurrent);
            await m.addColumn(items, items.progressTotal);
            await m.addColumn(items, items.progressUnit);
            await m.addColumn(items, items.tags);
            await m.addColumn(items, items.following);
            await m.createTable(watchEvents);
            await m.createTable(episodeMarks);
            await m.createTable(tombstones);
            await customStatement(
                'UPDATE items SET uid = lower(hex(randomblob(16))) '
                'WHERE uid IS NULL');
          }
        },
      );

  // ---------------------------------------------------------------- items

  Stream<List<MediaItem>> watchList(MediaCategory category, ListStatus status) {
    final query = select(items)
      ..where((t) =>
          t.category.equalsValue(category) & t.status.equalsValue(status))
      ..orderBy([
        (t) => OrderingTerm.asc(t.genre),
        (t) => OrderingTerm.asc(t.sortTitle),
      ]);
    return query.watch();
  }

  /// Every item in every list (used by search to count matches elsewhere).
  Stream<List<MediaItem>> watchAll() => select(items).watch();

  /// Every item, in any category or list, whose title matches [title].
  Future<List<MediaItem>> findDuplicates(String title) {
    final key = matchKey(title);
    return (select(items)..where((t) => t.matchKey.equals(key))).get();
  }

  Future<int> addItem({
    required MediaCategory category,
    required ListStatus status,
    required String title,
    String? typedTitle,
    int? year,
    String? genre,
    String? creator,
    String? coverUrl,
    String? source,
    String? sourceId,
    MatchState matchState = MatchState.unmatched,
    DateTime? now,
  }) {
    final clean = cleanTitle(title);
    if (clean.isEmpty) {
      throw ArgumentError.value(title, 'title', 'must not be empty');
    }
    final ts = now ?? DateTime.now();
    return into(items).insert(ItemsCompanion.insert(
      category: category,
      status: status,
      title: clean,
      sortTitle: sortKey(clean),
      matchKey: matchKey(clean),
      typedTitle: Value(typedTitle),
      uid: Value(newUid()),
      year: Value(year),
      genre: genre == null ? const Value.absent() : Value(genre),
      creator: Value(creator),
      coverUrl: Value(coverUrl),
      source: Value(source),
      sourceId: Value(sourceId),
      matchState: matchState,
      addedAt: ts,
      updatedAt: ts,
      completedAt: Value(status == ListStatus.done ? ts : null),
    ));
  }

  /// Moves an item between To Watch and Watched, stamping the completion date.
  Future<void> setStatus(int id, ListStatus status, {DateTime? now}) async {
    final ts = now ?? DateTime.now();
    await (update(items)..where((t) => t.id.equals(id))).write(ItemsCompanion(
      status: Value(status),
      completedAt: Value(status == ListStatus.done ? ts : null),
      updatedAt: Value(ts),
    ));
  }

  /// Saves an edited item. Title-derived keys are recalculated here so they
  /// can never drift out of sync with the title.
  Future<void> updateItem(MediaItem item) async {
    final title = cleanTitle(item.title);
    if (title.isEmpty) {
      throw ArgumentError.value(item.title, 'title', 'must not be empty');
    }
    await update(items).replace(item.copyWith(
      title: title,
      sortTitle: sortKey(title),
      matchKey: matchKey(title),
    ));
  }

  /// Every genre currently used in [category] (for the genre picker/filter).
  Future<Set<String>> genresInUse(MediaCategory category) async {
    final rows = await (select(items)
          ..where((t) => t.category.equalsValue(category)))
        .get();
    return {for (final r in rows) r.genre};
  }

  Future<MediaItem?> itemById(int id) =>
      (select(items)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Unmatched titles that haven't been retried since [notSince].
  Future<List<MediaItem>> unmatchedToRetry(DateTime notSince, {int limit = 15}) {
    return (select(items)
          ..where((t) =>
              t.matchState.equalsValue(MatchState.unmatched) &
              (t.lookupAttemptedAt.isNull() |
                  t.lookupAttemptedAt.isSmallerThanValue(notSince)))
          ..orderBy([(t) => OrderingTerm.desc(t.addedAt)])
          ..limit(limit))
        .get();
  }

  Future<void> markLookupAttempt(int id, DateTime when) async {
    await (update(items)..where((t) => t.id.equals(id)))
        .write(ItemsCompanion(lookupAttemptedAt: Value(when)));
  }

  /// Items with a cover address but no downloaded cover yet.
  Future<List<MediaItem>> missingCovers({int limit = 40}) {
    return (select(items)
          ..where((t) => t.coverUrl.isNotNull() & t.coverFile.isNull())
          ..limit(limit))
        .get();
  }

  /// Records the cached cover file for an item (or clears it).
  Future<void> setCoverFile(int id, String? fileName) async {
    await (update(items)..where((t) => t.id.equals(id)))
        .write(ItemsCompanion(coverFile: Value(fileName)));
  }

  Future<int> deleteItem(int id) =>
      (delete(items)..where((t) => t.id.equals(id))).go();

  /// Puts back an exact earlier copy of an item (used by Undo).
  Future<void> restoreItem(MediaItem item) async {
    await into(items).insertOnConflictUpdate(item);
  }

  // ------------------------------------------------------------- settings

  Future<Map<String, String>> readSettings() async {
    final rows = await select(settingsEntries).get();
    return {for (final r in rows) r.settingKey: r.settingValue};
  }

  Future<void> writeSetting(String key, String value) async {
    await into(settingsEntries).insertOnConflictUpdate(
      SettingsEntriesCompanion.insert(settingKey: key, settingValue: value),
    );
  }
}
