import '../volumes/volume.dart';

/// Undirected ortho edge between two path tiles.
class PathEdge {
  PathEdge(int ax, int ay, int bx, int by)
      : x0 = _min(ax, ay, bx, by).$1,
        y0 = _min(ax, ay, bx, by).$2,
        x1 = _max(ax, ay, bx, by).$1,
        y1 = _max(ax, ay, bx, by).$2;

  final int x0;
  final int y0;
  final int x1;
  final int y1;

  static (int, int) _min(int ax, int ay, int bx, int by) =>
      (ax < bx || (ax == bx && ay <= by)) ? (ax, ay) : (bx, by);

  static (int, int) _max(int ax, int ay, int bx, int by) =>
      (ax < bx || (ax == bx && ay <= by)) ? (bx, by) : (ax, ay);

  bool get isOrtho {
    final dx = (x1 - x0).abs();
    final dy = (y1 - y0).abs();
    return (dx == 1 && dy == 0) || (dx == 0 && dy == 1);
  }

  @override
  bool operator ==(Object other) =>
      other is PathEdge &&
      other.x0 == x0 &&
      other.y0 == y0 &&
      other.x1 == x1 &&
      other.y1 == y1;

  @override
  int get hashCode => Object.hash(x0, y0, x1, y1);
}

/// Outdoor path tiles plus explicit connections. Adjacency alone does not join.
class PathStore {
  PathStore({VolumeGrid? grid}) : grid = grid ?? const VolumeGrid();

  final VolumeGrid grid;
  final Set<(int, int)> tiles = {};
  final Set<PathEdge> edges = {};

  bool contains(int tx, int ty) => tiles.contains((tx, ty));

  /// Neighbor-edge mask for [tx],[ty] (N=1, E=2, S=4, W=8).
  int neighborMask(int tx, int ty) {
    var mask = 0;
    for (final side in VolumeSide.values) {
      final (dx, dy) = side.tileDelta;
      if (hasEdge(tx, ty, tx + dx, ty + dy)) mask |= side.maskBit;
    }
    return mask;
  }

  bool hasEdge(int ax, int ay, int bx, int by) =>
      edges.contains(PathEdge(ax, ay, bx, by));

  /// Click: a disconnected 4x4 island. No-op if already present or blocked.
  bool addIsland(
    int tx,
    int ty, {
    bool Function(int tx, int ty)? blocked,
  }) {
    if (!grid.inBounds(tx, ty)) return false;
    if (blocked?.call(tx, ty) ?? false) return false;
    return tiles.add((tx, ty));
  }

  /// Ensure both tiles exist and add an ortho [out_out] edge.
  bool connect(
    int ax,
    int ay,
    int bx,
    int by, {
    bool Function(int tx, int ty)? blocked,
  }) {
    final edge = PathEdge(ax, ay, bx, by);
    if (!edge.isOrtho) return false;
    if (!grid.inBounds(ax, ay) || !grid.inBounds(bx, by)) return false;
    if (blocked?.call(ax, ay) ?? false) return false;
    if (blocked?.call(bx, by) ?? false) return false;
    tiles.add((ax, ay));
    tiles.add((bx, by));
    return edges.add(edge);
  }

  /// Walk from [from] to [to], connecting each ortho step (diagonal → L).
  bool paintStroke(
    (int, int) from,
    (int, int) to, {
    bool Function(int tx, int ty)? blocked,
  }) {
    if (blocked?.call(from.$1, from.$2) ?? false) return false;
    var changed = addIsland(from.$1, from.$2, blocked: blocked);
    var x = from.$1;
    var y = from.$2;
    final x1 = to.$1;
    final y1 = to.$2;
    final sx = x1 > x ? 1 : (x1 < x ? -1 : 0);
    final sy = y1 > y ? 1 : (y1 < y ? -1 : 0);
    while (x != x1 || y != y1) {
      var stepped = false;
      if (x != x1) {
        final nx = x + sx;
        if (!grid.inBounds(nx, y) || (blocked?.call(nx, y) ?? false)) break;
        if (connect(x, y, nx, y, blocked: blocked)) changed = true;
        x = nx;
        stepped = true;
      }
      if (y != y1) {
        final ny = y + sy;
        if (!grid.inBounds(x, ny) || (blocked?.call(x, ny) ?? false)) break;
        if (connect(x, y, x, ny, blocked: blocked)) changed = true;
        y = ny;
        stepped = true;
      }
      if (!stepped) break;
    }
    return changed;
  }

  bool removeTile(int tx, int ty) {
    if (!tiles.remove((tx, ty))) return false;
    edges.removeWhere(
      (edge) =>
          (edge.x0 == tx && edge.y0 == ty) || (edge.x1 == tx && edge.y1 == ty),
    );
    return true;
  }

  void restore({
    required Set<(int, int)> tiles,
    required Set<PathEdge> edges,
  }) {
    this.tiles
      ..clear()
      ..addAll(tiles);
    this.edges
      ..clear()
      ..addAll(edges);
  }
}
