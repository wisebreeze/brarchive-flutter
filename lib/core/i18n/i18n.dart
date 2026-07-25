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
      try {
        final json = await rootBundle.loadString('assets/i18n/$code.json');
        bundles[code] = Map<String, String>.from(jsonDecode(json));
      } catch (e) {
        // Fallback: empty bundle, t() will return the key
        bundles[code] = {};
      }
    }
    // Ensure 'en' always has content as the ultimate fallback
    if (bundles['en']?.isEmpty ?? true) {
      bundles['en'] = _fallbackEn;
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

/// Hardcoded English fallback used when the JSON asset cannot be loaded
/// (e.g. asset bundle issues in certain release builds).
const Map<String, String> _fallbackEn = {
  'appTitle': 'BR Archive',
  'inputLabel': 'Input file',
  'inputHint': 'Select a .zip or .mcpack file',
  'outputLabel': 'Output directory',
  'outputHint': 'Defaults to Downloads folder',
  'browse': 'Browse',
  'pack': 'Pack',
  'unpack': 'Unpack',
  'console': 'Console',
  'consoleEmpty': 'No output yet. Operations will be logged here.',
  'more': 'More',
  'language': 'Language',
  'followSystem': 'Follow system',
  'english': 'English',
  'chinese': '简体中文',
  'theme': 'Theme',
  'themeFollowSystem': 'Follow system',
  'themeLight': 'Light',
  'themeDark': 'Dark',
  'selectFile': 'Select file',
  'selectDirectory': 'Select directory',
  'statusReady': 'Ready',
  'statusProcessing': 'Processing...',
  'statusDone': 'Done',
  'statusError': 'Error',
  'errNoInput': 'Please select an input file',
  'errNoOutput': 'Please select an output directory',
  'errInvalidInput': 'Input must be a .zip or .mcpack file',
  'errInputNotExist': 'Input file does not exist',
  'errOutputNotExist': 'Output directory does not exist',
  'logStarted': 'Started: {action} on {file}',
  'logExtracting': 'Extracting archive...',
  'logNoBrarchiveFound': 'No __brarchive folders found, copying as-is',
  'logFoundBrarchive': 'Found {count} __brarchive folder(s)',
  'logDeserializing': 'Deserializing {file}...',
  'logSerializing': 'Serializing {count} file(s) into {output}',
  'logWritingFile': 'Writing {file} ({size} bytes)',
  'logZipping': 'Creating output archive...',
  'logDone': 'Done in {duration}',
  'logError': 'Error: {error}',
  'logOutputAt': 'Output saved to: {path}',
  'logScanning': 'Scanning for target files (.json, .json5, .ui)...',
  'logFoundTargets': 'Found {count} target file(s) in {dir}',
  'logCreatingBrarchive': 'Creating __brarchive folder',
  'logRemovingOriginal': 'Removing original target files',
  'logCleaningEmptyDirs': 'Cleaning empty directories',
  'logFoundBrarchiveFiles': 'Found {count} .brarchive file(s)',
  'logRestoringFiles': 'Restoring files from {file}',
  'logRestoredFiles': 'Restored {count} file(s)',
  'logRemovingBrarchive': 'Removing __brarchive folder',
  'actionPack': 'Pack',
  'actionUnpack': 'Unpack',
  'settings': 'Settings',
  'githubRepo': 'GitHub Repository',
  'appearance': 'Appearance',
  'dynamicColor': 'Dynamic color',
  'dynamicColorDesc': 'Use system wallpaper colors (Android 12+)',
  'dynamicColorUnsupported': 'Not supported on this platform',
  'permissionRequired': 'Storage permission required',
  'permissionMessage': 'This app needs storage permission to access the selected file or directory. Please grant the permission in system settings.',
  'cancel': 'Cancel',
  'grant': 'Grant',
  'errPermissionDenied': 'Storage permission denied. Cannot proceed.',
  'author': 'Author',
  'license': 'License',
  'close': 'Close',
  'packOptions': 'Pack options',
  'packImages': 'Pack images',
  'packImagesDesc': 'Include .png/.jpg/.jpeg/.tga files in brarchive',
  'removeProcessedFiles': 'Delete original files',
  'removeProcessedFilesDesc': 'Remove source files after packing into brarchive',
  'skipEmptyEntries': 'Skip empty entries',
  'skipEmptyEntriesDesc': "Don't restore 0-byte entries from brarchive over existing files",
  'utf8Only': 'UTF-8 only',
  'utf8OnlyDesc': 'Skip files that are not valid UTF-8 during packing',
  'storage': 'Storage',
  'clearCache': 'Clear cache',
  'clearCacheDesc': 'Delete temporary files created by the app',
  'clearCacheConfirm': 'Are you sure you want to clear the cache? This will remove temporary files.',
  'clear': 'Clear',
  'cacheCleared': 'Cache cleared ({size} freed)',
  'clearConsole': 'Clear console',
  'shareLogs': 'Share logs',
};
