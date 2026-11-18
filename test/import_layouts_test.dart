import 'package:flutter_test/flutter_test.dart';
import 'package:watchedledger/data/models.dart';
import 'package:watchedledger/data/transfer/import_parsers.dart';

Map<String, ListStatus> statuses(String text, {String? fileName}) => {
      for (final r in parseImport(text, fileName: fileName).rows)
        r.title: r.status,
    };

void main() {
  test('status words after the title', () {
    final s = statuses('Heat - watched\n'
        'Alien (seen)\n'
        'Ronin: done\n'
        'Arrival ✓\n'
        'Dune [x]\n'
        'Tenet - to watch\n'
        'Up (not watched)\n'
        'Big [ ]\n'
        'Spider-Man: No Way Home\n');
    expect(s, {
      'Heat': ListStatus.done,
      'Alien': ListStatus.done,
      'Ronin': ListStatus.done,
      'Arrival': ListStatus.done,
      'Dune': ListStatus.done,
      'Tenet': ListStatus.todo,
      'Up': ListStatus.todo,
      'Big': ListStatus.todo,
      'Spider-Man: No Way Home': ListStatus.todo,
    });
    final rows = parseImport('Tenet - to watch\nHeat\n').rows;
    expect(rows.first.statusSure, isTrue);
    expect(rows.last.statusSure, isFalse);
  });

  test('table rows: title first, a tick anywhere means done', () {
    final rows = parseImport('| Title | Year | Seen |\n'
        '|---|---|---|\n'
        '| Heat | 1995 | ✓ |\n'
        '| Alien | 1979 | |\n'
        '| Ronin | 1998 | yes |\n').rows;
    expect([for (final r in rows) (r.title, r.year, r.status)], [
      ('Heat', 1995, ListStatus.done),
      ('Alien', 1979, ListStatus.todo),
      ('Ronin', 1998, ListStatus.done),
    ]);
  });

  test('spreadsheets with other column names', () {
    final rows = parseImport(
      'Movie,Seen?,Notes\nHeat,Y,great\nAlien,,\n',
      fileName: 'mine.csv',
    ).rows;
    expect([for (final r in rows) (r.title, r.status, r.category)], [
      ('Heat', ListStatus.done, MediaCategory.movie),
      ('Alien', ListStatus.todo, MediaCategory.movie),
    ]);

    final dated = parseImport(
      'Book,Date read\nDune,2024-03-01\nEmma,\n',
      fileName: 'books.csv',
    ).rows;
    expect(dated.first.status, ListStatus.done);
    expect(dated.first.finished, DateTime(2024, 3, 1));
    expect(dated.first.category, MediaCategory.book);
    expect(dated.last.status, ListStatus.todo);
  });
}
