import 'dart:io' show ZLibEncoder;
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchedledger/data/db/database.dart';
import 'package:watchedledger/data/models.dart';
import 'package:watchedledger/data/transfer/import_parsers.dart';
import 'package:watchedledger/data/transfer/import_plan.dart';
import 'package:watchedledger/data/transfer/samsung_notes.dart';
import 'package:watchedledger/data/transfer/zip_reader.dart';

// ------------------------------------------------- building test files

class _Bytes {
  final b = BytesBuilder();
  void u16(int v) => b.add((ByteData(2)..setUint16(0, v, Endian.little))
      .buffer
      .asUint8List());
  void u32(int v) => b.add((ByteData(4)..setUint32(0, v, Endian.little))
      .buffer
      .asUint8List());
  void text(String s) {
    for (final c in s.codeUnits) {
      u16(c);
    }
  }
}

/// A made-up note.note in the same layout Samsung Notes uses: a short
/// title block, then the body text, its styles and per-line settings.
Uint8List makeNote(List<(String, bool?)> lines) {
  final o = _Bytes();
  o.b.add(Uint8List(48));
  o.u32(5);
  o.text('Title');
  o.u32(0);
  o.u32(0);
  final text = lines.map((l) => l.$1).join('\n');
  o.u32(text.length);
  o.text(text);
  o.u32(1); // one style record (font size)
  o.u16(24);
  for (final v in [3, 0, text.length, 1, 0x41880000, 0]) {
    o.u32(v);
  }
  final paras = <List<int>>[];
  for (var i = 0; i < lines.length; i++) {
    paras.add([6, i, i + 1, 1, 0]);
    final box = lines[i].$2;
    if (box != null) paras.add([5, i, i + 1, 2, box ? 1 : 0, 0, 1]);
  }
  o.u32(paras.length);
  for (final p in paras) {
    o.u16(p.length * 4);
    for (final v in p) {
      o.u32(v);
    }
  }
  o.b.add(Uint8List(32));
  return o.b.toBytes();
}

/// A minimal ZIP with deflated entries.
Uint8List makeZip(Map<String, Uint8List> files) {
  final out = _Bytes();
  final central = _Bytes();
  var count = 0;
  for (final MapEntry(key: name, value: data) in files.entries) {
    final packed = Uint8List.fromList(ZLibEncoder(raw: true).convert(data));
    final offset = out.b.length;
    out
      ..u32(0x04034b50)
      ..u16(20)
      ..u16(0)
      ..u16(8)
      ..u16(0)
      ..u16(0)
      ..u32(0)
      ..u32(packed.length)
      ..u32(data.length)
      ..u16(name.length)
      ..u16(0);
    out.b
      ..add(name.codeUnits)
      ..add(packed);
    central
      ..u32(0x02014b50)
      ..u16(20)
      ..u16(20)
      ..u16(0)
      ..u16(8)
      ..u16(0)
      ..u16(0)
      ..u32(0)
      ..u32(packed.length)
      ..u32(data.length)
      ..u16(name.length)
      ..u16(0)
      ..u16(0)
      ..u16(0)
      ..u16(0)
      ..u32(0)
      ..u32(offset);
    central.b.add(name.codeUnits);
    count++;
  }
  final cdStart = out.b.length;
  final cd = central.b.toBytes();
  out.b.add(cd);
  out
    ..u32(0x06054b50)
    ..u16(0)
    ..u16(0)
    ..u16(count)
    ..u16(count)
    ..u32(cd.length)
    ..u32(cdStart)
    ..u16(0);
  return out.b.toBytes();
}

void main() {
  final note = [
    ('My list', null),
    ('', null),
    ('MOVIES', null),
    ('', null),
    ('Action movies', null),
    ('Die Hard', true),
    ('Raging bull', false),
    ('The Substance (friend recommendation)', true),
    ('', null),
    ('SERIES', null),
    ('', null),
    ('Drama Series', null),
    ('Mo season 1', true),
    ('Mo season 2 (waiting to get released)', false),
    ('', null),
    ('Watched', null),
    ('Goodfellas', null),
    ('', null),
    ('Video games', null),
    ('Arma Reforger', false),
    ('', null),
    ('Mixed list', null),
    ('-Jack Reacher', null),
    ('The Departed@', null),
    ('peacemaker tv series', null),
    ('￼', null),
  ];

  test('reads text and tick boxes from a Samsung Notes file', () {
    final file =
        makeZip({'note.note': makeNote(note), 'media/a.jpg': Uint8List(10)});
    final lines = readSamsungNote(file);
    expect(lines.firstWhere((l) => l.text == 'Die Hard').checked, isTrue);
    expect(lines.firstWhere((l) => l.text == 'Raging bull').checkbox, isTrue);
    expect(lines.firstWhere((l) => l.text == 'Raging bull').checked, isFalse);
    expect(lines.firstWhere((l) => l.text == 'MOVIES').checkbox, isFalse);
  });

  test('turns the note into rows: lists, categories, seasons, notes', () {
    final rows = rowsFromNote(readSamsungNote(
        makeZip({'note.note': makeNote(note)})));
    ImportRow row(String t) => rows.firstWhere((r) => r.title == t);

    expect(row('Die Hard').status, ListStatus.done);
    expect(row('Die Hard').category, MediaCategory.movie);
    expect(row('Raging bull').status, ListStatus.todo);
    expect(row('Raging bull').statusSure, isTrue);
    expect(row('The Substance').note, 'friend recommendation');

    final mo = row('Mo');
    expect(mo.category, MediaCategory.series);
    expect(mo.seasons, {1: true, 2: false});
    expect(mo.note, 'waiting to get released');

    expect(row('Goodfellas').status, ListStatus.done); // "Watched" heading
    expect(row('Arma Reforger').category, MediaCategory.game);
    expect(row('Jack Reacher').status, ListStatus.todo);
    expect(row('The Departed').status, ListStatus.done);
    expect(row('peacemaker tv series').category, MediaCategory.series);
    expect(row('peacemaker tv series').statusSure, isFalse);
    expect(rows.any((r) => r.title.contains('￼')), isFalse);
    expect(rows.any((r) => r.title == 'Action movies'), isFalse);
  });

  test('not a Samsung Notes file', () {
    expect(() => readSamsungNote(Uint8List.fromList([1, 2, 3, 4, 5])),
        throwsA(isA<SamsungNotesException>()));
    expect(() => readSamsungNote(makeZip({'other.txt': Uint8List(4)})),
        throwsA(isA<SamsungNotesException>()));
  });

  test('a zip bomb stops at the size limit', () {
    final bomb = makeZip({'note.note': Uint8List(5 * 1024 * 1024)});
    expect(bomb.length, lessThan(100 * 1024));
    expect(() => readZipEntry(bomb, 'note.note', maxBytes: 1024 * 1024),
        throwsA(isA<ZipException>()));
  });

  group('pasted lists', () {
    test('status headings', () {
      expect(statusHeading('Watched:')?.status, ListStatus.done);
      expect(statusHeading('To watch')?.status, ListStatus.todo);
      expect(statusHeading('Movies I’ve watched'), isNull);
      expect(statusHeading("Movies I've watched")?.status, ListStatus.done);
      expect(statusHeading('Watchlist (games)')?.category, MediaCategory.game);
      expect(statusHeading('Heat'), isNull);

      final r = parseImport('To watch\nHeat\nDune\n\nSeen:\nAlien');
      expect([for (final x in r.rows) x.status],
          [ListStatus.todo, ListStatus.todo, ListStatus.done]);
      expect(r.rows.every((x) => x.statusSure), isTrue);
    });

    test('lines with nothing to go on are marked "not sure"', () {
      final r = parseImport('Heat\n[ ] Dune\n[x] Alien');
      expect([for (final x in r.rows) x.statusSure], [false, true, true]);
    });

    test('seasons in titles become one show', () {
      final r = parseImport('[x] The Boys season 1\n[x] The Boys season 2\n'
          '[ ] The Boys season 3');
      expect(r.rows.single.title, 'The Boys');
      expect(r.rows.single.seasons, {1: true, 2: true, 3: false});
    });
  });

  group('text files', () {
    Uint8List utf16le(String s, {bool bom = true}) {
      final o = _Bytes();
      if (bom) o.b.add([0xFF, 0xFE]);
      o.text(s);
      return o.b.toBytes();
    }

    test('UTF-16 (Windows "Unicode") and UTF-8 with BOM', () {
      expect(decodeImportText(utf16le('Heat\nDune')), 'Heat\nDune');
      expect(decodeImportText(utf16le('Heat\nDune', bom: false)), 'Heat\nDune');
      expect(
          decodeImportText(Uint8List.fromList([0xEF, 0xBB, 0xBF, 0x48, 0x69])),
          'Hi');
    });

    test('binary files are refused', () {
      expect(decodeImportText(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0,
          0, 0, 13, 0, 1, 2, 3])), isNull);
    });
  });

  test('saving an imported show stores its watched seasons', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final rows = parseImport('[x] Mo season 1\n[ ] Mo season 2').rows;
    final entries = await prepareImport(db, rows, MediaCategory.series);
    await saveImport(db, entries);
    final item = (await db.select(db.items).get()).single;
    expect(item.title, 'Mo');
    expect(item.season, 1);
    final marks = await db.watchMarks(item.id).first;
    expect([for (final m in marks) (m.season, m.number)], [(1, 0)]);
  });
}
