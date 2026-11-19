import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchedledger/core/lock/app_lock.dart';
import 'package:watchedledger/features/lock/lock_gate.dart';

class FakeBiometrics implements Biometrics {
  FakeBiometrics({this.has = true, this.succeeds = true});
  bool has;
  bool succeeds;
  int prompts = 0;
  @override
  Future<bool> available() async => has;
  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    return succeeds;
  }
}

void main() {
  late MemoryLockStorage storage;
  late DateTime now;
  late FakeBiometrics bio;

  AppLock make() => AppLock(
        storage: storage,
        biometrics: bio,
        clock: () => now,
        pinIterations: 1000,
      );

  setUp(() {
    storage = MemoryLockStorage();
    now = DateTime(2026, 11, 17, 12);
    bio = FakeBiometrics();
  });

  test('off by default; never locked without a PIN', () async {
    final lock = make();
    await lock.load();
    expect(lock.enabled, isFalse);
    expect(lock.locked, isFalse);
    lock
      ..wentToBackground()
      ..cameToForeground()
      ..lockNow();
    expect(lock.locked, isFalse);
  });

  test('PIN is stored only as a salted hash', () async {
    final lock = make();
    await lock.load();
    await lock.setPin('482913');
    final record = storage.values['wl_lock_pin']!;
    expect(record, isNot(contains('482913')));
    expect(record, startsWith('pbkdf2-sha256:1000:'));

    // Same PIN again gets a different salt.
    await lock.setPin('482913');
    expect(storage.values['wl_lock_pin'], isNot(record));
  });

  test('rejects PINs that are too short, too long or not digits',
      () async {
    final lock = make();
    expect(AppLock.validPin('123'), isFalse);
    expect(AppLock.validPin('1234'), isTrue);
    expect(AppLock.validPin('1' * 13), isFalse);
    expect(AppLock.validPin('12a4'), isFalse);
    await expectLater(lock.setPin('12'), throwsArgumentError);
  });

  test('starts locked after restart; right PIN unlocks, wrong does not',
      () async {
    final first = make();
    await first.load();
    await first.setPin('2468');

    final lock = make();
    await lock.load();
    expect(lock.locked, isTrue);
    expect(await lock.unlockWithPin('1357'), isFalse);
    expect(lock.locked, isTrue);
    expect(await lock.unlockWithPin('2468'), isTrue);
    expect(lock.locked, isFalse);
  });

  test('locks again only after the chosen time away', () async {
    final lock = make();
    await lock.load();
    await lock.setPin('2468');
    await lock.setLockAfter(LockAfter.fiveMinutes);

    lock.wentToBackground();
    now = now.add(const Duration(minutes: 2));
    lock.cameToForeground();
    expect(lock.locked, isFalse);

    lock.wentToBackground();
    now = now.add(const Duration(minutes: 5));
    lock.cameToForeground();
    expect(lock.locked, isTrue);
  });

  test('"Immediately" locks on every return', () async {
    final lock = make();
    await lock.load();
    await lock.setPin('2468');
    await lock.setLockAfter(LockAfter.immediately);
    lock
      ..wentToBackground()
      ..cameToForeground();
    expect(lock.locked, isTrue);
  });

  test('5 wrong tries force a wait that grows and survives a restart',
      () async {
    final lock = make();
    await lock.load();
    await lock.setPin('2468');
    for (var i = 0; i < 4; i++) {
      expect(await lock.unlockWithPin('0000'), isFalse);
    }
    expect(lock.waitRemaining, isNull);
    expect(await lock.unlockWithPin('0000'), isFalse);
    expect(lock.waitRemaining, const Duration(seconds: 30));

    // Even the right PIN is refused while waiting.
    expect(await lock.unlockWithPin('2468'), isFalse);

    final restarted = make();
    await restarted.load();
    expect(restarted.waitRemaining, const Duration(seconds: 30));

    now = now.add(const Duration(seconds: 31));
    expect(await restarted.unlockWithPin('1111'), isFalse);
    expect(restarted.waitRemaining, const Duration(seconds: 60));

    now = now.add(const Duration(seconds: 61));
    expect(await restarted.unlockWithPin('2468'), isTrue);
    expect(restarted.waitRemaining, isNull);
    expect(storage.values.containsKey('wl_lock_fails'), isFalse);
  });

  test('biometrics unlock only when switched on and available', () async {
    final lock = make();
    await lock.load();
    await lock.setPin('2468');
    lock.lockNow();
    expect(await lock.unlockWithBiometrics(), isFalse);
    expect(bio.prompts, 0);

    await lock.setUseBiometrics(true);
    bio.succeeds = false;
    expect(await lock.unlockWithBiometrics(), isFalse);
    expect(lock.locked, isTrue);

    bio.succeeds = true;
    expect(await lock.unlockWithBiometrics(), isTrue);
    expect(lock.locked, isFalse);

    // Phone with no fingerprint set up: option is ignored.
    bio.has = false;
    final other = make();
    await other.load();
    expect(other.useBiometrics, isFalse);
  });

  test('turning the lock off removes the PIN', () async {
    final lock = make();
    await lock.load();
    await lock.setPin('2468');
    await lock.setUseBiometrics(true);
    await lock.disable();
    expect(lock.enabled, isFalse);
    expect(storage.values.containsKey('wl_lock_pin'), isFalse);
    expect(lock.useBiometrics, isFalse);
  });

  test('hide in app switcher only applies while the lock is on', () async {
    final lock = make();
    await lock.load();
    expect(lock.hideInSwitcher, isFalse);
    await lock.setPin('2468');
    expect(lock.hideInSwitcher, isTrue);
    await lock.setHideInSwitcher(false);
    expect(lock.hideInSwitcher, isFalse);
  });

  test('a damaged PIN record never unlocks', () async {
    storage.values['wl_lock_pin'] = 'pbkdf2-sha256:abc:!!:??';
    final lock = make();
    await lock.load();
    expect(lock.locked, isTrue);
    expect(await lock.unlockWithPin('2468'), isFalse);
  });

  testWidgets('the PIN pad can be reached on a small screen with large text',
      (t) async {
    t.view.physicalSize = const Size(320, 480);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final lock = make();
    await t.runAsync(() async {
      await lock.load();
      await lock.setPin('482913');
    });
    await t.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: LockScreen(lock: lock),
    ));
    // No overflow, and the last row of the pad scrolls into reach.
    expect(t.takeException(), isNull);
    await t.scrollUntilVisible(find.text('0'), 120);
    await t.tap(find.text('0'));
    await t.pump();
    expect(t.takeException(), isNull);
  });
  // Regression: the lock screen sits above the app's navigator (it is built
  // in MaterialApp.builder), where there is no Overlay. The OK and Delete
  // buttons have tooltips, which need one, so they failed to build and the
  // PIN could not be submitted.
  testWidgets('the PIN can be entered and submitted where the app shows it',
      (t) async {
    final lock = make();
    await t.runAsync(() async {
      await lock.load();
      await lock.setPin('482913');
    });
    lock.lockNow();
    await t.pumpWidget(MaterialApp(
      home: const Scaffold(body: Text('The library')),
      builder: (context, child) => LockGate(lock: lock, child: child!),
    ));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.text('WatchedLedger is locked'), findsOneWidget);
    expect(find.byTooltip('OK'), findsOneWidget);
    expect(find.byTooltip('Delete'), findsOneWidget);

    for (final d in '482913'.split('')) {
      await t.tap(find.text(d));
      await t.pump();
    }
    await t.tap(find.byTooltip('OK'));
    for (var i = 0; i < 50 && lock.locked; i++) {
      await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();
    }
    await t.pump();
    expect(t.takeException(), isNull);
    expect(lock.locked, isFalse);
    expect(find.text('WatchedLedger is locked'), findsNothing);
    expect(find.text('The library'), findsOneWidget);
  });
}
