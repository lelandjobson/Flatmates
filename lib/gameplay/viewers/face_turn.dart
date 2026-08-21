import 'dart:math' as math;
import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

import '../volumes/volume.dart';
import 'world_plane.dart';

/// Distance from [p] to the closest point on segment [a]–[b].
double distancePointToSegment2d(Offset p, Offset a, Offset b) {
  final abx = b.dx - a.dx;
  final aby = b.dy - a.dy;
  final len2 = abx * abx + aby * aby;
  if (len2 < 1e-12) return (p - a).distance;
  var t = ((p.dx - a.dx) * abx + (p.dy - a.dy) * aby) / len2;
  t = t.clamp(0.0, 1.0);
  final cx = a.dx + abx * t;
  final cy = a.dy + aby * t;
  final dx = p.dx - cx;
  final dy = p.dy - cy;
  return Offset(dx, dy).distance;
}

/// Adjacent face sharing the projected edge closest to [screenPoint].
///
/// [project] maps world edge endpoints to screen. Edges that fail to project
/// are skipped. Returns null when no edge projects.
VolumeFace? closestAdjacentVolumeFace({
  required VolumeFace face,
  required Vector3 min,
  required Vector3 max,
  required Offset screenPoint,
  required Offset? Function(Vector3 world) project,
}) {
  return closestVolumeFaceEdge(
    face: face,
    min: min,
    max: max,
    screenPoint: screenPoint,
    project: project,
  )?.adjacent;
}

VolumeFaceEdge? closestVolumeFaceEdge({
  required VolumeFace face,
  required Vector3 min,
  required Vector3 max,
  required Offset screenPoint,
  required Offset? Function(Vector3 world) project,
}) {
  VolumeFaceEdge? best;
  var bestDist = double.infinity;
  for (final edge in volumeFaceEdges(face, min, max)) {
    final a = project(edge.a);
    final b = project(edge.b);
    if (a == null || b == null) continue;
    final d = distancePointToSegment2d(screenPoint, a, b);
    if (d < bestDist) {
      bestDist = d;
      best = edge;
    }
  }
  return best;
}

/// Next plane2d face after the look-at has left [face] on [cell].
class FaceTurnTarget {
  const FaceTurnTarget({
    required this.volumeId,
    required this.cell,
    required this.face,
    required this.coplanar,
  });

  final int volumeId;
  final VolumeCell cell;
  final VolumeFace face;
  final bool coplanar;
}

/// Tile step across a face edge, or null when the edge is up/down.
(int dx, int dy)? tileDeltaAcrossFaceEdge(
  VolumeFace face,
  VolumeFace adjacent,
) {
  if (adjacent == VolumeFace.posY || adjacent == VolumeFace.negY) {
    return null;
  }
  return switch (face) {
    VolumeFace.posZ || VolumeFace.negZ || VolumeFace.posY || VolumeFace.negY =>
      switch (adjacent) {
        VolumeFace.posX => (1, 0),
        VolumeFace.negX => (-1, 0),
        VolumeFace.posZ => (0, 1),
        VolumeFace.negZ => (0, -1),
        _ => null,
      },
    VolumeFace.posX || VolumeFace.negX => switch (adjacent) {
        VolumeFace.posZ => (0, 1),
        VolumeFace.negZ => (0, -1),
        VolumeFace.posY || VolumeFace.negY => null,
        _ => null,
      },
  };
}

/// Collinear overlapping segments (works for rotated / trapezoid edges later).
bool segmentsShareEdge(
  Vector3 a,
  Vector3 b,
  Vector3 c,
  Vector3 d, {
  double eps = 1e-3,
}) {
  final ab = b - a;
  final abLen = ab.length;
  if (abLen < eps) return false;
  final dir = ab / abLen;
  final cd = d - c;
  final cdLen = cd.length;
  if (cdLen < eps) return false;
  if (dir.cross(cd).length > eps * cdLen) return false;

  double distToLine(Vector3 p) => (p - a).cross(dir).length;
  if (distToLine(c) > eps || distToLine(d) > eps) return false;

  final tc = (c - a).dot(dir);
  final td = (d - a).dot(dir);
  final lo = math.min(tc, td);
  final hi = math.max(tc, td);
  return math.min(abLen, hi) - math.max(0.0, lo) > eps;
}

bool facesShareWorldEdge({
  required VolumeFace aFace,
  required Vector3 aMin,
  required Vector3 aMax,
  required VolumeFace bFace,
  required Vector3 bMin,
  required Vector3 bMax,
  double eps = 1e-3,
}) {
  for (final a in volumeFaceEdges(aFace, aMin, aMax)) {
    for (final b in volumeFaceEdges(bFace, bMin, bMax)) {
      if (segmentsShareEdge(a.a, a.b, b.a, b.b, eps: eps)) return true;
    }
  }
  return false;
}

/// Prefer a neighbor face that shares the leaving edge over wrapping around
/// the current cell. Coplanar continuations keep the current plane.
FaceTurnTarget? nextPlane2dFaceTurn({
  required int volumeId,
  required VolumeCell cell,
  required VolumeFace face,
  required Vector3 lookAt,
  required Offset screenCenter,
  required Offset? Function(Vector3 world) project,
  required VolumeGrid grid,
  required Iterable<Volume> volumes,
  required WorldPlane currentPlane,
}) {
  final min = cell.box.worldMin(grid, cell.tx, cell.ty);
  final max = cell.box.worldMax(grid, cell.tx, cell.ty);
  if (face.liesOnFace(lookAt, min, max)) return null;

  FaceTurnTarget targetFor(int id, VolumeCell nextCell, VolumeFace nextFace) {
    final plane = WorldPlane.fromVolumeFace(
      grid: grid,
      cell: nextCell,
      face: nextFace,
    );
    return FaceTurnTarget(
      volumeId: id,
      cell: nextCell,
      face: nextFace,
      coplanar: currentPlane.isCoplanarWith(plane),
    );
  }

  // Look-at is still on this infinite plane: another coplanar face that
  // contains it (same volume or a neighbor in the row).
  for (final volume in volumes) {
    for (final other in volume.cells) {
      if (volume.id == volumeId &&
          other.tx == cell.tx &&
          other.ty == cell.ty) {
        continue;
      }
      final oMin = other.box.worldMin(grid, other.tx, other.ty);
      final oMax = other.box.worldMax(grid, other.tx, other.ty);
      if (face.liesOnFace(lookAt, oMin, oMax)) {
        return targetFor(volume.id, other, face);
      }
    }
  }

  final leaving = closestVolumeFaceEdge(
    face: face,
    min: min,
    max: max,
    screenPoint: screenCenter,
    project: project,
  );
  if (leaving == null) return null;

  FaceTurnTarget? best;
  var bestScore = -1;

  void consider(int id, VolumeCell nextCell, VolumeFace nextFace) {
    if (nextFace == VolumeFace.negY) return;
    if (id == volumeId &&
        nextCell.tx == cell.tx &&
        nextCell.ty == cell.ty &&
        nextFace == face) {
      return;
    }
    final oMin = nextCell.box.worldMin(grid, nextCell.tx, nextCell.ty);
    final oMax = nextCell.box.worldMax(grid, nextCell.tx, nextCell.ty);
    final plane = WorldPlane.fromVolumeFace(
      grid: grid,
      cell: nextCell,
      face: nextFace,
    );
    final shared = facesShareWorldEdge(
      aFace: face,
      aMin: min,
      aMax: max,
      bFace: nextFace,
      bMin: oMin,
      bMax: oMax,
    );
    final sameCell =
        id == volumeId && nextCell.tx == cell.tx && nextCell.ty == cell.ty;
    var score = 0;
    if (!sameCell) score += 100;
    if (nextFace == face) score += 50;
    if (currentPlane.isCoplanarWith(plane)) score += 20;
    if (currentPlane.normal.dot(plane.normal) > 0.99) score += 20;
    if (shared) score += 15;
    if (nextFace == leaving.adjacent) score += 1;
    if (score > bestScore) {
      bestScore = score;
      best = FaceTurnTarget(
        volumeId: id,
        cell: nextCell,
        face: nextFace,
        coplanar: currentPlane.isCoplanarWith(plane),
      );
    }
  }

  bool sharesLeaving(VolumeFace nextFace, VolumeCell nextCell) {
    final oMin = nextCell.box.worldMin(grid, nextCell.tx, nextCell.ty);
    final oMax = nextCell.box.worldMax(grid, nextCell.tx, nextCell.ty);
    for (final b in volumeFaceEdges(nextFace, oMin, oMax)) {
      if (segmentsShareEdge(leaving.a, leaving.b, b.a, b.b)) return true;
    }
    return false;
  }

  final delta = tileDeltaAcrossFaceEdge(face, leaving.adjacent);
  if (delta != null) {
    final ntx = cell.tx + delta.$1;
    final nty = cell.ty + delta.$2;
    for (final volume in volumes) {
      final neighbor = volume.cellAt(ntx, nty);
      if (neighbor == null) continue;
      consider(volume.id, neighbor, face);
      for (final otherFace in VolumeFace.values) {
        if (otherFace == face || otherFace == VolumeFace.negY) continue;
        if (sharesLeaving(otherFace, neighbor)) {
          consider(volume.id, neighbor, otherFace);
        }
      }
    }
  }

  for (final volume in volumes) {
    for (final other in volume.cells) {
      if (volume.id == volumeId && other.tx == cell.tx && other.ty == cell.ty) {
        continue;
      }
      for (final otherFace in VolumeFace.values) {
        if (otherFace == VolumeFace.negY) continue;
        if (sharesLeaving(otherFace, other)) {
          consider(volume.id, other, otherFace);
        }
      }
    }
  }

  consider(volumeId, cell, leaving.adjacent);
  return best;
}
