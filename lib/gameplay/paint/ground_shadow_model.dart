import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

/// Ground-only volume shadows. Not GI / face shade.
enum GroundShadowMode {
  off,
  footprint,
  cast,
}

/// Cheap screen-space shadows for volume AABBs on Y = 0.
@immutable
class GroundShadowModel {
  const GroundShadowModel({
    this.mode = GroundShadowMode.footprint,
    this.lightX = -0.55,
    this.lightY = -1.0,
    this.lightZ = -0.35,
    this.opacity = 0.22,
    this.blurSigma = 8,
    this.maxStretch = 14,
    this.color = const Color(0xFF2C2A32),
  });

  final GroundShadowMode mode;

  /// Light-travel vector (same convention as [PlaneShadeModel]).
  final double lightX;
  final double lightY;
  final double lightZ;

  final double opacity;
  final double blurSigma;

  /// Cap on how far a cast corner may travel along the light, in world units.
  final double maxStretch;

  final Color color;

  Vector3 get lightTravel => Vector3(lightX, lightY, lightZ);

  /// World-space polygon on the ground plane, CCW in XZ when looking down +Y.
  List<Vector3> polygon(Vector3 min, Vector3 max) {
    switch (mode) {
      case GroundShadowMode.off:
        return const [];
      case GroundShadowMode.footprint:
        return footprintPolygon(min, max);
      case GroundShadowMode.cast:
        return castPolygon(
          min,
          max,
          lightTravel: lightTravel,
          maxStretch: maxStretch,
        );
    }
  }

  GroundShadowModel copyWith({
    GroundShadowMode? mode,
    double? lightX,
    double? lightY,
    double? lightZ,
    double? opacity,
    double? blurSigma,
    double? maxStretch,
    Color? color,
  }) {
    return GroundShadowModel(
      mode: mode ?? this.mode,
      lightX: lightX ?? this.lightX,
      lightY: lightY ?? this.lightY,
      lightZ: lightZ ?? this.lightZ,
      opacity: opacity ?? this.opacity,
      blurSigma: blurSigma ?? this.blurSigma,
      maxStretch: maxStretch ?? this.maxStretch,
      color: color ?? this.color,
    );
  }

  static GroundShadowModel lerp(
    GroundShadowModel a,
    GroundShadowModel b,
    double t,
  ) {
    final u = t.clamp(0.0, 1.0);
    return GroundShadowModel(
      mode: u < 0.5 ? a.mode : b.mode,
      lightX: a.lightX + (b.lightX - a.lightX) * u,
      lightY: a.lightY + (b.lightY - a.lightY) * u,
      lightZ: a.lightZ + (b.lightZ - a.lightZ) * u,
      opacity: a.opacity + (b.opacity - a.opacity) * u,
      blurSigma: a.blurSigma + (b.blurSigma - a.blurSigma) * u,
      maxStretch: a.maxStretch + (b.maxStretch - a.maxStretch) * u,
      color: Color.lerp(a.color, b.color, u)!,
    );
  }
}

/// Axis-aligned box footprint on Y = 0.
List<Vector3> footprintPolygon(Vector3 min, Vector3 max) {
  return [
    Vector3(min.x, 0, min.z),
    Vector3(min.x, 0, max.z),
    Vector3(max.x, 0, max.z),
    Vector3(max.x, 0, min.z),
  ];
}

/// Project the AABB onto Y = 0 along [lightTravel], then take the XZ hull.
List<Vector3> castPolygon(
  Vector3 min,
  Vector3 max, {
  required Vector3 lightTravel,
  double maxStretch = 14,
}) {
  final corners = <Vector3>[
    Vector3(min.x, min.y, min.z),
    Vector3(max.x, min.y, min.z),
    Vector3(min.x, min.y, max.z),
    Vector3(max.x, min.y, max.z),
    Vector3(min.x, max.y, min.z),
    Vector3(max.x, max.y, min.z),
    Vector3(min.x, max.y, max.z),
    Vector3(max.x, max.y, max.z),
  ];
  final projected = [
    for (final p in corners)
      projectOntoGround(p, lightTravel, maxStretch: maxStretch),
  ];
  final hull = convexHullXz(projected);
  return hull.isEmpty ? footprintPolygon(min, max) : hull;
}

/// Hit Y = 0 along the light ray. Grazing lights are clamped to [maxStretch].
Vector3 projectOntoGround(
  Vector3 point,
  Vector3 lightTravel, {
  double maxStretch = 14,
}) {
  final ly = lightTravel.y;
  if (ly >= -1e-4) {
    return Vector3(point.x, 0, point.z);
  }
  var t = -point.y / ly;
  if (t < 0) t = 0;
  final horiz = Vector3(lightTravel.x, 0, lightTravel.z);
  final horizLen = horiz.length;
  if (horizLen > 1e-8) {
    final travel = t * horizLen;
    final cap = maxStretch.clamp(0.0, 1e6);
    if (travel > cap) t *= cap / travel;
  }
  return Vector3(
    point.x + lightTravel.x * t,
    0,
    point.z + lightTravel.z * t,
  );
}

/// Monotone-chain convex hull in the XZ plane. Returns CCW points on Y = 0.
List<Vector3> convexHullXz(List<Vector3> points) {
  if (points.length < 3) {
    return [for (final p in points) Vector3(p.x, 0, p.z)];
  }
  final sorted = [...points]..sort((a, b) {
      final dx = a.x - b.x;
      if (dx.abs() > 1e-8) return dx < 0 ? -1 : 1;
      final dz = a.z - b.z;
      if (dz.abs() > 1e-8) return dz < 0 ? -1 : 1;
      return 0;
    });

  double cross(Vector3 o, Vector3 a, Vector3 b) =>
      (a.x - o.x) * (b.z - o.z) - (a.z - o.z) * (b.x - o.x);

  final lower = <Vector3>[];
  for (final p in sorted) {
    while (lower.length >= 2 &&
        cross(lower[lower.length - 2], lower.last, p) <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }
  final upper = <Vector3>[];
  for (final p in sorted.reversed) {
    while (upper.length >= 2 &&
        cross(upper[upper.length - 2], upper.last, p) <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }
  if (lower.isNotEmpty) lower.removeLast();
  if (upper.isNotEmpty) upper.removeLast();
  return [for (final p in [...lower, ...upper]) Vector3(p.x, 0, p.z)];
}
