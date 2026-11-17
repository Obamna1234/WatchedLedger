// Drives the real app through its main features for the demo video.
//
// Runs on an Android emulator in the "Demo video" workflow while the screen
// is recorded. Each scene logs "MARK|<caption>" so the recording can be cut
// and captioned afterwards. Uses the real lookup services.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:watchedledger/main.dart' as app;

void mark(String caption) => debugPrint('MARK|$caption');

Future<void> idle(WidgetTester t, int ms) async {
  await Future<void>.delayed(Duration(milliseconds: ms));
  await t.pump();
}

/// Waits (real time) until [finder] finds something.
Future<bool> waitFor(WidgetTester t, Finder finder,
    {int timeoutMs = 20000}) async {
  final end = DateTime.now().add(Duration(milliseconds: timeoutMs));
  while (DateTime.now().isBefore(end)) {
    await idle(t, 150);
    if (finder.evaluate().isNotEmpty) return true;
  }
  return false;
}

Finder visible(Finder f) => f.hitTestable();

/// Closes the on-screen keyboard so it doesn't cover the list.
Future<void> hideKeyboard(WidgetTester t) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  await idle(t, 500);
}

Future<void> tap(WidgetTester t, Finder f, {int after = 500}) async {
  await t.tap(visible(f).first);
  await idle(t, after);
}

/// Types like a person, one letter at a time.
Future<void> type(WidgetTester t, Finder field, String text) async {
  for (var i = 1; i <= text.length; i++) {
    await t.enterText(visible(field).first, text.substring(0, i));
    await idle(t, 60);
  }
  await idle(t, 250);
}

Finder get sheet => find.byType(BottomSheet);
Finder get addField => find.byType(TextField);

/// Adds [typed]; if "Did you mean…?" appears, picks [pick] (or the first).
Future<void> add(WidgetTester t, String typed, {String? pick}) async {
  await type(t, addField, typed);
  await tap(t, find.byTooltip('Add'), after: 100);
  mark('~wait'); // network lookup: shortened in the video
  final added = find.textContaining('Added "');
  final asked = find.text('Did you mean…?');
  final end = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(end)) {
    await idle(t, 150);
    if (added.evaluate().isNotEmpty) {
      mark('~go');
      break;
    }
    if (asked.evaluate().isNotEmpty) {
      mark('~go');
      await idle(t, 1200); // let viewers read the suggestions
      final choice = pick == null
          ? find.descendant(of: sheet, matching: find.byType(ListTile))
          : find.descendant(of: sheet, matching: find.text(pick));
      await waitFor(t, choice);
      await tap(t, choice, after: 200);
      await waitFor(t, added);
      break;
    }
  }
  await hideKeyboard(t);
  await idle(t, 900);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('demo', (t) async {
    app.main();
    await waitFor(t, find.byTooltip('Add'), timeoutMs: 60000);
    await idle(t, 500);

    mark('start');
    await idle(t, 2500); // recording starts

    mark('Type a title. It is looked up and filed automatically.');
    await add(t, 'Inception');

    mark('Typo? "Did you mean...?" offers the right one.');
    await add(t, 'Intersteller', pick: 'Interstellar');

    mark('Series, books, audiobooks and podcasts too, with covers.');
    await tap(t, find.widgetWithText(Tab, 'Series'), after: 700);
    await add(t, 'Severence', pick: 'Severance');
    await tap(t, find.widgetWithText(Tab, 'Books'), after: 700);
    await add(t, 'The Hobbit');

    mark('Swipe right to tick it off. The date is saved, with Undo.');
    await tap(t, find.widgetWithText(Tab, 'Movies'), after: 900);
    await t.timedDrag(visible(find.text('Inception')).first,
        const Offset(420, 0), const Duration(milliseconds: 700));
    await idle(t, 1500);
    await tap(t, find.text('Watched'), after: 1500);

    mark('Tap a title to rate it, add a note or track progress.');
    await tap(t, find.text('Inception'), after: 900);
    await tap(t, find.byTooltip('5 stars'), after: 500);
    await type(t, find.widgetWithText(TextFormField, 'Note (one line, optional)'),
        'Rewatch soon');
    await hideKeyboard(t);
    await tap(t, find.text('Save'), after: 1600);

    mark('Search highlights every match, across all your lists.');
    await tap(t, find.text('To Watch'), after: 700);
    await tap(t, find.byTooltip('Search'), after: 500);
    await type(t, addField, 'in');
    await hideKeyboard(t);
    await idle(t, 1500);
    await tap(t, find.byTooltip('Close search'), after: 700);

    mark('Light, dark and AMOLED black themes.');
    await tap(t, find.byTooltip('Settings'), after: 900);
    await tap(t, find.text('AMOLED black'), after: 1500);

    mark('Private by design: offline mode, no accounts, no tracking.');
    await tap(t, find.text('What leaves this device'), after: 1200);
    await t.timedDrag(visible(find.byType(ListView)).first,
        const Offset(0, -450), const Duration(milliseconds: 900));
    await idle(t, 1500);
    await t.pageBack();
    await idle(t, 400);
    await t.pageBack();
    await idle(t, 1500);

    mark('end');
    await idle(t, 1500);
  }, timeout: const Timeout(Duration(minutes: 6)));
}
