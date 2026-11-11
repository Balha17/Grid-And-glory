import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/bidi.dart';
import '../../core/theme/tokens.dart';
import '../../l10n/app_localizations.dart';
import 'match_view_model.dart';
import 'widgets/answer_button.dart';
import 'widgets/pitch_viewport.dart';

/// The match screen: pitch on top 40%, quiz on bottom 60%, one thumb.
///
/// The split is computed from the *available* height inside `SafeArea`, so a device
/// with a taller notch does not silently give the pitch more room than the quiz.
class MatchScreen extends StatelessWidget {
  const MatchScreen({
    super.key,
    required this.state,
    required this.locale,
    required this.onAnswer,
    this.onForfeit,
  });

  final MatchUiState state;
  final Locale locale;
  final ValueChanged<String> onAnswer;
  final VoidCallback? onForfeit;

  static const double pitchFraction = 0.40;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        bottom: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final pitchHeight = constraints.maxHeight * pitchFraction;
            final quizHeight = constraints.maxHeight - pitchHeight;

            return Stack(
              children: [
                Column(
                  children: [
                    SizedBox(
                      height: pitchHeight,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: PitchViewport(
                              yourZone: state.yourZone,
                              opponentZone: state.opponentZone,
                              youHaveBall: state.youHaveBall,
                              locale: locale,
                              goalFlash: state.goalFlash,
                            ),
                          ),
                          // HUD overlays the pitch instead of sitting above it: the pitch
                          // stays a true 40% rather than 40% minus chrome.
                          PositionedDirectional(
                            top: 0,
                            start: 0,
                            end: 0,
                            child: _MatchHud(state: state, locale: locale, l10n: l10n, onForfeit: onForfeit),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: quizHeight,
                      child: _QuizPanel(
                        state: state,
                        locale: locale,
                        l10n: l10n,
                        onAnswer: onAnswer,
                      ),
                    ),
                  ],
                ),
                if (state.phase == 'half_time')
                  Positioned.fill(
                    child: _HalfTimeOverlay(
                      locale: locale,
                      l10n: l10n,
                      yourGoals: state.yourGoals,
                      opponentGoals: state.opponentGoals,
                    ),
                  ),
                if (!state.opponentConnected)
                  PositionedDirectional(
                    top: AppSpacing.sm,
                    start: AppSpacing.lg,
                    end: AppSpacing.lg,
                    child: _Banner(
                      text: l10n.opponentLeft,
                      locale: locale,
                      tone: AppColors.accent,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.locale, required this.tone});

  final String text;
  final Locale locale;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.bgSunken.withValues(alpha: 0.94),
        borderRadius: const BorderRadius.all(AppRadii.pill),
        border: Border.all(color: tone.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off, size: 16, color: tone),
          const SizedBox(width: AppSpacing.sm),
          Flexible(child: Text(text, style: AppType.label(locale).copyWith(color: tone))),
        ],
      ),
    );
  }
}

class _MatchHud extends StatelessWidget {
  const _MatchHud({required this.state, required this.locale, required this.l10n, this.onForfeit});

  final MatchUiState state;
  final Locale locale;
  final AppLocalizations l10n;
  final VoidCallback? onForfeit;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topCenter,
          end: AlignmentDirectional.bottomCenter,
          colors: [
            AppColors.bgBase.withValues(alpha: 0.85),
            AppColors.bgBase.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: Row(
        children: [
          // Possession dot: a filled/empty shape, so it survives colour-blindness.
          AnimatedContainer(
            duration: AppMotion.press,
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: state.youHaveBall ? AppColors.you : Colors.transparent,
              border: Border.all(color: AppColors.you.withValues(alpha: 0.6)),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          ScoreLine(
            yourGoals: state.yourGoals,
            opponentGoals: state.opponentGoals,
            locale: locale,
          ),
          const Spacer(),
          Text(l10n.matchHalf(state.half), style: AppType.label(locale)),
          if (onForfeit != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: locale.languageCode == 'ar' ? 'انسحاب' : 'Forfeit match',
              onPressed: onForfeit,
              icon: const Icon(Icons.flag_rounded, color: AppColors.wrong, size: 19),
            ),
        ],
      ),
    );
  }
}

/// The ring always sweeps clockwise. A counter-clockwise clock is a different
/// metaphor, not a translated one — see docs/04-ui-ux-spec.md §5.2.
class _TimerChip extends StatefulWidget {
  const _TimerChip({required this.seconds, required this.locale});

  final int seconds;
  final Locale locale;

  @override
  State<_TimerChip> createState() => _TimerChipState();
}

class _TimerChipState extends State<_TimerChip> {
  Timer? _ticker;
  late int _seconds;

  @override
  void initState() {
    super.initState();
    _seconds = widget.seconds;
    _startTicker();
  }

  @override
  void didUpdateWidget(covariant _TimerChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seconds != widget.seconds) {
      _seconds = widget.seconds;
      _startTicker();
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    if (_seconds <= 0) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _seconds <= 1) {
        timer.cancel();
        if (mounted) setState(() => _seconds = 0);
        return;
      }
      setState(() => _seconds -= 1);
      // Audible final-five-second ticks and stronger haptics near the deadline.
      if (_seconds <= 5 && _seconds > 0) {
        SystemSound.play(_seconds <= 3 ? SystemSoundType.alert : SystemSoundType.click);
      }
      if (_seconds <= 3 && _seconds > 0) HapticFeedback.heavyImpact();
      if (_seconds <= 2 && _seconds > 0) {
        Future<void>.delayed(const Duration(milliseconds: 180), () {
          if (mounted && _seconds <= 2) SystemSound.play(SystemSoundType.alert);
        });
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = _seconds;
    final locale = widget.locale;
    final urgent = seconds <= 3;
    return Semantics(
      label: '$seconds',
      child: SizedBox(
        width: 44,
        height: 44,
        child: Stack(
          alignment: AlignmentDirectional.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween<double>(end: (seconds / 9).clamp(0, 1).toDouble()),
              duration: const Duration(milliseconds: 300),
              builder: (context, value, _) => CustomPaint(
                size: const Size(40, 40),
                painter: _RingPainter(progress: value, urgent: urgent),
              ),
            ),
            Text(
              isoNum(seconds),
              style: AppType.numeric(locale, size: 14, weight: FontWeight.w800)
                  .copyWith(color: urgent ? AppColors.wrong : AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.urgent});

  final double progress;
  final bool urgent;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = AppColors.border;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = urgent ? AppColors.wrong : AppColors.accent;

    canvas.drawCircle(rect.center, size.width / 2 - 2, base);
    // -pi/2 start, positive sweep => clockwise in every locale.
    canvas.drawArc(
      Rect.fromCircle(center: rect.center, radius: size.width / 2 - 2),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.urgent != urgent;
}

class _ShootBanner extends StatelessWidget {
  const _ShootBanner({
    required this.locale,
    required this.l10n,
    required this.shooting,
  });

  final Locale locale;
  final AppLocalizations l10n;
  final bool shooting;

  @override
  Widget build(BuildContext context) {
    final tone = shooting ? AppColors.accent : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: const BorderRadius.all(AppRadii.sm),
        border: Border.all(color: tone.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(shooting ? Icons.sports_soccer : Icons.shield_outlined, size: 18, color: tone),
          const SizedBox(width: AppSpacing.sm),
          Text(
            shooting ? l10n.shootingChance : l10n.defending,
            style: AppType.label(locale).copyWith(color: tone, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _HalfTimeOverlay extends StatelessWidget {
  const _HalfTimeOverlay({
    required this.locale,
    required this.l10n,
    required this.yourGoals,
    required this.opponentGoals,
  });

  final Locale locale;
  final AppLocalizations l10n;
  final int yourGoals;
  final int opponentGoals;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.bgBase.withValues(alpha: 0.86),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.halfTime, style: AppType.display(locale)),
            const SizedBox(height: AppSpacing.lg),
            ScoreLine(
              yourGoals: yourGoals,
              opponentGoals: opponentGoals,
              locale: locale,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuizPanel extends StatelessWidget {
  const _QuizPanel({
    required this.state,
    required this.locale,
    required this.l10n,
    required this.onAnswer,
  });

  final MatchUiState state;
  final Locale locale;
  final AppLocalizations l10n;
  final ValueChanged<String> onAnswer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (state.phase == 'shoot')
                Expanded(
                  child: _ShootBanner(
                    locale: locale,
                    l10n: l10n,
                    shooting: state.youAreShooting == true,
                  ),
                )
              else ...[
                Text(l10n.matchRound(isoNum(state.roundNo)), style: AppType.label(locale)),
                const Spacer(),
                if (state.opponentAnswered)
                  Text(l10n.opponentAnswered, style: AppType.label(locale)),
              ],
              const SizedBox(width: AppSpacing.sm),
              _TimerChip(seconds: state.remainingSeconds, locale: locale),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // Overflow ladder step 1: the question card is the only flexible element.
          // It shrinks to its minimum before any answer row is allowed to move.
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 96),
              child: _QuestionCard(state: state, locale: locale),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          ...state.options.map(
            (option) => Padding(
              padding: const EdgeInsetsDirectional.only(bottom: AppSpacing.sm),
              child: AnswerButton(
                label: option.text,
                locale: locale,
                state: _visualStateFor(option.id),
                onPressed: () {
                  SystemSound.play(SystemSoundType.click);
                  HapticFeedback.selectionClick();
                  onAnswer(option.id);
                },
              ),
            ),
          ),
          if (state.phase == 'reveal' && state.explainer.isNotEmpty)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsetsDirectional.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.correct.withValues(alpha: 0.10),
                borderRadius: const BorderRadius.all(AppRadii.md),
                border: Border.all(color: AppColors.correct.withValues(alpha: 0.65)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.lightbulb_outline, color: AppColors.correct, size: 19),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      state.explainer,
                      style: AppType.label(locale).copyWith(color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  AnswerState _visualStateFor(String optionId) {
    if (state.phase == 'reveal' && state.correctOptionId != null) {
      if (optionId == state.correctOptionId) return AnswerState.correct;
      if (optionId == state.selectedOptionId) return AnswerState.wrong;
      return AnswerState.disabled;
    }
    if (optionId == state.selectedOptionId) return AnswerState.selected;
    if (state.answersEnabled) return AnswerState.idle;
    return AnswerState.disabled;
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.state, required this.locale});

  final MatchUiState state;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.bgSunken,
        borderRadius: const BorderRadius.all(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      // Last-resort overflow handling: only the card scrolls, never the answers.
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              state.prompt.isEmpty
                  ? (locale.languageCode == 'ar' ? 'استعد للسؤال التالي…' : 'Get ready for the next question…')
                  : state.prompt,
              style: AppType.title(locale),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (state.media.isNotEmpty && state.format != 'blur_reveal') ...[
              const SizedBox(height: AppSpacing.md),
              ClipRRect(
                borderRadius: const BorderRadius.all(AppRadii.sm),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(
                    state.media.first['url'] ?? '',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stack) => Container(
                      color: AppColors.bgRaised,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Text(
                        locale.languageCode == 'ar'
                            ? 'الصورة غير متاحة حالياً'
                            : 'Image unavailable',
                        style: AppType.label(locale),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (state.format != 'mc') ...[
              const SizedBox(height: AppSpacing.md),
              _FormatBody(state: state, locale: locale),
            ],
          ],
        ),
      ),
    );
  }
}

/// One widget per format. Keeping them separate is what stops the question card from
/// turning into a 400-line `if/else` the first time the schedule changes.
class _FormatBody extends StatelessWidget {
  const _FormatBody({required this.state, required this.locale});

  final MatchUiState state;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    switch (state.format) {
      case 'career_path':
        final clubs = ((state.formatData['clubs'] as List?) ?? const [])
            .whereType<Map>()
            .map((club) => Map<String, dynamic>.from(club))
            .where((club) => (club['name'] as String? ?? '').trim().isNotEmpty)
            .toList(growable: false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              locale.languageCode == 'ar' ? 'مسار الأندية بالترتيب الزمني' : 'CAREER PATH • CHRONOLOGICAL',
              style: AppType.label(locale).copyWith(
                color: AppColors.accent,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (clubs.isEmpty)
              Text(
                locale.languageCode == 'ar' ? 'تسلسل الأندية غير متاح لهذا السؤال' : 'Career sequence unavailable for this question',
                style: AppType.label(locale).copyWith(color: AppColors.wrong),
              )
            else
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (var i = 0; i < clubs.length; i++) ...[
                    Container(
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.bgRaised,
                        borderRadius: const BorderRadius.all(AppRadii.sm),
                        border: Border.all(color: AppColors.accent.withValues(alpha: 0.55)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${i + 1}. ', style: AppType.label(locale).copyWith(color: AppColors.accent)),
                          Flexible(child: Text(clubs[i]['name'] as String, style: AppType.label(locale))),
                        ],
                      ),
                    ),
                    if (i < clubs.length - 1)
                      Icon(
                        locale.languageCode == 'ar' ? Icons.arrow_back_rounded : Icons.arrow_forward_rounded,
                        color: AppColors.accent,
                        size: 17,
                      ),
                  ],
                ],
              ),
          ],
        );

      case 'emoji_story':
        // Already bidi-isolated by the server (U+2066 … U+2069). Do NOT re-order or
        // wrap it again: a doubled isolate renders stray brackets in some engines.
        return Center(
          child: Text(
            state.formatData['emoji'] as String? ?? '',
            style: const TextStyle(fontSize: 34, height: 1.3),
            textDirection: TextDirection.ltr,
          ),
        );

      case 'blur_reveal':
        final image = (state.formatData['image'] as Map?)?.cast<String, dynamic>();
        if (image == null) return const SizedBox.shrink();
        return _BlurReveal(
          url: image['url'] as String,
          revealMs: (state.formatData['revealMs'] as int?) ?? 5000,
          initialSigma: ((state.formatData['initialBlurSigma'] as num?) ?? 28).toDouble(),
          finalSigma: ((state.formatData['finalBlurSigma'] as num?) ?? 0).toDouble(),
        );

      case 'stat_highlow':
        final label = state.formatData['statLabel'] as String? ?? '';
        if (label.isEmpty) return const SizedBox.shrink();
        return Text(label, style: AppType.label(locale));

      default:
        return const SizedBox.shrink();
    }
  }
}

/// Progressive unblur. The blur curve is a *speed mechanic*, so it is driven by the
/// same deadline the server uses — a client that drifts cannot gain reading time.
class _BlurReveal extends StatelessWidget {
  const _BlurReveal({
    required this.url,
    required this.revealMs,
    required this.initialSigma,
    required this.finalSigma,
  });

  final String url;
  final int revealMs;
  final double initialSigma;
  final double finalSigma;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      return _image(finalSigma);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: initialSigma, end: finalSigma),
      duration: Duration(milliseconds: revealMs),
      curve: Curves.easeOut,
      builder: (context, sigma, _) => _image(sigma),
    );
  }

  Widget _image(double sigma) => ClipRRect(
        borderRadius: const BorderRadius.all(AppRadii.sm),
        child: ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: TileMode.decal,
          ),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => Container(
                color: AppColors.bgRaised,
                alignment: Alignment.center,
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(
                  'Image unavailable',
                  style: AppType.label(const Locale('en')),
                ),
              ),
            ),
          ),
        ),
      );
}
