import 'dart:math' as math;
import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

import '../volumes/volume.dart';
import '../volumes/volume_solid.dart';
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

bool _faceIsNavigable(
  Volume volume,
  VolumeCell cell,
  VolumeFace face,
  VolumeGrid grid,
) {
  if (face == VolumeFace.negY) return false;
  final solid = resolveVolumeSolid(volume, grid);
  return !solid.isFaceFullyInternal(cell.tx, cell.ty, face);
}

bool _segmentsShareVertex(
  Vector3 a,
  Vector3 b,
  Vector3 c,
  Vector3 d, {
  double eps = 1e-3,
}) {
  bool near(Vector3 p, Vector3 q) => p.distanceTo(q) <= eps;
  return near(a, c) || near(a, d) || near(b, c) || near(b, d);
}

List<VolumeFaceEdge> _navigableFaceEdges({
  required VolumeCell cell,
  required VolumeFace face,
  required VolumeGrid grid,
  required VolumeSolid solid,
}) {
  final min = cell.box.worldMin(grid, cell.tx, cell.ty);
  final max = cell.box.worldMax(grid, cell.tx, cell.ty);
  final surface = solid.surfaceForFace(cell.tx, cell.ty, face);
  if (surface == null || surface.isComplete) {
    return volumeFaceEdges(face, min, max);
  }
  final out = <VolumeFaceEdge>[];
  for (final fragment in surface.fragments) {
    final quad = volumeFaceFragmentQuad(
      min: min,
      max: max,
      handle: surface.handle,
      fragment: fragment,
      subtileSize: grid.subtileSize,
    );
    out.addAll([
      VolumeFaceEdge(adjacent: _uvAdjacent(face, uAxis: false, high: false), a: quad[0], b: quad[3]),
      VolumeFaceEdge(adjacent: _uvAdjacent(face, uAxis: false, high: true), a: quad[1], b: quad[2]),
      VolumeFaceEdge(adjacent: _uvAdjacent(face, uAxis: true, high: false), a: quad[0], b: quad[1]),
      VolumeFaceEdge(adjacent: _uvAdjacent(face, uAxis: true, high: true), a: quad[3], b: quad[2]),
    ]);
  }
  return out;
}

VolumeFace _uvAdjacent(
  VolumeFace face, {
  required bool uAxis,
  required bool high,
}) {
  return switch (face) {
    VolumeFace.posX || VolumeFace.negX => uAxis
        ? (high ? VolumeFace.posZ : VolumeFace.negZ)
        : (high ? VolumeFace.posY : VolumeFace.negY),
    VolumeFace.posZ || VolumeFace.negZ => uAxis
        ? (high ? VolumeFace.posX : VolumeFace.negX)
        : (high ? VolumeFace.posY : VolumeFace.negY),
    VolumeFace.posY || VolumeFace.negY => uAxis
        ? (high ? VolumeFace.posX : VolumeFace.negX)
        : (high ? VolumeFace.posZ : VolumeFace.negZ),
  };
}

VolumeFaceEdge? _closestProjectedEdge(
  Iterable<VolumeFaceEdge> edges,
  Offset screenPoint,
  Offset? Function(Vector3 world) project,
) {
  VolumeFaceEdge? best;
  var bestDist = double.infinity;
  for (final edge in edges) {
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

/// Prefer the exterior face that shares the leaving edge. Parallel faces
/// that are only in view do not win over a shared edge or corner.
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
  Volume? currentVolume;
  for (final volume in volumes) {
    if (volume.id == volumeId) {
      currentVolume = volume;
      break;
    }
  }
  currentVolume ??= Volume(id: volumeId, cells: [cell]);
  final currentSolid = resolveVolumeSolid(currentVolume, grid);
  if (currentSolid.containsFaceHit(
    cell: cell,
    face: face,
    grid: grid,
    world: lookAt,
  )) {
    return null;
  }

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

  // Look-at landed on another remaining solid face of the same facing.
  for (final volume in volumes) {
    final solid = resolveVolumeSolid(volume, grid);
    for (final other in volume.cells) {
      if (volume.id == volumeId &&
          other.tx == cell.tx &&
          other.ty == cell.ty) {
        continue;
      }
      if (solid.isFaceFullyInternal(other.tx, other.ty, face)) continue;
      if (solid.containsFaceHit(
        cell: other,
        face: face,
        grid: grid,
        world: lookAt,
      )) {
        return targetFor(volume.id, other, face);
      }
    }
  }

  final leaving = _closestProjectedEdge(
    _navigableFaceEdges(
      cell: cell,
      face: face,
      grid: grid,
      solid: currentSolid,
    ),
    screenCenter,
    project,
  );
  if (leaving == null) return null;

  FaceTurnTarget? best;
  var bestScore = -1;

  void consider(Volume volume, VolumeCell nextCell, VolumeFace nextFace) {
    if (nextFace == VolumeFace.negY) return;
    if (volume.id == volumeId &&
        nextCell.tx == cell.tx &&
        nextCell.ty == cell.ty &&
        nextFace == face) {
      return;
    }
    if (!_faceIsNavigable(volume, nextCell, nextFace, grid)) return;
    final solid = resolveVolumeSolid(volume, grid);
    final nextEdges = _navigableFaceEdges(
      cell: nextCell,
      face: nextFace,
      grid: grid,
      solid: solid,
    );
    var sharesEdge = false;
    var sharesVertex = false;
    for (final edge in nextEdges) {
      if (segmentsShareEdge(leaving.a, leaving.b, edge.a, edge.b)) {
        sharesEdge = true;
      }
      if (_segmentsShareVertex(leaving.a, leaving.b, edge.a, edge.b)) {
        sharesVertex = true;
      }
    }
    final sameCell = volume.id == volumeId &&
        nextCell.tx == cell.tx &&
        nextCell.ty == cell.ty;
    final step = tileDeltaAcrossFaceEdge(face, leaving.adjacent);
    final towardNeighbor = step != null &&
        nextCell.tx == cell.tx + step.$1 &&
        nextCell.ty == cell.ty + step.$2;
    final tileNeighborSameFace =
        towardNeighbor && nextFace == face;
    var score = 0;
    if (sharesEdge && !sameCell) score += 1000;
    if (tileNeighborSameFace) score += 800;
    if (sameCell && nextFace == leaving.adjacent) score += 500;
    if (sharesVertex && !sameCell) score += 200;
    if (score == 0) return;
    if (score > bestScore) {
      bestScore = score;
      final plane = WorldPlane.fromVolumeFace(
        grid: grid,
        cell: nextCell,
        face: nextFace,
      );
      best = FaceTurnTarget(
        volumeId: volume.id,
        cell: nextCell,
        face: nextFace,
        coplanar: currentPlane.isCoplanarWith(plane),
      );
    }
  }

  final delta = tileDeltaAcrossFaceEdge(face, leaving.adjacent);
  if (delta != null) {
    final ntx = cell.tx + delta.$1;
    final nty = cell.ty + delta.$2;
    for (final volume in volumes) {
      final neighbor = volume.cellAt(ntx, nty);
      if (neighbor == null) continue;
      consider(volume, neighbor, face);
      for (final otherFace in VolumeFace.values) {
        if (otherFace == face || otherFace == VolumeFace.negY) continue;
        consider(volume, neighbor, otherFace);
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
        consider(volume, other, otherFace);
      }
    }
  }

  consider(currentVolume, cell, leaving.adjacent);
  return best;
}
