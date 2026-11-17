import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:watchedledger/core/net/net_client.dart';
import 'package:watchedledger/core/sanitise.dart';
import 'package:watchedledger/data/db/database.dart';
import 'package:watchedledger/data/lookup/link_lookup.dart';
import 'package:watchedledger/data/lookup/lookup_service.dart';
import 'package:watchedledger/data/models.dart';
import 'package:watchedledger/data/transfer/backup.dart';

http.Response jsonResponse(Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  test('links are cleaned', () {
    expect(cleanLink(' https://youtu.be/abc '), 'https://youtu.be/abc');
    expect(cleanLink('javascript:alert(1)'), isNull);
    expect(cleanLink('file:///etc/passwd'), isNull);
    expect(cleanLink('https://user:pw@example.com/'), isNull);
    expect(cleanLink('not a link'), isNull);
    expect(LinkLookup.asLink('Heat 1995'), isNull);
  });

  test('YouTube link: title, channel and thumbnail via oEmbed', () async {
    final sent = <Uri>[];
    final net = NetClient(
      isOffline: () => false,
      inner: MockClient((req) async {
        sent.add(req.url);
        return jsonResponse({
          'title': 'Papa Meat pumpkin spice review',
          'author_name': 'Papa Meat',
          'thumbnail_url': 'https://i.ytimg.com/vi/abc/hqdefault.jpg',
        });
      }),
    );
    final link = LinkLookup.asLink('https://youtu.be/abc?si=xyz')!;
    expect(LinkLookup.categoryFor(link), MediaCategory.video);
    final c = (await LinkLookup(net).lookup(link))!;
    expect(c.title, 'Papa Meat pumpkin spice review');
    expect(c.creator, 'Papa Meat');
    expect(c.coverUrl, 'https://i.ytimg.com/vi/abc/hqdefault.jpg');
    expect(c.link, 'https://youtu.be/abc?si=xyz');
    expect(sent.single.host, 'www.youtube.com');
    expect(sent.single.queryParameters['url'], 'https://youtu.be/abc?si=xyz');
  });

  test('Facebook / Instagram: kept as Videos, title typed by hand', () async {
    final net = NetClient(
      isOffline: () => false,
      inner: MockClient((_) async => fail('nothing may be sent')),
    );
    final fb = LinkLookup.asLink('https://www.facebook.com/watch/?v=1')!;
    expect(LinkLookup.categoryFor(fb), MediaCategory.video);
    expect(LinkLookup.endpointFor(fb), isNull);
    expect(await LinkLookup(net).lookup(fb), isNull);
    expect(
        LinkLookup.categoryFor(
            LinkLookup.asLink('https://www.instagram.com/reel/x/')!),
        MediaCategory.video);
  });

  test('Wikidata is the last resort for niche titles', () async {
    final hosts = <String>[];
    final net = NetClient(
      isOffline: () => false,
      inner: MockClient((req) async {
        hosts.add(req.url.host);
        if (req.url.host == 'www.wikidata.org') {
          return jsonResponse({
            'search': [
              {
                'id': 'Q123',
                'label': 'Pissvakt',
                'description': '2025 Swedish comedy film by Some Director',
              },
              {'id': 'Q124', 'label': 'Pissvakt', 'description': 'surname'},
              {'id': 'bad', 'label': 'X', 'description': '2020 film'},
            ],
          });
        }
        return jsonResponse(req.url.host == 'itunes.apple.com'
            ? {'results': <Object>[]}
            : {'pages': <Object>[]});
      }),
    );
    final r = await LookupService(net).search('Pissvakt', MediaCategory.movie);
    expect(r.candidates.single.title, 'Pissvakt');
    expect(r.candidates.single.year, 2025);
    expect(r.candidates.single.source, 'wikidata');
    expect(hosts.last, 'www.wikidata.org');
  });

  test('schema v2 databases upgrade to v3 without losing data', () async {
    final dir = await Directory.systemTemp.createTemp('wl');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/db.sqlite');
    var db = AppDatabase(NativeDatabase(file));
    await db.addItem(
        category: MediaCategory.movie, status: ListStatus.done, title: 'Heat');
    for (final c in [
      'link', 'recommended_by', 'watch_with', 'where_to_watch', 'upcoming', //
      'release_date', 'deleted_at', 'is_private',
    ]) {
      await db.customStatement('ALTER TABLE items DROP COLUMN $c');
    }
    await db.customStatement('PRAGMA user_version = 2');
    await db.close();

    db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final item = (await db.select(db.items).get()).single;
    expect(item.title, 'Heat');
    expect(item.upcoming, isFalse);
    expect(item.isPrivate, isFalse);
    expect(item.link, isNull);
    expect(await db.select(db.watchEvents).get(), hasLength(1));
  });

  test('backups from older versions still restore', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final old = <String, Object?>{
      'app': 'WatchedLedger',
      'items': [
        {
          'id': 1,
          'category': 0,
          'status': 0,
          'title': 'Heat',
          'sortTitle': 'heat',
          'matchKey': 'heat',
          'genre': 'Crime',
          'matchState': 1,
          'addedAt': 1700000000000,
          'updatedAt': 1700000000000,
        },
      ],
    };
    await restoreSnapshot(db, old, replace: true);
    final item = (await db.select(db.items).get()).single;
    expect(item.title, 'Heat');
    expect(item.following, isFalse);
    expect(item.upcoming, isFalse);
  });
}
