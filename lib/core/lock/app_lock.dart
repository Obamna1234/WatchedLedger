import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

/// Where the lock keeps its PIN hash and options. In the app this is the
/// phone's secure storage (Keystore / Keychain), not the database, so a
/// restored backup can never switch the lock on without a PIN.
abstract class LockStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class MemoryLockStorage implements LockStorage {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// Fingerprint / Face ID. Faked in tests.
abstract class Biometrics {
  /// True if the phone has biometrics set up.
  Future<bool> available();

  /// Shows the system prompt. True only on success.
  Future<bool> authenticate(String reason);
}

/// How long the app may stay in the background before it locks again.
enum LockAfter { immediately, oneMinute, fiveMinutes, fifteenMinutes }

extension LockAfterInfo on LockAfter {
  Duration get duration => switch (this) {
        LockAfter.immediately => Duration.zero,
        LockAfter.oneMinute => const Duration(minutes: 1),
        LockAfter.fiveMinutes => const Duration(minutes: 5),
        LockAfter.fifteenMinutes => const Duration(minutes: 15),
      };
  String get label => switch (this) {
        LockAfter.immediately => 'Immediately',
        LockAfter.oneMinute => 'After 1 minute',
        LockAfter.fiveMinutes => 'After 5 minutes',
        LockAfter.fifteenMinutes => 'After 15 minutes',
      };
}

const int kMinPinLength = 4;
const int kMaxPinLength = 12;
const int kFreeAttempts = 5;

/// Optional PIN / biometric lock. The lock only hides the app's screens;
/// the data itself is always encrypted (see open.dart).
class AppLock extends ChangeNotifier {
  AppLock({
    required this.storage,
    this.biometrics,
    DateTime Function()? clock,
    this.pinIterations = 120000,
  }) : _clock = clock ?? DateTime.now;

  final LockStorage storage;
  final Biometrics? biometrics;
  final DateTime Function() _clock;

  /// PBKDF2 rounds for new PINs (lowered in tests).
  final int pinIterations;

  static const _kPin = 'wl_lock_pin';
  static const _kAfter = 'wl_lock_after';
  static const _kBio = 'wl_lock_bio';
  static const _kHide = 'wl_lock_hide';
  static const _kFails = 'wl_lock_fails';
  static const _kUntil = 'wl_lock_until';

  String? _pinRecord;
  LockAfter _after = LockAfter.oneMinute;
  bool _useBiometrics = false;
  bool _hideInSwitcher = true;
  bool _biometricsAvailable = false;
  int _fails = 0;
  DateTime? _blockedUntil;
  bool _locked = false;
  DateTime? _backgroundedAt;

  bool get enabled => _pinRecord != null;
  bool get locked => enabled && _locked;
  LockAfter get lockAfter => _after;
  bool get useBiometrics => _useBiometrics && _biometricsAvailable;
  bool get biometricsAvailable => _biometricsAvailable;

  /// Hide the app in the app switcher (and block screenshots on Android).
  bool get hideInSwitcher => enabled && _hideInSwitcher;
  bool get hideInSwitcherSetting => _hideInSwitcher;

  /// Time left before another PIN attempt is allowed, or null.
  Duration? get waitRemaining {
    final until = _blockedUntil;
    if (until == null) return null;
    final left = until.difference(_clock());
    return left > Duration.zero ? left : null;
  }

  Future<void> load() async {
    _pinRecord = await storage.read(_kPin);
    final after = int.tryParse(await storage.read(_kAfter) ?? '');
    _after = after != null && after >= 0 && after < LockAfter.values.length
        ? LockAfter.values[after]
        : LockAfter.oneMinute;
    _useBiometrics = await storage.read(_kBio) == '1';
    _hideInSwitcher = await storage.read(_kHide) != '0';
    _fails = int.tryParse(await storage.read(_kFails) ?? '') ?? 0;
    final until = int.tryParse(await storage.read(_kUntil) ?? '');
    _blockedUntil =
        until == null ? null : DateTime.fromMillisecondsSinceEpoch(until);
    try {
      _biometricsAvailable = await biometrics?.available() ?? false;
    } catch (_) {
      _biometricsAvailable = false;
    }
    _locked = enabled;
    notifyListeners();
  }

  // --------------------------------------------------------------- setup

  static bool validPin(String pin) =>
      pin.length >= kMinPinLength &&
      pin.length <= kMaxPinLength &&
      RegExp(r'^\d+$').hasMatch(pin);

  Future<void> setPin(String pin) async {
    if (!validPin(pin)) throw ArgumentError('PIN must be 4-12 digits');
    final salt = _randomBytes(16);
    final hash = await _hash(pin, salt, pinIterations);
    final record =
        'pbkdf2-sha256:$pinIterations:${base64Encode(salt)}:${base64Encode(hash)}';
    await storage.write(_kPin, record);
    _pinRecord = record;
    await _resetFails();
    _locked = false;
    notifyListeners();
  }

  /// Turns the lock off (after the user has proved they know the PIN).
  Future<void> disable() async {
    await storage.delete(_kPin);
    await storage.write(_kBio, '0');
    _pinRecord = null;
    _useBiometrics = false;
    _locked = false;
    await _resetFails();
    notifyListeners();
  }

  Future<void> setLockAfter(LockAfter value) async {
    _after = value;
    await storage.write(_kAfter, '${value.index}');
    notifyListeners();
  }

  Future<void> setUseBiometrics(bool value) async {
    _useBiometrics = value;
    await storage.write(_kBio, value ? '1' : '0');
    notifyListeners();
  }

  Future<void> setHideInSwitcher(bool value) async {
    _hideInSwitcher = value;
    await storage.write(_kHide, value ? '1' : '0');
    notifyListeners();
  }

  // ------------------------------------------------------------- unlocking

  /// Checks [pin] without unlocking (used before changing settings).
  /// Wrong guesses count towards the wait, same as on the lock screen.
  Future<bool> verifyPin(String pin) async {
    final record = _pinRecord;
    if (record == null) return true;
    if (waitRemaining != null) return false;
    final ok = await _matches(pin, record);
    if (ok) {
      await _resetFails();
    } else {
      _fails++;
      await storage.write(_kFails, '$_fails');
      if (_fails >= kFreeAttempts) {
        // 30 s after 5 wrong tries, doubling each time, up to an hour.
        final secs = min(3600, 30 * pow(2, _fails - kFreeAttempts).toInt());
        _blockedUntil = _clock().add(Duration(seconds: secs));
        await storage.write(
            _kUntil, '${_blockedUntil!.millisecondsSinceEpoch}');
      }
      notifyListeners();
    }
    return ok;
  }

  Future<bool> unlockWithPin(String pin) async {
    final ok = await verifyPin(pin);
    if (ok) _unlock();
    return ok;
  }

  Future<bool> unlockWithBiometrics() async {
    final bio = biometrics;
    if (bio == null || !useBiometrics) return false;
    bool ok;
    try {
      ok = await bio.authenticate('Unlock WatchedLedger');
    } catch (_) {
      ok = false;
    }
    if (ok) {
      await _resetFails();
      _unlock();
    }
    return ok;
  }

  void _unlock() {
    _locked = false;
    _backgroundedAt = null;
    notifyListeners();
  }

  /// Locks straight away (the "Lock now" button).
  void lockNow() {
    if (!enabled) return;
    _locked = true;
    notifyListeners();
  }

  /// Call when the app goes to the background.
  void wentToBackground() {
    _backgroundedAt ??= _clock();
  }

  /// Call when the app comes back. Locks if it was away long enough.
  void cameToForeground() {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (!enabled || since == null) return;
    if (_clock().difference(since) >= _after.duration) {
      _locked = true;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------- hashing

  Future<void> _resetFails() async {
    _fails = 0;
    _blockedUntil = null;
    await storage.delete(_kFails);
    await storage.delete(_kUntil);
  }

  static Future<bool> _matches(String pin, String record) async {
    final parts = record.split(':');
    if (parts.length != 4 || parts[0] != 'pbkdf2-sha256') return false;
    final iterations = int.tryParse(parts[1]);
    if (iterations == null || iterations < 1 || iterations > 2000000) {
      return false;
    }
    final List<int> salt, expected;
    try {
      salt = base64Decode(parts[2]);
      expected = base64Decode(parts[3]);
    } on FormatException {
      return false;
    }
    final actual = await _hash(pin, salt, iterations);
    if (actual.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < actual.length; i++) {
      diff |= actual[i] ^ expected[i];
    }
    return diff == 0;
  }

  static Future<List<int>> _hash(String pin, List<int> salt, int iterations) {
    return Isolate.run(() async {
      final kdf = Pbkdf2.hmacSha256(iterations: iterations, bits: 256);
      final key = await kdf.deriveKeyFromPassword(password: pin, nonce: salt);
      return key.extractBytes();
    });
  }

  static List<int> _randomBytes(int n) {
    final rnd = Random.secure();
    return List<int>.generate(n, (_) => rnd.nextInt(256));
  }
}
