import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/locale/locale_controller.dart';
import 'core/theme/tokens.dart';
import 'features/home/home_screen.dart';
import 'l10n/app_localizations.dart';

/// The app.
///
/// `MaterialApp.locale` is the single source of direction: `WidgetsApp` derives
/// `Directionality` from the resolved locale, so every `Row`, `EdgeInsetsDirectional`
/// and `PositionedDirectional` below it flips for free. There is deliberately no
/// hand-rolled `Directionality` wrapper — a second source of truth is how a screen ends
/// up in the wrong direction after a toggle.
class GridAndGloryApp extends ConsumerWidget {
  const GridAndGloryApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeControllerProvider);

    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: _theme(),
      home: const HomeScreen(),
    );
  }

  ThemeData _theme() {
    const scheme = ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: AppColors.bgBase,
      surface: AppColors.bgRaised,
      onSurface: AppColors.textPrimary,
      error: AppColors.wrong,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bgBase,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
    );
  }
}
