import 'dart:math';

import 'package:drift/drift.dart';

import '../../core/sanitise.dart';
import '../models.dart';
import '../tags.dart';

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

/// A diary entry with its item.
class DiaryEntry {
  const DiaryEntry(this.event, this.item);
  final WatchEvent event;
  final MediaItem item;
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
    int? pages,
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
    return transaction(() async {
      final id = await into(items).insert(ItemsCompanion.insert(
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
      pages: Value(pages),
      source: Value(source),
      sourceId: Value(sourceId),
      matchState: matchState,
      addedAt: ts,
      updatedAt: ts,
      completedAt: Value(status == ListStatus.done ? ts : null),
    ));
      if (status == ListStatus.done) await _addEvent(id, ts);
      return id;
    });
  }

  /// Moves an item between To Watch and Watched, stamping the completion date.
  /// Ticking adds a diary entry for today; unticking removes the entry
  /// that tick made (earlier entries stay in the diary).
  Future<void> setStatus(int id, ListStatus status, {DateTime? now}) async {
    final ts = now ?? DateTime.now();
    await transaction(() async {
      final before = await itemById(id);
      if (before == null) return;
      await (update(items)..where((t) => t.id.equals(id))).write(ItemsCompanion(
        status: Value(status),
        completedAt: Value(status == ListStatus.done ? ts : null),
        updatedAt: Value(ts),
      ));
      if (status == ListStatus.done && before.status != ListStatus.done) {
        await _addEvent(id, ts);
      } else if (status == ListStatus.todo && before.completedAt != null) {
        await (delete(watchEvents)
              ..where((e) =>
                  e.itemId.equals(id) & e.date.equals(before.completedAt!)))
            .go();
      }
    });
  }

  Future<int> _addEvent(int itemId, DateTime date,
          {int? rating, String? note}) =>
      into(watchEvents).insert(WatchEventsCompanion.insert(
        itemId: itemId,
        date: date,
        rating: Value(rating),
        note: Value(note),
        uid: Value(newUid()),
      ));

  // ---------------------------------------------------------------- diary

  /// "Watched again" / "Read again": a new diary entry; the item moves to
  /// (or stays in) the finished list with this as its latest date.
  Future<void> addRewatch(int itemId,
      {DateTime? date, int? rating, String? note, DateTime? now}) async {
    final ts = now ?? DateTime.now();
    final when = date ?? ts;
    await transaction(() async {
      final item = await itemById(itemId);
      if (item == null) return;
      await _addEvent(itemId, when,
          rating: rating?.clamp(1, 5),
          note: note == null || cleanText(note).isEmpty
              ? null
              : cleanText(note, maxLength: kMaxNoteLength));
      final latest = item.completedAt == null || when.isAfter(item.completedAt!)
          ? when
          : item.completedAt!;
      await (update(items)..where((t) => t.id.equals(itemId))).write(
          ItemsCompanion(
              status: const Value(ListStatus.done),
              completedAt: Value(latest),
              updatedAt: Value(ts)));
    });
  }

  /// Diary entries for one item, newest first.
  Stream<List<WatchEvent>> watchEventsFor(int itemId) =>
      (select(watchEvents)
            ..where((e) => e.itemId.equals(itemId))
            ..orderBy([(e) => OrderingTerm.desc(e.date)]))
          .watch();

  /// Every diary entry with its item, newest first (entries whose item was
  /// deleted are left out).
  Stream<List<DiaryEntry>> watchDiary() {
    final q = select(watchEvents).join([
      innerJoin(items, items.id.equalsExp(watchEvents.itemId)),
    ])
      ..orderBy([OrderingTerm.desc(watchEvents.date)]);
    return q.watch().map((rows) => [
          for (final r in rows)
            DiaryEntry(r.readTable(watchEvents), r.readTable(items)),
        ]);
  }

  Future<List<WatchEvent>> allEvents() => select(watchEvents).get();

  Stream<List<WatchEvent>> watchAllEvents() => select(watchEvents).watch();

  Future<void> deleteEvent(int eventId) async {
    await transaction(() async {
      final e = await (select(watchEvents)..where((t) => t.id.equals(eventId)))
          .getSingleOrNull();
      if (e == null) return;
      await (delete(watchEvents)..where((t) => t.id.equals(eventId))).go();
      final item = await itemById(e.itemId);
      if (item == null || item.completedAt != e.date) return;
      // That was the latest finish: fall back to the one before, if any.
      final previous = await (select(watchEvents)
            ..where((t) => t.itemId.equals(e.itemId))
            ..orderBy([(t) => OrderingTerm.desc(t.date)])
            ..limit(1))
          .getSingleOrNull();
      if (previous != null) {
        await (update(items)..where((t) => t.id.equals(item.id))).write(
            ItemsCompanion(
                completedAt: Value(previous.date),
                updatedAt: Value(DateTime.now())));
      }
    });
  }

  Future<void> updateEvent(WatchEvent e) async {
    await update(watchEvents).replace(e.copyWith(
      rating: Value(e.rating?.clamp(1, 5)),
      note: Value(e.note == null ? null : cleanText(e.note!,
          maxLength: kMaxNoteLength)),
    ));
  }

  /// Gives every finished item without a diary entry one entry on its
  /// finished date (for items finished before the diary existed, and
  /// imports). Safe to run often.
  Future<int> backfillDiary() async {
    return transaction(() async {
      final done = await (select(items)
            ..where((t) =>
                t.status.equalsValue(ListStatus.done) & t.completedAt.isNotNull()))
          .get();
      if (done.isEmpty) return 0;
      final withEvents = {
        for (final e in await select(watchEvents).get()) e.itemId,
      };
      var added = 0;
      for (final i in done) {
        if (withEvents.contains(i.id)) continue;
        await _addEvent(i.id, i.completedAt!, rating: i.rating, note: i.note);
        added++;
      }
      return added;
    });
  }

  // ------------------------------------------------------------ episodes

  Stream<MediaItem?> watchItem(int id) =>
      (select(items)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Stream<List<EpisodeMark>> watchMarks(int itemId) =>
      (select(episodeMarks)..where((m) => m.itemId.equals(itemId))).watch();

  /// Ticks or unticks episodes, then moves the series' S/E counters to the
  /// latest ticked episode.
  Future<void> setEpisodesWatched(
      int itemId, List<(int, int)> episodes, bool watched,
      {DateTime? now}) async {
    final ts = now ?? DateTime.now();
    await transaction(() async {
      for (final (season, number) in episodes) {
        if (watched) {
          await into(episodeMarks).insertOnConflictUpdate(
              EpisodeMarksCompanion.insert(
                  itemId: itemId,
                  season: season,
                  number: number,
                  watchedAt: ts));
        } else {
          await (delete(episodeMarks)
                ..where((m) =>
                    m.itemId.equals(itemId) &
                    m.season.equals(season) &
                    m.number.equals(number)))
              .go();
        }
      }
      await _countersFollowMarks(itemId, ts);
    });
  }

  /// Episode number 0 means "the whole season".
  static const int wholeSeason = 0;

  /// Ticks or unticks a whole season (without needing an episode list).
  Future<void> setSeasonWatched(int itemId, int season, bool watched,
      {DateTime? now}) async {
    final ts = now ?? DateTime.now();
    await transaction(() async {
      if (watched) {
        await into(episodeMarks).insertOnConflictUpdate(
            EpisodeMarksCompanion.insert(
                itemId: itemId,
                season: season,
                number: wholeSeason,
                watchedAt: ts));
      } else {
        // Unticking a season clears its episodes too.
        await (delete(episodeMarks)
              ..where((m) => m.itemId.equals(itemId) & m.season.equals(season)))
            .go();
      }
      await _countersFollowMarks(itemId, ts);
    });
  }

  /// The series' S/E counters show the latest season (and episode) ticked.
  Future<void> _countersFollowMarks(int itemId, DateTime ts) async {
    final marks = await (select(episodeMarks)
          ..where((m) => m.itemId.equals(itemId)))
        .get();
    int? season, episode;
    for (final m in marks) {
      if (season == null || m.season > season) {
        season = m.season;
        episode = null;
      }
      if (m.season == season && m.number != wholeSeason &&
          (episode == null || m.number > episode)) {
        episode = m.number;
      }
    }
    await (update(items)..where((t) => t.id.equals(itemId))).write(
        ItemsCompanion(
            season: Value(season), episode: Value(episode), updatedAt: Value(ts)));
  }

  Future<void> setFollowing(int itemId, bool following) async {
    await (update(items)..where((t) => t.id.equals(itemId))).write(
        ItemsCompanion(
            following: Value(following), updatedAt: Value(DateTime.now())));
  }

  /// Followed series that have a TVmaze ID.
  Future<List<MediaItem>> followedShows() => (select(items)
        ..where((t) =>
            t.following.equals(true) &
            t.category.equalsValue(MediaCategory.series) &
            t.source.equals('tvmaze') &
            t.sourceId.isNotNull()))
      .get();

  // ------------------------------------------------------- tags and goals

  /// Every tag used in [category] (or everywhere), sorted.
  Future<List<String>> tagsInUse([MediaCategory? category]) async {
    final q = select(items)..where((t) => t.tags.isNotNull());
    if (category != null) q.where((t) => t.category.equalsValue(category));
    final seen = <String, String>{};
    for (final i in await q.get()) {
      for (final t in decodeTags(i.tags)) {
        seen.putIfAbsent(t.toLowerCase(), () => t);
      }
    }
    return seen.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  static String _goalKey(MediaCategory c, int year) => 'goal_${c.name}_$year';

  Future<Map<MediaCategory, int>> goalsFor(int year) async {
    final all = await readSettings();
    return {
      for (final c in MediaCategory.values)
        if (int.tryParse(all[_goalKey(c, year)] ?? '') case final g?
            when g > 0)
          c: g,
    };
  }

  Future<void> setGoal(MediaCategory c, int year, int? goal) async {
    final key = _goalKey(c, year);
    if (goal == null || goal <= 0) {
      await (delete(settingsEntries)..where((t) => t.settingKey.equals(key)))
          .go();
    } else {
      await writeSetting(key, '${goal.clamp(1, 10000)}');
    }
  }

  /// Saves an edited item. Title-derived keys are recalculated here so they
  /// can never drift out of sync with the title.
  Future<void> updateItem(MediaItem item) async {
    final title = cleanTitle(item.title);
    if (title.isEmpty) {
      throw ArgumentError.value(item.title, 'title', 'must not be empty');
    }
    await transaction(() async {
      final before = await itemById(item.id);
      await update(items).replace(item.copyWith(
        title: title,
        sortTitle: sortKey(title),
        matchKey: matchKey(title),
      ));
      if (before != null) await _diaryFollows(before, item);
    });
  }

  /// Keeps the diary in step when an item's list or finished date changes
  /// (edits and Undo).
  Future<void> _diaryFollows(MediaItem before, MediaItem after) async {
    final wasDone = before.status == ListStatus.done;
    final isDone = after.status == ListStatus.done;
    final oldDate = before.completedAt;
    final newDate = after.completedAt;
    if (!wasDone && isDone && newDate != null) {
      final exists = await (select(watchEvents)
            ..where((e) => e.itemId.equals(after.id) & e.date.equals(newDate)))
          .get();
      if (exists.isEmpty) await _addEvent(after.id, newDate);
    } else if (wasDone && !isDone && oldDate != null) {
      await (delete(watchEvents)
            ..where((e) => e.itemId.equals(after.id) & e.date.equals(oldDate)))
          .go();
    } else if (wasDone && isDone && oldDate != null && newDate != null &&
        oldDate != newDate) {
      await (update(watchEvents)
            ..where((e) => e.itemId.equals(after.id) & e.date.equals(oldDate)))
          .write(WatchEventsCompanion(date: Value(newDate)));
    }
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

  /// Deletes an item. Its diary entries are kept so Undo can bring the
  /// whole thing back; they are hidden while the item is gone and tidied up
  /// at the next start. A tombstone lets sync delete it on other phones.
  Future<int> deleteItem(int id) async {
    return transaction(() async {
      final item = await itemById(id);
      final n = await (delete(items)..where((t) => t.id.equals(id))).go();
      final uid = item?.uid;
      if (n > 0 && uid != null) {
        await into(tombstones).insertOnConflictUpdate(
            TombstonesCompanion.insert(uid: uid, deletedAt: DateTime.now()));
      }
      return n;
    });
  }

  /// Puts back an exact earlier copy of an item (used by Undo).
  Future<void> restoreItem(MediaItem item) async {
    await transaction(() async {
      final current = await itemById(item.id);
      await into(items).insertOnConflictUpdate(item);
      if (current != null) await _diaryFollows(current, item);
      final uid = item.uid;
      if (uid != null) {
        await (delete(tombstones)..where((t) => t.uid.equals(uid))).go();
      }
    });
  }

  /// Removes diary entries and episode ticks whose item no longer exists.
  Future<void> tidyOrphans() async {
    await customStatement(
        'DELETE FROM watch_events WHERE item_id NOT IN (SELECT id FROM items)');
    await customStatement(
        'DELETE FROM episode_marks WHERE item_id NOT IN (SELECT id FROM items)');
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
