import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../volumes/volume.dart';
import 'wall_edge.dart';

/// How close a pointer must be to an edge midpoint, in tile units.
const kWallMidpointHitTiles = 0.28;

/// Walls occupy tile-boundary edges. Adjacency of tiles is not enough to join.
class WallStore {
  WallStore({VolumeGrid? grid}) : grid = grid ?? const VolumeGrid();

  final VolumeGrid grid;
  final Set<WallEdge> edges = {};

  bool contains(WallEdge edge) => edges.contains(edge);

  /// The stored edge (with kind), if present.
  WallEdge? lookup(WallEdge edge) => edges.lookup(edge);

  bool hasBetweenVertices(int ax, int ay, int bx, int by) =>
      edges.contains(WallEdge(ax, ay, bx, by));

  /// The unit wall on the shared side of two 4-adjacent tiles, if any.
  WallEdge? edgeBetween((int, int) a, (int, int) b) {
    final dx = b.$1 - a.$1;
    final dy = b.$2 - a.$2;
    if (dx == 1 && dy == 0) {
      return WallEdge(a.$1 + 1, a.$2, a.$1 + 1, a.$2 + 1);
    }
    if (dx == -1 && dy == 0) {
      return WallEdge(a.$1, a.$2, a.$1, a.$2 + 1);
    }
    if (dx == 0 && dy == 1) {
      return WallEdge(a.$1, a.$2 + 1, a.$1 + 1, a.$2 + 1);
    }
    if (dx == 0 && dy == -1) {
      return WallEdge(a.$1, a.$2, a.$1 + 1, a.$2);
    }
    return null;
  }

  /// Replace a solid fence with a path-width cut. No-op if missing or cut.
  bool cut(WallEdge edge) {
    final stored = lookup(edge);
    if (stored == null || stored.kind == WallKind.cutFence) return false;
    edges.remove(stored);
    return edges.add(
      WallEdge(stored.x0, stored.y0, stored.x1, stored.y1, kind: WallKind.cutFence),
    );
  }

  /// Restore a cut fence to a solid fence. No-op if missing or already solid.
  bool uncut(WallEdge edge) {
    final stored = lookup(edge);
    if (stored == null || stored.kind != WallKind.cutFence) return false;
    edges.remove(stored);
    return edges.add(
      WallEdge(stored.x0, stored.y0, stored.x1, stored.y1, kind: WallKind.fence),
    );
  }

  /// True when a solid wall blocks walking between 4-adjacent tiles.
  ///
  /// Cut fences stay region boundaries ([separatesTiles]) but do not block
  /// walking.
  bool blocksWalk((int, int) a, (int, int) b) {
    final edge = edgeBetween(a, b);
    if (edge == null) return true;
    final stored = lookup(edge);
    if (stored == null) return false;
    return stored.kind != WallKind.cutFence;
  }

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

  /// When [insteadOfAdd] returns true, the edge is not stored.
  bool add(
    WallEdge edge, {
    bool Function(WallEdge edge)? insteadOfAdd,
  }) {
    if (!edge.isUnitOrtho) return false;
    if (!_edgeInBounds(edge)) return false;
    if (insteadOfAdd?.call(edge) ?? false) return true;
    return edges.add(edge);
  }

  bool remove(WallEdge edge) => edges.remove(edge);

  /// Add the edge whose midpoint is nearest [world], if close enough.
  WallEdge? addAtMidpoint(
    Vector3 world, {
    bool Function(WallEdge edge)? insteadOfAdd,
  }) {
    final edge = hitEdgeAtMidpoint(world);
    if (edge == null) return null;
    return add(edge, insteadOfAdd: insteadOfAdd) ? edge : null;
  }

  /// Tap: add if missing, remove if present. Drag should use [paintStroke].
  bool toggleAtMidpoint(
    Vector3 world, {
    bool Function(WallEdge edge)? insteadOfAdd,
  }) {
    final edge = hitEdgeAtMidpoint(world);
    if (edge == null) return false;
    if (contains(edge)) return remove(edge);
    return add(edge, insteadOfAdd: insteadOfAdd);
  }

  /// Paint midpoints the stroke passes near. Adds only; never removes.
  bool paintStroke(
    Vector3 from,
    Vector3 to, {
    WallKind kind = WallKind.fence,
    bool Function(WallEdge edge)? insteadOfAdd,
  }) {
    var changed = false;
    for (final edge in edgesAlong(from, to, kind: kind)) {
      if (add(edge, insteadOfAdd: insteadOfAdd)) changed = true;
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

  /// The four boundary edges of tile [tx],[ty] that currently have a wall.
  List<WallEdge> edgesTouchingTile(int tx, int ty) {
    return [
      for (final edge in tileBoundaryEdges(tx, ty))
        if (contains(edge)) edge,
    ];
  }

  bool removeEdgesTouchingTile(int tx, int ty) {
    var changed = false;
    for (final edge in edgesTouchingTile(tx, ty)) {
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
    final lo = grid.originTile;
    final hi = grid.lastTile + 1;
    if (edge.x0 < lo || edge.y0 < lo || edge.x1 > hi || edge.y1 > hi) {
      return false;
    }
    return true;
  }

  (double fx, double fy) vertexFromWorld(Vector3 world) {
    final s = grid.tileSize;
    return (world.x / s, world.z / s);
  }

  Vector3 vertexWorld(int vx, int vy) => Vector3(
        vx * grid.tileSize,
        0,
        vy * grid.tileSize,
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
    final lo = grid.originTile;
    final hi = grid.lastTile + 1;
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
    if (vxH >= lo && vxH < hi && vyH >= lo && vyH <= hi) {
      consider(WallEdge(vxH, vyH, vxH + 1, vyH), vxH + 0.5, vyH.toDouble());
    }
    final vxV = fx.round();
    final vyV = fy.floor();
    if (vxV >= lo && vxV <= hi && vyV >= lo && vyV < hi) {
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
            (ax + dx * t) * grid.tileSize,
            0,
            (ay + dy * t) * grid.tileSize,
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

/// The four unit boundary edges of tile [tx],[ty], whether or not walls exist.
List<WallEdge> tileBoundaryEdges(int tx, int ty) => [
      WallEdge(tx, ty, tx + 1, ty),
      WallEdge(tx, ty, tx, ty + 1),
      WallEdge(tx + 1, ty, tx + 1, ty + 1),
      WallEdge(tx, ty + 1, tx + 1, ty + 1),
    ];
