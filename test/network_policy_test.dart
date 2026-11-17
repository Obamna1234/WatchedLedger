import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:watchedledger/core/net/net_client.dart';
import 'package:watchedledger/core/net/network_status.dart';
import 'package:watchedledger/core/settings.dart';
import 'package:watchedledger/data/covers/cover_cache.dart';
import 'package:watchedledger/data/db/database.dart';
import 'package:watchedledger/data/lookup/background_matcher.dart';
import 'package:watchedledger/data/lookup/lookup_service.dart';
import 'package:watchedledger/data/models.dart';

http.Response jsonResponse(Object body) => http.Response.bytes(
    utf8.encode(jsonEncode(body)), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  group('NetworkStatus', () {
    test('mobile data is metered unless Wi-Fi is also up', () {
      final s = NetworkStatus();
      s.update([ConnectivityResult.mobile]);
      expect(s.isMetered, isTrue);
      expect(s.label, 'On mobile data');
      s.update([ConnectivityResult.mobile, ConnectivityResult.wifi]);
      expect(s.isMetered, isFalse);
      s.update([ConnectivityResult.wifi]);
      expect(s.label, 'On Wi-Fi');
      s.update([ConnectivityResult.none]);
      expect(s.hasNoConnection, isTrue);
    });
  });

  group('mobile data setting', () {
    test('each option allows the right requests', () {
      expect(MobileDataUse.none.allows(NetPurpose.lookup), isFalse);
      expect(MobileDataUse.none.allows(NetPurpose.image), isFalse);
      expect(MobileDataUse.lookupsOnly.allows(NetPurpose.lookup), isTrue);
      expect(MobileDataUse.lookupsOnly.allows(NetPurpose.image), isFalse);
      expect(MobileDataUse.everything.allows(NetPurpose.image), isTrue);
    });

    test('blocked requests send nothing', () async {
      var calls = 0;
      final net = NetClient(
        isOffline: () => false,
        mayUseConnection: (p) => p == NetPurpose.lookup,
        inner: MockClient((_) async {
          calls++;
          return jsonResponse({});
        }),
      );
      await net.getJson(Uri.https('api.tvmaze.com', '/x'));
      await expectLater(
        net.getBytes(Uri.https('static.tvmaze.com', '/a.jpg'),
            purpose: NetPurpose.image),
        throwsA(isA<NotOnWifiException>()),
      );
      expect(calls, 1);
      expect(net.mayUse(NetPurpose.image), isFalse);
    });

    test('default is Wi-Fi only', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final settings = SettingsController(db);
      await settings.load();
      expect(settings.mobileData, MobileDataUse.none);
      await settings.setMobileData(MobileDataUse.lookupsOnly);
      final again = SettingsController(db);
      await again.load();
      expect(again.mobileData, MobileDataUse.lookupsOnly);
    });
  });

  group('BackgroundMatcher', () {
    late AppDatabase db;
    late SettingsController settings;
    var allowed = true;
    var requests = 0;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      settings = SettingsController(db);
      await settings.load();
      allowed = true;
      requests = 0;
    });
    tearDown(() => db.close());

    BackgroundMatcher matcher() {
      final net = NetClient(
        isOffline: () => false,
        mayUseConnection: (_) => allowed,
        inner: MockClient((req) async {
          requests++;
          if (req.url.host == 'api.tvmaze.com') {
            return jsonResponse([
              {
                'show': {
                  'id': 1,
                  'name': 'Severance',
                  'premiered': '2022-02-18',
                  'genres': ['Drama'],
                },
              },
            ]);
          }
          return jsonResponse({'results': []});
        }),
      );
      return BackgroundMatcher(
        db: db,
        lookup: LookupService(net),
        covers: CoverCache(net, Directory.systemTemp),
        net: net,
        settings: settings,
      );
    }

    test('matches titles saved on mobile data once allowed', () async {
      final id = await db.addItem(
        category: MediaCategory.series,
        status: ListStatus.todo,
        title: 'severance',
        typedTitle: 'severance',
      );
      allowed = false;
      await matcher().run();
      expect(requests, 0);
      expect((await db.itemById(id))!.matchState, MatchState.unmatched);

      allowed = true;
      await matcher().run();
      final item = (await db.itemById(id))!;
      expect(item.title, 'Severance');
      expect(item.year, 2022);
      expect(item.matchState, MatchState.matched);
    });

    test('never retries "save as typed" and waits days between retries',
        () async {
      await db.addItem(
        category: MediaCategory.series,
        status: ListStatus.todo,
        title: "Grandma's video",
        matchState: MatchState.manual,
      );
      final id = await db.addItem(
        category: MediaCategory.series,
        status: ListStatus.todo,
        title: 'Unknown Show XYZ',
      );
      final now = DateTime(2026, 11, 17);
      await matcher().run(now: now);
      expect(requests, greaterThan(0)); // only the unmatched one
      final tried = requests;
      await matcher().run(now: now.add(const Duration(hours: 5)));
      expect(requests, tried);
      expect((await db.itemById(id))!.lookupAttemptedAt, now);
    });
  });

  test('schema v1 databases upgrade without losing data', () async {
    final db = AppDatabase(NativeDatabase.memory(setup: (raw) {
      raw.execute('''
        CREATE TABLE "items" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          "category" INTEGER NOT NULL, "status" INTEGER NOT NULL,
          "title" TEXT NOT NULL, "sort_title" TEXT NOT NULL,
          "match_key" TEXT NOT NULL, "typed_title" TEXT NULL,
          "year" INTEGER NULL, "genre" TEXT NOT NULL DEFAULT 'Uncategorised',
          "extra_genres" TEXT NULL, "creator" TEXT NULL,
          "cover_url" TEXT NULL, "cover_file" TEXT NULL, "source" TEXT NULL,
          "source_id" TEXT NULL, "match_state" INTEGER NOT NULL,
          "rating" INTEGER NULL, "note" TEXT NULL, "season" INTEGER NULL,
          "episode" INTEGER NULL, "added_at" INTEGER NOT NULL,
          "completed_at" INTEGER NULL, "updated_at" INTEGER NOT NULL);
        CREATE TABLE "settings_entries" ("setting_key" TEXT NOT NULL,
          "setting_value" TEXT NOT NULL, PRIMARY KEY ("setting_key"));
        INSERT INTO items (category, status, title, sort_title, match_key,
          match_state, rating, added_at, completed_at, updated_at)
          VALUES (0, 1, 'Heat', 'heat', 'heat', 1, 5, 1700000000, 1700000000,
          1700000000);
        PRAGMA user_version = 1;
      ''');
    }));
    addTearDown(db.close);
    final item = (await db.select(db.items).get()).single;
    expect(item.title, 'Heat');
    expect(item.rating, 5);
    expect(item.following, isFalse);
    expect(item.uid, matches(RegExp(r'^[0-9a-f]{32}$')));
    // New tables exist.
    expect(await db.select(db.watchEvents).get(), isEmpty);
    await db.into(db.tombstones).insert(
        TombstonesCompanion.insert(uid: 'x', deletedAt: DateTime(2026)));
    // New items get a uid too.
    final id = await db.addItem(
        category: MediaCategory.book, status: ListStatus.todo, title: 'Dune');
    expect((await db.itemById(id))!.uid, isNotNull);
  });
}
