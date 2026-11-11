import 'dart:math' as math;
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
    final field = Offset.zero & size;
    final grass = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF167447), Color(0xFF0D5B38), Color(0xFF104D32)],
      ).createShader(field);
    canvas.drawRect(field, grass);

    final lane = Paint()..color = Colors.white.withValues(alpha: 0.035);
    final laneHeight = size.height / 10;
    for (var i = 0; i < 10; i++) {
      if (i.isEven) canvas.drawRect(Rect.fromLTWH(0, i * laneHeight, size.width, laneHeight), lane);
    }
    canvas.drawRect(
      field,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.24)],
          stops: const [0.58, 1],
        ).createShader(field),
    );

    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.78)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.35;
    final inset = math.min(size.width, size.height) * 0.055;
    final pitch = Rect.fromLTWH(inset, inset, size.width - inset * 2, size.height - inset * 2);
    canvas.drawRRect(RRect.fromRectAndRadius(pitch, const Radius.circular(5)), line);

    final middleY = size.height / 2;
    canvas.drawLine(Offset(inset, middleY), Offset(size.width - inset, middleY), line);
    canvas.drawCircle(Offset(size.width / 2, middleY), size.width * 0.115, line);
    canvas.drawCircle(Offset(size.width / 2, middleY), 2.1, Paint()..color = Colors.white);

    final boxWidth = size.width * 0.58;
    final boxHeight = size.height * 0.155;
    final sixWidth = size.width * 0.34;
    final sixHeight = size.height * 0.065;
    final goalWidth = size.width * 0.22;
    final goalDepth = size.height * 0.022;
    final left = (size.width - boxWidth) / 2;
    final sixLeft = (size.width - sixWidth) / 2;
    final goalLeft = (size.width - goalWidth) / 2;

    for (final isTop in [true, false]) {
      final top = isTop ? inset : size.height - inset - boxHeight;
      canvas.drawRect(Rect.fromLTWH(left, top, boxWidth, boxHeight), line);
      final sixTop = isTop ? top : top + boxHeight - sixHeight;
      canvas.drawRect(Rect.fromLTWH(sixLeft, sixTop, sixWidth, sixHeight), line);
      final spotY = isTop ? top + boxHeight * 0.68 : top + boxHeight * 0.32;
      canvas.drawCircle(Offset(size.width / 2, spotY), 1.8, Paint()..color = Colors.white);
      final arcCenterY = isTop ? top + boxHeight : top;
      final arcRect = Rect.fromCircle(center: Offset(size.width / 2, arcCenterY), radius: size.width * 0.105);
      canvas.drawArc(arcRect, isTop ? 0.18 : math.pi + 0.18, math.pi - 0.36, false, line);
    }

    final net = Paint()
      ..color = Colors.white.withValues(alpha: 0.42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final y in [inset - goalDepth, size.height - inset]) {
      final goal = Rect.fromLTWH(goalLeft, y, goalWidth, goalDepth);
      canvas.drawRect(goal, net);
      for (var x = goal.left + 5; x < goal.right; x += 7) {
        canvas.drawLine(Offset(x, goal.top), Offset(x, goal.bottom), net);
      }
    }

    final cornerRadius = size.width * 0.035;
    for (final x in [inset, size.width - inset]) {
      for (final y in [inset, size.height - inset]) {
        final rect = Rect.fromCircle(center: Offset(x, y), radius: cornerRadius);
        canvas.drawArc(rect, x == inset ? 0 : math.pi / 2, math.pi / 2, false, line);
      }
    }
  }

  void _paintAvatar(Canvas canvas, Offset centre, Color colour, bool hasBall) {
    if (hasBall) {
      canvas.drawCircle(centre, _avatarRadius + 10, Paint()..color = colour.withValues(alpha: 0.18));
      canvas.drawCircle(
        centre,
        _avatarRadius + 5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = colour.withValues(alpha: 0.72),
      );
    }
    final shirt = Path()
      ..moveTo(centre.dx - 10, centre.dy - 9)
      ..lineTo(centre.dx - 17, centre.dy - 4)
      ..lineTo(centre.dx - 13, centre.dy + 4)
      ..lineTo(centre.dx - 9, centre.dy + 2)
      ..lineTo(centre.dx - 8, centre.dy + 12)
      ..quadraticBezierTo(centre.dx, centre.dy + 16, centre.dx + 8, centre.dy + 12)
      ..lineTo(centre.dx + 9, centre.dy + 2)
      ..lineTo(centre.dx + 13, centre.dy + 4)
      ..lineTo(centre.dx + 17, centre.dy - 4)
      ..lineTo(centre.dx + 10, centre.dy - 9)
      ..quadraticBezierTo(centre.dx, centre.dy - 3, centre.dx - 10, centre.dy - 9)
      ..close();
    canvas.drawShadow(shirt, Colors.black.withValues(alpha: 0.42), 4, true);
    canvas.drawPath(shirt, Paint()..color = colour);
    canvas.drawPath(
      shirt,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.92),
    );
    canvas.drawLine(
      Offset(centre.dx - 5, centre.dy - 4),
      Offset(centre.dx + 5, centre.dy - 4),
      Paint()..color = Colors.white.withValues(alpha: 0.72)..strokeWidth = 1.2,
    );
  }

  void _paintBall(Canvas canvas, ({double you, double opponent}) lanes, Size size) {
    final owner = youHaveBall
        ? Offset(lanes.you, _yForZone(yourZone, size.height))
        : Offset(lanes.opponent, _yForZone(opponentZone, size.height));
    final ball = owner + const Offset(_avatarRadius * 0.85, _avatarRadius * 0.5);
    canvas.drawCircle(ball + const Offset(0, 2), 7, Paint()..color = Colors.black.withValues(alpha: 0.28));
    canvas.drawCircle(ball, 6, Paint()..color = const Color(0xFFF8FAFC));
    canvas.drawCircle(
      ball,
      6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = const Color(0xFF172033),
    );
    canvas.drawCircle(ball, 1.8, Paint()..color = const Color(0xFF172033));
  }

  @override
  bool shouldRepaint(_PitchPainter old) =>
      old.yourZone != yourZone ||
      old.opponentZone != opponentZone ||
      old.youHaveBall != youHaveBall ||
      old.isRtl != isRtl ||
      old.goalFlash != goalFlash;
}
