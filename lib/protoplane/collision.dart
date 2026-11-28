import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import 'geometry.dart';
import 'models.dart';
import 'room_geometry.dart';

/// Convex triangular prisms, tested with the separating-axis theorem. Curved
/// outlines and holes use the same triangulation as the visible surface.
bool solidsOverlap(CraftObject a, CraftPlane ap, CraftObject b, CraftPlane bp) {
  return CollisionSolid(a, ap).overlaps(CollisionSolid(b, bp));
}

/// Reuse immutable obstacle geometry while checking an animated swept solid.
class CollisionSolid {
  CollisionSolid(CraftObject object, CraftPlane plane)
    : cells = _cells(object, plane);
  final List<List<Vector3>> cells;
  late final List<Vector3> vertices = cells.expand((v) => v).toList();
  bool overlaps(CollisionSolid other) {
    if (!_boundsOverlap(vertices, other.vertices)) return false;
    for (final a in cells) {
      for (final b in other.cells) {
        if (_boundsOverlap(a, b) && _convexOverlap(a, b)) return true;
      }
    }
    return false;
  }
}

List<List<Vector3>> _cells(CraftObject o, CraftPlane plane) {
  // Flat paper has a small picking/rendering thickness too; it must not be
  // placed through an unrelated solid merely because its paid depth is zero.
  if (o.kind == CraftKind.room) {
    return [
      for (final panel in roomPanels(o, plane))
        for (final region in panel.regions)
          ..._cells(
            CraftObject(
              id: o.id,
              planeId: panel.frame.id,
              kind: CraftKind.paperSheet,
              region: region,
              depth: roomThickness,
            ),
            panel.frame,
          ),
    ];
  }
  final depth = math.max(.002, o.depth);
  if (o.kind == CraftKind.screen) {
    final result = <List<Vector3>>[];
    for (var i = 1; i < o.path.length; i++) {
      final a = plane.point(o.path[i - 1]), b = plane.point(o.path[i]);
      final n = (b - a).cross(plane.normal).normalized() * .004;
      final up = plane.normal * o.depth;
      // Two triangles in the screen's thin footprint, each extruded upward.
      for (final t in [
        [a + n, b + n, b - n],
        [a + n, b - n, a - n],
      ]) {
        result.add([...t, ...t.map((p) => p + up)]);
      }
    }
    return result;
  }
  return [
    for (final t in o.region.triangles)
      [...t.map((p) => plane.point(p)), ...t.map((p) => plane.point(p, depth))],
  ];
}

bool _boundsOverlap(List<Vector3> a, List<Vector3> b) {
  if (a.isEmpty || b.isEmpty) return false;
  for (var axis = 0; axis < 3; axis++) {
    final amin = a.map((p) => p[axis]).reduce(math.min),
        amax = a.map((p) => p[axis]).reduce(math.max);
    final bmin = b.map((p) => p[axis]).reduce(math.min),
        bmax = b.map((p) => p[axis]).reduce(math.max);
    if (math.min(amax, bmax) - math.max(amin, bmin) <= geometryEpsilon) {
      return false;
    }
  }
  return true;
}

bool _convexOverlap(List<Vector3> a, List<Vector3> b) {
  List<Vector3> edgeDirections(List<Vector3> v) => [
    v[1] - v[0],
    v[2] - v[1],
    v[0] - v[2],
    v[3] - v[0],
  ];
  List<Vector3> normals(List<Vector3> v) => [
    (v[1] - v[0]).cross(v[2] - v[0]),
    for (var i = 0; i < 3; i++) (v[(i + 1) % 3] - v[i]).cross(v[i + 3] - v[i]),
  ];
  final axes = [
    ...normals(a),
    ...normals(b),
    for (final ae in edgeDirections(a))
      for (final be in edgeDirections(b)) ae.cross(be),
  ];
  for (final axis in axes) {
    if (axis.length2 < 1e-16) continue;
    axis.normalize();
    final amin = a.map((p) => p.dot(axis)).reduce(math.min),
        amax = a.map((p) => p.dot(axis)).reduce(math.max);
    final bmin = b.map((p) => p.dot(axis)).reduce(math.min),
        bmax = b.map((p) => p.dot(axis)).reduce(math.max);
    if (math.min(amax, bmax) - math.max(amin, bmin) <= geometryEpsilon) {
      return false;
    }
  }
  return true;
}
