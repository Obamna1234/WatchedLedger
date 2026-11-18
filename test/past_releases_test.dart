// Every past release's database must open in this version with nothing lost.
//
// test/fixtures/db_<tag>.sqlite were saved by each release's own code (see
// tool/fixtures/make_fixture_test.dart and the "Past release databases"
// workflow). Add the new fixture after every release.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchedledger/data/db/database.dart';
import 'package:watchedledger/data/models.dart';

void main() {
  final fixtures = Directory('test/fixtures')
      .listSync()
      .whereType<File>()
      .where((f) => RegExp(r'db_v[\d.]+\.sqlite$').hasMatch(f.path))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('there are past-release databases to check', () {
    expect(fixtures.length, greaterThanOrEqualTo(6));
  });

  for (final fixture in fixtures) {
    final name = fixture.uri.pathSegments.last;
    test('$name opens in this version with nothing lost', () async {
      // Work on a copy: opening upgrades the file in place.
      final dir = await Directory.systemTemp.createTemp('wl-past-');
      addTearDown(() => dir.delete(recursive: true));
      final copy = await fixture.copy('${dir.path}/$name');
      final db = AppDatabase(NativeDatabase(copy));
      addTearDown(db.close);

      final items = {for (final i in await db.select(db.items).get()) i.title: i};
      expect(items.keys.toSet(), {
        'Heat',
        'Arrival',
        'Severance',
        'Amélie à Paris – «Édition spéciale»',
        'Project Hail Mary',
        'Typed exactly as is (unmatched)',
      });

      final heat = items['Heat']!;
      expect((heat.category, heat.status), (MediaCategory.movie, ListStatus.todo));
      expect((heat.year, heat.genre, heat.creator), (1995, 'Crime', 'Michael Mann'));
      expect(heat.matchState, MatchState.matched);

      final arrival = items['Arrival']!;
      expect(arrival.status, ListStatus.done);
      expect(arrival.rating, 5);
      expect(arrival.note, 'Watch again with subtitles');
      expect(arrival.completedAt, isNotNull);
      expect((arrival.completedAt!.year, arrival.completedAt!.month), (2026, 2));

      final show = items['Severance']!;
      expect((show.category, show.season, show.episode),
          (MediaCategory.series, 2, 4));

      expect(items['Project Hail Mary']!.category, MediaCategory.audiobook);
      expect(items['Typed exactly as is (unmatched)']!.category,
          MediaCategory.podcast);
      expect(items.values.where((i) => i.status == ListStatus.done).length, 2);

      expect((await db.readSettings())['fixture_check'], 'kept');

      // Upgraded to this version's layout, and still writable.
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), db.schemaVersion);
      final id = await db.addItem(
          category: MediaCategory.game,
          status: ListStatus.todo,
          title: 'Added after upgrade');
      expect((await db.itemById(id))!.title, 'Added after upgrade');
      for (final i in items.values) {
        expect(i.uid, matches(RegExp(r'^[0-9a-f]{32}$')));
      }
    });
  }
}
