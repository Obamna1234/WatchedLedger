import 'package:flutter/widgets.dart';

import '../data/db/database.dart';
import 'settings.dart';

/// Makes the database and settings available to every screen.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.db,
    required this.settings,
    required super.child,
  });

  final AppDatabase db;
  final SettingsController settings;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope above this widget');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      db != oldWidget.db || settings != oldWidget.settings;
}
