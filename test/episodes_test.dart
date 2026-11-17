import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:watchedledger/core/net/net_client.dart';
import 'package:watchedledger/core/reminders.dart';
import 'package:watchedledger/data/db/database.dart';
import 'package:watchedledger/data/lookup/episodes.dart';
import 'package:watchedledger/data/models.dart';

http.Response jsonResponse(Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  test('TVmaze episodes are parsed, sorted, specials and junk dropped',
      () async {
    final sent = <Uri>[];
    final net = NetClient(
      isOffline: () => false,
      inner: MockClient((req) async {
        sent.add(req.url);
        return jsonResponse([
          {
            'season': 1,
            'number': 2,
            'name': 'Half Loop',
            'airstamp': '2022-02-25T02:00:00+00:00',
            'runtime': 55,
          },
          {'season': 1, 'number': 1, 'name': 'Good News About Hell'},
          {'season': 1, 'number': null, 'name': 'Special'},
          'junk',
        ]);
      }),
    );
    final eps = await EpisodeService(net).episodes('44933');
    expect([for (final e in eps) e.code], ['S01E01', 'S01E02']);
    expect(eps[1].airstamp, DateTime.utc(2022, 2, 25, 2));
    expect(eps[1].runtime, 55);
    expect(sent.single.path, '/shows/44933/episodes');
    expect(await EpisodeService(net).episodes('../x'), isEmpty);
  });

  test('reminders: only future episodes within 45 days, soonest first', () {
    final show = MediaItem(
      id: 7,
      category: MediaCategory.series,
      status: ListStatus.todo,
      title: 'Severance',
      sortTitle: 'severance',
      matchKey: 'severance',
      genre: kUncategorised,
      matchState: MatchState.matched,
      following: true,
      upcoming: false,
      isPrivate: false,
      addedAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final now = DateTime.utc(2026, 11, 17);
    Episode ep(int n, DateTime? at) =>
        Episode(season: 3, number: n, name: 'Ep $n', airstamp: at);
    final plan = ReminderService.plan({
      show: [
        ep(1, DateTime.utc(2026, 11, 1)),
        ep(3, DateTime.utc(2026, 12, 8)),
        ep(2, DateTime.utc(2026, 12, 1)),
        ep(4, DateTime.utc(2027, 3, 1)),
        ep(5, null),
      ],
    }, now);
    expect([for (final r in plan) r.body],
        ['S03E02 "Ep 2" is out', 'S03E03 "Ep 3" is out']);
    expect(plan.first.title, 'Severance');
    expect(plan.map((r) => r.id).toSet(), hasLength(2));
  });

  group('database', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('ticking episodes moves the S/E counters to the latest', () async {
      final id = await db.addItem(
          category: MediaCategory.series,
          status: ListStatus.todo,
          title: 'Severance',
          source: 'tvmaze',
          sourceId: '44933');
      await db.setEpisodesWatched(id, [(1, 1), (1, 2), (2, 1)], true);
      var item = (await db.itemById(id))!;
      expect((item.season, item.episode), (2, 1));
      await db.setEpisodesWatched(id, [(2, 1)], false);
      item = (await db.itemById(id))!;
      expect((item.season, item.episode), (1, 2));
      expect(await db.watchMarks(id).first, hasLength(2));
    });

    test('whole seasons can be ticked without an episode list', () async {
      final id = await db.addItem(
          category: MediaCategory.series,
          status: ListStatus.todo,
          title: 'Mo');
      await db.setSeasonWatched(id, 1, true);
      var item = (await db.itemById(id))!;
      expect((item.season, item.episode), (1, null));

      await db.setEpisodesWatched(id, [(2, 3)], true);
      item = (await db.itemById(id))!;
      expect((item.season, item.episode), (2, 3));

      // Unticking a season clears its episodes too.
      await db.setSeasonWatched(id, 2, false);
      item = (await db.itemById(id))!;
      expect((item.season, item.episode), (1, null));
      expect(await db.watchMarks(id).first, hasLength(1));
    });

    test('followed shows need a TVmaze match', () async {
      final a = await db.addItem(
          category: MediaCategory.series,
          status: ListStatus.todo,
          title: 'A',
          source: 'tvmaze',
          sourceId: '1');
      final b = await db.addItem(
          category: MediaCategory.series,
          status: ListStatus.todo,
          title: 'B',
          source: 'itunes',
          sourceId: '2');
      await db.setFollowing(a, true);
      await db.setFollowing(b, true);
      expect([for (final i in await db.followedShows()) i.title], ['A']);
    });
  });
}
