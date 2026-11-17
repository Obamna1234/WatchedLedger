import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:watchedledger/core/net/net_client.dart';
import 'package:watchedledger/data/lookup/more_by.dart';
import 'package:watchedledger/data/models.dart';

http.Response jsonResponse(Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  final sent = <Uri>[];
  MoreByService service(Object Function(Uri) reply) {
    sent.clear();
    return MoreByService(NetClient(
      isOffline: () => false,
      inner: MockClient((req) async {
        sent.add(req.url);
        return jsonResponse(reply(req.url));
      }),
    ));
  }

  test('primary name', () {
    expect(MoreByService.primaryName('Joel Coen, Ethan Coen'), 'Joel Coen');
    expect(MoreByService.primaryName('Terry Pratchett & Neil Gaiman'),
        'Terry Pratchett');
    expect(MoreByService.available(MediaCategory.movie, 'Al'), isFalse);
    expect(MoreByService.available(MediaCategory.movie, null), isFalse);
  });

  test('films: keeps only films by that director, newest first', () async {
    final s = service((_) => {
          'query': {
            'pages': [
              {
                'title': 'Heat (1995 film)',
                'description': '1995 film by Michael Mann',
                'thumbnail': {'source': 'https://upload.wikimedia.org/h.jpg'},
              },
              {
                'title': 'Collateral',
                'description': '2004 film by Michael Mann',
              },
              {'title': 'Michael Mann', 'description': 'American filmmaker'},
              {'title': 'Se7en', 'description': '1995 film by David Fincher'},
              {'title': 'Junk', 'description': 7},
            ],
          },
        });
    final r = await s.worksBy('Michael Mann', MediaCategory.movie);
    expect([for (final c in r) c.title], ['Collateral', 'Heat']);
    expect(r[1].year, 1995);
    expect(r[1].coverUrl, 'https://upload.wikimedia.org/h.jpg');
    expect(r[1].sourceId, 'Heat_(1995_film)');
    expect(sent.single.host, 'en.wikipedia.org');
    expect(sent.single.queryParameters['gsrsearch'],
        '"directed by Michael Mann"');
  });

  test('series: TVmaze person, then their shows', () async {
    final s = service((u) => u.path == '/search/people'
        ? [
            {
              'person': {'id': 123, 'name': 'Vince Gilligan'},
            },
          ]
        : [
            {
              '_embedded': {
                'show': {
                  'id': 169,
                  'name': 'Breaking Bad',
                  'premiered': '2008-01-20',
                  'genres': ['Drama', 'Crime'],
                },
              },
            },
            {
              '_embedded': {
                'show': {
                  'id': 618,
                  'name': 'Better Call Saul',
                  'premiered': '2015-02-08',
                },
              },
            },
          ]);
    final r = await s.worksBy('Vince Gilligan', MediaCategory.series);
    expect([for (final c in r) c.title], ['Better Call Saul', 'Breaking Bad']);
    expect(sent.last.path, '/people/123/crewcredits');
  });

  test('books: Open Library author search, other authors dropped', () async {
    final s = service((_) => {
          'docs': [
            {
              'key': '/works/1',
              'title': 'Mort',
              'author_name': ['Terry Pratchett'],
              'first_publish_year': 1987,
              'number_of_pages_median': 272,
            },
            {
              'key': '/works/2',
              'title': 'Mort',
              'author_name': ['Terry Pratchett'],
              'first_publish_year': 1990,
            },
            {
              'key': '/works/3',
              'title': 'Study Guide',
              'author_name': ['Someone Else'],
            },
          ],
        });
    final r = await s.worksBy('Terry Pratchett', MediaCategory.book);
    expect([for (final c in r) c.title], ['Mort']);
    expect(r.single.pages, 272);
    expect(sent.single.queryParameters['author'], 'Terry Pratchett');
  });

  test('offline sends nothing', () async {
    final s = MoreByService(NetClient(
      isOffline: () => true,
      inner: MockClient((_) async => fail('nothing may be sent')),
    ));
    await expectLater(s.worksBy('Michael Mann', MediaCategory.movie),
        throwsA(isA<OfflineException>()));
  });
}
