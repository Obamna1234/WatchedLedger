import 'package:flutter/material.dart';

import 'core/app_scope.dart';
import 'core/settings.dart';
import 'core/theme.dart';
import 'data/db/database.dart';
import 'features/home/home_page.dart';

class WatchedLedgerApp extends StatelessWidget {
  const WatchedLedgerApp({super.key, required this.db, required this.settings});

  final AppDatabase db;
  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      db: db,
      settings: settings,
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final mode = settings.themeMode;
          return MaterialApp(
            title: 'WatchedLedger',
            debugShowCheckedModeBanner: false,
            theme: lightTheme(),
            darkTheme: mode == AppThemeMode.amoled ? amoledTheme() : darkTheme(),
            themeMode: mode.materialMode,
            home: const HomePage(),
          );
        },
      ),
    );
  }
}
