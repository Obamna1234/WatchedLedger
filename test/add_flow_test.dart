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

/// Pretend services that behave like the real ones (see the live check):
/// TVmaze and Wikipedia forgive typos; iTunes only finds exact spellings
/// and no longer returns movies at all.
Future<http.Response> fakeServices(http.Request req) async {
  final q = req.url.queryParameters;
  if (req.url.host == 'en.wikipedia.org') {
    if (req.url.path.startsWith('/api/rest_v1/page/summary/')) {
      return jsonResponse({
        'title': 'Inception',
        'extract': 'Inception is a 2010 science fiction action film written '
            'and directed by Christopher Nolan.',
      });
    }
    final term = (q['q'] ?? '').toLowerCase();
    if (term.startsWith('incep')) {
      return jsonResponse({
        'pages': [
          {
            'key': 'Inception',
            'title': 'Inception',
            'description': '2010 film by Christopher Nolan',
          },
          {
            'key': 'Inception_(deep_learning_architecture)',
            'title': 'Inception (deep learning architecture)',
            'description': 'Family of convolutional neural networks',
          },
        ],
      });
    }
    return jsonResponse({'pages': []});
  }
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
    if (q['media'] == 'podcast' &&
        (q['term'] ?? '').toLowerCase() == 'hardcore history') {
      return jsonResponse({
        'results': [
          {
            'collectionId': 173001861,
            'collectionName': "Dan Carlin's Hardcore History",
            'artistName': 'Dan Carlin',
            'primaryGenreName': 'History',
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
  await pumpABit(tester);
}

Finder get sheet => find.byType(BottomSheet);

/// Advances the test clock ~2 seconds. (pumpAndSettle would never return
/// while the Add button's progress spinner is turning behind the sheet.)
Future<void> pumpABit(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Waits for [future] by advancing the test clock (the database and the
/// pretend network both run on it).
Future<T> settle<T>(WidgetTester tester, Future<T> future) async {
  late T value;
  var done = false;
  Object? error;
  future.then((v) {
    value = v;
    done = true;
  }, onError: (Object e) {
    error = e;
    done = true;
  }).ignore();
  for (var i = 0; i < 100 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  if (error != null) throw error!;
  expect(done, isTrue, reason: 'timed out waiting');
  return value;
}

Future<List<MediaItem>> saved(WidgetTester tester, Harness h) =>
    settle(tester, h.db.select(h.db.items).get());

/// Let snackbars time out and unmount everything, so no timers are left.
Future<void> finish(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
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
    await pumpABit(tester);
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

  testWidgets('misspelled "Inceptoin" → Did you mean → Inception (2010)',
      (tester) async {
    final h = await pumpAddBar(tester, MediaCategory.movie);
    await typeAndAdd(tester, 'Inceptoin');

    expect(find.text('Did you mean…?'), findsOneWidget);
    // Only the film is offered, not the deep-learning article.
    final results = find.descendant(of: sheet, matching: find.byType(ListTile));
    expect(results, findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('Inception')),
        findsOneWidget);

    await tester.tap(results);
    await pumpABit(tester);

    final item = (await saved(tester, h)).single;
    expect(item.title, 'Inception');
    expect(item.year, 2010);
    expect(item.creator, 'Christopher Nolan');
    expect(item.genre, 'Science Fiction'); // from the Wikipedia summary
    expect(item.typedTitle, 'Inceptoin');
    expect(item.source, 'wikipedia');
    await finish(tester);
  });

  testWidgets('typo nothing recognises → fix it in the box → search again',
      (tester) async {
    final h = await pumpAddBar(tester, MediaCategory.podcast);
    // Neither pretend service recognises this typo, so the sheet says
    // "No matches" and the user corrects it there.
    await typeAndAdd(tester, 'Hardcore Histroy');
    expect(find.textContaining('No matches'), findsOneWidget);

    final box = find.descendant(of: sheet, matching: find.byType(TextField));
    await tester.enterText(box, 'Hardcore History');
    await tester.tap(find.byTooltip('Search again'));
    await pumpABit(tester);

    final result = find.descendant(of: sheet, matching: find.byType(ListTile));
    expect(result, findsOneWidget);
    await tester.tap(result);
    await pumpABit(tester);

    final item = (await saved(tester, h)).single;
    expect(item.title, "Dan Carlin's Hardcore History");
    expect(item.genre, 'History');
    await finish(tester);
  });

  testWidgets('nothing found → save exactly what was typed', (tester) async {
    final h = await pumpAddBar(tester, MediaCategory.movie);
    await typeAndAdd(tester, "Grandma's 80th Birthday Video");

    expect(find.textContaining('No matches'), findsOneWidget);
    await tester.tap(find.textContaining('" as typed'));
    await pumpABit(tester);

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
    expect(item.year, 2010);
    expect(item.matchState, MatchState.matched);
    await finish(tester);
  });

  testWidgets('offline mode saves as typed and sends nothing', (tester) async {
    final h = await pumpAddBar(tester, MediaCategory.movie);
    await settle(tester, h.settings.setOfflineMode(true));
    await typeAndAdd(tester, 'Inceptoin');

    expect(sheet, findsNothing);
    expect(h.requests, isEmpty);
    final item = (await saved(tester, h)).single;
    expect(item.title, 'Inceptoin');
    expect(item.matchState, MatchState.unmatched);
    await finish(tester);
  });
}
