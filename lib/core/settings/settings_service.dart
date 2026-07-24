import 'package:shared_preferences/shared_preferences.dart';
import '../i18n/i18n.dart';
import '../theme/app_theme.dart';

/// Persists user preferences (language and theme mode) using shared_preferences.
class SettingsService {
  static const _languageKey = 'app_language';
  static const _themeKey = 'app_theme_mode';

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
}
