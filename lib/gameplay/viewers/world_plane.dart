import 'package:vector_math/vector_math_64.dart';

import '../volumes/volume.dart';

/// Infinite world plane. Pan tracks the plane, not a finite face.
class WorldPlane {
  factory WorldPlane({
    required Vector3 origin,
    required Vector3 normal,
    Vector3? up,
    required double subtileSize,
  }) {
    final n = Vector3.copy(normal);
    if (n.length2 < 1e-12) {
      n.setValues(0, 1, 0);
    } else {
      n.normalize();
    }
    final upHint = Vector3.copy(up ?? stableUp(n))..normalize();
    var tangent = upHint.cross(n);
    if (tangent.length2 < 1e-10) {
      tangent = Vector3(1, 0, 0).cross(n);
      if (tangent.length2 < 1e-10) {
        tangent = Vector3(0, 0, 1).cross(n);
      }
    }
    tangent.normalize();
    final bitangent = n.cross(tangent)..normalize();
    return WorldPlane._(
      origin: Vector3.copy(origin),
      normal: n,
      up: bitangent,
      tangent: tangent,
      bitangent: bitangent,
      subtileSize: subtileSize,
    );
  }

  WorldPlane._({
    required this.origin,
    required this.normal,
    required this.up,
    required this.tangent,
    required this.bitangent,
    required this.subtileSize,
  });

  final Vector3 origin;
  final Vector3 normal;
  final Vector3 up;
  final Vector3 tangent;
  final Vector3 bitangent;
  final double subtileSize;

  bool get isGround => normal.y > 0.9 && origin.y.abs() < 1e-3;

  /// World-axis pair that lies in this plane (for a lattice that does not
  /// depend on where the user clicked).
  (Vector3 a, Vector3 b) get worldLatticeAxes {
    final nx = normal.x.abs();
    final ny = normal.y.abs();
    final nz = normal.z.abs();
    if (ny >= nx && ny >= nz) {
      return (Vector3(1, 0, 0), Vector3(0, 0, 1));
    }
    if (nx >= nz) {
      return (Vector3(0, 1, 0), Vector3(0, 0, 1));
    }
    return (Vector3(1, 0, 0), Vector3(0, 1, 0));
  }

  /// Point on this plane at lattice coordinates (a, b) along [worldLatticeAxes].
  Vector3 latticePoint(double a, double b) {
    final nx = normal.x.abs();
    final ny = normal.y.abs();
    final nz = normal.z.abs();
    if (ny >= nx && ny >= nz) {
      return Vector3(a, origin.y, b);
    }
    if (nx >= nz) {
      return Vector3(origin.x, a, b);
    }
    return Vector3(a, b, origin.z);
  }

  (double a, double b) worldLatticeCoords(Vector3 world) {
    final nx = normal.x.abs();
    final ny = normal.y.abs();
    final nz = normal.z.abs();
    if (ny >= nx && ny >= nz) return (world.x, world.z);
    if (nx >= nz) return (world.y, world.z);
    return (world.x, world.y);
  }

  Vector3 point(double u, double v) => origin + tangent * u + bitangent * v;

  (double u, double v) toUv(Vector3 world) {
    final d = world - origin;
    return (d.dot(tangent), d.dot(bitangent));
  }

  Vector3? intersectRay(Vector3 rayOrigin, Vector3 rayDir) {
    final denom = rayDir.dot(normal);
    if (denom.abs() < 1e-8) return null;
    final t = (origin - rayOrigin).dot(normal) / denom;
    if (t < 0) return null;
    return rayOrigin + rayDir * t;
  }

  static Vector3 stableUp(Vector3 normal) {
    final n = Vector3.copy(normal)..normalize();
    final worldUp = Vector3(0, 1, 0);
    if (n.dot(worldUp).abs() > 0.95) {
      return Vector3(0, 0, n.y >= 0 ? 1 : -1);
    }
    return worldUp;
  }

  factory WorldPlane.ground({
    required Vector3 origin,
    required double subtileSize,
  }) {
    return WorldPlane(
      origin: Vector3(origin.x, 0, origin.z),
      normal: Vector3(0, 1, 0),
      subtileSize: subtileSize,
    );
  }

  factory WorldPlane.fromVolumeFace({
    required VolumeGrid grid,
    required VolumeCell cell,
    required VolumeFace face,
  }) {
    final min = cell.box.worldMin(grid, cell.tx, cell.ty);
    final max = cell.box.worldMax(grid, cell.tx, cell.ty);
    final (origin, normal) = face.originAndNormal(min, max);
    return WorldPlane(
      origin: origin,
      normal: normal,
      subtileSize: grid.subtileSize,
    );
  }

  /// True when [other] has the same facing and lies on this plane.
  /// Does not assume axis-aligned or equal origins (rotated / trapezoid later).
  bool isCoplanarWith(WorldPlane other, {double eps = 1e-3}) {
    if (normal.dot(other.normal) < 0.99) return false;
    return (other.origin - origin).dot(normal).abs() <= eps;
  }

  Vector3 projectPoint(Vector3 point) =>
      point - normal * (point - origin).dot(normal);
}

/// All six AABB faces of a volume cell, including the floor (−Y).
enum VolumeFace { posX, negX, posY, negY, posZ, negZ }

extension VolumeFaceX on VolumeFace {
  Vector3 get worldNormal => switch (this) {
        VolumeFace.posX => Vector3(1, 0, 0),
        VolumeFace.negX => Vector3(-1, 0, 0),
        VolumeFace.posY => Vector3(0, 1, 0),
        VolumeFace.negY => Vector3(0, -1, 0),
        VolumeFace.posZ => Vector3(0, 0, 1),
        VolumeFace.negZ => Vector3(0, 0, -1),
      };

  (Vector3 origin, Vector3 normal) originAndNormal(Vector3 min, Vector3 max) {
    final midX = (min.x + max.x) * 0.5;
    final midY = (min.y + max.y) * 0.5;
    final midZ = (min.z + max.z) * 0.5;
    return switch (this) {
      VolumeFace.posX => (Vector3(max.x, midY, midZ), Vector3(1, 0, 0)),
      VolumeFace.negX => (Vector3(min.x, midY, midZ), Vector3(-1, 0, 0)),
      VolumeFace.posY => (Vector3(midX, max.y, midZ), Vector3(0, 1, 0)),
      VolumeFace.negY => (Vector3(midX, min.y, midZ), Vector3(0, -1, 0)),
      VolumeFace.posZ => (Vector3(midX, midY, max.z), Vector3(0, 0, 1)),
      VolumeFace.negZ => (Vector3(midX, midY, min.z), Vector3(0, 0, -1)),
    };
  }

  bool containsHit(Vector3 hit, Vector3 min, Vector3 max, {double eps = 1e-4}) {
    return switch (this) {
      VolumeFace.posX || VolumeFace.negX =>
        hit.y >= min.y - eps &&
            hit.y <= max.y + eps &&
            hit.z >= min.z - eps &&
            hit.z <= max.z + eps,
      VolumeFace.posY || VolumeFace.negY =>
        hit.x >= min.x - eps &&
            hit.x <= max.x + eps &&
            hit.z >= min.z - eps &&
            hit.z <= max.z + eps,
      VolumeFace.posZ || VolumeFace.negZ =>
        hit.x >= min.x - eps &&
            hit.x <= max.x + eps &&
            hit.y >= min.y - eps &&
            hit.y <= max.y + eps,
    };
  }

  /// [containsHit] plus sitting on this face's plane.
  bool liesOnFace(Vector3 hit, Vector3 min, Vector3 max, {double eps = 1e-3}) {
    if (!containsHit(hit, min, max, eps: eps)) return false;
    final (origin, normal) = originAndNormal(min, max);
    return (hit - origin).dot(normal).abs() <= eps;
  }
}

/// One AABB edge of a face, shared with [adjacent].
class VolumeFaceEdge {
  const VolumeFaceEdge({
    required this.adjacent,
    required this.a,
    required this.b,
  });

  final VolumeFace adjacent;
  final Vector3 a;
  final Vector3 b;
}

/// Four edges of [face] on the AABB [min]/[max], each tagged with the
/// neighboring face that shares that edge.
List<VolumeFaceEdge> volumeFaceEdges(
  VolumeFace face,
  Vector3 min,
  Vector3 max,
) {
  return switch (face) {
    VolumeFace.posX => [
        VolumeFaceEdge(
          adjacent: VolumeFace.posY,
          a: Vector3(max.x, max.y, min.z),
          b: Vector3(max.x, max.y, max.z),
        ),
        VolumeFaceEdge(
          adjacent: VolumeFace.negZ,
          a: Vector3(max.x, min.y, min.z),
          b: Vector3(max.x, max.y, min.z),
        ),
        VolumeFaceEdge(
          adjacent: VolumeFace.posZ,
          a: Vector3(max.x, min.y, max.z),
          b: Vector3(max.x, max.y, max.z),
        ),
        VolumeFaceEdge(
          adjacent: VolumeFace.negY,
          a: Vector3(max.x, min.y, min.z),
          b: Vector3(max.x, min.y, max.z),
        ),
      ],
    VolumeFace.negX => [
        VolumeFaceEdge(
          adjacent: VolumeFace.negY,
          a: Vector3(min.x, min.y, min.z),
          b: Vector3(min.x, min.y, max.z),
        ),
        VolumeFaceEdge(
          adjacent: VolumeFace.posY,
          a: Vector3(min.x, max.y, min.z),
          b: Vector3(min.x, max.y, max.z),
        ),
        VolumeFaceEdge(
          adjacent: VolumeFace.negZ,
          a: Vector3(min.x, min.y, min.z),
          b: Vector3(min.x, max.y, min.z),
        ),
        VolumeFaceEdge(
          adjacent: VolumeFace.posZ,
          a: Vector3(min.x, min.y, max.z),
          b: Vector3(min.x, max.y, max.z),
        ),
      ],
    VolumeFace.posZ => [
        VolumeFaceEdge(
          adjacent: VolumeFace.negY,
          a: Vector3(min.x, min.y, max.z),
          b: Vector3(max.x, min.y, max.z),
        ),
        VolumeFaceEdge(
          adjacent: VolumeFace.posY,
          a: Vector3(min.x, max.y, max.z),
          b: Vector3(max.x, max.y, max.z),
        ),
        VolumeFaceEdge(
          adjacent: VolumeFace.negX,
          a: Vector3(min.x, min.y, max.z),
          b: Vector3(min.x, max.y, max.z),
        ),
        VolumeFaceEdge(
          adjacent: VolumeFace.posX,
          a: Vector3(max.x, min.y, max.z),
          b: Vector3(max.x, max.y, max.z),
        ),
      ],
    VolumeFace.negZ => [
        VolumeFaceEdge(
          adjacent: VolumeFace.negY,
          a: Vector3(min.x, min.y, min.z),
          b: Vector3(max.x, min.y, min.z),
        ),
        VolumeFaceEdge(
          adjacent: VolumeFace.posY,
          a: Vector3(min.x, max.y, min.z),
          b: Vector3(max.x, max.y, min.z),
        ),
        VolumeFaceEdge(
          adjacent: VolumeFace.negX,
          a: Vector3(min.x, min.y, min.z),
          b: Vector3(min.x, max.y, min.z),
        ),
        VolumeFaceEdge(
          adjacent: VolumeFace.posX,
          a: Vector3(max.x, min.y, min.z),
          b: Vector3(max.x, max.y, min.z),
        ),
      ],
    VolumeFace.posY => [
        VolumeFaceEdge(
          adjacent: VolumeFace.negX,
          a: Vector3(min.x, max.y, min.z),
          b: Vector3(min.x, max.y, max.z),
        ),
        VolumeFaceEdge(
          adjacent: VolumeFace.posX,
          a: Vector3(max.x, max.y, min.z),
          b: Vector3(max.x, max.y, max.z),
        ),
        VolumeFaceEdge(
          adjacent: VolumeFace.negZ,
          a: Vector3(min.x, max.y, min.z),
          b: Vector3(max.x, max.y, min.z),
        ),
        VolumeFaceEdge(
          adjacent: VolumeFace.posZ,
          a: Vector3(min.x, max.y, max.z),
          b: Vector3(max.x, max.y, max.z),
        ),
      ],
    VolumeFace.negY => [
        VolumeFaceEdge(
          adjacent: VolumeFace.negX,
          a: Vector3(min.x, min.y, min.z),
          b: Vector3(min.x, min.y, max.z),
        ),
        VolumeFaceEdge(
          adjacent: VolumeFace.posX,
          a: Vector3(max.x, min.y, min.z),
          b: Vector3(max.x, min.y, max.z),
        ),
        VolumeFaceEdge(
          adjacent: VolumeFace.negZ,
          a: Vector3(min.x, min.y, min.z),
          b: Vector3(max.x, min.y, min.z),
        ),
        VolumeFaceEdge(
          adjacent: VolumeFace.posZ,
          a: Vector3(min.x, min.y, max.z),
          b: Vector3(max.x, min.y, max.z),
        ),
      ],
  };
}
