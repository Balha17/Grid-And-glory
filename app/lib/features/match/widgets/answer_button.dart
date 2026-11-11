import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/l10n/bidi.dart';

enum AnswerState { idle, selected, correct, wrong, disabled }

/// One answer row.
///
/// Design constraints (docs/04-ui-ux-spec.md §4.5):
///   * full width, single column — a 2×2 grid halves Arabic text width and forces
///     wrapping that makes two options look like one question
///   * min 56 dp tall, always
///   * the state is carried by a glyph as well as a colour, never colour alone
///   * no optimistic colouring: the server has not confirmed yet, so pressing an
///     answer must not look like it was right
class AnswerButton extends StatelessWidget {
  const AnswerButton({
    super.key,
    required this.label,
    required this.state,
    required this.locale,
    this.onPressed,
  });

  final String label;
  final AnswerState state;
  final Locale locale;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final isActive = state != AnswerState.disabled && state != AnswerState.correct && state != AnswerState.wrong;
    final accent = _accentFor(state);

    return Semantics(
      button: true,
      enabled: isActive,
      label: label,
      child: AnimatedOpacity(
        duration: AppMotion.respecting(context, AppMotion.reveal),
        opacity: state == AnswerState.disabled ? 0.45 : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isActive ? onPressed : null,
            borderRadius: const BorderRadius.all(AppRadii.md),
            splashColor: accent.withValues(alpha: 0.18),
            child: AnimatedContainer(
              duration: AppMotion.respecting(context, AppMotion.press),
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                color: state == AnswerState.selected
                    ? accent.withValues(alpha: 0.12)
                    : AppColors.bgRaised,
                borderRadius: const BorderRadius.all(AppRadii.md),
                border: Border.all(
                  color: state == AnswerState.idle ? AppColors.border : accent,
                  width: state == AnswerState.idle ? 1 : 2,
                ),
              ),
              // Row follows the ambient Directionality, so the glyph lands on the
              // trailing edge in both languages without any manual mirroring.
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: AppType.body(locale),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      // Explicit: option text can be a Latin club name inside an
                      // Arabic card, and inheriting the paragraph direction would
                      // reorder it.
                      textDirection: _textDirectionOf(label, locale),
                    ),
                  ),
                  if (state == AnswerState.selected ||
                      state == AnswerState.correct ||
                      state == AnswerState.wrong) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Icon(_iconFor(state), size: 20, color: accent),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static TextDirection _textDirectionOf(String text, Locale locale) {
    final hasArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(text);
    return hasArabic ? TextDirection.rtl : TextDirection.ltr;
  }

  static Color _accentFor(AnswerState state) {
    switch (state) {
      case AnswerState.idle:
        return AppColors.textSecondary;
      case AnswerState.selected:
        return AppColors.accent;
      case AnswerState.correct:
        return AppColors.correct;
      case AnswerState.wrong:
        return AppColors.wrong;
      case AnswerState.disabled:
        return AppColors.border;
    }
  }

  static IconData _iconFor(AnswerState state) {
    switch (state) {
      case AnswerState.selected:
        return Icons.radio_button_checked;
      case AnswerState.correct:
        return Icons.check_circle;
      case AnswerState.wrong:
        return Icons.cancel;
      case AnswerState.idle:
      case AnswerState.disabled:
        return Icons.radio_button_unchecked;
    }
  }
}

/// The scoreline. Mirrors as a container (so "you" keeps the reading-start side) but
/// the numeral sequence inside never reorders.
class ScoreLine extends StatelessWidget {
  const ScoreLine({
    super.key,
    required this.yourGoals,
    required this.opponentGoals,
    required this.locale,
  });

  final int yourGoals;
  final int opponentGoals;
  final Locale locale;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(isoNum(yourGoals), style: AppType.numeric(locale, size: 28)),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.sm),
          child: Text('–', style: AppType.numeric(locale, size: 22)),
        ),
        Text(isoNum(opponentGoals), style: AppType.numeric(locale, size: 28)),
      ],
    );
  }
}
