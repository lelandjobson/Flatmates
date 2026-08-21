import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../gameplay/viewers/world_plane.dart';
import '../../rendering/scene/camera.dart';

/// Subtile lattice on the focused [WorldPlane], projected to screen.
///
/// Lines follow world-axis multiples of [WorldPlane.subtileSize], not the
/// click origin, so the grid stays locked to landscape / volume subtles.
class PlaneSubtileGridOverlay extends StatelessWidget {
  const PlaneSubtileGridOverlay({
    super.key,
    required this.plane,
    required this.camera,
    required this.viewport,
    required this.lookAt,
    this.listenable,
  });

  final WorldPlane plane;
  final Camera camera;
  final Size viewport;
  final Vector3 lookAt;
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
    return IgnorePointer(
      child: CustomPaint(
        size: viewport,
        painter: _PlaneGridPainter(
          plane: plane,
          camera: camera,
          viewport: viewport,
          lookAt: lookAt,
        ),
      ),
    );
  }
}

class _PlaneGridPainter extends CustomPainter {
  _PlaneGridPainter({
    required this.plane,
    required this.camera,
    required this.viewport,
    required this.lookAt,
  });

  final WorldPlane plane;
  final Camera camera;
  final Size viewport;
  final Vector3 lookAt;

  @override
  void paint(Canvas canvas, Size size) {
    final s = plane.subtileSize;
    if (s <= 1e-6) return;
    final (aLook, bLook) = plane.worldLatticeCoords(lookAt);
    final a0 = (aLook / s).floor() * s;
    final b0 = (bLook / s).floor() * s;
    const half = 24;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    Offset? project(double a, double b) =>
        camera.projectToScreen(plane.latticePoint(a, b), viewport);

    for (var i = -half; i <= half; i++) {
      final a = a0 + i * s;
      final p0 = project(a, b0 - half * s);
      final p1 = project(a, b0 + half * s);
      if (p0 != null && p1 != null) canvas.drawLine(p0, p1, paint);
    }
    for (var j = -half; j <= half; j++) {
      final b = b0 + j * s;
      final p0 = project(a0 - half * s, b);
      final p1 = project(a0 + half * s, b);
      if (p0 != null && p1 != null) canvas.drawLine(p0, p1, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PlaneGridPainter oldDelegate) =>
      oldDelegate.lookAt != lookAt ||
      oldDelegate.camera != camera ||
      oldDelegate.viewport != viewport ||
      oldDelegate.plane.origin != plane.origin;
}
