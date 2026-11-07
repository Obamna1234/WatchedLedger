// Drives the real add box and "Did you mean…?" sheet like a user would,
// with pretend lookup services, to check what happens with misspellings.
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:watchedledger/core/app_scope.dart';
import 'package:watchedledger/core/net/net_client.dart';
import 'package:watchedledger/core/settings.dart';
import 'package:watchedledger/data/covers/cover_cache.dart';
import 'package:watchedledger/data/db/database.dart';
import 'package:watchedledger/data/lookup/lookup_service.dart';
import 'package:watchedledger/data/models.dart';
import 'package:watchedledger/features/add/quick_add_bar.dart';

http.Response jsonResponse(Object body) => http.Response.bytes(
    utf8.encode(jsonEncode(body)), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});

/// Pretend services: TVmaze is spelling-tolerant (like the real one);
/// iTunes only finds correctly spelled titles.
Future<http.Response> fakeServices(http.Request req) async {
  final q = req.url.queryParameters;
  if (req.url.host == 'api.tvmaze.com') {
    if ((q['q'] ?? '').toLowerCase().startsWith('sever')) {
      return jsonResponse([
        {
          'show': {
            'id': 44933,
            'name': 'Severance',
            'premiered': '2022-02-18',
            'genres': ['Drama', 'Mystery', 'Science-Fiction'],
          },
        },
      ]);
    }
    return jsonResponse([]);
  }
  if (req.url.host == 'itunes.apple.com') {
    if ((q['term'] ?? '').toLowerCase() == 'inception') {
      return jsonResponse({
        'results': [
          {
            'trackId': 400763833,
            'trackName': 'Inception',
            'artistName': 'Christopher Nolan',
            'releaseDate': '2010-07-16T07:00:00Z',
            'primaryGenreName': 'Action & Adventure',
          },
        ],
      });
    }
    return jsonResponse({'resultCount': 0, 'results': []});
  }
  return http.Response('', 404);
}

class Harness {
  Harness(this.db, this.settings, this.requests);
  final AppDatabase db;
  final SettingsController settings;
  final List<Uri> requests;
}

Future<Harness> pumpAddBar(WidgetTester tester, MediaCategory category) async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final settings = SettingsController(db);
  final requests = <Uri>[];
  final net = NetClient(
    isOffline: () => settings.offlineMode,
    inner: MockClient((req) {
      requests.add(req.url);
      return fakeServices(req);
    }),
  );
  await tester.pumpWidget(AppScope(
    db: db,
    settings: settings,
    net: net,
    lookup: LookupService(net),
    covers: CoverCache(net, Directory.systemTemp),
    child: MaterialApp(
      home: Scaffold(body: QuickAddBar(category: category)),
    ),
  ));
  return Harness(db, settings, requests);
}

Future<void> typeAndAdd(WidgetTester tester, String title) async {
  await tester.enterText(find.byType(TextField).first, title);
  await tester.tap(find.byTooltip('Add'));
  await tester.pumpAndSettle();
}

Finder get sheet => find.byType(BottomSheet);

Future<List<MediaItem>> saved(WidgetTester tester, Harness h) async =>
    (await tester.runAsync(() => h.db.select(h.db.items).get()))!;

/// Let snackbars time out so no timers are left running.
Future<void> finish(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('misspelled "Severence" → Did you mean → pick Severance',
      (tester) async {
    final h = await pumpAddBar(tester, MediaCategory.series);
    await typeAndAdd(tester, 'Severence');

    // Not filed automatically: the spelling differs, so the user chooses.
    expect(find.text('Did you mean…?'), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('Severance')),
        findsOneWidget);

    await tester.tap(find.descendant(of: sheet, matching: find.text('Severance')));
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);

    final items = await saved(tester, h);
    expect(items, hasLength(1));
    final item = items.single;
    expect(item.title, 'Severance');
    expect(item.typedTitle, 'Severence');
    expect(item.year, 2022);
    expect(item.genre, 'Science Fiction');
    expect(item.matchState, MatchState.matched);
    expect(find.textContaining('Added "Severance (2022)"'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('misspelled "Inceptoin" finds nothing → fix it in the box → pick',
      (tester) async {
    final h = await pumpAddBar(tester, MediaCategory.movie);
    await typeAndAdd(tester, 'Inceptoin');

    expect(find.text('Did you mean…?'), findsOneWidget);
    expect(find.textContaining('No matches in iTunes'), findsOneWidget);

    // Keep typing in the sheet and search again.
    final box = find.descendant(of: sheet, matching: find.byType(TextField));
    await tester.enterText(box, 'Inception');
    await tester.tap(find.byTooltip('Search again'));
    await tester.pumpAndSettle();

    final result = find.descendant(of: sheet, matching: find.byType(ListTile));
    expect(result, findsOneWidget);
    await tester.tap(result);
    await tester.pumpAndSettle();

    final item = (await saved(tester, h)).single;
    expect(item.title, 'Inception');
    expect(item.year, 2010);
    expect(item.creator, 'Christopher Nolan');
    expect(item.genre, 'Action');
    expect(item.typedTitle, 'Inceptoin');
    await finish(tester);
  });

  testWidgets('nothing found → save exactly what was typed', (tester) async {
    final h = await pumpAddBar(tester, MediaCategory.movie);
    await typeAndAdd(tester, "Grandma's 80th Birthday Video");

    await tester.tap(find.textContaining('" as typed'));
    await tester.pumpAndSettle();

    final item = (await saved(tester, h)).single;
    expect(item.title, "Grandma's 80th Birthday Video");
    expect(item.matchState, MatchState.manual);
    expect(item.year, isNull);
    expect(item.genre, kUncategorised);
    await finish(tester);
  });

  testWidgets('correct spelling is filed straight away, no sheet',
      (tester) async {
    final h = await pumpAddBar(tester, MediaCategory.movie);
    await typeAndAdd(tester, 'inception');

    expect(sheet, findsNothing);
    final item = (await saved(tester, h)).single;
    expect(item.title, 'Inception');
    expect(item.matchState, MatchState.matched);
    await finish(tester);
  });

  testWidgets('offline mode saves as typed and sends nothing', (tester) async {
    final h = await pumpAddBar(tester, MediaCategory.movie);
    await tester.runAsync(() => h.settings.setOfflineMode(true));
    await tester.pump();
    await typeAndAdd(tester, 'Inceptoin');

    expect(sheet, findsNothing);
    expect(h.requests, isEmpty);
    final item = (await saved(tester, h)).single;
    expect(item.title, 'Inceptoin');
    expect(item.matchState, MatchState.unmatched);
    await finish(tester);
  });
}
