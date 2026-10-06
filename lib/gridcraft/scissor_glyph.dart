import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../papercut/camera.dart';
import 'tool_animation.dart';
import 'tool_flight.dart';

/// Green ring and white center used for a cut or fold point.
void paintCraftPoint(
  Canvas canvas,
  Offset at, {
  required double scale,
  required double alpha,
}) {
  final opacity = alpha.clamp(0.0, 1.0);
  if (opacity <= 0) return;
  final size = scale.abs();
  canvas.drawCircle(
    at,
    5.5 * size,
    Paint()..color = const Color(0xFF1B5E20).withValues(alpha: opacity),
  );
  canvas.drawCircle(
    at,
    3.2 * size,
    Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: opacity),
  );
}

/// Flat tool glyph. The tip sits on [ToolPose.tip] and the blades point
/// along the pose direction.
class ScissorGlyphPainter extends CustomPainter {
  ScissorGlyphPainter({
    required this.camera,
    required this.pose,
    required this.tool,
    this.glyphScale = 1,
    this.destination,
  });

  final PapercutCamera camera;
  final ToolPose pose;
  final ToolAnimation tool;

  /// 1 is the grid-puzzle glyph. Mixed crafting draws it at half size.
  final double glyphScale;

  /// Snapped grid or crease point under the reticle, once the cut has a start.
  final Offset? destination;

  @override
  void paint(Canvas canvas, Size size) {
    if (pose.visible <= 0) return;
    final tip = _project(pose.tip, size);
    if (tip == null) return;
    final ahead = _project(pose.tip + pose.direction * 10, size);
    if (ahead == null) return;
    final heading = ahead - tip;
    if (heading.distance < 0.5) return;
    final angle = math.atan2(heading.dy, heading.dx) + toolYaw(tool, pose);
    final perp = screenPerpendicular(heading);
    final visual = tip + perp * pose.lateral;

    canvas.save();
    canvas.translate(visual.dx, visual.dy);
    canvas.scale(glyphScale);
    paintRolledTool(canvas: canvas, tool: tool, pose: pose, heading: angle);
    canvas.restore();
    _paintPoints(canvas, size, tip);
  }

  /// Start at the blade, and the snapped end once the cut is locked.
  ///
  /// Both sit on the cut, before the side offset that cocks the glyph off
  /// the line.
  void _paintPoints(Canvas canvas, Size size, Offset tip) {
    final alpha = pose.visible.clamp(0.0, 1.0);
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
  bool shouldRepaint(covariant ScissorGlyphPainter oldDelegate) => true;
}
