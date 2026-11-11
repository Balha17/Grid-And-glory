import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/locale/locale_controller.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../match/match_flow.dart';

/// Home. Deliberately almost empty: one decision (which language), one action (play).
///
/// The language control is a two-segment switch showing **each language in its own
/// script**. Naming a language in the other language is the classic localization
/// mistake: an Arabic speaker looking for Arabic should see "العربية", not "Arabic".
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeControllerProvider);
    final l10n = AppLocalizations.of(context)!;
    final isArabic = locale.languageCode == 'ar';

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),

              // Both titles are always present. The app is bilingual; hiding one half of
              // its name depending on a setting is a strange thing to do.
              Text(
                l10n.appTitle,
                style: AppType.display(locale),
                textAlign: TextAlign.center,
                textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                isArabic ? 'Grid & Glory' : 'التحدي الكروي',
                style: AppType.title(locale).copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
                textDirection: isArabic ? TextDirection.ltr : TextDirection.rtl,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                l10n.appSubtitle,
                style: AppType.label(locale),
                textAlign: TextAlign.center,
              ),

              const Spacer(),

              LanguageSwitch(
                locale: locale,
                onChanged: (next) =>
                    ref.read(localeControllerProvider.notifier).set(next),
              ),

              const SizedBox(height: AppSpacing.xxl),

              SizedBox(
                height: 64,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const MatchFlowScreen(),
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.bgBase,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(AppRadii.md),
                    ),
                  ),
                  child: Text(
                    l10n.playOnline,
                    style: AppType.title(locale)
                        .copyWith(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: 58,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const MatchFlowScreen(playVsAi: true),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    side: const BorderSide(color: AppColors.accent),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(AppRadii.md),
                    ),
                  ),
                  child: Text(
                    l10n.playVsAi,
                    style: AppType.title(locale).copyWith(fontSize: 17),
                  ),
                ),
              ),

              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}

/// Two segments, each labelled in its own script, switching in place with no reload.
class LanguageSwitch extends StatelessWidget {
  const LanguageSwitch({
    super.key,
    required this.locale,
    required this.onChanged,
  });

  final Locale locale;
  final ValueChanged<Locale> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.bgSunken,
        borderRadius: const BorderRadius.all(AppRadii.pill),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _segment(context, const Locale('en'), 'English', TextDirection.ltr),
          _segment(context, const Locale('ar'), 'العربية', TextDirection.rtl),
        ],
      ),
    );
  }

  Widget _segment(
    BuildContext context,
    Locale value,
    String label,
    TextDirection labelDirection,
  ) {
    final selected = locale.languageCode == value.languageCode;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          onTap: () => onChanged(value),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: AppMotion.respecting(context, const Duration(milliseconds: 180)),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: selected ? AppColors.bgRaised : Colors.transparent,
              borderRadius: const BorderRadius.all(AppRadii.pill),
              border: Border.all(
                color: selected ? AppColors.accent : Colors.transparent,
                width: 1.5,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              // Each label keeps its own script direction even inside the other locale.
              textDirection: labelDirection,
              style: AppType.body(locale).copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppColors.textPrimary : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
