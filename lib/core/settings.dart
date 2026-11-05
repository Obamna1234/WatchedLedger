import 'package:flutter/foundation.dart';

import '../data/db/database.dart';
import 'theme.dart';

/// App preferences, stored inside the encrypted database.
class SettingsController extends ChangeNotifier {
  SettingsController(this._db);

  final AppDatabase _db;

  static const _kTheme = 'theme';
  static const _kOffline = 'offline_mode';
  static const _kLookups = 'lookups_enabled';

  AppThemeMode _themeMode = AppThemeMode.system;
  bool _offlineMode = false;
  bool _lookupsEnabled = true;

  AppThemeMode get themeMode => _themeMode;

  /// When on, the app makes no network requests at all.
  bool get offlineMode => _offlineMode;

  /// When off, new titles are saved exactly as typed (no lookup).
  bool get lookupsEnabled => _lookupsEnabled;

  Future<void> load() async {
    final values = await _db.readSettings();
    _themeMode = AppThemeMode.values.firstWhere(
      (m) => m.name == values[_kTheme],
      orElse: () => AppThemeMode.system,
    );
    _offlineMode = values[_kOffline] == 'true';
    _lookupsEnabled = values[_kLookups] != 'false';
    notifyListeners();
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    await _db.writeSetting(_kTheme, mode.name);
  }

  Future<void> setOfflineMode(bool value) async {
    _offlineMode = value;
    notifyListeners();
    await _db.writeSetting(_kOffline, value.toString());
  }

  Future<void> setLookupsEnabled(bool value) async {
    _lookupsEnabled = value;
    notifyListeners();
    await _db.writeSetting(_kLookups, value.toString());
  }
}
