import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'app_lock.dart';

/// Lock settings live in the Keystore / Keychain, never in the database
/// or in backups.
class SecureLockStorage implements LockStorage {
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class DeviceBiometrics implements Biometrics {
  final LocalAuthentication _auth = LocalAuthentication();

  @override
  Future<bool> available() async {
    if (!await _auth.isDeviceSupported()) return false;
    if (!await _auth.canCheckBiometrics) return false;
    return (await _auth.getAvailableBiometrics()).isNotEmpty;
  }

  @override
  Future<bool> authenticate(String reason) => _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
}

/// Android: stops the app's screen appearing in the app switcher and in
/// screenshots. (iOS uses a cover drawn by the app instead.)
class SecureWindow {
  static const MethodChannel _channel = MethodChannel('watchedledger/window');
  static bool? _current;

  static Future<void> set(bool on) async {
    if (_current == on) return;
    _current = on;
    try {
      await _channel.invokeMethod<void>('setSecure', on);
    } on MissingPluginException {
      // iOS, tests: nothing to do.
    } on PlatformException {
      // Ignore: the cover drawn by the app still applies.
    }
  }
}
