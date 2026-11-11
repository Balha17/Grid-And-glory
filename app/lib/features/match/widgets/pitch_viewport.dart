import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';

/// The top 40% of the match screen: a vertical 6-zone pitch with two lanes.
///
/// **Mirroring rule.** The pitch never flips vertically and attack is always upward
/// for the local player. Only *lane assignment* mirrors, so in Arabic your lane sits
/// on the right (the reading-start side) while you still attack toward the top.
///
/// The alternative — mirroring the whole pitch — makes Arabic players attack
/// downward and plays every celebration upside-down, for zero semantic gain.
class PitchViewport extends StatelessWidget {
  const PitchViewport({
    super.key,
    required this.yourZone,
    required this.opponentZone,
    required this.youHaveBall,
    required this.locale,
    this.goalFlash = false,
  });

  /// 0 = own goal line, 5 = opponent's goal mouth.
  final int yourZone;
  final int opponentZone;
  final bool youHaveBall;
  final Locale locale;
  final bool goalFlash;

  static const int zoneCount = 6;

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final duration = AppMotion.respecting(context, AppMotion.zoneAdvance);

    // Two independent animations: the avatars move at different speeds and must not
    // be welded to a single timeline.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: yourZone.toDouble(), end: yourZone.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, animatedYou, _) {
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: opponentZone.toDouble(), end: opponentZone.toDouble()),
          duration: duration,
          curve: Curves.easeOutCubic,
          builder: (context, animatedOpponent, _) {
            return RepaintBoundary(
              child: CustomPaint(
                painter: _PitchPainter(
                  yourZone: animatedYou,
                  opponentZone: animatedOpponent,
                  youHaveBall: youHaveBall,
                  isRtl: isRtl,
                  goalFlash: goalFlash,
                ),
                child: const SizedBox.expand(),
              ),
            );
          },
        );
      },
    );
  }
}

class _PitchPainter extends CustomPainter {
  _PitchPainter({
    required this.yourZone,
    required this.opponentZone,
    required this.youHaveBall,
    required this.isRtl,
    required this.goalFlash,
  });

  final double yourZone;
  final double opponentZone;
  final bool youHaveBall;
  final bool isRtl;
  final bool goalFlash;

  static const double _avatarRadius = 20;

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrass(canvas, size);
    _paintGoalMouths(canvas, size);

    final lanes = _laneXs(size);
    _paintAvatar(
      canvas,
      Offset(lanes.you, _yForZone(yourZone, size.height)),
      AppColors.you,
      youHaveBall,
    );
    _paintAvatar(
      canvas,
      Offset(lanes.opponent, _yForZone(opponentZone, size.height)),
      AppColors.opponent,
      !youHaveBall,
    );
    _paintBall(canvas, lanes, size);
  }

  /// zone 0 sits at the bottom, zone 5 at the top — for BOTH players.
  double _yForZone(double zone, double height) {
    final band = height / PitchViewport.zoneCount;
    return height - (zone + 0.5) * band;
  }

  /// Lane assignment mirrors; the vertical axis does not.
  ({double you, double opponent}) _laneXs(Size size) {
    final sign = isRtl ? -1.0 : 1.0;
    final centre = size.width / 2;
    final offset = size.width * 0.19;
    return (you: centre + sign * offset, opponent: centre - sign * offset);
  }

  void _paintGrass(Canvas canvas, Size size) {
    final band = size.height / PitchViewport.zoneCount;
    final paint = Paint();
    for (var i = 0; i < PitchViewport.zoneCount; i++) {
      paint.color = i.isEven ? AppColors.grassA : AppColors.grassB;
      canvas.drawRect(Rect.fromLTWH(0, i * band, size.width, band), paint);
    }

    // Thin centre line, no zone numbers during play — they are noise at speed.
    final centreLine = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      centreLine,
    );
  }

  void _paintGoalMouths(Canvas canvas, Size size) {
    final band = size.height / PitchViewport.zoneCount;
    final net = Paint()
      ..color = Colors.white.withValues(alpha: goalFlash ? 0.30 : 0.14)
      ..strokeWidth = 1;

    for (final top in [0.0, size.height - band]) {
      final rect = Rect.fromLTWH(0, top, size.width, band);
      canvas.drawRect(
        rect,
        Paint()..color = Colors.white.withValues(alpha: 0.05),
      );
      for (var x = 0.0; x < size.width; x += 12) {
        canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), net);
      }
      for (var y = rect.top; y < rect.bottom; y += 12) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), net);
      }
    }
  }

  void _paintAvatar(Canvas canvas, Offset centre, Color colour, bool hasBall) {
    if (hasBall) {
      canvas.drawCircle(
        centre,
        _avatarRadius + 7,
        Paint()..color = colour.withValues(alpha: 0.18),
      );
    }
    canvas.drawCircle(centre, _avatarRadius, Paint()..color = AppColors.bgBase);
    canvas.drawCircle(
      centre,
      _avatarRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = colour,
    );
    // The jersey number is the identity marker; no faces means no uncanny mirroring.
    final label = TextPainter(
      text: TextSpan(
        text: hasBall ? '●' : '○',
        style: TextStyle(color: colour, fontSize: 14, height: 1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, centre - Offset(label.width / 2, label.height / 2));
  }

  void _paintBall(Canvas canvas, ({double you, double opponent}) lanes, Size size) {
    final owner = youHaveBall
        ? Offset(lanes.you, _yForZone(yourZone, size.height))
        : Offset(lanes.opponent, _yForZone(opponentZone, size.height));
    final ball = owner + const Offset(_avatarRadius * 0.85, _avatarRadius * 0.5);

    canvas.drawCircle(ball, 6, Paint()..color = Colors.white);
    canvas.drawCircle(
      ball,
      6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = AppColors.bgBase,
    );
  }

  @override
  bool shouldRepaint(_PitchPainter old) =>
      old.yourZone != yourZone ||
      old.opponentZone != opponentZone ||
      old.youHaveBall != youHaveBall ||
      old.isRtl != isRtl ||
      old.goalFlash != goalFlash;
}
