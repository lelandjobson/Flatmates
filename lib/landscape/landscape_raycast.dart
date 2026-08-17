import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../rendering/scene/camera.dart';

/// Result of picking a material pixel on the landscape plane.
@immutable
class LandscapePixelHit {
  const LandscapePixelHit({
    required this.wx,
    required this.wy,
    required this.worldPoint,
  });

  final int wx;
  final int wy;
  final Vector3 worldPoint;
}

/// Screen → camera ray → Y=0 plane → material pixel indices.
class LandscapeRaycast {
  /// Returns null if the ray misses the plane or falls outside the grid.
  static LandscapePixelHit? hitPixel({
    required Offset screen,
    required Size viewport,
    required Camera camera,
    required double worldSize,
    required int worldPixelsSide,
  }) {
    if (viewport.width <= 0 ||
        viewport.height <= 0 ||
        worldSize <= 0 ||
        worldPixelsSide <= 0) {
      return null;
    }

    final aspect = viewport.width / viewport.height;
    final mvp = camera.projectionMatrix(aspect) * camera.viewMatrix;
    final inv = Matrix4.copy(mvp);
    final det = inv.invert();
    if (det.abs() < 1e-10) return null;

    // NDC from screen (Flutter Y grows down; NDC Y grows up).
    final ndcX = (screen.dx / viewport.width) * 2.0 - 1.0;
    final ndcY = 1.0 - (screen.dy / viewport.height) * 2.0;

    final nearPoint = _unproject(inv, ndcX, ndcY, -1.0);
    final farPoint = _unproject(inv, ndcX, ndcY, 1.0);
    if (nearPoint == null || farPoint == null) return null;

    final origin = Vector3.copy(camera.position);
    final dir = farPoint - nearPoint;
    if (dir.length2 < 1e-12) return null;
    dir.normalize();

    // Ray: origin + t * dir. Intersect Y = 0.
    if (dir.y.abs() < 1e-8) return null;
    final t = -origin.y / dir.y;
    if (t < 0) return null;

    final hit = origin + dir * t;
    final half = worldSize * 0.5;
    if (hit.x < -half || hit.x >= half || hit.z < -half || hit.z >= half) {
      // Allow the max edge by using half-open on max with a tiny epsilon.
      if (hit.x < -half ||
          hit.x > half ||
          hit.z < -half ||
          hit.z > half) {
        return null;
      }
    }

    final u = ((hit.x + half) / worldSize).clamp(0.0, 1.0 - 1e-9);
    final v = ((hit.z + half) / worldSize).clamp(0.0, 1.0 - 1e-9);
    final wx = (u * worldPixelsSide).floor().clamp(0, worldPixelsSide - 1);
    final wy = (v * worldPixelsSide).floor().clamp(0, worldPixelsSide - 1);

    return LandscapePixelHit(wx: wx, wy: wy, worldPoint: hit);
  }

  static Vector3? _unproject(Matrix4 invMvp, double ndcX, double ndcY, double ndcZ) {
    final clip = Vector4(ndcX, ndcY, ndcZ, 1.0);
    invMvp.transform(clip);
    if (!_finite4(clip) || clip.w.abs() < 1e-8) return null;
    return Vector3(clip.x / clip.w, clip.y / clip.w, clip.z / clip.w);
  }

  static bool _finite4(Vector4 v) =>
      v.x.isFinite && v.y.isFinite && v.z.isFinite && v.w.isFinite;
}
