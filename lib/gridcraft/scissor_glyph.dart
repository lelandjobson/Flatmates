import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../papercut/camera.dart';
import 'tool_animation.dart';
import 'tool_flight.dart';

/// Flat tool glyph. The tip sits on [ToolPose.tip] and the blades point
/// along the pose direction.
class ScissorGlyphPainter extends CustomPainter {
  ScissorGlyphPainter({
    required this.camera,
    required this.pose,
    required this.tool,
  });

  final PapercutCamera camera;
  final ToolPose pose;
  final ToolAnimation tool;

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
    paintRolledTool(canvas: canvas, tool: tool, pose: pose, heading: angle);
    canvas.restore();
    _paintCutPoint(canvas, tip);
  }

  /// The blade's place on the cut. Drawn at the tip, before the side offset
  /// that cocks the glyph off the line.
  void _paintCutPoint(Canvas canvas, Offset tip) {
    final alpha = pose.visible.clamp(0.0, 1.0);
    canvas.drawCircle(
      tip,
      5.5,
      Paint()..color = const Color(0xFF1B5E20).withValues(alpha: alpha),
    );
    canvas.drawCircle(
      tip,
      3.2,
      Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: alpha),
    );
  }

  Offset? _project(Offset point, Size size) {
    return camera.camera.projectToScreen(
      Vector3(point.dx, point.dy, 0),
      size,
    );
  }

  @override
  bool shouldRepaint(covariant ScissorGlyphPainter oldDelegate) => true;
}
