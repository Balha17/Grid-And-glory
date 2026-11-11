import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:async';

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
      home: const _LaunchExperience(),
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


class _LaunchExperience extends StatefulWidget {
  const _LaunchExperience();
  @override
  State<_LaunchExperience> createState() => _LaunchExperienceState();
}
class _LaunchExperienceState extends State<_LaunchExperience> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade, _scale;
  Timer? _timer;
  bool _showHome = false;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1150));
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scale = Tween<double>(begin: .88, end: 1).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _controller.forward();
    _timer = Timer(const Duration(milliseconds: 1850), () { if (mounted) setState(() => _showHome = true); });
  }
  @override
  void dispose() { _timer?.cancel(); _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (_showHome) return const HomeScreen();
    final ar = Localizations.localeOf(context).languageCode == 'ar';
    return Scaffold(backgroundColor: const Color(0xFF071321), body: Stack(fit: StackFit.expand, children: [
      const DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(center: Alignment(0, -.18), radius: .95,
        colors: [Color(0xFF193B55), Color(0xFF0C1D30), Color(0xFF071321)]))),
      FadeTransition(opacity: _fade, child: ScaleTransition(scale: _scale, child: Center(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: SvgPicture.asset('assets/images/launch_art.svg', fit: BoxFit.contain, width: double.infinity))))),
      Positioned(left: 0, right: 0, bottom: 44, child: FadeTransition(opacity: _fade, child: Column(children: [
        const Text('GRID & GLORY', style: TextStyle(color: Color(0xFFFFD166), fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: 4)),
        const SizedBox(height: 8),
        Text(ar ? 'المعرفة • السرعة • المجد' : 'KNOWLEDGE  •  SPEED  •  GLORY',
          style: const TextStyle(color: Color(0xFFB5C7D8), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
      ]))),
    ]));
  }
}
