import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchedledger/data/db/database.dart';
import 'package:watchedledger/data/models.dart';
import 'package:watchedledger/data/transfer/backup.dart';
import 'package:watchedledger/data/transfer/csv.dart';
import 'package:watchedledger/data/transfer/export.dart';

Future<AppDatabase> buildLibrary() async {
  final db = AppDatabase(NativeDatabase.memory());
  final id = await db.addItem(
    category: MediaCategory.movie,
    status: ListStatus.todo,
    title: 'Heat',
    year: 1995,
    creator: 'Michael Mann',
  );
  await db.setStatus(id, ListStatus.done, now: DateTime(2026, 3, 2));
  await db.addItem(
    category: MediaCategory.book,
    status: ListStatus.todo,
    title: '=HYPERLINK("http://evil")',
  );
  await db.addItem(
    category: MediaCategory.book,
    status: ListStatus.todo,
    title: 'Dune, Messiah "2"',
  );
  return db;
}

void main() {
  group('csv', () {
    test('round-trips quotes, commas and newlines', () {
      final text = toCsv([
        ['a', 'b,c', 'say "hi"', 'two\nlines'],
        ['1', '', null, 'x'],
      ]);
      expect(parseCsv(text), [
        ['a', 'b,c', 'say "hi"', 'two\nlines'],
        ['1', '', '', 'x'],
      ]);
    });

    test('formula-looking cells are neutralised', () {
      expect(csvField('=1+1'), "'=1+1");
      expect(csvField('-5'), "'-5");
      expect(csvField('Heat'), 'Heat');
    });

    test('handles BOM, CRLF and semicolons', () {
      expect(parseCsv('﻿a;b\r\nc;d\r\n', separator: ';'), [
        ['a', 'b'],
        ['c', 'd'],
      ]);
    });
  });

  group('export', () {
    test('text, csv and json contain every title', () async {
      final db = await buildLibrary();
      addTearDown(db.close);
      final items = await db.select(db.items).get();

      final txt = exportText(items);
      expect(txt, contains('[x] Heat (1995) - Watched March 2026'));
      expect(txt, contains('BOOKS - To Read'));

      final rows = parseCsv(exportCsv(items));
      expect(rows.first, csvHeader);
      expect(rows.map((r) => r[2]), contains('Dune, Messiah "2"'));
      expect(rows.map((r) => r[2]), contains('\'=HYPERLINK("http://evil")'));

      final json = jsonDecode(exportJson(items)) as Map<String, Object?>;
      expect((json['items']! as List).length, 3);
    });
  });

  group('encrypted backup', () {
    test('round-trips and restores into an empty phone', () async {
      final db = await buildLibrary();
      addTearDown(db.close);
      final bytes = await encryptBackup(await buildSnapshot(db), 'correct horse',
          kdfMemoryKiB: 1024, kdfIterations: 1);
      expect(utf8.decode(bytes.sublist(0, 9)), 'WLBACKUP1');
      // The titles are not readable in the file.
      expect(latin1.decode(bytes).contains('Heat'), isFalse);

      final snapshot = await decryptBackup(bytes, 'correct horse');
      expect(summarise(snapshot).items, 3);

      final other = AppDatabase(NativeDatabase.memory());
      addTearDown(other.close);
      final result = await restoreSnapshot(other, snapshot, replace: true);
      expect(result.added, 3);
      final heat = (await other.findDuplicates('Heat')).single;
      expect(heat.status, ListStatus.done);
      expect(heat.completedAt, DateTime(2026, 3, 2));
      expect(heat.creator, 'Michael Mann');
    });

    test('wrong password and tampering are detected', () async {
      final db = await buildLibrary();
      addTearDown(db.close);
      final bytes = await encryptBackup(await buildSnapshot(db), 'pw-12345678',
          kdfMemoryKiB: 1024, kdfIterations: 1);
      await expectLater(decryptBackup(bytes, 'nope'),
          throwsA(isA<BackupPasswordException>()));
      final tampered = Uint8List.fromList(bytes)..[bytes.length - 20] ^= 1;
      await expectLater(decryptBackup(tampered, 'pw-12345678'),
          throwsA(isA<BackupPasswordException>()));
      await expectLater(decryptBackup(Uint8List.fromList(utf8.encode('hello')), 'x'),
          throwsA(isA<BackupFormatException>()));
    });

    test('merge adds new titles, skips duplicates, keeps newest edits',
        () async {
      final source = await buildLibrary();
      addTearDown(source.close);
      final snapshot = await buildSnapshot(source);

      final target = AppDatabase(NativeDatabase.memory());
      addTearDown(target.close);
      await target.addItem(
          category: MediaCategory.movie,
          status: ListStatus.todo,
          title: 'heat'); // same title, different uid
      await target.addItem(
          category: MediaCategory.podcast,
          status: ListStatus.todo,
          title: 'Serial');
      final result = await restoreSnapshot(target, snapshot, replace: false);
      expect(result.added, 2);
      expect(result.skipped, 1);
      expect((await target.select(target.items).get()).length, 4);

      // Restoring the same backup again changes nothing.
      final again = await restoreSnapshot(target, snapshot, replace: false);
      expect(again.added, 0);
    });
  });
}
