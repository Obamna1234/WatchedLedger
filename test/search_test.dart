import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchedledger/core/sanitise.dart';
import 'package:watchedledger/data/db/database.dart';
import 'package:watchedledger/data/models.dart';
import 'package:watchedledger/features/search/list_search.dart';

MediaItem item(String title, {String? creator, String? note}) {
  final t = DateTime(2025);
  return MediaItem(
    id: 1,
    category: MediaCategory.movie,
    status: ListStatus.todo,
    title: title,
    sortTitle: sortKey(title),
    matchKey: matchKey(title),
    genre: kUncategorised,
    creator: creator,
    note: note,
    matchState: MatchState.unmatched,
    addedAt: t,
    updatedAt: t,
  );
}

void main() {
  group('findMatches', () {
    test('case-insensitive, every occurrence', () {
      expect(findMatches('Star Wars: A New Hope — star', 'STAR'),
          [(0, 4), (24, 28)]);
    });

    test('accents fold both ways, ranges point at the original text', () {
      const t = 'Le Fabuleux Destin d’Amélie Poulain';
      final m = findMatches(t, 'amelie');
      expect(m, hasLength(1));
      expect(t.substring(m.single.$1, m.single.$2), 'Amélie');
      expect(findMatches('Amelie', 'AMÉLIE'), [(0, 6)]);
    });

    test('characters that fold to two letters', () {
      const t = 'Æon Flux';
      final m = findMatches(t, 'aeon');
      expect(t.substring(m.single.$1, m.single.$2), 'Æon');
      // Half of "æ" still highlights the whole character.
      final half = findMatches(t, 'a');
      expect(t.substring(half.first.$1, half.first.$2), 'Æ');
    });

    test('emoji and empty input are safe', () {
      expect(findMatches('😀 Up', 'up'), [(3, 5)]);
      expect(findMatches('Up', '   '), isEmpty);
      expect(findMatches('', 'x'), isEmpty);
    });
  });

  test('items match on title, creator or note', () {
    expect(itemMatches(item('Heat'), 'hea'), isTrue);
    expect(itemMatches(item('Heat', creator: 'Michael Mann'), 'mann'), isTrue);
    expect(itemMatches(item('Heat', note: 'rewatch with Sam'), 'sam'), isTrue);
    expect(itemMatches(item('Heat'), 'cold'), isFalse);
    expect(itemMatches(item('Heat'), ''), isFalse);
  });

  group('ListSearch', () {
    test('counter, wrap-around and clamping', () {
      final s = ListSearch()..open();
      expect(s.counterLabel, '');
      s.setQuery('the');
      expect(s.counterLabel, 'No matches');
      s.reportTotal(12);
      expect(s.counterLabel, '1 of 12');
      s.next();
      s.next();
      expect(s.counterLabel, '3 of 12');
      s.previous();
      s.previous();
      s.previous();
      expect(s.counterLabel, '12 of 12');
      // An item was ticked away: the counter stays in range.
      s.reportTotal(5);
      expect(s.counterLabel, '5 of 5');
    });

    test('every move asks the list to scroll', () {
      final s = ListSearch()..open();
      final start = s.jumpRequest;
      s.setQuery('a');
      s.reportTotal(3);
      s.next();
      s.restart();
      expect(s.jumpRequest, start + 3);
      expect(s.current, 0);
    });

    test('closing clears everything', () {
      final s = ListSearch()
        ..open()
        ..setQuery('dune')
        ..reportTotal(2)
        ..close();
      expect(s.query, '');
      expect(s.total, 0);
      expect(s.hasQuery, isFalse);
    });
  });

  test('highlightSpan marks only the matches', () {
    const hl = TextStyle(fontWeight: FontWeight.bold);
    final span = highlightSpan('Dune: Part Two', 'part', highlight: hl);
    final parts = [
      for (final c in span.children!.cast<TextSpan>()) (c.text, c.style == hl),
    ];
    expect(parts, [('Dune: ', false), ('Part', true), (' Two', false)]);
    expect(highlightSpan('Dune', '', highlight: hl).text, 'Dune');
  });
}
