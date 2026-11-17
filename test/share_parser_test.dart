import 'package:flutter_test/flutter_test.dart';
import 'package:watchedledger/data/models.dart';
import 'package:watchedledger/data/share_parser.dart';

void main() {
  test('IMDb title with year', () {
    final s = parseShared(
        'Heat (1995) - IMDb\nhttps://www.imdb.com/title/tt0113277/')!;
    expect(s.title, 'Heat');
    expect(s.year, 1995);
    expect(s.query, 'Heat 1995');
  });

  test('IMDb TV series', () {
    final s = parseShared('Severance (TV Series 2022– ) ⭐ 8.7 | '
        'Drama, Mystery https://m.imdb.com/title/tt11280740/')!;
    expect(s.title, 'Severance');
    expect(s.category, MediaCategory.series);
    expect(s.year, 2022);
  });

  test('Netflix wording', () {
    final s = parseShared(
        'Watch "Arcane" on Netflix https://www.netflix.com/title/81435684')!;
    expect(s.title, 'Arcane');
  });

  test('Goodreads book with author', () {
    final s = parseShared('Check out Dune by Frank Herbert '
        'https://www.goodreads.com/book/show/44767458-dune')!;
    expect(s.title, 'Dune');
    expect(s.category, MediaCategory.book);
  });

  test('just a Goodreads link uses the slug', () {
    final s = parseShared(
        'https://www.goodreads.com/book/show/44767458-project-hail-mary')!;
    expect(s.title, 'project hail mary');
    expect(s.category, MediaCategory.book);
  });

  test('podcast and audiobook links set the category', () {
    expect(
        parseShared('The Rest Is History on Apple Podcasts '
                'https://podcasts.apple.com/gb/podcast/the-rest-is-history/id1537788786')!
            .category,
        MediaCategory.podcast);
    expect(
        parseShared('Project Hail Mary https://www.audible.com/pd/B08G9PRS1K')!
            .category,
        MediaCategory.audiobook);
  });

  test('Letterboxd', () {
    final s = parseShared(
        'Heat (1995) — Letterboxd https://boxd.it/29Ve')!;
    expect(s.title, 'Heat');
    expect(s.category, MediaCategory.movie);
  });

  test('plain text and nothing usable', () {
    expect(parseShared('  The Bear  ')!.title, 'The Bear');
    expect(parseShared('https://www.netflix.com/title/81435684'), isNull);
    expect(parseShared('   '), isNull);
  });

  test('hidden characters are cleaned', () {
    expect(parseShared('He\u200Bat\u202E')!.title, 'Heat');
  });
}
