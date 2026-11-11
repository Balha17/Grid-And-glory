import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/locale/locale_controller.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../match/match_flow.dart';

/// Premium football-inspired landing screen. All decoration is drawn locally, so
/// the first frame is complete even with no network connection.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeControllerProvider);
    final l10n = AppLocalizations.of(context)!;
    final isArabic = locale.languageCode == 'ar';

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _HomeAtmosphere(),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsetsDirectional.fromSTEB(22, 14, 22, 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight - 38),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const _BrandMark(size: 42),
                          const SizedBox(width: 10),
                          Text(
                            'GRID & GLORY',
                            style: AppType.label(locale).copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w900,
                              letterSpacing: isArabic ? 0 : 1.8,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsetsDirectional.symmetric(
                              horizontal: 11,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.bgRaised.withValues(alpha: 0.78),
                              borderRadius: const BorderRadius.all(AppRadii.pill),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    color: AppColors.correct,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  '1 VS 1',
                                  style: AppType.label(locale).copyWith(
                                    color: AppColors.textSecondary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            tooltip: isArabic ? 'اسم اللاعب' : 'Player nickname',
                            onPressed: () => _editPlayerName(context, ref, locale),
                            icon: const Icon(Icons.edit_rounded, color: AppColors.accent),
                          ),
                        ],
                      ),
                      const SizedBox(height: 26),
                      const Center(child: _HeroEmblem()),
                      const SizedBox(height: 17),
                      Text(
                        l10n.appTitle,
                        textAlign: TextAlign.center,
                        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
                        style: AppType.display(locale).copyWith(
                          fontSize: isArabic ? 31 : 34,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                          shadows: const [
                            Shadow(color: Color(0x6648A9FF), blurRadius: 24),
                          ],
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        isArabic ? 'GRID & GLORY' : 'التحدي الكروي',
                        textAlign: TextAlign.center,
                        textDirection: isArabic ? TextDirection.ltr : TextDirection.rtl,
                        style: AppType.title(locale).copyWith(
                          color: AppColors.accent,
                          fontSize: 17,
                          letterSpacing: isArabic ? 1.6 : 0,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        l10n.appSubtitle,
                        textAlign: TextAlign.center,
                        style: AppType.label(locale).copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _FeatureChip(
                            icon: Icons.bolt_rounded,
                            label: isArabic ? 'تحديات سريعة' : 'FAST DUELS',
                            locale: locale,
                          ),
                          _FeatureChip(
                            icon: Icons.smart_toy_rounded,
                            label: isArabic ? 'خصم ذكي' : 'AI RIVAL',
                            locale: locale,
                          ),
                          _FeatureChip(
                            icon: Icons.translate_rounded,
                            label: isArabic ? 'عربي • English' : 'ARABIC • ENGLISH',
                            locale: locale,
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      _SectionEyebrow(
                        locale: locale,
                        text: isArabic ? 'اختر ساحة المنافسة' : 'CHOOSE YOUR ARENA',
                      ),
                      const SizedBox(height: 12),
                      _ModeCard(
                        locale: locale,
                        title: l10n.playOnline,
                        subtitle: isArabic
                            ? 'ابحث عن لاعب، وسينضم الذكاء الاصطناعي عند الانتظار'
                            : 'Find a player — AI joins if matchmaking takes too long',
                        icon: Icons.public_rounded,
                        primary: true,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const MatchFlowScreen(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _ModeCard(
                        locale: locale,
                        title: l10n.playVsAi,
                        subtitle: isArabic
                            ? 'ابدأ مباراة فوراً ضد خصم ذكي'
                            : 'Start instantly against an AI opponent',
                        icon: Icons.smart_toy_rounded,
                        primary: false,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const MatchFlowScreen(playVsAi: true),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      LanguageSwitch(
                        locale: locale,
                        onChanged: (next) =>
                            ref.read(localeControllerProvider.notifier).set(next),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        isArabic
                            ? 'المعرفة • السرعة • المجد'
                            : 'KNOWLEDGE  •  SPEED  •  GLORY',
                        textAlign: TextAlign.center,
                        style: AppType.label(locale).copyWith(
                          color: AppColors.textSecondary.withValues(alpha: 0.72),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: isArabic ? 0 : 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


Future<void> _editPlayerName(BuildContext context, WidgetRef ref, Locale locale) async {
  final prefs = ref.read(sharedPreferencesProvider);
  final controller = TextEditingController(text: prefs.getString('player_nickname') ?? '');
  final isArabic = locale.languageCode == 'ar';
  final value = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.bgRaised,
      title: Text(isArabic ? 'اختر لقبك' : 'Choose your nickname',
          style: AppType.title(locale).copyWith(color: AppColors.textPrimary)),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 18,
        textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        style: AppType.body(locale).copyWith(color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: isArabic ? 'لقب يظهر للمنافس' : 'Shown to your opponent',
          hintStyle: AppType.label(locale).copyWith(color: AppColors.textSecondary),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(isArabic ? 'إلغاء' : 'Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
          child: Text(isArabic ? 'حفظ' : 'Save'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (value == null) return;
  final clean = value.trim();
  if (clean.length < 2) return;
  await prefs.setString('player_nickname', String.fromCharCodes(clean.runes.take(18)));
}

class _HomeAtmosphere extends StatelessWidget {
  const _HomeAtmosphere();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _AtmospherePainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _AtmospherePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF101F35), Color(0xFF0B1424), Color(0xFF080E19)],
        ).createShader(rect),
    );

    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF1677B8).withValues(alpha: 0.24),
          const Color(0xFF1677B8).withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width * 0.5, size.height * 0.34),
        radius: size.width * 0.76,
      ));
    canvas.drawRect(rect, glow);

    final field = Paint()
      ..color = const Color(0xFF55B98A).withValues(alpha: 0.075)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final fieldRect = Rect.fromCenter(
      center: Offset(size.width * 0.5, size.height * 0.39),
      width: size.width * 0.88,
      height: size.width * 0.88,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(fieldRect, const Radius.circular(28)),
      field,
    );
    canvas.drawLine(
      Offset(fieldRect.left, fieldRect.center.dy),
      Offset(fieldRect.right, fieldRect.center.dy),
      field,
    );
    canvas.drawCircle(fieldRect.center, fieldRect.width * 0.19, field);
    canvas.drawCircle(fieldRect.center, 3, Paint()..color = field.color);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(fieldRect.left, fieldRect.center.dy - 48, 30, 96),
        const Radius.circular(8),
      ),
      field,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(fieldRect.right - 30, fieldRect.center.dy - 48, 30, 96),
        const Radius.circular(8),
      ),
      field,
    );

    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.025)
      ..strokeWidth = 0.7;
    for (var x = 0.0; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
  }

  @override
  bool shouldRepaint(_AtmospherePainter oldDelegate) => false;
}

/// Shield + pitch-grid mark, drawn as vector artwork (crisp at every density).
class _BrandMark extends StatelessWidget {
  const _BrandMark({this.size = 52});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _BrandMarkPainter()),
      );
}

class _BrandMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 52;
    canvas.save();
    canvas.scale(scale);
    final shield = Path()
      ..moveTo(26, 2)
      ..lineTo(47, 10)
      ..lineTo(44, 32)
      ..quadraticBezierTo(41, 43, 26, 50)
      ..quadraticBezierTo(11, 43, 8, 32)
      ..lineTo(5, 10)
      ..close();
    canvas.drawShadow(shield, Colors.black.withValues(alpha: 0.45), 5, true);
    canvas.drawPath(
      shield,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFFFD978), Color(0xFFDB8C27)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(const Rect.fromLTWH(5, 2, 42, 48)),
    );
    final inner = Path()
      ..moveTo(26, 7)
      ..lineTo(42, 13)
      ..lineTo(39, 31)
      ..quadraticBezierTo(37, 40, 26, 45)
      ..quadraticBezierTo(15, 40, 13, 31)
      ..lineTo(10, 13)
      ..close();
    canvas.drawPath(inner, Paint()..color = const Color(0xFF10233A));
    final line = Paint()
      ..color = const Color(0xFF75D6B0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7;
    canvas.drawRect(const Rect.fromLTWH(16, 15, 20, 20), line);
    canvas.drawLine(const Offset(26, 15), const Offset(26, 35), line);
    canvas.drawLine(const Offset(16, 25), const Offset(36, 25), line);
    canvas.drawCircle(const Offset(26, 25), 5, Paint()..color = AppColors.accent);
    canvas.drawCircle(
      const Offset(26, 25),
      5,
      Paint()
        ..color = const Color(0xFF10233A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BrandMarkPainter oldDelegate) => false;
}

class _HeroEmblem extends StatelessWidget {
  const _HeroEmblem();

  @override
  Widget build(BuildContext context) => Container(
        width: 154,
        height: 154,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              const Color(0xFF245B75).withValues(alpha: 0.55),
              const Color(0xFF14243A).withValues(alpha: 0.12),
            ],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2D9DD2).withValues(alpha: 0.13),
              blurRadius: 34,
              spreadRadius: 3,
            ),
          ],
        ),
        child: const Center(child: _BrandMark(size: 104)),
      );
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({
    required this.icon,
    required this.label,
    required this.locale,
  });

  final IconData icon;
  final String label;
  final Locale locale;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.bgRaised.withValues(alpha: 0.72),
          borderRadius: const BorderRadius.all(AppRadii.pill),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.9)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.accent),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppType.label(locale).copyWith(
                color: AppColors.textSecondary,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: locale.languageCode == 'ar' ? 0 : 0.7,
              ),
            ),
          ],
        ),
      );
}

class _SectionEyebrow extends StatelessWidget {
  const _SectionEyebrow({required this.locale, required this.text});

  final Locale locale;
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        textAlign: locale.languageCode == 'ar' ? TextAlign.right : TextAlign.left,
        style: AppType.label(locale).copyWith(
          color: AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: locale.languageCode == 'ar' ? 0 : 1.5,
        ),
      );
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.locale,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.primary,
    required this.onTap,
  });

  final Locale locale;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = primary ? AppColors.accent.withValues(alpha: 0.72) : AppColors.border;
    return Material(
      color: primary ? const Color(0xFF182B40) : const Color(0xCC111D2F),
      borderRadius: const BorderRadius.all(AppRadii.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(AppRadii.lg),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(AppRadii.lg),
            border: Border.all(color: borderColor, width: primary ? 1.4 : 1),
            gradient: primary
                ? const LinearGradient(
                    colors: [Color(0xFF243B50), Color(0xFF142337)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.all(17),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: primary ? 0.16 : 0.09),
                    borderRadius: const BorderRadius.all(AppRadii.md),
                  ),
                  child: Icon(
                    icon,
                    color: AppColors.accent,
                    size: 25,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppType.title(locale).copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: AppType.label(locale).copyWith(fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  locale.languageCode == 'ar'
                      ? Icons.arrow_back_rounded
                      : Icons.arrow_forward_rounded,
                  color: primary ? AppColors.accent : AppColors.textSecondary,
                  size: 20,
                ),
              ],
            ),
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
        color: AppColors.bgSunken.withValues(alpha: 0.85),
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
