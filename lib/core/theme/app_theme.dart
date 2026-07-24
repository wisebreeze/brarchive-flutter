import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';

/// Theme mode preference for the app.
enum AppThemeMode { followSystem, light, dark }

extension AppThemeModeX on AppThemeMode {
  String get code {
    switch (this) {
      case AppThemeMode.followSystem:
        return 'system';
      case AppThemeMode.light:
        return 'light';
      case AppThemeMode.dark:
        return 'dark';
    }
  }

  static AppThemeMode fromCode(String? code) {
    switch (code) {
      case 'light':
        return AppThemeMode.light;
      case 'dark':
        return AppThemeMode.dark;
      default:
        return AppThemeMode.followSystem;
    }
  }

  ThemeMode toThemeMode() {
    switch (this) {
      case AppThemeMode.followSystem:
        return ThemeMode.system;
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
    }
  }
}

/// Material 3 theme definitions for the app.
class AppTheme {
  AppTheme._();

  static const _seedColor = Color(0xFF6750A4);

  /// Synchronous fallback themes used before async dynamic color resolves.
  static ThemeData fallbackLight() => buildTheme(ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: Brightness.light,
      ));

  static ThemeData fallbackDark() => buildTheme(ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: Brightness.dark,
      ));

  /// Builds light theme. Uses dynamic color scheme if [dynamicColor] is true
  /// and the platform supports it (Android 12+).
  static Future<ThemeData> light({bool dynamicColor = true}) async {
    if (dynamicColor) {
      final systemColors = await DynamicColorPlugin.getCorePalette();
      if (systemColors != null) {
        return buildTheme(systemColors.toColorScheme(brightness: Brightness.light));
      }
    }
    return buildTheme(ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.light,
    ));
  }

  static Future<ThemeData> dark({bool dynamicColor = true}) async {
    if (dynamicColor) {
      final systemColors = await DynamicColorPlugin.getCorePalette();
      if (systemColors != null) {
        return buildTheme(systemColors.toColorScheme(brightness: Brightness.dark));
      }
    }
    return buildTheme(ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    ));
  }

  static ThemeData buildTheme(ColorScheme colorScheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: colorScheme.surface,
        surfaceTintColor: colorScheme.surfaceTint,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 3,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        color: colorScheme.surfaceContainerLow,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outline, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
