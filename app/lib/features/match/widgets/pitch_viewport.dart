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
    final grass = Paint();
    // A broadcast-style natural pitch: alternating mowing lanes are subtle, not six
    // oversized blocks competing with the players and the question.
    for (var i = 0; i < PitchViewport.zoneCount * 2; i++) {
      grass.color = i.isEven
          ? AppColors.grassA.withValues(alpha: 0.94)
          : AppColors.grassB.withValues(alpha: 0.94);
      canvas.drawRect(
        Rect.fromLTWH(0, i * size.height / 12, size.width, size.height / 12 + 0.5),
        grass,
      );
    }

    final line = Paint()
      ..color = Colors.white.withValues(alpha: goalFlash ? 0.48 : 0.34)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.35;

    // Touchlines and goal lines.
    canvas.drawRect(
      Rect.fromLTWH(7, 7, size.width - 14, size.height - 14),
      line,
    );
    // Halfway line and centre circle, correctly oriented for an attacking-up pitch.
    canvas.drawLine(
      Offset(7, size.height / 2),
      Offset(size.width - 7, size.height / 2),
      line,
    );
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.width * 0.115,
      line,
    );
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      2.2,
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );

    // Penalty areas and six-yard boxes at both ends.
    final boxWidth = size.width * 0.58;
    final sixWidth = size.width * 0.30;
    final boxDepth = size.height * 0.145;
    final sixDepth = size.height * 0.065;
    for (final top in [true, false]) {
      final y = top ? 7.0 : size.height - 7 - boxDepth;
      canvas.drawRect(Rect.fromLTWH((size.width - boxWidth) / 2, y, boxWidth, boxDepth), line);
      final sixY = top ? 7.0 : size.height - 7 - sixDepth;
      canvas.drawRect(Rect.fromLTWH((size.width - sixWidth) / 2, sixY, sixWidth, sixDepth), line);
      final spotY = top ? 7 + boxDepth * 0.70 : size.height - 7 - boxDepth * 0.70;
      canvas.drawCircle(Offset(size.width / 2, spotY), 2, Paint()..color = Colors.white.withValues(alpha: 0.55));
    }

    // Soft stadium edge shading adds depth without covering the field.
    final shade = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x26000000), Color(0x00000000), Color(0x26000000)],
        stops: [0, 0.5, 1],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, shade);
    // Keep the six gameplay zones readable through faint separators.
    final separators = Paint()
      ..color = Colors.white.withValues(alpha: 0.055)
      ..strokeWidth = 0.7;
    for (var i = 1; i < PitchViewport.zoneCount; i++) {
      final y = band * i;
      canvas.drawLine(Offset(8, y), Offset(size.width - 8, y), separators);
    }
  }

  void _paintGoalMouths(Canvas canvas, Size size) {
    final goalWidth = size.width * 0.38;
    final goalDepth = 9.0;
    final net = Paint()
      ..color = Colors.white.withValues(alpha: goalFlash ? 0.58 : 0.28)
      ..strokeWidth = 0.8;
    for (final top in [true, false]) {
      final left = (size.width - goalWidth) / 2;
      final y = top ? 0.0 : size.height - goalDepth;
      final goal = Rect.fromLTWH(left, y, goalWidth, goalDepth);
      canvas.drawRect(goal, Paint()..color = Colors.white.withValues(alpha: 0.10));
      canvas.drawRect(goal, net..style = PaintingStyle.stroke..strokeWidth = 1.5);
      for (var x = left + 8; x < left + goalWidth; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(x, y + goalDepth), net);
      }
      canvas.drawLine(Offset(left, y + goalDepth / 2), Offset(left + goalWidth, y + goalDepth / 2), net);
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
