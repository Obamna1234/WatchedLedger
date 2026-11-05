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
}

@DataClassName('SettingEntry')
class SettingsEntries extends Table {
  TextColumn get settingKey => text()();
  TextColumn get settingValue => text()();

  @override
  Set<Column<Object>> get primaryKey => {settingKey};
}

@DriftDatabase(tables: [Items, SettingsEntries])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
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
      matchState: MatchState.unmatched,
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
