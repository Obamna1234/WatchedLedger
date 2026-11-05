import 'package:flutter/widgets.dart';

import '../data/covers/cover_cache.dart';
import '../data/db/database.dart';
import '../data/lookup/lookup_service.dart';
import 'net/net_client.dart';
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
    required super.child,
  });

  final AppDatabase db;
  final SettingsController settings;
  final NetClient net;
  final LookupService lookup;
  final CoverCache covers;

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
      covers != oldWidget.covers;
}
