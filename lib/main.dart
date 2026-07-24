import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'core/i18n/i18n.dart';
import 'core/settings/settings_service.dart';
import 'core/theme/app_theme.dart';
import 'ui/screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BrarchiveApp());
}

class BrarchiveApp extends StatefulWidget {
  const BrarchiveApp({super.key});

  @override
  State<BrarchiveApp> createState() => _BrarchiveAppState();
}

class _BrarchiveAppState extends State<BrarchiveApp> with WidgetsBindingObserver {
  late final AppState _appState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appState = AppState(SettingsService());
    _initLocale();
  }

  void _initLocale() {
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    _appState.init(locale);
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    final locale = locales?.firstOrNull ?? const Locale('en');
    _appState.onLocaleChanged(locale);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _appState,
      child: ListenableBuilder(
        listenable: _appState,
        builder: (context, _) {
          if (!_appState.initialized) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              home: const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              ),
            );
          }
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: _appState.i18n.t('appTitle'),
            locale: _appState.i18n.effectiveLocale,
            supportedLocales: I18n.supportedLocales,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: _appState.themeMode.toThemeMode(),
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
