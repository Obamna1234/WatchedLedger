import 'package:flutter/foundation.dart';

import '../data/db/database.dart';
import 'net/net_client.dart';
import 'theme.dart';

/// What may use mobile data (Wi-Fi is always allowed).
enum MobileDataUse { none, lookupsOnly, everything }

extension MobileDataUseLabels on MobileDataUse {
  String get label => switch (this) {
        MobileDataUse.none => 'Wi-Fi only',
        MobileDataUse.lookupsOnly => 'Mobile data for title lookups',
        MobileDataUse.everything => 'Wi-Fi and mobile data',
      };

  String get description => switch (this) {
        MobileDataUse.none => 'Nothing uses mobile data. Titles added on mobile '
            'data are saved as typed and matched once you are on Wi-Fi.',
        MobileDataUse.lookupsOnly => 'Lookups use a few KB of mobile data. '
            'Cover pictures wait for Wi-Fi.',
        MobileDataUse.everything => 'Lookups and cover pictures use mobile '
            'data too.',
      };

  bool allows(NetPurpose purpose) => switch (this) {
        MobileDataUse.none => false,
        MobileDataUse.lookupsOnly => purpose == NetPurpose.lookup,
        MobileDataUse.everything => true,
      };
}

/// App preferences, stored inside the encrypted database.
class SettingsController extends ChangeNotifier {
  SettingsController(this._db);

  final AppDatabase _db;

  static const _kTheme = 'theme';
  static const _kOffline = 'offline_mode';
  static const _kLookups = 'lookups_enabled';
  static const _kMobileData = 'mobile_data';
  static const _kReminders = 'episode_reminders';

  AppThemeMode _themeMode = AppThemeMode.system;
  bool _offlineMode = false;
  bool _lookupsEnabled = true;
  MobileDataUse _mobileData = MobileDataUse.none;
  bool _episodeReminders = false;

  AppThemeMode get themeMode => _themeMode;

  /// When on, the app makes no network requests at all.
  bool get offlineMode => _offlineMode;

  /// When off, new titles are saved exactly as typed (no lookup).
  bool get lookupsEnabled => _lookupsEnabled;

  /// Default: Wi-Fi only, so a forgotten setting never eats mobile data.
  MobileDataUse get mobileData => _mobileData;

  /// "New episode" reminders for followed shows. Off by default.
  bool get episodeReminders => _episodeReminders;

  Future<void> load() async {
    final values = await _db.readSettings();
    _themeMode = AppThemeMode.values.firstWhere(
      (m) => m.name == values[_kTheme],
      orElse: () => AppThemeMode.system,
    );
    _offlineMode = values[_kOffline] == 'true';
    _lookupsEnabled = values[_kLookups] != 'false';
    _episodeReminders = values[_kReminders] == 'true';
    _mobileData = MobileDataUse.values.firstWhere(
      (m) => m.name == values[_kMobileData],
      orElse: () => MobileDataUse.none,
    );
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

  Future<void> setMobileData(MobileDataUse value) async {
    _mobileData = value;
    notifyListeners();
    await _db.writeSetting(_kMobileData, value.name);
  }

  Future<void> setLookupsEnabled(bool value) async {
    _lookupsEnabled = value;
    notifyListeners();
    await _db.writeSetting(_kLookups, value.toString());
  }

  Future<void> setEpisodeReminders(bool value) async {
    _episodeReminders = value;
    notifyListeners();
    await _db.writeSetting(_kReminders, value.toString());
  }
}
