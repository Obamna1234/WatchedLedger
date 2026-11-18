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
      // Clear, easy-to-scan text: bold titles, softer details.
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        subtitleTextStyle: TextStyle(
          fontSize: 14,
          color: scheme.onSurfaceVariant,
        ),
      ),
      // The top bar and bottom bar sit apart from the list.
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surfaceContainer,
        scrolledUnderElevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontSize: 13,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: scheme.onSurface,
            )),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: const WidgetStatePropertyAll(
              TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? scheme.primary
                  : null),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? scheme.onPrimary
                  : scheme.onSurface),
        ),
      ),
    );

// contrastLevel 0.5: a little more contrast than the default, so text and
// controls stand out in both light and dark.
ThemeData lightTheme() =>
    _base(ColorScheme.fromSeed(seedColor: _seed, contrastLevel: 0.5));

ThemeData darkTheme() => _base(
      ColorScheme.fromSeed(
          seedColor: _seed, brightness: Brightness.dark, contrastLevel: 0.5),
    );

/// Pure black surfaces: pixels are switched off on OLED screens.
ThemeData amoledTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: Brightness.dark,
    contrastLevel: 0.5,
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
