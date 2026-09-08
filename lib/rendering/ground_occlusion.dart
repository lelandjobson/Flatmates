import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import 'scene/camera.dart';

/// How far the clip hole is grown so the door rim does not flicker.
const kWallHoleClipPad = 0.06;

const _kPlaneEps = 1e-4;

/// Rectangle in Z = [z] with a hole. Blocks rays that hit the wall, not the hole.
class WallHoleOccluder {
  const WallHoleOccluder({
    required this.z,
    required this.x0,
    required this.x1,
    required this.y0,
    required this.y1,
    required this.holeX0,
    required this.holeX1,
    required this.holeY0,
    required this.holeY1,
  });

  final double z;
  final double x0;
  final double x1;
  final double y0;
  final double y1;
  final double holeX0;
  final double holeX1;
  final double holeY0;
  final double holeY1;

  /// Slightly larger hole used when clipping so the opening stays stable.
  WallHoleOccluder get clipHole {
    const pad = kWallHoleClipPad;
    return WallHoleOccluder(
      z: z,
      x0: x0,
      x1: x1,
      y0: y0,
      y1: y1,
      holeX0: math.max(x0, holeX0 - pad),
      holeX1: math.min(x1, holeX1 + pad),
      holeY0: math.max(y0, holeY0 - pad),
      holeY1: math.min(y1, holeY1 + pad),
    );
  }
}

/// Axis-aligned hole in the ground plane. Used to clip underground faces
/// to the camera frustum through the cut, so they do not show through grass.
class GroundHoleRect {
  const GroundHoleRect({
    required this.x0,
    required this.x1,
    required this.z0,
    required this.z1,
    this.y = 0,
  });

  final double x0;
  final double x1;
  final double z0;
  final double z1;
  final double y;

  static GroundHoleRect? fromTiles(
    Set<(int, int)> tiles,
    double tileSize, {
    double y = 0,
  }) {
    if (tiles.isEmpty) return null;
    var minX = double.infinity;
    var maxX = double.negativeInfinity;
    var minZ = double.infinity;
    var maxZ = double.negativeInfinity;
    for (final (tx, ty) in tiles) {
      minX = math.min(minX, tx * tileSize);
      maxX = math.max(maxX, (tx + 1) * tileSize);
      minZ = math.min(minZ, ty * tileSize);
      maxZ = math.max(maxZ, (ty + 1) * tileSize);
    }
    return GroundHoleRect(x0: minX, x1: maxX, z0: minZ, z1: maxZ, y: y);
  }
}

/// Opt-in ground-plane occlusion for underground meshes.
///
/// A point below [planeY] is visible only if the camera ray hits the plane
/// inside [holeTiles] before the point. At-grade meshes leave this null.
class GroundOcclusion {
  const GroundOcclusion({
    required this.holeTiles,
    this.planeY = 0,
    this.tileSize = 8,
    this.clipPartial = true,
    this.wallHole,
    this.groundHole,
    this.visibilityProbe,
  });

  final Set<(int, int)> holeTiles;
  final double planeY;
  final double tileSize;

  /// When false, a face is kept whole or dropped from [visibilityProbe]
  /// (or its center). Use for solid walls that must stay opaque.
  final bool clipPartial;

  /// Optional facade that hides points whose camera ray hits the wall.
  final WallHoleOccluder? wallHole;

  /// When set, faces are clipped to the camera frustum through this hole
  /// instead of a per-vertex tile test.
  final GroundHoleRect? groundHole;

  /// Shared probe for [clipPartial] == false so a multi-quad wall stays whole.
  final Vector3? visibilityProbe;

  (int, int) tileAtHit(double x, double z) =>
      ((x / tileSize).floor(), (z / tileSize).floor());

  GroundOcclusion withoutWallHole() => GroundOcclusion(
        holeTiles: holeTiles,
        planeY: planeY,
        tileSize: tileSize,
        clipPartial: clipPartial,
        groundHole: groundHole,
        visibilityProbe: visibilityProbe,
      );
}

/// True when the camera ray to [point] misses [wall], or goes through its hole.
bool visiblePastWallHole(
  Camera camera,
  Vector3 point,
  WallHoleOccluder wall,
) {
  final origin = camera.position;
  final dz = point.z - origin.z;
  if (dz.abs() < 1e-12) return true;
  final t = (wall.z - origin.z) / dz;
  if (t <= _kPlaneEps || t >= 1 - _kPlaneEps) return true;
  final hitX = origin.x + (point.x - origin.x) * t;
  final hitY = origin.y + (point.y - origin.y) * t;
  final onWall = hitX >= wall.x0 &&
      hitX <= wall.x1 &&
      hitY >= wall.y0 &&
      hitY <= wall.y1;
  if (!onWall) return true;
  return hitX >= wall.holeX0 &&
      hitX <= wall.holeX1 &&
      hitY >= wall.holeY0 &&
      hitY <= wall.holeY1;
}

/// True when [point] is not covered by solid ground from [camera].
bool visibleThroughGround(
  Camera camera,
  Vector3 point,
  GroundOcclusion occlusion,
) {
  var throughHole = true;
  if (point.y < occlusion.planeY - 1e-8) {
    final origin = camera.position;
    if (origin.y > occlusion.planeY + 1e-8) {
      final dy = origin.y - point.y;
      if (dy.abs() >= 1e-10) {
        final t = (origin.y - occlusion.planeY) / dy;
        if (t > 1e-8 && t < 1 - 1e-8) {
          final hitX = origin.x + (point.x - origin.x) * t;
          final hitZ = origin.z + (point.z - origin.z) * t;
          throughHole =
              occlusion.holeTiles.contains(occlusion.tileAtHit(hitX, hitZ));
        }
      }
    }
  }
  if (!throughHole) return false;
  final wall = occlusion.wallHole;
  return wall == null || visiblePastWallHole(camera, point, wall);
}

Vector3 _lerp(Vector3 a, Vector3 b, double t) =>
    Vector3(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t);

double _side(Vector3 p, Vector3 planePoint, Vector3 normal) =>
    normal.dot(p - planePoint);

Vector3? _intersect(
  Vector3 a,
  Vector3 b,
  Vector3 planePoint,
  Vector3 normal,
) {
  final denom = normal.dot(b - a);
  if (denom.abs() < 1e-12) return null;
  final t = normal.dot(planePoint - a) / denom;
  return _lerp(a, b, t.clamp(0.0, 1.0));
}

/// Sutherland–Hodgman clip of [poly] to n·(p − planePoint) ≥ −eps.
List<Vector3> clipPolygonHalfspace(
  List<Vector3> poly,
  Vector3 planePoint,
  Vector3 normal, {
  double eps = _kPlaneEps,
}) {
  if (poly.length < 3) return const [];
  final out = <Vector3>[];
  for (var i = 0; i < poly.length; i++) {
    final s = poly[i];
    final e = poly[(i + 1) % poly.length];
    final sIn = _side(s, planePoint, normal) >= -eps;
    final eIn = _side(e, planePoint, normal) >= -eps;
    if (eIn) {
      if (!sIn) {
        final hit = _intersect(s, e, planePoint, normal);
        if (hit != null) out.add(hit);
      }
      out.add(e);
    } else if (sIn) {
      final hit = _intersect(s, e, planePoint, normal);
      if (hit != null) out.add(hit);
    }
  }
  return out.length >= 3 ? out : const [];
}

List<Vector3>? clipSegmentHalfspace(
  Vector3 a,
  Vector3 b,
  Vector3 planePoint,
  Vector3 normal, {
  double eps = _kPlaneEps,
}) {
  final aIn = _side(a, planePoint, normal) >= -eps;
  final bIn = _side(b, planePoint, normal) >= -eps;
  if (aIn && bIn) return [a, b];
  if (!aIn && !bIn) return null;
  final hit = _intersect(a, b, planePoint, normal);
  if (hit == null) return aIn ? [a, b] : null;
  return aIn ? [a, hit] : [hit, b];
}

List<Vector3> clipPolygonByZ(
  List<Vector3> poly,
  double z, {
  required bool keepFront,
}) {
  return clipPolygonHalfspace(
    poly,
    Vector3(0, 0, z),
    Vector3(0, 0, keepFront ? 1.0 : -1.0),
  );
}

List<Vector3>? clipSegmentByZ(
  Vector3 a,
  Vector3 b,
  double z, {
  required bool keepFront,
}) {
  return clipSegmentHalfspace(
    a,
    b,
    Vector3(0, 0, z),
    Vector3(0, 0, keepFront ? 1.0 : -1.0),
  );
}

List<Vector3> clipPolygonToDoorFrustum(
  List<Vector3> poly,
  Camera camera,
  WallHoleOccluder wall,
) {
  final hole = wall.clipHole;
  final origin = camera.position;
  final corners = [
    Vector3(hole.holeX0, hole.holeY0, hole.z),
    Vector3(hole.holeX1, hole.holeY0, hole.z),
    Vector3(hole.holeX1, hole.holeY1, hole.z),
    Vector3(hole.holeX0, hole.holeY1, hole.z),
  ];
  final mid = Vector3(
    (hole.holeX0 + hole.holeX1) * 0.5,
    (hole.holeY0 + hole.holeY1) * 0.5,
    hole.z,
  );
  var out = poly;
  for (var i = 0; i < 4; i++) {
    final a = corners[i];
    final b = corners[(i + 1) % 4];
    var n = (a - origin).cross(b - origin);
    if (n.length2 < 1e-16) continue;
    if (n.dot(mid - origin) < 0) n = -n;
    out = clipPolygonHalfspace(out, origin, n);
    if (out.length < 3) return const [];
  }
  return out;
}

List<Vector3>? clipSegmentToDoorFrustum(
  Vector3 a,
  Vector3 b,
  Camera camera,
  WallHoleOccluder wall,
) {
  final hole = wall.clipHole;
  final origin = camera.position;
  final corners = [
    Vector3(hole.holeX0, hole.holeY0, hole.z),
    Vector3(hole.holeX1, hole.holeY0, hole.z),
    Vector3(hole.holeX1, hole.holeY1, hole.z),
    Vector3(hole.holeX0, hole.holeY1, hole.z),
  ];
  final mid = Vector3(
    (hole.holeX0 + hole.holeX1) * 0.5,
    (hole.holeY0 + hole.holeY1) * 0.5,
    hole.z,
  );
  Vector3? sa = a;
  Vector3? sb = b;
  for (var i = 0; i < 4; i++) {
    final ca = corners[i];
    final cb = corners[(i + 1) % 4];
    var n = (ca - origin).cross(cb - origin);
    if (n.length2 < 1e-16) continue;
    if (n.dot(mid - origin) < 0) n = -n;
    final clipped = clipSegmentHalfspace(sa!, sb!, origin, n);
    if (clipped == null) return null;
    sa = clipped[0];
    sb = clipped[1];
  }
  return [sa!, sb!];
}

List<Vector3> clipPolygonToGroundHoleFrustum(
  List<Vector3> poly,
  Camera camera,
  GroundHoleRect hole,
) {
  const pad = kWallHoleClipPad;
  final x0 = hole.x0 - pad;
  final x1 = hole.x1 + pad;
  // Do not pad the north (min-Z) seam — that is the door, and padding it
  // into the bridge lets the wall show through the grass.
  final z0 = hole.z0;
  final z1 = hole.z1 + pad;
  final origin = camera.position;
  final corners = [
    Vector3(x0, hole.y, z0),
    Vector3(x1, hole.y, z0),
    Vector3(x1, hole.y, z1),
    Vector3(x0, hole.y, z1),
  ];
  final mid = Vector3((x0 + x1) * 0.5, hole.y, (z0 + z1) * 0.5);
  var out = poly;
  for (var i = 0; i < 4; i++) {
    final a = corners[i];
    final b = corners[(i + 1) % 4];
    var n = (a - origin).cross(b - origin);
    if (n.length2 < 1e-16) continue;
    if (n.dot(mid - origin) < 0) n = -n;
    out = clipPolygonHalfspace(out, origin, n);
    if (out.length < 3) return const [];
  }
  return out;
}

List<Vector3>? clipSegmentToGroundHoleFrustum(
  Vector3 a,
  Vector3 b,
  Camera camera,
  GroundHoleRect hole,
) {
  const pad = kWallHoleClipPad;
  final x0 = hole.x0 - pad;
  final x1 = hole.x1 + pad;
  final z0 = hole.z0;
  final z1 = hole.z1 + pad;
  final origin = camera.position;
  final corners = [
    Vector3(x0, hole.y, z0),
    Vector3(x1, hole.y, z0),
    Vector3(x1, hole.y, z1),
    Vector3(x0, hole.y, z1),
  ];
  final mid = Vector3((x0 + x1) * 0.5, hole.y, (z0 + z1) * 0.5);
  Vector3? sa = a;
  Vector3? sb = b;
  for (var i = 0; i < 4; i++) {
    final ca = corners[i];
    final cb = corners[(i + 1) % 4];
    var n = (ca - origin).cross(cb - origin);
    if (n.length2 < 1e-16) continue;
    if (n.dot(mid - origin) < 0) n = -n;
    final clipped = clipSegmentHalfspace(sa!, sb!, origin, n);
    if (clipped == null) return null;
    sa = clipped[0];
    sb = clipped[1];
  }
  return [sa!, sb!];
}

Vector3? groundVisibilitySplit(
  Camera camera,
  Vector3 a,
  Vector3 b,
  GroundOcclusion occlusion,
) {
  final visA = visibleThroughGround(camera, a, occlusion);
  final visB = visibleThroughGround(camera, b, occlusion);
  if (visA == visB) return null;
  var t0 = 0.0;
  var t1 = 1.0;
  var vis0 = visA;
  for (var i = 0; i < 18; i++) {
    final tm = (t0 + t1) * 0.5;
    final mid = _lerp(a, b, tm);
    if (visibleThroughGround(camera, mid, occlusion) == vis0) {
      t0 = tm;
    } else {
      t1 = tm;
    }
  }
  return _lerp(a, b, (t0 + t1) * 0.5);
}

List<Vector3> _clipPolygonToGroundHole(
  Camera camera,
  List<Vector3> worldVerts,
  GroundOcclusion occlusion,
) {
  if (worldVerts.length < 3) return const [];
  final rect = occlusion.groundHole;
  if (rect != null && camera.position.y > rect.y + 1e-6) {
    var clipped = clipPolygonToGroundHoleFrustum(worldVerts, camera, rect);
    if (clipped.length < 3) return const [];
    // Drop the at-grade lip so the wall cannot composite over the grass.
    return clipPolygonHalfspace(
      clipped,
      Vector3(0, rect.y - 0.03, 0),
      Vector3(0, -1, 0),
    );
  }
  final vis = [
    for (final v in worldVerts) visibleThroughGround(camera, v, occlusion),
  ];
  if (vis.every((v) => v)) return worldVerts;
  if (vis.every((v) => !v)) return const [];

  final out = <Vector3>[];
  final n = worldVerts.length;
  for (var i = 0; i < n; i++) {
    final j = (i + 1) % n;
    final a = worldVerts[i];
    final b = worldVerts[j];
    final aVis = vis[i];
    final bVis = vis[j];
    if (bVis) {
      if (!aVis) {
        final split = groundVisibilitySplit(camera, a, b, occlusion);
        if (split != null) out.add(split);
      }
      out.add(b);
    } else if (aVis) {
      final split = groundVisibilitySplit(camera, a, b, occlusion);
      if (split != null) out.add(split);
    }
  }
  return out.length >= 3 ? out : const [];
}

List<Vector3> _clipSegmentToGroundHole(
  Camera camera,
  Vector3 a,
  Vector3 b,
  GroundOcclusion occlusion,
) {
  final rect = occlusion.groundHole;
  if (rect != null && camera.position.y > rect.y + 1e-6) {
    final through = clipSegmentToGroundHoleFrustum(a, b, camera, rect);
    if (through == null) return const [];
    return clipSegmentHalfspace(
          through[0],
          through[1],
          Vector3(0, rect.y - 0.03, 0),
          Vector3(0, -1, 0),
        ) ??
        const [];
  }
  final visA = visibleThroughGround(camera, a, occlusion);
  final visB = visibleThroughGround(camera, b, occlusion);
  if (visA && visB) return [a, b];
  if (!visA && !visB) return const [];
  final split = groundVisibilitySplit(camera, a, b, occlusion);
  if (split == null) return visA ? [a, b] : const [];
  return visA ? [a, split] : [split, b];
}

bool _atGrade(Vector3 p, GroundOcclusion occlusion) =>
    p.y >= occlusion.planeY - 1e-6;

/// Visible remnants of [worldVerts] after ground and door-frustum clips.
List<List<Vector3>> clipFaceToVisibleParts(
  Camera camera,
  List<Vector3> worldVerts,
  GroundOcclusion occlusion,
) {
  if (worldVerts.length < 3) return const [];
  if (worldVerts.every((v) => _atGrade(v, occlusion))) {
    return [worldVerts];
  }
  if (!occlusion.clipPartial) {
    final center = Vector3.zero();
    for (final v in worldVerts) {
      center.add(v);
    }
    center.scale(1 / worldVerts.length);
    final probe = occlusion.visibilityProbe ??
        (center.y >= occlusion.planeY - 1e-6
            ? Vector3(center.x, occlusion.planeY - 0.1, center.z)
            : center);
    return visibleThroughGround(camera, probe, occlusion.withoutWallHole())
        ? [worldVerts]
        : const [];
  }

  final wall = occlusion.wallHole;
  final hole = occlusion.withoutWallHole();
  if (wall == null) {
    final clipped = _clipPolygonToGroundHole(camera, worldVerts, hole);
    return clipped.length >= 3 ? [clipped] : const [];
  }

  final parts = <List<Vector3>>[];
  final front = clipPolygonByZ(worldVerts, wall.z, keepFront: true);
  if (front.length >= 3) {
    final clipped = _clipPolygonToGroundHole(camera, front, hole);
    if (clipped.length >= 3) parts.add(clipped);
  }
  var back = clipPolygonByZ(worldVerts, wall.z, keepFront: false);
  if (back.length >= 3) {
    back = clipPolygonToDoorFrustum(back, camera, wall);
    if (back.length >= 3) {
      final clipped = _clipPolygonToGroundHole(camera, back, hole);
      if (clipped.length >= 3) parts.add(clipped);
    }
  }
  return parts;
}

/// Visible remnants of segment [a]–[b].
List<List<Vector3>> clipSegmentToVisibleParts(
  Camera camera,
  Vector3 a,
  Vector3 b,
  GroundOcclusion occlusion,
) {
  if (_atGrade(a, occlusion) && _atGrade(b, occlusion)) {
    return [
      [a, b],
    ];
  }
  if (!occlusion.clipPartial) {
    final probe = occlusion.visibilityProbe ?? _lerp(a, b, 0.5);
    return visibleThroughGround(camera, probe, occlusion.withoutWallHole())
        ? [
            [a, b],
          ]
        : const [];
  }

  final wall = occlusion.wallHole;
  final hole = occlusion.withoutWallHole();
  if (wall == null) {
    final clipped = _clipSegmentToGroundHole(camera, a, b, hole);
    return clipped.length >= 2 ? [clipped] : const [];
  }

  final parts = <List<Vector3>>[];
  final front = clipSegmentByZ(a, b, wall.z, keepFront: true);
  if (front != null) {
    final clipped = _clipSegmentToGroundHole(camera, front[0], front[1], hole);
    if (clipped.length >= 2) parts.add(clipped);
  }
  final back = clipSegmentByZ(a, b, wall.z, keepFront: false);
  if (back != null) {
    final through = clipSegmentToDoorFrustum(back[0], back[1], camera, wall);
    if (through != null) {
      final clipped =
          _clipSegmentToGroundHole(camera, through[0], through[1], hole);
      if (clipped.length >= 2) parts.add(clipped);
    }
  }
  return parts;
}

/// Visible remnant of segment [a]–[b], or empty if the whole edge is hidden.
List<Vector3> clipSegmentToVisible(
  Camera camera,
  Vector3 a,
  Vector3 b,
  GroundOcclusion occlusion,
) {
  final parts = clipSegmentToVisibleParts(camera, a, b, occlusion);
  return parts.isEmpty ? const [] : parts.first;
}

/// Keeps the portion of [worldVerts] visible through the ground hole.
///
/// Empty when the whole face is hidden. One polygon otherwise. Prefer
/// [clipFaceToVisibleParts] when a door can split a face in two.
List<Vector3> clipFaceToVisible(
  Camera camera,
  List<Vector3> worldVerts,
  GroundOcclusion occlusion,
) {
  final parts = clipFaceToVisibleParts(camera, worldVerts, occlusion);
  return parts.isEmpty ? const [] : parts.first;
}
