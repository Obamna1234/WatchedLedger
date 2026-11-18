// Writes a small library to a database file using THIS checkout's code.
//
// The "Past release databases" workflow copies this file into a checkout of
// each release tag and runs it there, so each fixture in test/fixtures/ is a
// database saved by that release's own code. test/past_releases_test.dart
// then opens every fixture with the current code.
//
// Only APIs that every release has are used (addItem, setStatus, updateItem,
// writeSetting). The data is made up: no personal data.
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchedledger/data/db/database.dart';
import 'package:watchedledger/data/models.dart';

void main() {
  test('write fixture database', () async {
    final out = File(Platform.environment['FIXTURE_OUT']!);
    if (out.existsSync()) out.deleteSync();
    final db = AppDatabase(NativeDatabase(out));
    final t = DateTime(2026, 1, 2, 3, 4);
    Future<MediaItem> byId(int id) =>
        (db.select(db.items)..where((i) => i.id.equals(id))).getSingle();

    await db.addItem(
        category: MediaCategory.movie,
        status: ListStatus.todo,
        title: 'Heat',
        year: 1995,
        genre: 'Crime',
        creator: 'Michael Mann',
        matchState: MatchState.matched,
        now: t);
    final arrival = await db.addItem(
        category: MediaCategory.movie,
        status: ListStatus.todo,
        title: 'Arrival',
        year: 2016,
        genre: 'Science Fiction',
        now: t);
    await db.setStatus(arrival, ListStatus.done, now: DateTime(2026, 2, 3));
    final rated = await byId(arrival);
    await db.updateItem(rated.copyWith(
        rating: const Value(5), note: const Value('Watch again with subtitles')));

    final show = await db.addItem(
        category: MediaCategory.series,
        status: ListStatus.todo,
        title: 'Severance',
        year: 2022,
        now: t);
    final s = await byId(show);
    await db.updateItem(
        s.copyWith(season: const Value(2), episode: const Value(4)));

    await db.addItem(
        category: MediaCategory.book,
        status: ListStatus.done,
        title: 'Amélie à Paris – «Édition spéciale»',
        now: t);
    await db.addItem(
        category: MediaCategory.audiobook,
        status: ListStatus.todo,
        title: 'Project Hail Mary',
        now: t);
    await db.addItem(
        category: MediaCategory.podcast,
        status: ListStatus.todo,
        title: 'Typed exactly as is (unmatched)',
        now: t);
    await db.writeSetting('fixture_check', 'kept');
    await db.close();
  });
}
