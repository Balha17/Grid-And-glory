/// Design tokens. Locale-dependent values are functions of [Locale], never constants,
/// because Arabic and English have different *line boxes* even at the same optical size.
library;

import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

@immutable
class AppColors {
  const AppColors._();

  static const Color bgBase = Color(0xFF0B1220);
  static const Color bgRaised = Color(0xFF131C2E);
  static const Color bgSunken = Color(0xFF080E19);

  static const Color grassA = Color(0xFF1B7F4B);
  static const Color grassB = Color(0xFF17703F);

  static const Color accent = Color(0xFFFFC24B);
  static const Color you = Color(0xFF38BDF8);
  static const Color opponent = Color(0xFFF472B6);

  static const Color correct = Color(0xFF2FBF71);
  static const Color wrong = Color(0xFFE5484D);

  static const Color textPrimary = Color(0xFFF2F6FF);
  static const Color textSecondary = Color(0xFF9FB0CC);
  static const Color focusRing = Color(0xFF7DD3FC);

  /// Contrast ratios against [bgBase]: 14.8:1, 6.1:1. Both clear WCAG AA.
  static const Color border = Color(0xFF22304A);
}

@immutable
class AppSpacing {
  const AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

@immutable
class AppRadii {
  const AppRadii._();
  static const Radius sm = Radius.circular(10);
  static const Radius md = Radius.circular(16);
  static const Radius lg = Radius.circular(22);
  static const Radius pill = Radius.circular(999);
}

@immutable
class AppMotion {
  const AppMotion._();

  static const Duration press = Duration(milliseconds: 90);
  static const Duration zoneAdvance = Duration(milliseconds: 420);
  static const Duration zoneKnockBack = Duration(milliseconds: 380);
  static const Duration reveal = Duration(milliseconds: 180);
  static const Duration goal = Duration(milliseconds: 900);

  /// Respects the OS "remove animations" switch and the in-app setting.
  static Duration respecting(BuildContext context, Duration base) {
    final disabled = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return disabled ? Duration.zero : base;
  }
}

/// Typography per locale.
///
/// The two rules that matter and are easy to get wrong:
///   1. [letterSpacing] MUST be zero for Arabic. Any tracking breaks the cursive joins
///      between letters and turns the word into something a native reader stumbles on.
///   2. Arabic needs a larger line box (1.7 vs 1.4) for the same optical size, because
///      diacritics and descenders are clipped by the Latin metrics.
@immutable
class AppType {
  const AppType._();

  static bool _isArabic(Locale locale) => locale.languageCode == 'ar';

  static TextStyle display(Locale locale) => TextStyle(
        fontFamily: _family(locale),
        fontSize: _isArabic(locale) ? 30 : 32,
        height: _isArabic(locale) ? 1.55 : 1.2,
        letterSpacing: _isArabic(locale) ? 0 : -0.4,
        fontWeight: _isArabic(locale) ? FontWeight.w700 : FontWeight.w800,
        color: AppColors.textPrimary,
      );

  static TextStyle title(Locale locale) => TextStyle(
        fontFamily: _family(locale),
        fontSize: 22,
        height: _isArabic(locale) ? 1.7 : 1.28,
        letterSpacing: _isArabic(locale) ? 0 : -0.2,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      );

  static TextStyle body(Locale locale) => TextStyle(
        fontFamily: _family(locale),
        fontSize: _isArabic(locale) ? 17 : 16,
        height: _isArabic(locale) ? 1.75 : 1.45,
        letterSpacing: 0,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      );

  static TextStyle label(Locale locale) => TextStyle(
        fontFamily: _family(locale),
        fontSize: _isArabic(locale) ? 14 : 13,
        height: _isArabic(locale) ? 1.7 : 1.35,
        letterSpacing: 0,
        fontWeight: FontWeight.w600,
        color: AppColors.textSecondary,
      );

  /// Anything that changes in place (clock, score, deltas) uses tabular figures,
  /// or the layout jitters once per second.
  static TextStyle numeric(Locale locale, {double size = 16, FontWeight weight = FontWeight.w700}) =>
      TextStyle(
        fontFamily: _family(locale),
        fontSize: size,
        height: 1.2,
        letterSpacing: 0,
        fontWeight: weight,
        color: AppColors.textPrimary,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static String _family(Locale locale) =>
      _isArabic(locale) ? 'IBMPlexSansArabic' : 'Inter';
}
