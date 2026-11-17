import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchedledger/core/net/net_client.dart';
import 'package:watchedledger/data/db/database.dart';
import 'package:watchedledger/data/models.dart';
import 'package:watchedledger/data/sync/sync_merge.dart';
import 'package:watchedledger/data/sync/sync_service.dart';
import 'package:watchedledger/data/transfer/backup.dart';

/// Syncs two in-memory phones the way the real thing does: B merges A's
/// snapshot, then A merges B's merged snapshot.
Future<(SyncResult, SyncResult)> sync(AppDatabase a, AppDatabase b) async {
  final onB = await mergeSync(b, await buildSyncSnapshot(a));
  final onA = await mergeSync(a, await buildSyncSnapshot(b));
  return (onA, onB);
}

Future<List<String>> titles(AppDatabase db) async =>
    [for (final i in await db.select(db.items).get()) i.title]..sort();

void main() {
  late AppDatabase a, b;
  setUp(() {
    a = AppDatabase(NativeDatabase.memory());
    b = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() async {
    await a.close();
    await b.close();
  });

  test('new items, diary entries and episode ticks reach both phones',
      () async {
    final heat = await a.addItem(
        category: MediaCategory.movie,
        status: ListStatus.done,
        title: 'Heat',
        now: DateTime(2026, 1, 1));
    await a.addRewatch(heat, date: DateTime(2026, 5, 1));
    final show = await b.addItem(
        category: MediaCategory.series,
        status: ListStatus.todo,
        title: 'Severance');
    await b.setEpisodesWatched(show, [(1, 1), (1, 2)], true);

    final (onA, onB) = await sync(a, b);
    expect(onB.added, 1);
    expect(onB.diaryEntries, 2);
    expect(onA.added, 1);
    expect(await titles(a), ['Heat', 'Severance']);
    expect(await titles(b), ['Heat', 'Severance']);
    expect(await b.select(b.watchEvents).get(), hasLength(2));
    expect(await a.select(a.episodeMarks).get(), hasLength(2));

    // Syncing again changes nothing and duplicates nothing.
    final (again1, again2) = await sync(a, b);
    expect(again1.nothingChanged && again2.nothingChanged, isTrue);
    expect(await b.select(b.watchEvents).get(), hasLength(2));
  });

  test('the most recent edit wins', () async {
    await a.addItem(
        category: MediaCategory.movie, status: ListStatus.todo, title: 'Up');
    await sync(a, b);
    final onA = (await a.select(a.items).get()).single;
    final onB = (await b.select(b.items).get()).single;
    await a.updateItem(onA.copyWith(
        rating: const Value(2), updatedAt: DateTime(2030, 1, 1)));
    await b.updateItem(onB.copyWith(
        rating: const Value(5), updatedAt: DateTime(2030, 1, 2)));
    await sync(a, b);
    expect((await a.select(a.items).get()).single.rating, 5);
    expect((await b.select(b.items).get()).single.rating, 5);
  });

  test('deletions sync, unless edited later on the other phone', () async {
    await a.addItem(
        category: MediaCategory.movie, status: ListStatus.todo, title: 'X');
    await a.addItem(
        category: MediaCategory.movie, status: ListStatus.todo, title: 'Y');
    await sync(a, b);
    final x = (await a.select(a.items).get()).firstWhere((i) => i.title == 'X');
    await a.deleteItem(x.id);
    // Y deleted on A, but edited on B afterwards: B's edit survives.
    final yA = (await a.select(a.items).get()).firstWhere((i) => i.title == 'Y');
    await a.deleteItem(yA.id);
    final yB = (await b.select(b.items).get()).firstWhere((i) => i.title == 'Y');
    await b.updateItem(yB.copyWith(
        note: const Value('keep'),
        updatedAt: DateTime.now().add(const Duration(minutes: 1))));

    final (_, onB) = await sync(a, b);
    expect(onB.deleted, 1);
    expect(await titles(b), ['Y']);
    expect(await titles(a), ['Y']);
  });

  test('the same title added on both phones becomes one', () async {
    await a.addItem(
        category: MediaCategory.book, status: ListStatus.todo, title: 'Dune');
    await b.addItem(
        category: MediaCategory.book, status: ListStatus.todo, title: 'Dune');
    await sync(a, b);
    await sync(a, b);
    final ua = (await a.select(a.items).get()).single.uid;
    final ub = (await b.select(b.items).get()).single.uid;
    expect(ua, ub);
  });

  test('codes and addresses', () {
    final code = SyncCode.generate();
    expect(code, matches(RegExp(r'^[A-Z2-9]{4}-[A-Z2-9]{4}$')));
    expect(SyncCode.normalise(' k7q2 9xmf '), 'K7Q2-9XMF');
    expect(SyncCode.normalise('K7Q2-9XM0'), isNull); // 0 isn't used
    expect(parseSyncAddress('192.168.1.23:41234').toString(),
        'http://192.168.1.23:41234/sync');
    expect(parseSyncAddress('8.8.8.8:41234'), isNull);
    expect(parseSyncAddress('192.168.1.23'), isNull);
    expect(parseSyncAddress('example.com:4000'), isNull);
  });

  test('the network gate only allows private addresses for sync', () async {
    expect(NetClient.isLocalSyncAddress(Uri.parse('http://10.0.0.5:4000/sync')),
        isTrue);
    expect(
        NetClient.isLocalSyncAddress(Uri.parse('http://172.32.0.1:4000/sync')),
        isFalse);
    expect(
        NetClient.isLocalSyncAddress(Uri.parse('https://192.168.0.2/sync')),
        isFalse);
    expect(
        NetClient.isLocalSyncAddress(Uri.parse('http://192.168.0.2/other')),
        isFalse);
    final offline = NetClient(isOffline: () => true);
    await expectLater(
        offline.postLocal(Uri.parse('http://192.168.0.2:4000/sync'), [1]),
        throwsA(isA<OfflineException>()));
  });

  test('a wrong code cannot read a sync message', () async {
    final sealed = await encryptBackup(
        {'kind': 'sync', 'items': <Object>[]}, 'AAAA-BBBB',
        kdfMemoryKiB: 1024, kdfIterations: 1);
    await expectLater(decryptBackup(Uint8List.fromList(sealed), 'AAAA-BBBC'),
        throwsA(isA<BackupPasswordException>()));
    // Refuses key settings above what sync uses.
    await expectLater(
        decryptBackup(sealed, 'AAAA-BBBB', maxMemoryKiB: 512),
        throwsA(isA<BackupFormatException>()));
  });
}
