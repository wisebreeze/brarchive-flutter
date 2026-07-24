import 'package:flutter/material.dart';
import '../core/i18n/i18n.dart';
import '../core/settings/settings_service.dart';
import '../core/theme/app_theme.dart';

/// Central app state: i18n, theme mode, and processing status.
///
/// Notifies listeners when language or theme changes so the MaterialApp
/// can rebuild with the new locale / theme.
class AppState extends ChangeNotifier {
  AppState(this._settings);

  final SettingsService _settings;

  late I18n _i18n;
  AppThemeMode _themeMode = AppThemeMode.followSystem;
  bool _initialized = false;

  I18n get i18n => _i18n;
  AppThemeMode get themeMode => _themeMode;
  bool get initialized => _initialized;

  Future<void> init(Locale systemLocale) async {
    final language = await _settings.getLanguage();
    final themeMode = await _settings.getThemeMode();
    _i18n = await I18n.load(language, systemLocale);
    _themeMode = themeMode;
    _initialized = true;
    notifyListeners();
  }

  void _updateSystemLocale(Locale locale) {
    if (!_initialized) return;
    _i18n.update(_i18n.language, locale);
    notifyListeners();
  }

  Future<void> setLanguage(AppLanguage language) async {
    await _settings.setLanguage(language);
    _i18n.update(language, _i18n.systemLocale);
    notifyListeners();
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    await _settings.setThemeMode(mode);
    _themeMode = mode;
    notifyListeners();
  }

  /// Called by the WidgetsBindingObserver when the platform locale changes.
  void onLocaleChanged(Locale locale) => _updateSystemLocale(locale);
}
