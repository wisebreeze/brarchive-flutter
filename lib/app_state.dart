import 'package:flutter/material.dart';
import '../core/i18n/i18n.dart';
import '../core/settings/settings_service.dart';
import '../core/theme/app_theme.dart';

/// Central app state: i18n, theme mode, dynamic color, and pack options.
///
/// Notifies listeners when any setting changes so the MaterialApp and
/// converter can rebuild with the new configuration.
class AppState extends ChangeNotifier {
  AppState(this._settings);

  final SettingsService _settings;

  late I18n _i18n;
  AppThemeMode _themeMode = AppThemeMode.followSystem;
  bool _useDynamicColor = true;
  bool _packImages = false;
  bool _removeProcessedFiles = true;
  bool _initialized = false;

  I18n get i18n => _i18n;
  AppThemeMode get themeMode => _themeMode;
  bool get useDynamicColor => _useDynamicColor;
  bool get packImages => _packImages;
  bool get removeProcessedFiles => _removeProcessedFiles;
  bool get initialized => _initialized;

  Future<void> init(Locale systemLocale) async {
    try {
      final language = await _settings.getLanguage();
      final themeMode = await _settings.getThemeMode();
      final dynamicColor = await _settings.getDynamicColor();
      final packImages = await _settings.getPackImages();
      final removeProcessed = await _settings.getRemoveProcessedFiles();
      _i18n = await I18n.load(language, systemLocale);
      _themeMode = themeMode;
      _useDynamicColor = dynamicColor;
      _packImages = packImages;
      _removeProcessedFiles = removeProcessed;
    } catch (e) {
      _i18n = await I18n.load(AppLanguage.followSystem, systemLocale);
      _themeMode = AppThemeMode.followSystem;
      _useDynamicColor = true;
      _packImages = false;
      _removeProcessedFiles = true;
    }
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

  Future<void> setDynamicColor(bool enabled) async {
    await _settings.setDynamicColor(enabled);
    _useDynamicColor = enabled;
    notifyListeners();
  }

  Future<void> setPackImages(bool enabled) async {
    await _settings.setPackImages(enabled);
    _packImages = enabled;
    notifyListeners();
  }

  Future<void> setRemoveProcessedFiles(bool enabled) async {
    await _settings.setRemoveProcessedFiles(enabled);
    _removeProcessedFiles = enabled;
    notifyListeners();
  }

  /// Called by the WidgetsBindingObserver when the platform locale changes.
  void onLocaleChanged(Locale locale) => _updateSystemLocale(locale);
}
