import 'package:flutter/material.dart';

enum AppThemeMode { system, light, dark, amoled }

extension AppThemeModeLabels on AppThemeMode {
  String get label => switch (this) {
        AppThemeMode.system => 'Follow system',
        AppThemeMode.light => 'Light',
        AppThemeMode.dark => 'Dark',
        AppThemeMode.amoled => 'AMOLED black',
      };

  ThemeMode get materialMode => switch (this) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark || AppThemeMode.amoled => ThemeMode.dark,
      };
}

const Color _seed = Color(0xFF2E6B5E); // ledger green

ThemeData _base(ColorScheme scheme, {Color? scaffold}) => ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold ?? scheme.surface,
      visualDensity: VisualDensity.standard,
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 12),
      ),
    );

ThemeData lightTheme() => _base(ColorScheme.fromSeed(seedColor: _seed));

ThemeData darkTheme() => _base(
      ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark),
    );

/// Pure black surfaces: pixels are switched off on OLED screens.
ThemeData amoledTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: Brightness.dark,
  ).copyWith(
    surface: Colors.black,
    surfaceContainerLowest: Colors.black,
    surfaceContainerLow: const Color(0xFF070707),
    surfaceContainer: const Color(0xFF0D0D0D),
    surfaceContainerHigh: const Color(0xFF141414),
    surfaceContainerHighest: const Color(0xFF1B1B1B),
  );
  return _base(scheme, scaffold: Colors.black);
}
