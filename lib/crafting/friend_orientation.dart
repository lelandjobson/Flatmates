import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../geometry/geometry.dart';

// ---------------------------------------------------------------------------
// Orientation enum
// ---------------------------------------------------------------------------

enum FriendOrientation {
  flatFlush,
  edgeFlush,
  intersecting;

  Color get color => switch (this) {
        FriendOrientation.flatFlush => Colors.yellow,
        FriendOrientation.edgeFlush => Colors.blue,
        FriendOrientation.intersecting => Colors.red,
      };

  String get label => switch (this) {
        FriendOrientation.flatFlush => 'flat_flush',
        FriendOrientation.edgeFlush => 'edge_flush',
        FriendOrientation.intersecting => 'intersecting',
      };
}

// ---------------------------------------------------------------------------
// Line types (cut/scored onto papers)
// ---------------------------------------------------------------------------

enum LineType { cut, scoring }

class DrawnLine {
  const DrawnLine({
    required this.start,
    required this.end,
    required this.type,
  });

  final Offset start;
  final Offset end;
  final LineType type;
}

// ---------------------------------------------------------------------------
// Ground edge with facing-face info
// ---------------------------------------------------------------------------

class GroundEdge {
  const GroundEdge({
    required this.worldA,
    required this.worldB,
    required this.isFacingEdge,
  });

  final Vector3 worldA;
  final Vector3 worldB;
  final bool isFacingEdge;

  Offset get xyA => Offset(worldA.x, worldA.y);
  Offset get xyB => Offset(worldB.x, worldB.y);
}

const double _tolerance = 1e-3;

/// Computes the minimum z among all vertices after applying [rotation].
///
/// Uses only the third row of the rotation matrix (avoids full transforms).
double minZForRotation(List<Vector3> vertices, Quaternion rotation) {
  final rot = rotation.asRotationMatrix();
  final r20 = rot.entry(2, 0);
  final r21 = rot.entry(2, 1);
  final r22 = rot.entry(2, 2);
  double minZ = double.infinity;
  for (final v in vertices) {
    final rz = r20 * v.x + r21 * v.y + r22 * v.z;
    if (rz < minZ) minZ = rz;
  }
  return minZ;
}

/// Returns the z-extent (max z - min z) of the rotated geometry.
double friendHeightForRotation(List<Vector3> vertices, Quaternion rotation) {
  final rot = rotation.asRotationMatrix();
  final r20 = rot.entry(2, 0);
  final r21 = rot.entry(2, 1);
  final r22 = rot.entry(2, 2);
  double minZ = double.infinity;
  double maxZ = double.negativeInfinity;
  for (final v in vertices) {
    final rz = r20 * v.x + r21 * v.y + r22 * v.z;
    if (rz < minZ) minZ = rz;
    if (rz > maxZ) maxZ = rz;
  }
  return maxZ - minZ;
}

/// Classifies the friend's orientation relative to the ground plane (z = 0).
///
/// Priority: intersecting > flatFlush > edgeFlush.
FriendOrientation classifyOrientation(
  Geometry geometry,
  Quaternion rotation,
  Vector3 position,
) {
  final rot = rotation.asRotationMatrix();

  // Check for intersection: any world-space vertex below -tolerance.
  final r20 = rot.entry(2, 0);
  final r21 = rot.entry(2, 1);
  final r22 = rot.entry(2, 2);
  for (final v in geometry.vertices) {
    final worldZ = r20 * v.x + r21 * v.y + r22 * v.z + position.z;
    if (worldZ < -_tolerance) return FriendOrientation.intersecting;
  }

  // Check for flat flush: any face normal (rotated) nearly parallel to ±Z.
  for (final face in geometry.faces) {
    if (face.length < 3) continue;
    final a = geometry.vertices[face[0]];
    final b = geometry.vertices[face[1]];
    final c = geometry.vertices[face[2]];
    final e1 = b - a;
    final e2 = c - a;
    final localNormal = e1.cross(e2);
    if (localNormal.length2 < 1e-12) continue;
    localNormal.normalize();
    // Only need the z-component of the rotated normal.
    final nz = r20 * localNormal.x + r21 * localNormal.y + r22 * localNormal.z;
    if (nz.abs() > 1.0 - _tolerance) return FriendOrientation.flatFlush;
  }

  return FriendOrientation.edgeFlush;
}

/// Finds the face whose outward normal (in local space) best aligns with
/// [localFacingDir]. Returns the face index, or 0 if the geometry is empty.
int findFacingFaceIndex(Geometry geometry, Vector3 localFacingDir) {
  int bestFace = 0;
  double bestDot = double.negativeInfinity;
  for (int fi = 0; fi < geometry.faces.length; fi++) {
    final face = geometry.faces[fi];
    if (face.length < 3) continue;
    final a = geometry.vertices[face[0]];
    final b = geometry.vertices[face[1]];
    final c = geometry.vertices[face[2]];
    final normal = (b - a).cross(c - a);
    if (normal.length2 < 1e-12) continue;
    normal.normalize();
    final dot = normal.dot(localFacingDir);
    if (dot > bestDot) {
      bestDot = dot;
      bestFace = fi;
    }
  }
  return bestFace;
}

/// Returns world-space ground edges with facing-face classification.
///
/// An edge is marked [GroundEdge.isFacingEdge] when both its vertex indices
/// appear as an adjacent pair in the face at [facingFaceIndex].
List<GroundEdge> classifyGroundEdges(
  Geometry geometry,
  Quaternion rotation,
  Vector3 position,
  int facingFaceIndex,
) {
  final rot = rotation.asRotationMatrix();
  final worldVerts = <Vector3>[];
  for (final v in geometry.vertices) {
    worldVerts.add(Vector3(
      rot.entry(0, 0) * v.x + rot.entry(0, 1) * v.y + rot.entry(0, 2) * v.z + position.x,
      rot.entry(1, 0) * v.x + rot.entry(1, 1) * v.y + rot.entry(1, 2) * v.z + position.y,
      rot.entry(2, 0) * v.x + rot.entry(2, 1) * v.y + rot.entry(2, 2) * v.z + position.z,
    ));
  }

  // Collect the edge-set of the facing face for quick lookup.
  final facingEdges = <(int, int)>{};
  if (facingFaceIndex < geometry.faces.length) {
    final ff = geometry.faces[facingFaceIndex];
    for (var i = 0; i < ff.length; i++) {
      final ai = ff[i];
      final bi = ff[(i + 1) % ff.length];
      facingEdges.add(ai < bi ? (ai, bi) : (bi, ai));
    }
  }

  const groundTolerance = 2.0;
  final result = <GroundEdge>[];
  final visited = <(int, int)>{};

  for (final face in geometry.faces) {
    for (var i = 0; i < face.length; i++) {
      final ai = face[i];
      final bi = face[(i + 1) % face.length];
      final edgeKey = ai < bi ? (ai, bi) : (bi, ai);
      if (!visited.add(edgeKey)) continue;

      final va = worldVerts[ai];
      final vb = worldVerts[bi];
      if (va.z.abs() <= groundTolerance && vb.z.abs() <= groundTolerance) {
        result.add(GroundEdge(
          worldA: va,
          worldB: vb,
          isFacingEdge: facingEdges.contains(edgeKey),
        ));
      }
    }
  }
  return result;
}

/// Returns lines to cut/score onto the drawing plane for the current
/// orientation.
///
/// - flat_flush: only the facing edge → cut line; other ground edges ignored.
/// - edge_flush: all ground edges → scoring lines.
/// - intersecting: all ground edges → cut lines.
List<DrawnLine> buildCutLines(
  List<GroundEdge> edges,
  FriendOrientation orientation,
) {
  final lines = <DrawnLine>[];
  switch (orientation) {
    case FriendOrientation.flatFlush:
      for (final e in edges) {
        if (e.isFacingEdge) {
          lines.add(DrawnLine(start: e.xyA, end: e.xyB, type: LineType.cut));
        }
      }
    case FriendOrientation.edgeFlush:
      for (final e in edges) {
        lines.add(DrawnLine(start: e.xyA, end: e.xyB, type: LineType.scoring));
      }
    case FriendOrientation.intersecting:
      for (final e in edges) {
        lines.add(DrawnLine(start: e.xyA, end: e.xyB, type: LineType.cut));
      }
  }
  return lines;
}

/// Projects the friend's silhouette (all rotated vertices) onto the XY plane
/// as a convex hull, returning the 2D boundary in world XY coordinates.
List<Offset> friendShadowPolygon(
  Geometry geometry,
  Quaternion rotation,
  Vector3 position,
) {
  final rot = rotation.asRotationMatrix();
  final projectedPoints = <Offset>[];
  for (final v in geometry.vertices) {
    final wx = rot.entry(0, 0) * v.x + rot.entry(0, 1) * v.y + rot.entry(0, 2) * v.z + position.x;
    final wy = rot.entry(1, 0) * v.x + rot.entry(1, 1) * v.y + rot.entry(1, 2) * v.z + position.y;
    projectedPoints.add(Offset(wx, wy));
  }
  return _convexHull2D(projectedPoints);
}

List<Offset> _convexHull2D(List<Offset> points) {
  if (points.length < 3) return List.from(points);

  var lowest = points[0];
  for (final p in points) {
    if (p.dy < lowest.dy || (p.dy == lowest.dy && p.dx < lowest.dx)) {
      lowest = p;
    }
  }

  final sorted = List<Offset>.from(points)..remove(lowest);
  sorted.sort((a, b) {
    final angleA = math.atan2(a.dy - lowest.dy, a.dx - lowest.dx);
    final angleB = math.atan2(b.dy - lowest.dy, b.dx - lowest.dx);
    if ((angleA - angleB).abs() < 1e-9) {
      return (a - lowest).distance.compareTo((b - lowest).distance);
    }
    return angleA.compareTo(angleB);
  });

  final hull = <Offset>[lowest];
  for (final point in sorted) {
    while (hull.length > 1) {
      final top = hull[hull.length - 1];
      final nextToTop = hull[hull.length - 2];
      final cross = (top.dx - nextToTop.dx) * (point.dy - nextToTop.dy) -
          (top.dy - nextToTop.dy) * (point.dx - nextToTop.dx);
      if (cross <= 1e-9) {
        hull.removeLast();
      } else {
        break;
      }
    }
    hull.add(point);
  }
  return hull;
}
