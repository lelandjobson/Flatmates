import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Diameter and stroke of the reticle's circle, shared with the scissors'
/// handle so the two are the same circle.
const double kReticleDiameter = 14;
const double kReticleStroke = 3.5;

/// The reticle's circle, centered on [at].
void paintReticleCircle(Canvas canvas, Offset at, Color color) {
  final box = kReticleDiameter + kReticleStroke;
  canvas.save();
  canvas.translate(at.dx - box / 2, at.dy - box / 2);
  CrosshairPainter(
    diameter: kReticleDiameter,
    strokeWidth: kReticleStroke,
    color: color,
    morph: 0,
  ).paint(canvas, Size.square(box));
  canvas.restore();
}

/// Center-fixed pointer: a thick-stroke circle that morphs into an X
/// when nothing under the cursor can be selected.
class ViewCrosshair extends StatelessWidget {
  const ViewCrosshair({
    super.key,
    this.selectable = true,
    this.diameter = kReticleDiameter,
    this.strokeWidth = kReticleStroke,
    this.color = const Color(0xF2FFFFFF),
    this.duration = const Duration(milliseconds: 220),
  });

  final bool selectable;
  final double diameter;
  final double strokeWidth;
  final Color color;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: selectable ? 0 : 1),
          duration: duration,
          curve: Curves.easeInOutCubic,
          builder: (context, morph, _) {
            return CustomPaint(
              size: Size.square(diameter + strokeWidth),
              painter: CrosshairPainter(
                diameter: diameter,
                strokeWidth: strokeWidth,
                color: color,
                morph: morph,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// [morph] 0 = circle, 1 = X.
class CrosshairPainter extends CustomPainter {
  CrosshairPainter({
    required this.diameter,
    required this.strokeWidth,
    required this.color,
    required this.morph,
  });

  final double diameter;
  final double strokeWidth;
  final Color color;
  final double morph;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.5);
    final radius = diameter * 0.5;
    final t = morph.clamp(0.0, 1.0);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final sweep = math.pi * (1 - t);
    if (sweep > 0.04) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      final rot = t * math.pi / 4;
      canvas.drawArc(rect, rot, sweep, false, paint);
      canvas.drawArc(rect, rot + math.pi, sweep, false, paint);
    }

    if (t > 0.02) {
      final half = radius * 0.72 * Curves.easeOutCubic.transform(t);
      canvas.drawLine(
        center + Offset(-half, -half),
        center + Offset(half, half),
        paint,
      );
      canvas.drawLine(
        center + Offset(-half, half),
        center + Offset(half, -half),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CrosshairPainter oldDelegate) {
    return oldDelegate.diameter != diameter ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.color != color ||
        oldDelegate.morph != morph;
  }
}
