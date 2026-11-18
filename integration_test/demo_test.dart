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

// print (not debugPrint, which is throttled) keeps the timestamps tight.
// ignore: avoid_print
void mark(String caption) => print('MARK|$caption');

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

/// The To Watch / Watched switch (not the add bar's list button).
Finder listSwitch(String label) => find.descendant(
    of: find.byWidgetPredicate((w) => w is SegmentedButton),
    matching: find.text(label));
Finder get addField => find.byType(TextField);

/// Adds [typed]; if "Did you mean…?" appears, picks [pick] (or the first).
Future<void> add(WidgetTester t, String typed, {String? pick}) async {
  // Clear the previous "Added …" message so it isn't mistaken for this one.
  t.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first)
      .removeCurrentSnackBar();
  await idle(t, 200);
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

/// Hides the "Added …" message so taps on a title hit the list row.
Future<void> clearSnack(WidgetTester t) async {
  t.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first)
      .removeCurrentSnackBar();
  await idle(t, 300);
}

/// Scrolls the tab bar so [name] is on screen, then opens that tab.
Future<void> openTab(WidgetTester t, String name, {int after = 700}) async {
  final tab = find.widgetWithText(Tab, name);
  await t.ensureVisible(tab);
  await idle(t, 250);
  await tap(t, tab, after: after);
}

/// Scrolls the open page until [f] shows, then taps it.
Future<void> scrollTo(WidgetTester t, Finder f) async {
  final page = find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down);
  await t.dragUntilVisible(f, visible(page).first, const Offset(0, -250));
  await idle(t, 400);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  // Let enterText() type into the app (off by default on real devices). This
  // also keeps the on-screen keyboard out of the recording.
  binding.testTextInput.register();

  testWidgets('demo', (t) async {
    app.main();
    await waitFor(t, find.byTooltip('Add'), timeoutMs: 60000);
    await idle(t, 500);

    // A few titles before the camera rolls, so the lists look lived in.
    await add(t, 'Dune');
    await add(t, 'Arrival');
    await add(t, 'The Matrix');
    await idle(t, 800);

    mark('start');
    await idle(t, 2500); // recording starts

    mark('Type a title. It is looked up and filed for you.');
    await add(t, 'Inception');

    mark('Typo? "Did you mean...?" fixes it.');
    await add(t, 'Intersteller', pick: 'Interstellar');

    mark('New: Games, for every console.');
    await openTab(t, 'Games');
    await add(t, 'Minecraft');

    mark('New: paste a YouTube or social link. It fills itself in.');
    await openTab(t, 'Videos');
    await add(t, 'https://www.youtube.com/watch?v=aqz-KE-bpKQ');

    mark('New: tick a whole show, a season or single episodes.');
    await openTab(t, 'Series');
    await add(t, 'Severence', pick: 'Severance');
    await clearSnack(t);
    await tap(t, find.textContaining('Severance'), after: 900);
    final seasons = find.textContaining('Seasons & episodes');
    await scrollTo(t, seasons);
    await tap(t, seasons, after: 300);
    final tickSeason = find.text('Tick season');
    if (await waitFor(t, tickSeason, timeoutMs: 12000)) {
      await tap(t, tickSeason, after: 1400);
    } else {
      await tap(t, find.text('Whole show watched'), after: 1400);
    }
    await tap(t, find.byTooltip('Back'), after: 700);
    await tap(t, find.text('Save'), after: 1000);

    mark('Swipe right to tick it off. Undo is always there.');
    await openTab(t, 'Movies', after: 900);
    await t.timedDrag(visible(find.text('Inception')).first,
        const Offset(420, 0), const Duration(milliseconds: 700));
    await idle(t, 1500);
    await tap(t, listSwitch('Watched'), after: 1200);

    mark('Rate it and save where you watched it.');
    await tap(t, find.text('Inception'), after: 900);
    await tap(t, find.byTooltip('5 stars'), after: 400);
    final netflix = find.widgetWithText(ChoiceChip, 'Netflix');
    await scrollTo(t, netflix);
    await tap(t, netflix, after: 900);
    await tap(t, find.text('Save'), after: 1300);

    mark('Long-press to select several. Move, tag or delete together.');
    await tap(t, listSwitch('To Watch'), after: 800);
    await clearSnack(t);
    await t.longPress(visible(find.textContaining('Dune')).first);
    await idle(t, 500);
    await tap(t, find.textContaining('Arrival'), after: 600);
    await tap(t, find.byTooltip('Add to a folder'), after: 600);
    await type(t, find.widgetWithText(TextField, 'New folder name'),
        'Movie night');
    await tap(t, find.text('Add'), after: 1300);

    mark('New: share a folder as a simple message. No app needed.');
    await tap(t, find.byTooltip('Folders'), after: 1000);
    await tap(t, find.text('Movie night'), after: 2200);
    await tap(t, find.byTooltip('Back'), after: 500);
    await tap(t, find.byTooltip('Back'), after: 700);

    mark("Can't decide? Let it pick from your list.");
    await tap(t, find.byTooltip('Pick something for me'), after: 800);
    await tap(t, find.text('Pick for me'), after: 1800);
    await tap(t, find.byTooltip('Back'), after: 700);

    mark('Themes, app lock, private items and backups in Settings.');
    await tap(t, find.byTooltip('Settings'), after: 900);
    await tap(t, find.text('AMOLED black'), after: 1200);
    await t.timedDrag(visible(find.byType(ListView)).first,
        const Offset(0, -700), const Duration(milliseconds: 1100));
    await idle(t, 1600);
    await tap(t, find.byTooltip('Back'), after: 1200);

    mark('end');
    await idle(t, 1500);
  }, timeout: const Timeout(Duration(minutes: 8)));
}
