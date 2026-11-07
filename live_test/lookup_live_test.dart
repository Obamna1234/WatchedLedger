// Live check against the REAL lookup services (needs internet).
//
// Not part of the normal test run. Runs in the "Live lookup check" workflow,
// which writes a results table to the run's summary page.
//
//   flutter test live_test/
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:watchedledger/core/net/net_client.dart';
import 'package:watchedledger/core/sanitise.dart';
import 'package:watchedledger/data/lookup/lookup_service.dart';
import 'package:watchedledger/data/models.dart';

typedef Case = (MediaCategory category, String typed, String expected);

const List<Case> exact = [
  (MediaCategory.movie, 'Inception', 'Inception'),
  (MediaCategory.series, 'Severance', 'Severance'),
  (MediaCategory.book, 'Project Hail Mary', 'Project Hail Mary'),
  (MediaCategory.audiobook, 'Project Hail Mary', 'Project Hail Mary'),
  (MediaCategory.podcast, 'Hardcore History', 'Hardcore History'),
];

const List<Case> misspelled = [
  (MediaCategory.movie, 'Inceptoin', 'Inception'),
  (MediaCategory.movie, 'Intersteller', 'Interstellar'),
  (MediaCategory.movie, 'The Godfathr', 'The Godfather'),
  (MediaCategory.series, 'Severence', 'Severance'),
  (MediaCategory.series, 'Braking Bad', 'Breaking Bad'),
  (MediaCategory.book, 'Harry Poter', 'Harry Potter'),
  (MediaCategory.book, 'The Hobit', 'The Hobbit'),
  (MediaCategory.audiobook, 'Project Hail Merry', 'Project Hail Mary'),
  (MediaCategory.podcast, 'Hardcore Histroy', 'Hardcore History'),
  (MediaCategory.podcast, 'Searial', 'Serial'),
];

void main() {
  late NetClient net;
  late LookupService lookup;
  final rows = <String>[];

  setUpAll(() {
    HttpOverrides.global = null; // make sure the real network is used
    net = NetClient(isOffline: () => false);
    lookup = LookupService(net);
  });

  tearDownAll(() {
    net.close();
    final table = StringBuffer()
      ..writeln('## Live lookup check')
      ..writeln()
      ..writeln('| Tab | Typed | Filed automatically? | Correct title offered? '
          '| Top results |')
      ..writeln('|---|---|---|---|---|')
      ..writeAll(rows, '\n')
      ..writeln();
    // ignore: avoid_print
    print(table);
    final summary = Platform.environment['GITHUB_STEP_SUMMARY'];
    if (summary != null) {
      File(summary).writeAsStringSync(table.toString(), mode: FileMode.append);
    }
  });

  /// Runs one lookup like the add box does and records the outcome.
  Future<bool> check(Case c) async {
    final (category, typed, expected) = c;
    final result = await lookup.search(typed, category);
    final auto = LookupService.confidentMatch(typed, result.candidates);
    final want = matchKey(expected);
    final offered =
        result.candidates.any((x) => matchKey(x.title).contains(want));
    final top = result.candidates
        .take(3)
        .map((x) => '${x.title}${x.year == null ? '' : ' (${x.year})'}')
        .join('; ');
    rows.add([
      '',
      category.tabLabel,
      typed,
      auto == null
          ? 'No → "Did you mean…?"'
          : 'Yes: ${auto.title}${auto.year == null ? '' : ' (${auto.year})'}',
      offered ? '✅' : '❌',
      result.couldNotReach
          ? 'ERROR: ${result.error}'
          : (top.isEmpty ? 'nothing found' : top.replaceAll('|', '/')),
      '',
    ].join(' | ').trim());
    return offered;
  }

  test('exact titles are found by every service', () async {
    final missing = <String>[];
    for (final c in exact) {
      if (!await check(c)) missing.add('${c.$1.tabLabel}: ${c.$2}');
    }
    expect(missing, isEmpty, reason: 'A lookup service may be down or changed');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('misspellings (report only)', () async {
    for (final c in misspelled) {
      await check(c);
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
