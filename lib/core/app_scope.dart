import 'package:flutter/widgets.dart';

import '../data/covers/cover_cache.dart';
import '../data/db/database.dart';
import '../data/lookup/background_matcher.dart';
import '../data/lookup/lookup_service.dart';
import 'lock/app_lock.dart';
import 'net/net_client.dart';
import 'net/network_status.dart';
import 'settings.dart';

/// Makes the app's services available to every screen.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.db,
    required this.settings,
    required this.net,
    required this.lookup,
    required this.covers,
    required this.network,
    this.matcher,
    this.lock,
    required super.child,
  });

  final AppDatabase db;
  final SettingsController settings;
  final NetClient net;
  final LookupService lookup;
  final CoverCache covers;
  final NetworkStatus network;

  /// Matches titles saved as typed once lookups are possible (null in tests).
  final BackgroundMatcher? matcher;

  /// Optional PIN / biometric lock (null in tests).
  final AppLock? lock;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope above this widget');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      db != oldWidget.db ||
      settings != oldWidget.settings ||
      net != oldWidget.net ||
      lookup != oldWidget.lookup ||
      covers != oldWidget.covers ||
      network != oldWidget.network ||
      matcher != oldWidget.matcher ||
      lock != oldWidget.lock;
}
