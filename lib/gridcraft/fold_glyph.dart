import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../papercut/camera.dart';
import 'scissor_glyph.dart';
import 'tool_animation.dart';
import 'tool_flight.dart';

/// Placeholder folder. A rounded rect in the crease color, flown by [ToolFlight]
/// the same way the scissors fly: the body slides in, the tip stays on the point.
class FoldGlyphPainter extends CustomPainter {
  FoldGlyphPainter({
    required this.camera,
    required this.pose,
    this.glyphScale = 0.5,
    this.destination,
  });

  final PapercutCamera camera;
  final ToolPose pose;

  /// Mixed crafting draws this at half size, matching the scissors.
  final double glyphScale;

  /// Snapped grid or crease point under the reticle, once the fold has a start.
  final Offset? destination;

  static const _color = Color(0xFFFFB74D);

  /// Local body, tip toward +x, before [glyphScale].
  static const _body = Rect.fromLTRB(-70, -11, -6, 11);

  @override
  void paint(Canvas canvas, Size size) {
    if (pose.visible <= 0) return;
    final tip = _project(pose.tip, size);
    if (tip == null) return;
    final ahead = _project(pose.tip + pose.direction * 10, size);
    if (ahead == null) return;
    final heading = ahead - tip;
    if (heading.distance < 0.5) return;
    final angle = math.atan2(heading.dy, heading.dx);
    final visual = tip + screenPerpendicular(heading) * pose.lateral;
    final alpha = pose.visible.clamp(0.0, 1.0);

    canvas.save();
    canvas.translate(visual.dx, visual.dy);
    canvas.scale(glyphScale);
    canvas.rotate(angle);
    canvas.scale(1, rollFaceScale(pose.roll));
    canvas.drawRRect(
      RRect.fromRectAndRadius(_body, const Radius.circular(3)),
      Paint()..color = _color.withValues(alpha: alpha),
    );
    canvas.restore();

    paintCraftPoint(canvas, tip, scale: glyphScale, alpha: alpha);
    final end = destination;
    if (end == null) return;
    final screen = _project(end, size);
    if (screen == null) return;
    paintCraftPoint(canvas, screen, scale: glyphScale, alpha: alpha);
  }

  Offset? _project(Offset point, Size size) {
    return camera.camera.projectToScreen(Vector3(point.dx, point.dy, 0), size);
  }

  @override
  bool shouldRepaint(covariant FoldGlyphPainter oldDelegate) => true;
}
