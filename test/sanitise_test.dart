import 'package:flutter_test/flutter_test.dart';
import 'package:watchedledger/core/sanitise.dart';

void main() {
  group('cleanTitle', () {
    test('trims and collapses whitespace', () {
      expect(cleanTitle('  The   Matrix \n'), 'The Matrix');
    });

    test('removes control, zero-width and bidi override characters', () {
      expect(cleanTitle('Dune\u0000\u200B Part\u202E Two\uFEFF'),
          'Dune Part Two');
    });

    test('caps length without splitting emoji', () {
      final long = '${'a' * 299}😀😀';
      final cleaned = cleanTitle(long);
      expect(cleaned.length, lessThanOrEqualTo(kMaxTitleLength));
      expect(cleaned, 'a' * 299);
    });
  });

  group('keys', () {
    test('sortKey drops leading article and punctuation', () {
      expect(sortKey('The Matrix'), 'matrix');
      expect(sortKey('A Quiet Place'), 'quiet place');
      expect(sortKey('Spider-Man: No Way Home'), 'spider man no way home');
    });

    test('matchKey treats spacing, case and accents as equal', () {
      expect(matchKey('Spider-Man'), matchKey('spiderman'));
      expect(matchKey('Amélie'), matchKey('AMELIE'));
      expect(matchKey('Fast & Furious'), matchKey('fast and furious'));
    });

    test('a title that is only an article is kept', () {
      expect(sortKey('A'), 'a');
    });
  });
}
