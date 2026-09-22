import '../volumes/volume.dart';
import '../walls/wall_edge.dart';
import '../walls/wall_regions.dart';
import '../walls/wall_store.dart';

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

  /// The tile-boundary wall that would sit on this connection.
  WallEdge get crossingWall {
    if (x1 == x0 + 1 && y1 == y0) {
      return WallEdge(x1, y0, x1, y0 + 1);
    }
    return WallEdge(x0, y1, x0 + 1, y1);
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
  final Set<(int, int)> lockedTiles = {};

  bool isLocked(int tx, int ty) => lockedTiles.contains((tx, ty));

  void lockTile(int tx, int ty) => lockedTiles.add((tx, ty));

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

  bool _opensRegion(
    int ax,
    int ay,
    int bx,
    int by, {
    required WallStore walls,
    required Iterable<Playground> regions,
  }) {
    final wall = PathEdge(ax, ay, bx, by).crossingWall;
    return walls.contains(wall) && wallBoundsRegion(wall, regions);
  }

  /// Fence the path tool would cut at [tx],[ty], if any.
  ///
  /// One side must already be a path and the wall must bound a region (or
  /// touch a region tile). The region-side tile is never paved.
  WallEdge? gateWallAt(
    int tx,
    int ty, {
    required WallStore walls,
    required Iterable<Playground> regions,
  }) {
    for (final side in VolumeSide.values) {
      final (dx, dy) = side.tileDelta;
      final nx = tx + dx;
      final ny = ty + dy;
      final wall = PathEdge(tx, ty, nx, ny).crossingWall;
      if (!walls.contains(wall)) continue;
      final herePath = contains(tx, ty);
      final therePath = contains(nx, ny);
      if (herePath == therePath) continue;
      final bounds = wallBoundsRegion(wall, regions);
      final hereIn = playgroundContaining(regions, tx, ty) != null;
      final thereIn = playgroundContaining(regions, nx, ny) != null;
      if (bounds || hereIn || thereIn) return wall;
    }
    return null;
  }

  /// Cut the gate wall at [tx],[ty]. Does not place a path tile.
  bool openRegionGatesAt(
    int tx,
    int ty, {
    required WallStore walls,
    required Iterable<Playground> regions,
  }) {
    final wall = gateWallAt(tx, ty, walls: walls, regions: regions);
    if (wall == null) return false;
    return walls.cut(wall);
  }

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

  /// Place a path tile and join it to every 4-adjacent path.
  bool placeAndJoin(
    int tx,
    int ty, {
    bool Function(int tx, int ty)? blocked,
    WallStore? walls,
    Iterable<Playground>? regions,
  }) {
    if (!grid.inBounds(tx, ty)) return false;
    if (blocked?.call(tx, ty) ?? false) return false;
    if (walls != null &&
        regions != null &&
        gateWallAt(tx, ty, walls: walls, regions: regions) != null) {
      return openRegionGatesAt(tx, ty, walls: walls, regions: regions);
    }

    var changed = false;
    if (tiles.add((tx, ty))) changed = true;
    for (final side in VolumeSide.values) {
      final (dx, dy) = side.tileDelta;
      final nx = tx + dx;
      final ny = ty + dy;
      if (!contains(nx, ny)) continue;
      if (connect(
        tx,
        ty,
        nx,
        ny,
        blocked: blocked,
        walls: walls,
        regions: regions,
      )) {
        changed = true;
      }
    }
    return changed;
  }

  /// Drop the connection only; tiles stay.
  bool disconnect(int ax, int ay, int bx, int by) =>
      edges.remove(PathEdge(ax, ay, bx, by));

  /// True when [wall] lies on a live path connection.
  bool connectionAcross(WallEdge? wall) {
    if (wall == null) return false;
    final pair = wall.separatedTiles;
    if (pair == null) return false;
    final a = pair.$1;
    final b = pair.$2;
    return hasEdge(a.$1, a.$2, b.$1, b.$2);
  }

  bool severAcross(WallEdge wall) {
    final pair = wall.separatedTiles;
    if (pair == null) return false;
    return disconnect(pair.$1.$1, pair.$1.$2, pair.$2.$1, pair.$2.$2);
  }

  /// Ensure both tiles exist and add an ortho [out_out] edge.
  ///
  /// A non-region wall on that boundary is removed so a path never crosses a
  /// wall. A region-bounding wall is cut instead; the path stays on the
  /// outdoor side and no edge crosses the gate.
  bool connect(
    int ax,
    int ay,
    int bx,
    int by, {
    bool Function(int tx, int ty)? blocked,
    WallStore? walls,
    Iterable<Playground>? regions,
  }) {
    final edge = PathEdge(ax, ay, bx, by);
    if (!edge.isOrtho) return false;
    if (!grid.inBounds(ax, ay) || !grid.inBounds(bx, by)) return false;
    if (blocked?.call(ax, ay) ?? false) return false;
    if (blocked?.call(bx, by) ?? false) return false;
    if (walls != null &&
        regions != null &&
        _opensRegion(ax, ay, bx, by, walls: walls, regions: regions)) {
      var changed = walls.cut(edge.crossingWall);
      final aIn = playgroundContaining(regions, ax, ay) != null;
      final bIn = playgroundContaining(regions, bx, by) != null;
      if (!aIn && tiles.add((ax, ay))) changed = true;
      if (!bIn && tiles.add((bx, by))) changed = true;
      return changed;
    }
    tiles.add((ax, ay));
    tiles.add((bx, by));
    var changed = edges.add(edge);
    if (walls != null && walls.remove(edge.crossingWall)) changed = true;
    return changed;
  }

  /// Walk from [from] to [to], connecting each ortho step (diagonal → L).
  ///
  /// [skippable] tiles are not placed. The stroke continues past them.
  bool paintStroke(
    (int, int) from,
    (int, int) to, {
    bool Function(int tx, int ty)? blocked,
    bool Function(int tx, int ty)? skippable,
    WallStore? walls,
    Iterable<Playground>? regions,
  }) {
    bool skip(int tx, int ty) => skippable?.call(tx, ty) ?? false;
    bool block(int tx, int ty) => blocked?.call(tx, ty) ?? false;
    if (!grid.inBounds(from.$1, from.$2)) return false;
    if (block(from.$1, from.$2)) return false;

    var changed = false;
    (int, int)? last;
    var crossingYard = false;

    bool inRegion(int tx, int ty) =>
        regions != null && playgroundContaining(regions, tx, ty) != null;

    bool openGate(int tx, int ty) {
      if (walls == null || regions == null) return false;
      return openRegionGatesAt(tx, ty, walls: walls, regions: regions);
    }

    if (!skip(from.$1, from.$2)) {
      if (walls != null &&
          regions != null &&
          gateWallAt(from.$1, from.$2, walls: walls, regions: regions) !=
              null) {
        if (openGate(from.$1, from.$2)) changed = true;
        if (inRegion(from.$1, from.$2)) crossingYard = true;
        if (contains(from.$1, from.$2)) last = from;
      } else {
        changed = addIsland(from.$1, from.$2, blocked: blocked);
        last = from;
      }
    }

    var x = from.$1;
    var y = from.$2;
    final x1 = to.$1;
    final y1 = to.$2;
    final sx = x1 > x ? 1 : (x1 < x ? -1 : 0);
    final sy = y1 > y ? 1 : (y1 < y ? -1 : 0);

    bool placeStep(int nx, int ny) {
      if (skip(nx, ny)) return false;
      if (walls != null &&
          regions != null &&
          gateWallAt(nx, ny, walls: walls, regions: regions) != null) {
        final did = openGate(nx, ny);
        if (inRegion(nx, ny)) crossingYard = true;
        return did;
      }
      final prev = last;
      if (prev != null &&
          walls != null &&
          regions != null &&
          _opensRegion(
            prev.$1,
            prev.$2,
            nx,
            ny,
            walls: walls,
            regions: regions,
          )) {
        final did = connect(
          prev.$1,
          prev.$2,
          nx,
          ny,
          blocked: blocked,
          walls: walls,
          regions: regions,
        );
        crossingYard = inRegion(nx, ny);
        return did;
      }
      if (crossingYard && inRegion(nx, ny)) return false;
      if (crossingYard && !inRegion(nx, ny)) {
        var did = false;
        if (walls != null && regions != null) {
          for (final side in VolumeSide.values) {
            final (dx, dy) = side.tileDelta;
            final n = (nx + dx, ny + dy);
            final wall = PathEdge(nx, ny, n.$1, n.$2).crossingWall;
            if (!_opensRegion(
              nx,
              ny,
              n.$1,
              n.$2,
              walls: walls,
              regions: regions,
            )) {
              continue;
            }
            if (walls.cut(wall)) did = true;
          }
        }
        crossingYard = false;
        if (addIsland(nx, ny, blocked: blocked)) did = true;
        return did;
      }
      if (prev != null) {
        final dx = (nx - prev.$1).abs();
        final dy = (ny - prev.$2).abs();
        if ((dx == 1 && dy == 0) || (dx == 0 && dy == 1)) {
          return connect(
            prev.$1,
            prev.$2,
            nx,
            ny,
            blocked: blocked,
            walls: walls,
            regions: regions,
          );
        }
      }
      return addIsland(nx, ny, blocked: blocked);
    }

    while (x != x1 || y != y1) {
      var stepped = false;
      if (x != x1) {
        final nx = x + sx;
        if (!grid.inBounds(nx, y) || block(nx, y)) break;
        if (placeStep(nx, y)) changed = true;
        if (!skip(nx, y) && contains(nx, y)) last = (nx, y);
        x = nx;
        stepped = true;
      }
      if (y != y1) {
        final ny = y + sy;
        if (!grid.inBounds(x, ny) || block(x, ny)) break;
        if (placeStep(x, ny)) changed = true;
        if (!skip(x, ny) && contains(x, ny)) last = (x, ny);
        y = ny;
        stepped = true;
      }
      if (!stepped) break;
    }
    return changed;
  }

  bool removeTile(int tx, int ty) {
    if (isLocked(tx, ty)) return false;
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
      ..addAll(tiles)
      ..addAll(lockedTiles);
    this.edges
      ..clear()
      ..addAll(edges);
  }
}
