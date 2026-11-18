// Step 1 of the update test: runs inside the LAST RELEASE's code (the
// "Update keeps the library" workflow copies it into a checkout of that tag)
// and saves a small library in the app's real, encrypted database.
// Step 2 (upgrade_check_test.dart) installs the new build over it and checks
// that everything is still there.
//
// Only APIs every release has: keep it that way.
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:watchedledger/core/app_scope.dart';
import 'package:watchedledger/data/db/database.dart';
import 'package:watchedledger/data/models.dart';
import 'package:watchedledger/main.dart' as app;

Future<AppDatabase> appDatabase(WidgetTester t) async {
  final inApp = find.descendant(
      of: find.byType(AppScope), matching: find.byType(Scaffold));
  for (var i = 0; i < 600; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await t.pump();
    if (inApp.evaluate().isNotEmpty) {
      return AppScope.of(t.element(inApp.first)).db;
    }
  }
  fail('The app never opened its library.');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('save a library with the last release', (t) async {
    app.main();
    final db = await appDatabase(t);
    Future<MediaItem> byId(int id) =>
        (db.select(db.items)..where((i) => i.id.equals(id))).getSingle();

    await db.addItem(
        category: MediaCategory.movie,
        status: ListStatus.todo,
        title: 'Heat',
        year: 1995,
        genre: 'Crime');
    final arrival = await db.addItem(
        category: MediaCategory.movie,
        status: ListStatus.todo,
        title: 'Arrival',
        year: 2016);
    await db.setStatus(arrival, ListStatus.done);
    await db.updateItem((await byId(arrival)).copyWith(
        rating: const Value(5), note: const Value('Kept across updates')));
    final show = await db.addItem(
        category: MediaCategory.series,
        status: ListStatus.todo,
        title: 'Severance');
    await db.updateItem((await byId(show))
        .copyWith(season: const Value(2), episode: const Value(4)));
    await db.writeSetting('upgrade_check', 'kept');
    await t.pump(const Duration(seconds: 1));
    debugPrint('UPGRADE|seeded ${(await db.select(db.items).get()).length}');
  });
}
