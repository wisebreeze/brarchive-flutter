import 'dart:io';
import 'package:flutter/material.dart';
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
          const Divider(),
          ListTile(
            leading: const Icon(Icons.code),
            title: Text(i18n.t('githubRepo')),
            subtitle: const Text('github.com/wisebreeze/brarchive-flutter'),
            onTap: () => _launchUrl('https://github.com/wisebreeze/brarchive-flutter'),
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

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
