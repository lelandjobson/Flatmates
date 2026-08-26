import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../volumes/volume.dart';
import 'wall_edge.dart';

/// How close a pointer must be to an edge midpoint, in tile units.
const kWallMidpointHitTiles = 0.2;

/// Walls occupy tile-boundary edges. Adjacency of tiles is not enough to join.
class WallStore {
  WallStore({VolumeGrid? grid}) : grid = grid ?? const VolumeGrid();

  final VolumeGrid grid;
  final Set<WallEdge> edges = {};

  bool contains(WallEdge edge) => edges.contains(edge);

  bool hasBetweenVertices(int ax, int ay, int bx, int by) =>
      edges.contains(WallEdge(ax, ay, bx, by));

  /// True when a wall blocks the shared side of two 4-adjacent tiles.
  bool separatesTiles((int, int) a, (int, int) b) {
    final dx = b.$1 - a.$1;
    final dy = b.$2 - a.$2;
    if (dx == 1 && dy == 0) {
      return hasBetweenVertices(a.$1 + 1, a.$2, a.$1 + 1, a.$2 + 1);
    }
    if (dx == -1 && dy == 0) {
      return hasBetweenVertices(a.$1, a.$2, a.$1, a.$2 + 1);
    }
    if (dx == 0 && dy == 1) {
      return hasBetweenVertices(a.$1, a.$2 + 1, a.$1 + 1, a.$2 + 1);
    }
    if (dx == 0 && dy == -1) {
      return hasBetweenVertices(a.$1, a.$2, a.$1 + 1, a.$2);
    }
    return true;
  }

  bool add(WallEdge edge) {
    if (!edge.isUnitOrtho) return false;
    if (!_edgeInBounds(edge)) return false;
    return edges.add(edge);
  }

  bool remove(WallEdge edge) => edges.remove(edge);

  /// Add the edge whose midpoint is nearest [world], if close enough.
  WallEdge? addAtMidpoint(Vector3 world) {
    final edge = hitEdgeAtMidpoint(world);
    if (edge == null) return null;
    return add(edge) ? edge : null;
  }

  /// Tap: add if missing, remove if present. Drag should use [paintStroke].
  bool toggleAtMidpoint(Vector3 world) {
    final edge = hitEdgeAtMidpoint(world);
    if (edge == null) return false;
    if (contains(edge)) return remove(edge);
    return add(edge);
  }

  /// Paint midpoints the stroke passes near. Adds only; never removes.
  bool paintStroke(Vector3 from, Vector3 to, {WallKind kind = WallKind.fence}) {
    var changed = false;
    for (final edge in edgesAlong(from, to, kind: kind)) {
      if (add(edge)) changed = true;
    }
    return changed;
  }

  /// Erase every wall whose segment comes within [radius] of [world].
  bool eraseNear(Vector3 world, double radius) {
    final hit = <WallEdge>{};
    for (final edge in edges) {
      if (_distanceToEdge(world, edge) <= radius) hit.add(edge);
    }
    var changed = false;
    for (final edge in hit) {
      if (edges.remove(edge)) changed = true;
    }
    return changed;
  }

  void restore(Set<WallEdge> next) {
    edges
      ..clear()
      ..addAll(next);
  }

  bool _edgeInBounds(WallEdge edge) {
    final n = grid.tilesSide;
    if (edge.x0 < 0 || edge.y0 < 0 || edge.x1 > n || edge.y1 > n) {
      return false;
    }
    return true;
  }

  (double fx, double fy) vertexFromWorld(Vector3 world) {
    final half = grid.mapHalf;
    final s = grid.tileSize;
    return ((world.x + half) / s, (world.z + half) / s);
  }

  Vector3 vertexWorld(int vx, int vy) => Vector3(
        -grid.mapHalf + vx * grid.tileSize,
        0,
        -grid.mapHalf + vy * grid.tileSize,
      );

  /// Nearest unit edge whose midpoint is within [maxDistTiles] of [world].
  ///
  /// Corners are ~0.5 tiles from every midpoint, so they miss. Cheaper than
  /// overlay hit-targets: two candidate midpoints, constant time.
  WallEdge? hitEdgeAtMidpoint(
    Vector3 world, {
    double maxDistTiles = kWallMidpointHitTiles,
  }) {
    final (fx, fy) = vertexFromWorld(world);
    final n = grid.tilesSide;
    WallEdge? best;
    var bestDist = maxDistTiles;

    void consider(WallEdge? edge, double mx, double my) {
      if (edge == null || !_edgeInBounds(edge)) return;
      final dx = fx - mx;
      final dy = fy - my;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist <= bestDist) {
        bestDist = dist;
        best = edge;
      }
    }

    final vxH = fx.floor();
    final vyH = fy.round();
    if (vxH >= 0 && vxH < n && vyH >= 0 && vyH <= n) {
      consider(WallEdge(vxH, vyH, vxH + 1, vyH), vxH + 0.5, vyH.toDouble());
    }
    final vxV = fx.round();
    final vyV = fy.floor();
    if (vxV >= 0 && vxV <= n && vyV >= 0 && vyV < n) {
      consider(WallEdge(vxV, vyV, vxV, vyV + 1), vxV.toDouble(), vyV + 0.5);
    }
    return best;
  }

  Iterable<WallEdge> edgesAlong(
    Vector3 from,
    Vector3 to, {
    WallKind kind = WallKind.fence,
  }) {
    final seen = <WallEdge>{};
    final collected = <WallEdge>[];
    void collect(WallEdge? edge) {
      if (edge == null || !edge.isUnitOrtho || !_edgeInBounds(edge)) return;
      final keyed = WallEdge(edge.x0, edge.y0, edge.x1, edge.y1, kind: kind);
      if (seen.add(keyed)) collected.add(keyed);
    }

    final (ax, ay) = vertexFromWorld(from);
    final (bx, by) = vertexFromWorld(to);
    collect(hitEdgeAtMidpoint(from));
    collect(hitEdgeAtMidpoint(to));

    final dx = bx - ax;
    final dy = by - ay;
    final steps = ((dx.abs() + dy.abs()) * 12).ceil().clamp(1, 256);
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      collect(
        hitEdgeAtMidpoint(
          Vector3(
            -grid.mapHalf + (ax + dx * t) * grid.tileSize,
            0,
            -grid.mapHalf + (ay + dy * t) * grid.tileSize,
          ),
        ),
      );
    }
    return collected;
  }

  double _distanceToEdge(Vector3 world, WallEdge edge) {
    final a = vertexWorld(edge.x0, edge.y0);
    final b = vertexWorld(edge.x1, edge.y1);
    final abx = b.x - a.x;
    final abz = b.z - a.z;
    final apx = world.x - a.x;
    final apz = world.z - a.z;
    final ab2 = abx * abx + abz * abz;
    var t = 0.0;
    if (ab2 > 1e-12) {
      t = ((apx * abx + apz * abz) / ab2).clamp(0.0, 1.0);
    }
    final dx = world.x - (a.x + abx * t);
    final dz = world.z - (a.z + abz * t);
    return math.sqrt(dx * dx + dz * dz);
  }
}
