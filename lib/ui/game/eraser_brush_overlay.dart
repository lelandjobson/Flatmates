import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../rendering/scene/camera.dart';

/// Ground-plane circle showing the map eraser radius.
class EraserBrushOverlay extends StatelessWidget {
  const EraserBrushOverlay({
    super.key,
    required this.worldCenter,
    required this.radius,
    required this.camera,
    required this.viewport,
    this.listenable,
  });

  final Vector3? worldCenter;
  final double radius;
  final Camera camera;
  final Size viewport;
  final Listenable? listenable;

  @override
  Widget build(BuildContext context) {
    final listenable = this.listenable;
    if (listenable != null) {
      return ListenableBuilder(
        listenable: listenable,
        builder: (context, _) => _paint(),
      );
    }
    return _paint();
  }

  Widget _paint() {
    final center = worldCenter;
    if (center == null || radius <= 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        size: viewport,
        painter: _EraserBrushPainter(
          worldCenter: center,
          radius: radius,
          camera: camera,
          viewport: viewport,
        ),
      ),
    );
  }
}

class _EraserBrushPainter extends CustomPainter {
  _EraserBrushPainter({
    required this.worldCenter,
    required this.radius,
    required this.camera,
    required this.viewport,
  });

  final Vector3 worldCenter;
  final double radius;
  final Camera camera;
  final Size viewport;

  @override
  void paint(Canvas canvas, Size size) {
    const steps = 32;
    final path = Path();
    Offset? first;
    for (var i = 0; i < steps; i++) {
      final a = i / steps * math.pi * 2;
      final world = Vector3(
        worldCenter.x + radius * math.cos(a),
        0.06,
        worldCenter.z + radius * math.sin(a),
      );
      final screen = camera.projectToScreen(world, viewport);
      if (screen == null) continue;
      if (first == null) {
        first = screen;
        path.moveTo(screen.dx, screen.dy);
      } else {
        path.lineTo(screen.dx, screen.dy);
      }
    }
    if (first == null) return;
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0x55FF8A80)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xCCFF8A80)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _EraserBrushPainter oldDelegate) =>
      oldDelegate.worldCenter != worldCenter ||
      oldDelegate.radius != radius ||
      oldDelegate.camera != camera ||
      oldDelegate.viewport != viewport;
}
