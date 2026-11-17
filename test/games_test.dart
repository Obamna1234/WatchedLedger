import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:watchedledger/core/net/net_client.dart';
import 'package:watchedledger/data/lookup/genre_map.dart';
import 'package:watchedledger/data/lookup/lookup_service.dart';
import 'package:watchedledger/data/models.dart';
import 'package:watchedledger/data/share_parser.dart';
import 'package:watchedledger/data/transfer/import_parsers.dart';

http.Response jsonResponse(Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  test('games are the last category, so stored data keeps its meaning', () {
    expect(MediaCategory.game.index, 5);
    expect(MediaCategory.game.todoLabel, 'To Play');
    expect(MediaCategory.game.doneLabel, 'Played');
  });

  test('Wikipedia game lookup: typo-tolerant, games only, genre read',
      () async {
    final sent = <Uri>[];
    final net = NetClient(
      isOffline: () => false,
      inner: MockClient((req) async {
        sent.add(req.url);
        if (req.url.path.contains('/search/title')) {
          return jsonResponse({
            'pages': [
              {
                'key': 'The_Witcher_3:_Wild_Hunt',
                'title': 'The Witcher 3: Wild Hunt',
                'description': '2015 video game',
              },
              {
                'key': 'The_Witcher_(video_game_series)',
                'title': 'The Witcher (video game series)',
                'description': 'Video game series',
              },
              {
                'key': 'The_Witcher_(TV_series)',
                'title': 'The Witcher (TV series)',
                'description': 'Fantasy drama television series',
              },
            ],
          });
        }
        return jsonResponse({
          'extract': 'The Witcher 3: Wild Hunt is a 2015 action role-playing '
              'game developed by CD Projekt Red.',
        });
      }),
    );
    final lookup = LookupService(net);
    final r = await lookup.search('witchr 3', MediaCategory.game);
    expect([for (final c in r.candidates) c.title],
        ['The Witcher 3: Wild Hunt']);
    expect(r.candidates.single.year, 2015);
    final d = await lookup.details(r.candidates.single);
    expect(d.genre, 'Role-Playing');
    expect(sent.first.host, 'en.wikipedia.org');
  });

  test('game genres', () {
    expect(mapGenre(MediaCategory.game, ['first-person shooter']), 'Shooter');
    expect(mapGenre(MediaCategory.game, ['survival horror']), 'Horror');
    expect(mapGenre(MediaCategory.game, ['kart racing']), 'Racing');
  });

  test('imports and shares know about games', () {
    final r = parseImport('Video games\nArma Reforger\nGames - Played\nDoom');
    expect(r.rows[0].category, MediaCategory.game);
    expect(r.rows[1].status, ListStatus.done);
    expect(
        parseShared('Arma Reforger on Steam '
                'https://store.steampowered.com/app/1874880/Arma_Reforger/')!
            .category,
        MediaCategory.game);
  });
}
