import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_state.dart';
import '../../core/i18n/i18n.dart';
import '../../core/theme/app_theme.dart';

/// Settings screen with language, theme, and dynamic color options.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final i18n = state.i18n;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(i18n.t('settings')),
      ),
      body: ListView(
        children: [
          _sectionHeader(i18n.t('language'), cs),
          _buildLanguageSection(state, i18n),
          const SizedBox(height: 8),
          _sectionHeader(i18n.t('theme'), cs),
          _buildThemeSection(state, i18n),
          const SizedBox(height: 8),
          _sectionHeader(i18n.t('appearance'), cs),
          _buildDynamicColorTile(state, i18n),
          const SizedBox(height: 8),
          _sectionHeader(i18n.t('packOptions'), cs),
          _buildPackImagesTile(state, i18n),
          _buildRemoveProcessedTile(state, i18n),
          _buildSkipEmptyEntriesTile(state, i18n),
          const SizedBox(height: 8),
          _sectionHeader(i18n.t('storage'), cs),
          _buildClearCacheTile(state, i18n),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.code),
            title: Text(i18n.t('githubRepo')),
            subtitle: const Text('github.com/wisebreeze/brarchive-flutter'),
            onTap: () => _launchUrl('https://github.com/wisebreeze/brarchive-flutter'),
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(i18n.t('author')),
            subtitle: const Text('wisebreeze'),
            onTap: () => _launchUrl('https://github.com/wisebreeze'),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(i18n.t('license')),
            subtitle: const Text('Apache-2.0'),
            onTap: () => _showLicenseDialog(context, i18n),
          ),
        ],
      ),
    );
  }

  void _showLicenseDialog(BuildContext context, I18n i18n) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(i18n.t('license')),
        content: FutureBuilder<String>(
          future: rootBundle.loadString('assets/licenses/apache-2.0.txt'),
          builder: (context, snapshot) {
            return SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Text(
                  snapshot.data ?? 'Loading...',
                  style: const TextStyle(fontSize: 11, height: 1.4),
                ),
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(i18n.t('close')),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  Widget _buildLanguageSection(AppState state, I18n i18n) {
    return Column(
      children: [
        RadioListTile<AppLanguage>(
          value: AppLanguage.followSystem,
          groupValue: state.i18n.language,
          title: Text(i18n.t('followSystem')),
          onChanged: (v) => state.setLanguage(v!),
        ),
        RadioListTile<AppLanguage>(
          value: AppLanguage.english,
          groupValue: state.i18n.language,
          title: Text(i18n.t('english')),
          onChanged: (v) => state.setLanguage(v!),
        ),
        RadioListTile<AppLanguage>(
          value: AppLanguage.chinese,
          groupValue: state.i18n.language,
          title: Text(i18n.t('chinese')),
          onChanged: (v) => state.setLanguage(v!),
        ),
      ],
    );
  }

  Widget _buildThemeSection(AppState state, I18n i18n) {
    return Column(
      children: [
        RadioListTile<AppThemeMode>(
          value: AppThemeMode.followSystem,
          groupValue: state.themeMode,
          title: Text(i18n.t('themeFollowSystem')),
          onChanged: (v) => state.setThemeMode(v!),
        ),
        RadioListTile<AppThemeMode>(
          value: AppThemeMode.light,
          groupValue: state.themeMode,
          title: Text(i18n.t('themeLight')),
          onChanged: (v) => state.setThemeMode(v!),
        ),
        RadioListTile<AppThemeMode>(
          value: AppThemeMode.dark,
          groupValue: state.themeMode,
          title: Text(i18n.t('themeDark')),
          onChanged: (v) => state.setThemeMode(v!),
        ),
      ],
    );
  }

  Widget _buildDynamicColorTile(AppState state, I18n i18n) {
    final supported = _isDynamicColorSupported();
    return SwitchListTile(
      title: Text(i18n.t('dynamicColor')),
      subtitle: Text(
        supported
            ? i18n.t('dynamicColorDesc')
            : i18n.t('dynamicColorUnsupported'),
      ),
      value: supported && state.useDynamicColor,
      onChanged: supported
          ? (v) => state.setDynamicColor(v)
          : null,
    );
  }

  /// Dynamic color (Material You) requires Android 12+ (API 31).
  /// Not supported on Windows or other desktop platforms.
  bool _isDynamicColorSupported() {
    if (Platform.isAndroid) {
      return true; // The native side will check SDK version; Flutter can't
      // directly query it, so we allow the toggle and the theme builder
      // will fall back gracefully on older Android.
    }
    return false;
  }

  Widget _buildPackImagesTile(AppState state, I18n i18n) {
    return SwitchListTile(
      title: Text(i18n.t('packImages')),
      subtitle: Text(i18n.t('packImagesDesc')),
      value: state.packImages,
      onChanged: (v) => state.setPackImages(v),
    );
  }

  Widget _buildRemoveProcessedTile(AppState state, I18n i18n) {
    return SwitchListTile(
      title: Text(i18n.t('removeProcessedFiles')),
      subtitle: Text(i18n.t('removeProcessedFilesDesc')),
      value: state.removeProcessedFiles,
      onChanged: (v) => state.setRemoveProcessedFiles(v),
    );
  }

  Widget _buildSkipEmptyEntriesTile(AppState state, I18n i18n) {
    return SwitchListTile(
      title: Text(i18n.t('skipEmptyEntries')),
      subtitle: Text(i18n.t('skipEmptyEntriesDesc')),
      value: state.skipEmptyEntries,
      onChanged: (v) => state.setSkipEmptyEntries(v),
    );
  }

  Widget _buildClearCacheTile(AppState state, I18n i18n) {
    return ListTile(
      leading: const Icon(Icons.cleaning_services_outlined),
      title: Text(i18n.t('clearCache')),
      subtitle: Text(i18n.t('clearCacheDesc')),
      onTap: () => _clearCache(context, i18n),
    );
  }

  Future<void> _clearCache(BuildContext context, I18n i18n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(i18n.t('clearCache')),
        content: Text(i18n.t('clearCacheConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(i18n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(i18n.t('clear')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final cacheDir = await getTemporaryDirectory();
      if (cacheDir.existsSync()) {
        final size = _dirSize(cacheDir);
        cacheDir.deleteSync(recursive: true);
        cacheDir.createSync(recursive: true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(i18n.t('cacheCleared', {'size': _formatSize(size)}))),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(i18n.t('logError', {'error': e.toString()}))),
        );
      }
    }
  }

  int _dirSize(Directory dir) {
    var size = 0;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File) {
        size += entity.lengthSync();
      }
    }
    return size;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

