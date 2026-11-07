import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:watchedledger/core/net/net_client.dart';
import 'package:watchedledger/data/covers/cover_cache.dart';
import 'package:watchedledger/data/lookup/candidate.dart';
import 'package:watchedledger/data/lookup/genre_map.dart';
import 'package:watchedledger/data/lookup/lookup_service.dart';
import 'package:watchedledger/data/lookup/providers.dart';
import 'package:watchedledger/data/models.dart';

http.Response jsonResponse(Object body, {int status = 200}) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

NetClient client(MockClientHandler handler, {bool offline = false}) =>
    NetClient(isOffline: () => offline, inner: MockClient(handler));

void main() {
  group('NetClient', () {
    test('offline mode sends nothing', () async {
      var calls = 0;
      final net = client((_) async {
        calls++;
        return jsonResponse({});
      }, offline: true);
      await expectLater(
        net.getJson(Uri.https('itunes.apple.com', '/search')),
        throwsA(isA<OfflineException>()),
      );
      expect(calls, 0);
    });

    test('only HTTPS to allowed hosts', () {
      expect(NetClient.isAllowed(Uri.parse('https://itunes.apple.com/x')), isTrue);
      expect(NetClient.isAllowed(Uri.parse('https://is1-ssl.mzstatic.com/a.jpg')),
          isTrue);
      expect(NetClient.isAllowed(Uri.parse('http://itunes.apple.com/x')), isFalse);
      expect(NetClient.isAllowed(Uri.parse('https://evil.example.com/')), isFalse);
      expect(NetClient.isAllowed(Uri.parse('https://mzstatic.com.evil.io/')),
          isFalse);
      expect(NetClient.isAllowed(Uri.parse('https://itunes.apple.com:8443/')),
          isFalse);
    });

    test('redirects are followed only to allowed hosts', () async {
      final net = client((req) async {
        if (req.url.host == 'covers.openlibrary.org') {
          return http.Response('', 302,
              headers: {'location': 'https://ia800.us.archive.org/c.jpg'});
        }
        if (req.url.host == 'ia800.us.archive.org') {
          return http.Response.bytes([0xFF, 0xD8, 0xFF, 0, 0, 0, 0, 0, 0, 0, 0, 0], 200);
        }
        return http.Response('', 404);
      });
      final bytes = await net.getBytes(
          Uri.parse('https://covers.openlibrary.org/b/id/1-M.jpg'),
          accept: 'image/*');
      expect(CoverCache.looksLikeImage(bytes), isTrue);

      final bad = client((_) async => http.Response('', 302,
          headers: {'location': 'https://tracker.example.com/'}));
      await expectLater(
        bad.getBytes(Uri.parse('https://openlibrary.org/x')),
        throwsA(isA<BlockedRequestException>()),
      );
    });

    test('sends a generic user agent and no cookies', () async {
      late http.BaseRequest seen;
      final net = client((req) async {
        seen = req;
        return jsonResponse({});
      });
      await net.getJson(Uri.https('api.tvmaze.com', '/search/shows'));
      expect(seen.headers['User-Agent'], 'WatchedLedger');
      expect(seen.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('cookie')));
    });

    test('oversized responses are rejected', () async {
      final net = client((_) async => http.Response('x' * 3000000, 200));
      await expectLater(
        net.getBytes(Uri.https('openlibrary.org', '/search.json')),
        throwsA(isA<http.ClientException>()),
      );
    });
  });

  group('providers', () {
    test('iTunes movies', () async {
      final net = client((req) async {
        expect(req.url.queryParameters['media'], 'movie');
        return jsonResponse({
          'resultCount': 2,
          'results': [
            {
              'trackId': 1,
              'trackName': 'Dune',
              'artistName': 'Denis Villeneuve',
              'releaseDate': '2021-10-22T07:00:00Z',
              'primaryGenreName': 'Sci-Fi & Fantasy',
              'artworkUrl100':
                  'https://is1-ssl.mzstatic.com/image/thumb/a/100x100bb.jpg',
            },
            {
              'trackId': 2,
              'trackName': 'Dune\u202E',
              'releaseDate': '1984-12-14T08:00:00Z',
              'primaryGenreName': 'Sci-Fi & Fantasy',
              'artworkUrl100': 'http://evil.example.com/x.jpg',
            },
          ],
        });
      });
      final r = await ItunesProvider(net, ItunesMedia.movie)
          .search('dune', MediaCategory.movie);
      expect(r, hasLength(2));
      expect(r[0].title, 'Dune');
      expect(r[0].year, 2021);
      expect(r[0].genre, 'Science Fiction');
      expect(r[0].creator, 'Denis Villeneuve');
      expect(r[0].coverUrl,
          'https://is1-ssl.mzstatic.com/image/thumb/a/300x300bb.jpg');
      // Cleaned title, unsafe cover dropped.
      expect(r[1].title, 'Dune');
      expect(r[1].coverUrl, isNull);
    });

    test('TVmaze series', () async {
      final net = client((_) async => jsonResponse([
            {
              'score': 0.9,
              'show': {
                'id': 44933,
                'name': 'Severance',
                'premiered': '2022-02-18',
                'genres': ['Drama', 'Mystery', 'Science-Fiction'],
                'image': {
                  'medium': 'https://static.tvmaze.com/uploads/m.jpg',
                },
              },
            },
            {'score': 0.1, 'show': 'garbage'},
          ]));
      final r = await TvmazeProvider(net).search('severance', MediaCategory.series);
      expect(r, hasLength(1));
      expect(r.single.year, 2022);
      expect(r.single.genre, 'Science Fiction');
      expect(r.single.coverUrl, 'https://static.tvmaze.com/uploads/m.jpg');
      expect(r.single.sourceId, '44933');
    });

    test('Open Library books', () async {
      final net = client((_) async => jsonResponse({
            'docs': [
              {
                'key': '/works/OL262758W',
                'title': 'The Hobbit',
                'author_name': ['J.R.R. Tolkien'],
                'first_publish_year': 1937,
                'cover_i': 14627509,
                'subject': ['Accessible book', 'Fantasy fiction', 'Fiction'],
              },
            ],
          }));
      final r = await OpenLibraryProvider(net).search('hobbit', MediaCategory.book);
      expect(r.single.creator, 'J.R.R. Tolkien');
      expect(r.single.genre, 'Fantasy');
      expect(r.single.coverUrl,
          'https://covers.openlibrary.org/b/id/14627509-M.jpg');
    });

    test('Google Books upgrades cover links to HTTPS', () async {
      final net = client((_) async => jsonResponse({
            'items': [
              {
                'id': 'abc',
                'volumeInfo': {
                  'title': 'Project Hail Mary',
                  'authors': ['Andy Weir'],
                  'publishedDate': '2021-05-04',
                  'categories': ['Fiction'],
                  'imageLinks': {
                    'thumbnail':
                        'http://books.google.com/books/content?id=abc&edge=curl'
                  },
                },
              },
            ],
          }));
      final r = await GoogleBooksProvider(net).search('hail mary', MediaCategory.book);
      expect(r.single.year, 2021);
      expect(r.single.genre, 'Fiction');
      expect(r.single.coverUrl, 'https://books.google.com/books/content?id=abc');
    });

    test('malformed responses give no results instead of crashing', () async {
      final net = client((_) async => jsonResponse({'results': 'nope'}));
      expect(
          await ItunesProvider(net, ItunesMedia.podcast)
              .search('x', MediaCategory.podcast),
          isEmpty);
    });
  });

  group('LookupService', () {
    test('falls back to the next source', () async {
      final hosts = <String>[];
      final net = client((req) async {
        hosts.add(req.url.host);
        if (req.url.host == 'openlibrary.org') return jsonResponse({'docs': []});
        return jsonResponse({
          'items': [
            {
              'id': 'g1',
              'volumeInfo': {'title': 'Piranesi'},
            },
          ],
        });
      });
      final r = await LookupService(net).search('piranesi', MediaCategory.book);
      expect(hosts, ['openlibrary.org', 'www.googleapis.com']);
      expect(r.candidates.single.source, 'googlebooks');
      expect(r.sourcesTried, ['Open Library', 'Google Books']);
    });

    test('network failure is reported, not thrown', () async {
      final net = client((_) async => throw http.ClientException('down'));
      final r = await LookupService(net).search('dune', MediaCategory.movie);
      expect(r.couldNotReach, isTrue);
    });

    test('offline mode is thrown so the caller can save as typed', () async {
      final net = client((_) async => jsonResponse({}), offline: true);
      await expectLater(
        LookupService(net).search('dune', MediaCategory.movie),
        throwsA(isA<OfflineException>()),
      );
    });

    const dune2021 = LookupCandidate(
        title: 'Dune', year: 2021, source: 's', sourceId: '1');
    const dune1984 = LookupCandidate(
        title: 'Dune', year: 1984, source: 's', sourceId: '2');
    const partTwo = LookupCandidate(
        title: 'Dune: Part Two', year: 2024, source: 's', sourceId: '3');

    test('auto-files only when the match is clear', () {
      expect(LookupService.confidentMatch('Dune', [dune2021, dune1984, partTwo]),
          isNull);
      expect(
          LookupService.confidentMatch('Dune 2021', [dune2021, dune1984]),
          same(dune2021));
      expect(LookupService.confidentMatch('dune part two', [dune2021, partTwo]),
          same(partTwo));
      expect(LookupService.confidentMatch('Dnue', [dune2021]), isNull);
    });

    test('ranking puts exact matches first', () {
      final ranked = LookupService.rank(
          ParsedQuery.parse('Dune (1984)'), [partTwo, dune2021, dune1984]);
      expect(ranked.first, same(dune1984));
      expect(ranked.last, same(partTwo));
    });

    test('query years are parsed sensibly', () {
      expect(ParsedQuery.parse('Dune 2021').year, 2021);
      expect(ParsedQuery.parse('Dune 2021').text, 'Dune');
      expect(ParsedQuery.parse('Heat (1995)').text, 'Heat');
      expect(ParsedQuery.parse('1917').year, isNull);
      expect(ParsedQuery.parse('Blade Runner 2049').year, isNull);
    });
  });

  group('genre mapping', () {
    test('specific beats broad', () {
      expect(mapGenre(MediaCategory.movie, ['Drama', 'Sci-Fi & Fantasy']),
          'Science Fiction');
      expect(mapGenre(MediaCategory.movie, ['Action & Adventure']), 'Action');
      expect(mapGenre(MediaCategory.series, ['Reality']), 'Reality');
    });

    test('podcasts keep Apple categories', () {
      expect(mapGenre(MediaCategory.podcast, ['True Crime', 'Podcasts']),
          'True Crime');
      expect(mapGenre(MediaCategory.podcast, ['Podcasts', 'Comedy Interviews']),
          'Comedy Interviews');
    });

    test('unknown book subjects become Uncategorised', () {
      expect(mapGenre(MediaCategory.book, ['Accessible book', 'Protected DAISY']),
          kUncategorised);
      expect(mapGenre(MediaCategory.book, []), kUncategorised);
    });
  });

  test('cover file names are stable and safe', () {
    final a = CoverCache.nameFor('https://x.mzstatic.com/a.jpg');
    expect(a, CoverCache.nameFor('https://x.mzstatic.com/a.jpg'));
    expect(a, isNot(CoverCache.nameFor('https://x.mzstatic.com/b.jpg')));
    expect(a, matches(RegExp(r'^[0-9a-f]{16}\.img$')));
  });

  group('Wikipedia', () {
    http.Response pages(List<Map<String, Object?>> p) =>
        jsonResponse({'pages': p});

    test('keeps films only, reads year and director, tidies titles', () async {
      final net = client((_) async => pages([
            {
              'key': 'Interstellar_Overdrive',
              'title': 'Interstellar Overdrive',
              'description': '1967 instrumental by Pink Floyd',
            },
            {
              'key': 'Interstellar_(film)',
              'title': 'Interstellar (film)',
              'description': '2014 film by Christopher Nolan',
              'thumbnail': {'url': '//upload.wikimedia.org/a/b.jpg'},
            },
            {
              'key': 'The_Godfather_(film_series)',
              'title': 'The Godfather (film series)',
              'description': 'American crime film series',
            },
            {
              'key': 'Christopher_Nolan',
              'title': 'Christopher Nolan',
              'description': 'British-American filmmaker (born 1970)',
            },
          ]));
      final r = await WikipediaProvider(net, WikiKind.film)
          .search('intersteller', MediaCategory.movie);
      expect(r, hasLength(1));
      expect(r.single.title, 'Interstellar');
      expect(r.single.year, 2014);
      expect(r.single.creator, 'Christopher Nolan');
      expect(r.single.coverUrl, 'https://upload.wikimedia.org/a/b.jpg');
      expect(r.single.sourceId, 'Interstellar_(film)');
    });

    test('details read the genre from the summary', () async {
      late Uri asked;
      final net = client((req) async {
        asked = req.url;
        return jsonResponse({
          'extract': 'Interstellar is a 2014 epic science fiction film '
              'directed by Christopher Nolan.',
        });
      });
      const c = LookupCandidate(
          title: 'Interstellar',
          year: 2014,
          source: 'wikipedia',
          sourceId: 'Interstellar_(film)');
      final d = await LookupService(net).details(c);
      expect(asked.path, '/api/rest_v1/page/summary/Interstellar_(film)');
      expect(d.genre, 'Science Fiction');
      expect(d.year, 2014);
    });

    test('details never fail the add', () async {
      final net = client((_) async => throw http.ClientException('down'));
      const c = LookupCandidate(
          title: 'X', source: 'wikipedia', sourceId: 'X');
      expect(await LookupService(net).details(c), same(c));
    });

    test('movies try Wikipedia first, then iTunes', () async {
      final hosts = <String>[];
      final net = client((req) async {
        hosts.add(req.url.host);
        return req.url.host == 'en.wikipedia.org'
            ? pages([])
            : jsonResponse({'results': []});
      });
      await LookupService(net).search('nothing', MediaCategory.movie);
      expect(hosts, ['en.wikipedia.org', 'itunes.apple.com']);
    });

    test('podcast typos are respelled via Wikipedia, then iTunes again',
        () async {
      final terms = <String>[];
      final net = client((req) async {
        if (req.url.host == 'en.wikipedia.org') {
          return pages([
            {
              'key': 'Hardcore_History',
              'title': 'Hardcore History',
              'description': 'History podcast by Dan Carlin',
            },
          ]);
        }
        final term = req.url.queryParameters['term']!;
        terms.add(term);
        if (term == 'Hardcore History') {
          return jsonResponse({
            'results': [
              {
                'collectionId': 1,
                'collectionName': "Dan Carlin's Hardcore History",
              },
            ],
          });
        }
        return jsonResponse({'results': []});
      });
      final r =
          await LookupService(net).search('Hardcore Histroy', MediaCategory.podcast);
      expect(terms, ['Hardcore Histroy', 'Hardcore History']);
      expect(r.candidates.first.title, "Dan Carlin's Hardcore History");
    });
  });
}
