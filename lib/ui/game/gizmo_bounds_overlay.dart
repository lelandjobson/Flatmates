import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../gameplay/gizmo/gizmo_target.dart';
import '../../rendering/scene/camera.dart';
import '../../rendering/scene/scene.dart';

/// Light AABB wire around the selected gizmo group.
class GizmoBoundsOverlay extends StatelessWidget {
  const GizmoBoundsOverlay({
    super.key,
    required this.target,
    required this.camera,
    required this.viewport,
    required this.listenable,
  });

  final GizmoTarget target;
  final Camera camera;
  final Size viewport;
  final Scene listenable;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        return CustomPaint(
          size: viewport,
          painter: _BoundsPainter(
            target: target,
            camera: camera,
            viewport: viewport,
          ),
        );
      },
    );
  }
}

class _BoundsPainter extends CustomPainter {
  _BoundsPainter({
    required this.target,
    required this.camera,
    required this.viewport,
  });

  final GizmoTarget target;
  final Camera camera;
  final Size viewport;

  @override
  void paint(Canvas canvas, Size size) {
    final (min, max) = target.worldBounds;
    final corners = [
      Vector3(min.x, min.y, min.z),
      Vector3(max.x, min.y, min.z),
      Vector3(max.x, min.y, max.z),
      Vector3(min.x, min.y, max.z),
      Vector3(min.x, max.y, min.z),
      Vector3(max.x, max.y, min.z),
      Vector3(max.x, max.y, max.z),
      Vector3(min.x, max.y, max.z),
    ];
    final projected = [
      for (final c in corners) camera.projectToScreen(c, viewport),
    ];
    const edges = [
      (0, 1),
      (1, 2),
      (2, 3),
      (3, 0),
      (4, 5),
      (5, 6),
      (6, 7),
      (7, 4),
      (0, 4),
      (1, 5),
      (2, 6),
      (3, 7),
    ];
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    for (final (a, b) in edges) {
      final pa = projected[a];
      final pb = projected[b];
      if (pa == null || pb == null) continue;
      canvas.drawLine(pa, pb, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BoundsPainter oldDelegate) => true;
}
