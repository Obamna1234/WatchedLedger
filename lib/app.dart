import 'package:flutter/material.dart';

import 'core/app_scope.dart';
import 'core/net/net_client.dart';
import 'core/settings.dart';
import 'core/theme.dart';
import 'data/covers/cover_cache.dart';
import 'data/db/database.dart';
import 'data/lookup/lookup_service.dart';
import 'features/home/home_page.dart';

/// Everything created once at startup after the database opens.
class AppServices {
  const AppServices({
    required this.db,
    required this.settings,
    required this.net,
    required this.lookup,
    required this.covers,
  });

  final AppDatabase db;
  final SettingsController settings;
  final NetClient net;
  final LookupService lookup;
  final CoverCache covers;
}

class WatchedLedgerApp extends StatelessWidget {
  const WatchedLedgerApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final settings = services.settings;
    return AppScope(
      db: services.db,
      settings: settings,
      net: services.net,
      lookup: services.lookup,
      covers: services.covers,
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
