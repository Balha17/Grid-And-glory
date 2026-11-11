import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/theme/tokens.dart';

/// Broadcast-style vertical football pitch. The local player always attacks upward;
/// only the two player lanes mirror for RTL.
class PitchViewport extends StatelessWidget {
  const PitchViewport({super.key, required this.yourZone, required this.opponentZone,
    required this.youHaveBall, required this.locale, this.goalFlash = false, this.phase = 'open', this.youAreShooting});
  final int yourZone, opponentZone;
  final bool youHaveBall;
  final Locale locale;
  final bool goalFlash;
  final String phase;
  final bool? youAreShooting;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final duration = AppMotion.respecting(context, AppMotion.zoneAdvance);
    final attacking = phase == 'shoot' ? youAreShooting == true : youHaveBall;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: yourZone.toDouble(), end: yourZone.toDouble()),
      duration: duration, curve: Curves.easeOutCubic,
      builder: (context, you, _) => TweenAnimationBuilder<double>(
        tween: Tween(begin: opponentZone.toDouble(), end: opponentZone.toDouble()),
        duration: duration, curve: Curves.easeOutCubic,
        builder: (context, rival, _) => RepaintBoundary(
          child: CustomPaint(
            painter: _PitchPainter(you: you, rival: rival, possession: attacking, rtl: rtl, goalFlash: goalFlash, shooting: phase == 'shoot', locale: locale),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _PitchPainter extends CustomPainter {
  _PitchPainter({required this.you, required this.rival, required this.possession, required this.rtl, required this.goalFlash, required this.shooting, required this.locale});
  final double you, rival;
  final bool possession, rtl, goalFlash, shooting;
  final Locale locale;
  static const blue = Color(0xFF38BDF8);
  static const red = Color(0xFFFF555F);
  static const line = Color(0xD9FFFFFF);
  static const radius = 10.5;

  @override
  void paint(Canvas canvas, Size size) {
    _stadium(canvas, size);
    final f = Rect.fromLTRB(8, 48, size.width - 8, size.height - 8);
    _grass(canvas, f);
    _markings(canvas, f);
    _goals(canvas, f);
    final dx = f.width * 0.20 * (rtl ? -1 : 1);
    final pYou = Offset(f.center.dx + dx, _zoneY(you, f));
    final pRival = Offset(f.center.dx - dx, _rivalZoneY(rival, f));
    _team(canvas, f, pYou, blue, true, possession);
    _team(canvas, f, pRival, red, false, !possession);
    final owner = possession ? pYou : pRival;
    _ball(canvas, owner, shooting);
    _status(canvas, size);
    if (goalFlash) {
      final glow = Rect.fromLTWH(f.left, f.top, f.width, f.height * .17);
      canvas.drawRect(glow, Paint()..shader = LinearGradient(
        colors: [const Color(0xFFFFC24B).withValues(alpha: .25), Colors.transparent],
        begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(glow));
    }
  }

  void _stadium(Canvas c, Size s) {
    final r = Offset.zero & s;
    c.drawRect(r, Paint()..shader = const LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Color(0xFF142237), Color(0xFF08111D)]).createShader(r));
    for (final x in [s.width*.12, s.width*.88]) {
      final light = Rect.fromCircle(center: Offset(x,s.height*.22), radius:s.width*.27);
      c.drawCircle(light.center, light.width/2, Paint()..shader = RadialGradient(
        colors:[Colors.white.withValues(alpha:.05),Colors.transparent]).createShader(light));
    }
    final label = TextPainter(text: const TextSpan(text:'GRID & GLORY  •  MATCHDAY',
      style:TextStyle(color:Color(0xFF9FB0CC),fontSize:8,fontWeight:FontWeight.w900,letterSpacing:1.4)),
      textDirection:TextDirection.ltr)..layout(maxWidth:s.width-24);
    label.paint(c,const Offset(12,10));
  }

  void _grass(Canvas c, Rect f) {
    final rr=RRect.fromRectAndRadius(f,const Radius.circular(13));
    c.drawRRect(rr,Paint()..color=const Color(0xFF145B3A));
    c.save(); c.clipRRect(rr);
    final h=f.height/12;
    for(var i=0;i<12;i++){
      final band=Rect.fromLTWH(f.left,f.top+i*h,f.width,h+1);
      c.drawRect(band,Paint()..shader=LinearGradient(
        begin:AlignmentDirectional.centerStart,end:AlignmentDirectional.centerEnd,
        colors:i.isEven?const [Color(0xFF247B4D),Color(0xFF1A663F)]:const [Color(0xFF1A693F),Color(0xFF155735)]
      ).createShader(band));
    }
    c.drawRect(f,Paint()..shader=LinearGradient(
      begin:Alignment.topCenter,end:Alignment.bottomCenter,
      colors:[Colors.white.withValues(alpha:.05),Colors.transparent,Colors.black.withValues(alpha:.10)]
    ).createShader(f));
    c.restore();
    c.drawRRect(rr,Paint()..style=PaintingStyle.stroke..strokeWidth=1.5..color=line);
  }

  void _markings(Canvas c, Rect f) {
    final p=Paint()..style=PaintingStyle.stroke..strokeWidth=1.15..color=line;
    final mid=f.center.dy;
    c.drawLine(Offset(f.left,mid),Offset(f.right,mid),p);
    c.drawCircle(Offset(f.center.dx,mid),f.width*.145,p);
    c.drawCircle(Offset(f.center.dx,mid),2,Paint()..color=line);
    final boxW=f.width*.64, sixW=f.width*.34, boxH=f.height*.135, sixH=f.height*.052;
    for(final top in [true,false]){
      c.drawRect(Rect.fromLTWH(f.center.dx-boxW/2,top?f.top:f.bottom-boxH,boxW,boxH),p);
      c.drawRect(Rect.fromLTWH(f.center.dx-sixW/2,top?f.top:f.bottom-sixH,sixW,sixH),p);
      final spot=Offset(f.center.dx,top?f.top+boxH*.70:f.bottom-boxH*.70);
      c.drawCircle(spot,2,Paint()..color=line);
      c.drawArc(Rect.fromCircle(center:spot,radius:f.width*.145),top ? 0.20 : math.pi + 0.20,math.pi-.4,false,p);
    }
    for (final x in [f.left, f.right]) {
      for (final y in [f.top, f.bottom]) {
        final start = (x == f.left ? 0.0 : math.pi / 2) + (y == f.top ? 0 : math.pi);
        c.drawArc(Rect.fromCircle(center: Offset(x, y), radius: 7), start, math.pi / 2, false, p);
      }
    }
  }

  void _goals(Canvas c, Rect f) {
    final w=f.width*.27;
    for(final top in [true,false]){
      final r=Rect.fromLTWH(f.center.dx-w/2,top?f.top-7:f.bottom,w,7);
      c.drawRect(r,Paint()..color=Colors.white.withValues(alpha:.10));
      for(var x=r.left+5;x<r.right;x+=6){
        c.drawLine(Offset(x,r.top),Offset(x,r.bottom),Paint()..color=Colors.white.withValues(alpha:.20)..strokeWidth = .6);
      }
      c.drawRect(r,Paint()..style=PaintingStyle.stroke..strokeWidth=2.4..color=Colors.white.withValues(alpha:.9));
    }
  }

  double _zoneY(double z,Rect f)=>f.bottom-(z.clamp(0,5).toDouble()+.5)*(f.height/6);
  double _rivalZoneY(double z, Rect f)=>f.top+(z.clamp(0,5).toDouble()+.5)*(f.height/6);

  // A compact formation makes attack and defence visibly different: support players
  // move behind the ball carrier, while the opposing team presses from its own half.
  void _team(Canvas c, Rect f, Offset focus, Color color, bool isBlue, bool active) {
    final dir = isBlue ? 1.0 : -1.0;
    _player(c, Offset(f.center.dx, isBlue ? f.bottom - 8 : f.top + 8), color.withValues(alpha: .85), false, 'GK');
    final offsets = <Offset>[
      Offset(-f.width * .22, dir * f.height * .12),
      Offset(-f.width * .09, dir * f.height * .18),
      Offset(f.width * .09, dir * f.height * .18),
      Offset(f.width * .22, dir * f.height * .12),
    ];
    for (var i = 0; i < offsets.length; i++) {
      final point = Offset((focus.dx + offsets[i].dx).clamp(f.left + 11, f.right - 11).toDouble(),
        (focus.dy + offsets[i].dy).clamp(f.top + 12, f.bottom - 12).toDouble());
      _player(c, point, color, active && i == 1, '${i + 2}');
    }
    _player(c, focus, color, active, isBlue ? '10' : '09');
  }

  void _status(Canvas c, Size s) {
    final ar = locale.languageCode == 'ar';
    final label = shooting ? (ar ? 'فرصة للتسجيل' : 'SHOOTING CHANCE')
      : possession ? (ar ? 'هجومك • استحواذ' : 'YOUR ATTACK • IN POSSESSION')
      : (ar ? 'دفاعك • استعد للافتكاك' : 'DEFENDING • WIN IT BACK');
    final color = shooting ? const Color(0xFFFFD166) : possession ? blue : red;
    final w = math.min(s.width - 24, shooting ? 142.0 : 174.0).toDouble();
    final rect = Rect.fromLTWH((s.width - w) / 2, s.height - 28, w, 16);
    c.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(9)),
      Paint()..color = const Color(0xFF071321).withValues(alpha: .9));
    c.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(9)),
      Paint()..style = PaintingStyle.stroke..strokeWidth = .8..color = color);
    final text = TextPainter(text: TextSpan(text: label, style: TextStyle(color: color, fontSize: 6.2, fontWeight: FontWeight.w900)),
      textDirection: TextDirection.ltr, maxLines: 1)..layout(maxWidth: w - 8);
    text.paint(c, Offset(rect.center.dx - text.width / 2, rect.top + 4));
  }

  void _player(Canvas c,Offset p,Color color,bool ball,String number){
    if(ball){
      c.drawCircle(p,radius+9,Paint()..color=color.withValues(alpha:.19));
      c.drawCircle(p,radius+5,Paint()..style=PaintingStyle.stroke..strokeWidth=1.4..color=color.withValues(alpha:.75));
    }
    c.drawCircle(p+const Offset(0,3),radius+2,Paint()..color=Colors.black.withValues(alpha:.3));
    c.drawCircle(p,radius,Paint()..color=const Color(0xFF071321));
    c.drawCircle(p,radius-2,Paint()..shader=LinearGradient(colors:[color,color.withValues(alpha:.72)]).createShader(Rect.fromCircle(center:p,radius:radius)));
    c.drawCircle(p,radius,Paint()..style=PaintingStyle.stroke..strokeWidth=2..color=Colors.white.withValues(alpha:.9));
    final t=TextPainter(text:TextSpan(text:number,style:const TextStyle(color:Colors.white,fontSize:10,fontWeight:FontWeight.w900)),
      textDirection:TextDirection.ltr)..layout();
    t.paint(c,p-Offset(t.width/2,t.height/2));
  }

  void _ball(Canvas c,Offset owner, bool dramatic){
    final p=owner+const Offset(radius*.88,radius*.58);
    if (dramatic) {
      c.drawLine(p + const Offset(-13, 7), p + const Offset(-4, 2), Paint()..color = const Color(0xFFFFD166)..strokeWidth = 2.1..strokeCap = StrokeCap.round);
      c.drawCircle(p, radius * .8, Paint()..color = const Color(0xFFFFD166).withValues(alpha: .18));
    }
    c.drawCircle(p+const Offset(0,2),6,Paint()..color=Colors.black38);
    c.drawCircle(p,5.2,Paint()..color=Colors.white);
    c.drawCircle(p,5.2,Paint()..style=PaintingStyle.stroke..strokeWidth = 1.1..color=const Color(0xFF1A2638));
    c.drawLine(p+const Offset(-2,-1),p+const Offset(2,1),Paint()..color=const Color(0xFF1A2638)..strokeWidth=1);
  }

  @override
  bool shouldRepaint(_PitchPainter old)=>old.you!=you||old.rival!=rival||old.possession!=possession||old.rtl!=rtl||old.goalFlash!=goalFlash||old.shooting!=shooting||old.locale!=locale;
}
