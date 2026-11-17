import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:watchedledger/core/net/net_client.dart';
import 'package:watchedledger/data/db/database.dart';
import 'package:watchedledger/data/lookup/lookup_service.dart';
import 'package:watchedledger/data/models.dart';
import 'package:watchedledger/data/transfer/export.dart';
import 'package:watchedledger/data/transfer/import_parsers.dart';
import 'package:watchedledger/data/transfer/import_plan.dart';

http.Response jsonResponse(Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});

List<String> titles(ImportParseResult r) => [for (final x in r.rows) x.title];

void main() {
  group('plain lists and Samsung Notes', () {
    test('one title per line, bullets and numbers removed', () {
      final r = parseImport('Heat\n\n- Dune\n• Arrival\n3. Alien\n  * Up  \n');
      expect(r.format, ImportFormat.lines);
      expect(titles(r), ['Heat', 'Dune', 'Arrival', 'Alien', 'Up']);
      expect(r.rows.every((x) => x.status == ListStatus.todo), isTrue);
    });

    test('titles that start with numbers are kept', () {
      final r = parseImport('1917\n2001: A Space Odyssey\n12 Angry Men');
      expect(titles(r), ['1917', '2001: A Space Odyssey', '12 Angry Men']);
    });

    test('ticked, crossed-out and checked items go to Watched', () {
      final r = parseImport([
        '☑ Heat',
        '☐ Dune',
        '[x] Alien',
        '[ ] Up',
        '~~Arrival~~',
        'H\u0336e\u0336a\u0336t\u0336 2',
        '✅ Fargo',
        'Brazil ✓',
        'Jaws (watched)',
      ].join('\n'));
      expect(titles(r), [
        'Heat', 'Dune', 'Alien', 'Up', 'Arrival', 'Heat 2', 'Fargo', //
        'Brazil', 'Jaws',
      ]);
      expect([for (final x in r.rows) x.status == ListStatus.done],
          [true, false, true, false, true, true, true, true, true]);
    });

    test('a year in brackets is read as the year', () {
      final r = parseImport('Heat (1995)\nBlade Runner 2049');
      expect(r.rows[0].title, 'Heat');
      expect(r.rows[0].year, 1995);
      expect(r.rows[0].query, 'Heat 1995');
      expect(r.rows[1].title, 'Blade Runner 2049');
      expect(r.rows[1].year, isNull);
    });

    test('section headings set category and list', () {
      final r = parseImport('Movies\nHeat\nBooks - Read\nDune\nPodcasts:\nSerial');
      expect(titles(r), ['Heat', 'Dune', 'Serial']);
      expect(r.rows[0].category, MediaCategory.movie);
      expect(r.rows[1].category, MediaCategory.book);
      expect(r.rows[1].status, ListStatus.done);
      expect(r.rows[2].category, MediaCategory.podcast);
    });

    test('hidden and control characters are cleaned', () {
      final r = parseImport('He\u200Bat\u202E\nDune\u0007');
      expect(titles(r), ['Heat', 'Dune']);
    });
  });

  group('WatchedLedger files', () {
    MediaItem item(String title, MediaCategory c, ListStatus s,
            {int? year, int? rating, String? note}) =>
        MediaItem(
          id: 1,
          category: c,
          status: s,
          title: title,
          sortTitle: title.toLowerCase(),
          matchKey: title.toLowerCase(),
          year: year,
          genre: kUncategorised,
          matchState: MatchState.matched,
          rating: rating,
          note: note,
          addedAt: DateTime(2026, 1, 1),
          completedAt: s == ListStatus.done ? DateTime(2026, 3, 4) : null,
          updatedAt: DateTime(2026, 1, 1),
          following: false,
        );

    final items = [
      item('Heat', MediaCategory.movie, ListStatus.done,
          year: 1995, rating: 4, note: 'Great, tense'),
      item('Dune', MediaCategory.book, ListStatus.todo, year: 1965),
      item('=cmd', MediaCategory.podcast, ListStatus.todo),
    ];

    test('text export reads back', () {
      final r = parseImport(exportText(items));
      expect(r.format, ImportFormat.watchedLedgerText);
      expect(titles(r), ['Heat', 'Dune', '=cmd']);
      expect(r.rows[0].category, MediaCategory.movie);
      expect(r.rows[0].status, ListStatus.done);
      expect(r.rows[0].year, 1995);
      expect(r.rows[0].rating, 4);
      expect(r.rows[0].note, 'Great, tense');
      expect(r.rows[1].category, MediaCategory.book);
      expect(r.rows[1].status, ListStatus.todo);
    });

    test('CSV export reads back, including formula-guarded cells', () {
      final r = parseImport(exportCsv(items), fileName: 'x.csv');
      expect(r.format, ImportFormat.watchedLedgerCsv);
      expect(titles(r), containsAll(['Heat', 'Dune', '=cmd']));
      final heat = r.rows.firstWhere((x) => x.title == 'Heat');
      expect(heat.rating, 4);
      expect(heat.status, ListStatus.done);
      expect(heat.finished, isNotNull);
    });
  });

  group('other apps', () {
    test('Letterboxd diary and watchlist', () {
      const diary = 'Date,Name,Year,Letterboxd URI,Rating,Rewatch,Tags,'
          'Watched Date\n'
          '2024-01-02,Heat,1995,https://boxd.it/x,4.5,,"crime, rewatch",'
          '2024-01-01\n';
      final r = parseImport(diary, fileName: 'diary.csv');
      expect(r.format, ImportFormat.letterboxd);
      expect(r.rows.single.title, 'Heat');
      expect(r.rows.single.year, 1995);
      expect(r.rows.single.rating, 5);
      expect(r.rows.single.status, ListStatus.done);
      expect(r.rows.single.finished, DateTime(2024));
      expect(r.rows.single.tags, ['crime', 'rewatch']);

      const list = 'Date,Name,Year,Letterboxd URI\n2024-01-02,Dune,2021,u\n';
      final w = parseImport(list, fileName: 'watchlist.csv');
      expect(w.rows.single.status, ListStatus.todo);
    });

    test('Goodreads shelves, audiobooks and series numbers', () {
      const csv = 'Book Id,Title,Author,My Rating,Number of Pages,'
          'Original Publication Year,Date Read,Bookshelves,Exclusive Shelf,'
          'Binding,My Review\n'
          '1,"The Way of Kings (The Stormlight Archive, #1)",Brandon '
          'Sanderson,5,1007,2010,2023/05/17,"fantasy",read,Hardcover,'
          '"<b>Loved</b> it"\n'
          '2,Project Hail Mary,Andy Weir,0,,2021,,,to-read,Audible Audio,\n';
      final r = parseImport(csv, fileName: 'goodreads_library_export.csv');
      expect(r.format, ImportFormat.goodreads);
      final a = r.rows[0], b = r.rows[1];
      expect(a.title, 'The Way of Kings');
      expect(a.creator, 'Brandon Sanderson');
      expect(a.category, MediaCategory.book);
      expect(a.status, ListStatus.done);
      expect(a.rating, 5);
      expect(a.pages, 1007);
      expect(a.year, 2010);
      expect(a.finished, DateTime(2023, 5, 17));
      expect(a.note, 'Loved it');
      expect(a.tags, ['fantasy']);
      expect(b.category, MediaCategory.audiobook);
      expect(b.status, ListStatus.todo);
      expect(b.rating, isNull);
    });

    test('IMDb ratings use a 10-point scale', () {
      const csv = 'Const,Your Rating,Date Rated,Title,URL,Title Type,'
          'IMDb Rating,Runtime (mins),Year,Genres,Num Votes,Release Date,'
          'Directors\n'
          'tt1,8,2024-02-03,Heat,u,Movie,8.3,170,1995,Crime,1,1995-12-15,'
          'Michael Mann\n'
          'tt2,10,2024-02-04,The Wire,u,TV Series,9.3,59,2002,Crime,1,,\n';
      final r = parseImport(csv, fileName: 'ratings.csv');
      expect(r.format, ImportFormat.imdb);
      expect(r.rows[0].rating, 4);
      expect(r.rows[0].runtimeMinutes, 170);
      expect(r.rows[0].creator, 'Michael Mann');
      expect(r.rows[0].status, ListStatus.done);
      expect(r.rows[1].category, MediaCategory.series);
      expect(r.rows[1].rating, 5);
    });

    test('Trakt JSON history and watchlist', () {
      final history = jsonEncode([
        {
          'plays': 2,
          'last_watched_at': '2024-03-01T20:00:00.000Z',
          'movie': {'title': 'Heat', 'year': 1995},
        },
        {
          'last_watched_at': '2024-03-02T20:00:00.000Z',
          'show': {'title': 'Severance', 'year': 2022},
        },
        {'junk': true},
      ]);
      final r = parseImport(history, fileName: 'watched-movies.json');
      expect(r.format, ImportFormat.trakt);
      expect(titles(r), ['Heat', 'Severance']);
      expect(r.rows[0].status, ListStatus.done);
      expect(r.rows[1].category, MediaCategory.series);

      final watchlist = jsonEncode([
        {
          'listed_at': '2024-03-01T20:00:00.000Z',
          'movie': {'title': 'Dune', 'year': 2021},
        },
      ]);
      expect(parseImport(watchlist).rows.single.status, ListStatus.todo);
    });

    test('any spreadsheet with a Title column', () {
      const csv = 'Title,Type,Status,Year\nHeat,Movie,Watched,1995\n'
          'Dune,Book,,\n';
      final r = parseImport(csv);
      expect(r.format, ImportFormat.genericCsv);
      expect(r.rows[0].category, MediaCategory.movie);
      expect(r.rows[0].status, ListStatus.done);
      expect(r.rows[1].category, MediaCategory.book);
      expect(r.rows[1].status, ListStatus.todo);
    });

    test('a list that starts with [x] is not mistaken for JSON', () {
      final r = parseImport('[x] Heat\n[ ] Dune');
      expect(r.format, ImportFormat.lines);
      expect(titles(r), ['Heat', 'Dune']);
    });
  });

  group('review and save', () {
    late AppDatabase db;
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.addItem(
          category: MediaCategory.movie,
          status: ListStatus.done,
          title: 'Heat');
    });
    tearDown(() => db.close());

    test('duplicates (library and within the import) start unticked',
        () async {
      final rows = parseImport('Heat\nDune\ndune\nHeat').rows;
      final entries = await prepareImport(db, rows, MediaCategory.movie);
      expect([for (final e in entries) e.duplicate],
          [true, false, true, true]);
      expect([for (final e in entries) e.include],
          [false, true, false, false]);
    });

    test('the same title in another category is not a duplicate', () async {
      final rows = parseImport('Heat').rows;
      final entries = await prepareImport(db, rows, MediaCategory.book);
      expect(entries.single.duplicate, isFalse);
    });

    test('lookup fills clear matches and leaves the rest for review',
        () async {
      final net = NetClient(
        isOffline: () => false,
        inner: MockClient((req) async {
          final q = req.url.queryParameters['q'] ?? '';
          if (q.contains('severance')) {
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
          return jsonResponse([]);
        }),
      );
      final rows = parseImport('severance\nzzqx unknown').rows;
      final entries = await prepareImport(db, rows, MediaCategory.series);
      final progress = <int>[];
      await lookupAll(LookupService(net), entries,
          onProgress: (d, _) => progress.add(d));
      expect(entries[0].match?.title, 'Severance');
      expect(entries[0].year, 2022);
      expect(entries[1].match, isNull);
      expect(entries[1].needsAttention, isTrue);
      expect(progress, [0, 1, 2]);
    });

    test('offline: lookup stops and nothing is marked as looked', () async {
      final net = NetClient(
        isOffline: () => true,
        inner: MockClient((_) async => fail('nothing may be sent')),
      );
      final entries = await prepareImport(
          db, parseImport('Dune').rows, MediaCategory.movie);
      await lookupAll(LookupService(net), entries);
      expect(entries.single.looked, isFalse);
    });

    test('save keeps status, rating, dates and skips unticked rows', () async {
      const csv = 'Date,Name,Year,Letterboxd URI,Rating,Watched Date\n'
          '2024-01-02,Heat,1995,u,4,2024-01-01\n'
          '2024-01-02,Alien,1979,u,2.5,2023-06-05\n';
      final entries = await prepareImport(
          db, parseImport(csv, fileName: 'diary.csv').rows,
          MediaCategory.movie);
      final added = await saveImport(db, entries, now: DateTime(2026, 11, 17));
      expect(added, 1);
      final all = await db.select(db.items).get();
      final alien = all.firstWhere((i) => i.title == 'Alien');
      expect(alien.status, ListStatus.done);
      expect(alien.year, 1979);
      expect(alien.rating, 3);
      expect(alien.completedAt, DateTime(2023, 6, 5));
      expect(alien.matchState, MatchState.unmatched);
      expect(alien.uid, hasLength(32));
      expect(all, hasLength(2));
    });
  });
}
