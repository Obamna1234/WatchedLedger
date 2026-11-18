// Step 2 of the update test: the NEW build, installed over the last release
// that upgrade_seed_test.dart filled. The library must open (same encryption
// key, database upgraded) with nothing lost, and show on screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:watchedledger/data/models.dart';
import 'package:watchedledger/main.dart' as app;

import 'upgrade_seed_test.dart' show appDatabase;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the new version keeps the library', (t) async {
    app.main();
    final db = await appDatabase(t);
    final items = {
      for (final i in await db.select(db.items).get()) i.title: i,
    };
    expect(items.keys.toSet(), {'Heat', 'Arrival', 'Severance'},
        reason: 'every title saved by the last release is still there');

    final arrival = items['Arrival']!;
    expect(arrival.status, ListStatus.done);
    expect(arrival.rating, 5);
    expect(arrival.note, 'Kept across updates');
    expect(arrival.completedAt, isNotNull);
    expect((items['Severance']!.season, items['Severance']!.episode), (2, 4));
    expect(items['Heat']!.year, 1995);
    expect((await db.readSettings())['upgrade_check'], 'kept');
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), db.schemaVersion);

    // And it shows: Movies → To Watch lists Heat.
    var shown = false;
    for (var i = 0; i < 100 && !shown; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await t.pump();
      shown = find.text('Heat').evaluate().isNotEmpty;
    }
    expect(shown, isTrue, reason: 'Heat is on the Movies list');
    debugPrint('UPGRADE|checked ${items.length}');
  });
}
