// The main features, on the real built app (Android emulator and iPhone
// simulator): the "Checks for this app" part of the owner's release checklist
// that can run on a device. Offline mode is switched on first, so nothing here
// depends on outside lookup services (the daily live lookup check covers them).
//
// On Android the workflow also shares text into the app (it waits for the
// FEATURES|share-ready log line) and checks "Hide in recent apps" really sets
// FLAG_SECURE after the test (FEATURES|left-locked).
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:watchedledger/data/models.dart';
import 'package:watchedledger/main.dart' as app;

Future<void> settle(WidgetTester t, [int ms = 400]) async {
  await Future<void>.delayed(Duration(milliseconds: ms));
  await t.pump();
}

/// Waits up to [seconds] for [f]; fails with [what] if it never shows.
Future<void> expectSoon(WidgetTester t, Finder f, String what,
    {int seconds = 20}) async {
  for (var i = 0; i < seconds * 10; i++) {
    if (f.hitTestable().evaluate().isNotEmpty) return;
    await settle(t, 100);
  }
  // Say what WAS on screen, so a failure can be read from the log.
  final shown = <String>{
    for (final e in find.byType(Text).hitTestable().evaluate())
      if ((e.widget as Text).data case final d?) d,
  };
  fail('Never saw: $what. On screen: ${shown.join(' | ')}');
}

Future<void> tapOn(WidgetTester t, Finder f, String what) async {
  await expectSoon(t, f, what);
  await t.tap(f.hitTestable().first);
  await settle(t, 600);
}

Finder nav(String label) => find.descendant(
    of: find.byType(NavigationBar), matching: find.text(label));

Finder inSheet(Finder f) =>
    find.descendant(of: find.byType(BottomSheet), matching: f);

Future<void> openCategory(WidgetTester t, MediaCategory c) async {
  await tapOn(t, find.byIcon(Icons.arrow_drop_down), 'the category button');
  await tapOn(t, inSheet(find.text(c.tabLabel)), '${c.tabLabel} in the list');
}

Future<void> scrollTo(WidgetTester t, Finder f) async {
  final page = find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down);
  await t.dragUntilVisible(f, page.hitTestable().first, const Offset(0, -250));
  await settle(t);
}

Future<void> clearSnack(WidgetTester t) async {
  t.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first)
      .removeCurrentSnackBar();
  await settle(t);
}

/// The tick box on the row showing [title].
Finder tickFor(String title) => find.descendant(
    of: find.ancestor(of: find.text(title), matching: find.byType(ListTile)),
    matching: find.byType(Checkbox));

Future<void> addTitle(WidgetTester t, String title) async {
  await tapOn(t, find.widgetWithText(FloatingActionButton, 'Add'), 'Add');
  await t.enterText(
      inSheet(find.byType(TextField)).hitTestable().first, title);
  await settle(t, 200);
  await tapOn(t, inSheet(find.byTooltip('Add')), 'the + button');
  await expectSoon(t, find.text(title), '"$title" on the list');
  await clearSnack(t);
}

Future<void> enterPin(WidgetTester t, String pin) async {
  for (final d in pin.split('')) {
    await t.tap(find.text(d).hitTestable().last);
    await settle(t, 120);
  }
  await tapOn(t, find.byTooltip('OK'), 'OK on the keypad');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('main features on a real device', (t) async {
    app.main();
    await expectSoon(t, find.widgetWithText(FloatingActionButton, 'Add'),
        'the app opening', seconds: 60);

    // Offline mode: everything below stays on the phone.
    await tapOn(t, nav('More'), 'More');
    final offline = find.text('Offline mode');
    await scrollTo(t, offline);
    await tapOn(t, offline, 'Offline mode');
    await tapOn(t, nav('Lists'), 'Lists');

    // Every category: add (saved exactly as typed), tick, undo.
    for (final c in MediaCategory.values) {
      await openCategory(t, c);
      final title = 'Device check ${c.tabLabel} éè';
      await addTitle(t, title);

      await tapOn(t, tickFor(title), 'the tick box for "$title"');
      expect(find.text(title).hitTestable(), findsNothing,
          reason: 'ticked items leave ${c.todoLabel}');
      await tapOn(t, find.text('Undo'), 'Undo after ticking');
      await expectSoon(t, find.text(title), '"$title" back after Undo');
      await clearSnack(t);

      await tapOn(t, tickFor(title), 'the tick box again');
      await clearSnack(t);
      await tapOn(t, find.text(c.doneLabel), c.doneLabel);
      await expectSoon(t, find.text(title), '"$title" in ${c.doneLabel}');
      await tapOn(t, find.text(c.todoLabel), c.todoLabel);
    }

    // Search: highlight count and jumping between matches.
    await openCategory(t, MediaCategory.movie);
    await addTitle(t, 'Search target one');
    await addTitle(t, 'Search target two');
    await tapOn(t, find.text('Search'), 'the Search box');
    await t.enterText(find.byType(TextField).hitTestable().first, 'target');
    await expectSoon(t, find.text('1 of 2'), 'the "1 of 2" counter');
    await tapOn(t, find.byTooltip('Next match'), 'next match');
    await expectSoon(t, find.text('2 of 2'), 'the "2 of 2" counter');
    await tapOn(t, find.byTooltip('Close search'), 'close search');

    // Import a pasted list in someone else's layout.
    await tapOn(t, nav('More'), 'More');
    await tapOn(t, find.text('Import a list or file'), 'Import');
    await t.enterText(find.byType(TextField).hitTestable().first,
        'Pasted Watched Film - watched\nPasted Later Film (to watch)\n');
    FocusManager.instance.primaryFocus?.unfocus(); // the keyboard covers it
    await settle(t, 800);
    await scrollTo(t, find.text('Continue'));
    await tapOn(t, find.text('Continue'), 'Continue');
    await tapOn(t, find.text('Add 2 titles'), 'Add 2 titles');
    await tapOn(t, nav('Lists'), 'Lists');
    await openCategory(t, MediaCategory.movie);
    await expectSoon(t, find.text('Pasted Later Film'), 'the imported to-watch');
    await tapOn(t, find.text('Watched'), 'Watched');
    await expectSoon(t, find.text('Pasted Watched Film'), 'the imported watched');
    await tapOn(t, find.text('To Watch'), 'To Watch');

    // Shared into the app from another app (Android).
    if (Platform.isAndroid) {
      debugPrint('FEATURES|share-ready');
      await expectSoon(t, find.text('Add 1 title'), 'the shared title to review',
          seconds: 90);
      await tapOn(t, find.text('Add 1 title'), 'Add 1 title');
      await expectSoon(t, find.text('Shared From Another App'),
          'the shared title on the list');
    }

    // App lock: PIN, lock, can't see the library, unlock.
    await tapOn(t, nav('More'), 'More');
    final lockRow = find.text('App lock');
    await scrollTo(t, lockRow);
    await tapOn(t, lockRow, 'App lock');
    await tapOn(t, find.text('Lock with a PIN'), 'Lock with a PIN');
    await enterPin(t, '482913');
    await enterPin(t, '482913');
    await tapOn(t, find.text('Hide in recent apps'), 'Hide in recent apps');
    await tapOn(t, find.text('Lock now'), 'Lock now');
    await expectSoon(t, find.text('WatchedLedger is locked'), 'the lock screen');
    expect(find.textContaining('Device check').hitTestable(), findsNothing,
        reason: 'nothing from the library shows while locked');
    await enterPin(t, '000000');
    // Checking a PIN takes a moment on purpose; wait for the answer.
    await expectSoon(t, find.text('Wrong PIN'), 'the "Wrong PIN" message',
        seconds: 30);
    expect(find.text('WatchedLedger is locked').hitTestable(), findsOneWidget,
        reason: 'a wrong PIN does not unlock');
    await enterPin(t, '482913');
    await expectSoon(t, find.text('Lock now'), 'unlocked again', seconds: 30);

    // Leave it locked with "Hide in recent apps" on, for the FLAG_SECURE check.
    await tapOn(t, find.text('Lock now'), 'Lock now');
    debugPrint('FEATURES|left-locked');
    await settle(t, 1500);
  }, timeout: const Timeout(Duration(minutes: 12)));
}
