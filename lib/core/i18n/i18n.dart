import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';

/// Supported app languages.
enum AppLanguage { followSystem, english, chinese }

extension AppLanguageX on AppLanguage {
  String get code {
    switch (this) {
      case AppLanguage.followSystem:
        return 'system';
      case AppLanguage.english:
        return 'en';
      case AppLanguage.chinese:
        return 'zh';
    }
  }

  static AppLanguage fromCode(String? code) {
    switch (code) {
      case 'en':
        return AppLanguage.english;
      case 'zh':
        return AppLanguage.chinese;
      default:
        return AppLanguage.followSystem;
    }
  }

  Locale? toLocale(Locale? systemLocale) {
    switch (this) {
      case AppLanguage.english:
        return const Locale('en');
      case AppLanguage.chinese:
        return const Locale('zh');
      case AppLanguage.followSystem:
        return systemLocale;
    }
  }
}

/// Internationalization manager. Loads JSON translation bundles and resolves
/// localized strings with parameter substitution.
class I18n {
  I18n._(this._bundles, this._language, this._systemLocale);

  final Map<String, Map<String, String>> _bundles;
  AppLanguage _language;
  Locale _systemLocale;

  static const _supportedLocales = [
    Locale('en'),
    Locale('zh'),
  ];

  static List<Locale> get supportedLocales => _supportedLocales;

  static Future<I18n> load(AppLanguage language, Locale systemLocale) async {
    final bundles = <String, Map<String, String>>{};
    for (final locale in _supportedLocales) {
      final code = locale.languageCode;
      final json = await rootBundle.loadString('assets/i18n/$code.json');
      bundles[code] = Map<String, String>.from(jsonDecode(json));
    }
    return I18n._(bundles, language, systemLocale);
  }

  AppLanguage get language => _language;
  Locale get systemLocale => _systemLocale;

  Locale get effectiveLocale => _language.toLocale(_systemLocale) ?? const Locale('en');

  void update(AppLanguage language, Locale systemLocale) {
    _language = language;
    _systemLocale = systemLocale;
  }

  /// Translates [key] with optional [args] for placeholder substitution.
  /// Placeholders use the form `{name}` in the JSON bundle.
  String t(String key, [Map<String, String> args = const {}]) {
    final code = effectiveLocale.languageCode;
    final bundle = _bundles[code] ?? _bundles['en']!;
    var value = bundle[key] ?? _bundles['en']![key] ?? key;
    args.forEach((k, v) {
      value = value.replaceAll('{$k}', v);
    });
    return value;
  }
}
