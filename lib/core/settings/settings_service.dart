import 'package:shared_preferences/shared_preferences.dart';
import '../i18n/i18n.dart';
import '../theme/app_theme.dart';

/// Persists user preferences (language, theme mode, dynamic color, pack
/// options) using shared_preferences.
class SettingsService {
  static const _languageKey = 'app_language';
  static const _themeKey = 'app_theme_mode';
  static const _dynamicColorKey = 'app_dynamic_color';
  static const _packImagesKey = 'pack_images';
  static const _removeProcessedFilesKey = 'remove_processed_files';

  Future<AppLanguage> getLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return AppLanguageX.fromCode(prefs.getString(_languageKey));
  }

  Future<void> setLanguage(AppLanguage language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, language.code);
  }

  Future<AppThemeMode> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return AppThemeModeX.fromCode(prefs.getString(_themeKey));
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode.code);
  }

  Future<bool> getDynamicColor() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_dynamicColorKey) ?? true;
  }

  Future<void> setDynamicColor(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dynamicColorKey, enabled);
  }

  Future<bool> getPackImages() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_packImagesKey) ?? false;
  }

  Future<void> setPackImages(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_packImagesKey, enabled);
  }

  Future<bool> getRemoveProcessedFiles() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_removeProcessedFilesKey) ?? true;
  }

  Future<void> setRemoveProcessedFiles(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_removeProcessedFilesKey, enabled);
  }
}
