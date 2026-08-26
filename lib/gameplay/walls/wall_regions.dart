import '../volumes/volume.dart';
import 'wall_edge.dart';
import 'wall_store.dart';

/// One bounded inner face of the wall arrangement.
class WallRegion {
  WallRegion(Set<(int, int)> tiles) : tiles = Set<(int, int)>.from(tiles);

  final Set<(int, int)> tiles;

  List<WallEdge> get outline => tileSetOutline(tiles);

  @override
  bool operator ==(Object other) =>
      other is WallRegion &&
      other.tiles.length == tiles.length &&
      other.tiles.containsAll(tiles);

  @override
  int get hashCode => Object.hashAll(tiles);
}

/// Enumerates distinct enclosed regions via a DCEL face walk.
///
/// Matches Boost.Graph `planar_face_traversal`: each vertex stores a clockwise
/// embedding (E, S, W, N). A face is the cycle formed by taking the next
/// clockwise outgoing half-edge after the twin at each destination.
///
/// The unbounded outer face is wound opposite the inner faces (negative
/// signed area in x/z) and is discarded. Each remaining face is its own
/// region — two rooms that share a wall stay separate, as do nested yards.
///
/// See https://www.boost.org/doc/libs/1_87_0/libs/graph/doc/planar_face_traversal.html
List<WallRegion> computeEnclosedRegions(WallStore store) {
  if (store.edges.isEmpty) return const [];

  final halfEdges = <_HalfEdge>[];
  final outgoing = <(int, int), List<_HalfEdge>>{};

  for (final edge in store.edges) {
    if (!edge.isUnitOrtho) continue;
    final a = (edge.x0, edge.y0);
    final b = (edge.x1, edge.y1);
    final ab = _HalfEdge(a, b, edge);
    final ba = _HalfEdge(b, a, edge);
    ab.twin = ba;
    ba.twin = ab;
    halfEdges.add(ab);
    halfEdges.add(ba);
    outgoing.putIfAbsent(a, () => []).add(ab);
    outgoing.putIfAbsent(b, () => []).add(ba);
  }

  for (final list in outgoing.values) {
    list.sort((a, b) => a.dirIndex.compareTo(b.dirIndex));
  }

  for (final he in halfEdges) {
    final destOut = outgoing[he.dest]!;
    final i = destOut.indexOf(he.twin!);
    // Previous in the clockwise embedding = left turn. Inner faces then
    // wind opposite the outer border, matching Boost planar_face_traversal.
    he.next = destOut[(i - 1 + destOut.length) % destOut.length];
  }

  final regions = <WallRegion>[];
  for (final start in halfEdges) {
    if (start.visited) continue;
    final walk = <_HalfEdge>[];
    var e = start;
    do {
      e.visited = true;
      walk.add(e);
      e = e.next!;
    } while (!identical(e, start));

    // Inner faces are opposite the outer border (positive area here).
    if (_signedArea(walk) <= 1e-9) continue;

    final seeds = <(int, int)>{};
    for (final he in walk) {
      final tile = _interiorTile(he);
      if (tile == null) continue;
      if (!store.grid.inBounds(tile.$1, tile.$2)) continue;
      seeds.add(tile);
    }
    if (seeds.isEmpty) continue;

    final tiles = _floodFace(store, seeds);
    if (tiles.isEmpty) continue;
    // The outer face can pick up in-bounds seeds just outside a cycle; those
    // components reach the map rim. Inner faces never do.
    if (_reachesMapExterior(store, tiles)) continue;
    regions.add(WallRegion(tiles));
  }
  return regions;
}

Set<(int, int)> enclosedTilesOf(Iterable<WallRegion> regions) {
  return {for (final region in regions) ...region.tiles};
}

/// Enclosed region that contains tile ([tx], [ty]), if any.
WallRegion? wallRegionContaining(
  Iterable<WallRegion> regions,
  int tx,
  int ty,
) {
  for (final region in regions) {
    if (region.tiles.contains((tx, ty))) return region;
  }
  return null;
}

/// Perimeter segments of [tiles] in vertex space (unit grid edges).
List<WallEdge> tileSetOutline(Set<(int, int)> tiles) {
  final outline = <WallEdge>[];
  for (final (tx, ty) in tiles) {
    if (!tiles.contains((tx, ty - 1))) {
      outline.add(WallEdge(tx, ty, tx + 1, ty));
    }
    if (!tiles.contains((tx + 1, ty))) {
      outline.add(WallEdge(tx + 1, ty, tx + 1, ty + 1));
    }
    if (!tiles.contains((tx, ty + 1))) {
      outline.add(WallEdge(tx, ty + 1, tx + 1, ty + 1));
    }
    if (!tiles.contains((tx - 1, ty))) {
      outline.add(WallEdge(tx, ty, tx, ty + 1));
    }
  }
  return outline;
}

/// Map-edge segments used by the world-border overlay.
List<WallEdge> worldBorderEdges(VolumeGrid grid) {
  final n = grid.tilesSide;
  return [
    for (var i = 0; i < n; i++) WallEdge(i, 0, i + 1, 0),
    for (var i = 0; i < n; i++) WallEdge(n, i, n, i + 1),
    for (var i = 0; i < n; i++) WallEdge(i, n, i + 1, n),
    for (var i = 0; i < n; i++) WallEdge(0, i, 0, i + 1),
  ];
}

class _HalfEdge {
  _HalfEdge(this.origin, this.dest, this.undirected);

  final (int, int) origin;
  final (int, int) dest;
  final WallEdge undirected;
  _HalfEdge? twin;
  _HalfEdge? next;
  bool visited = false;

  /// Clockwise from +X when viewed from +Y: E, S, W, N.
  int get dirIndex {
    final dx = dest.$1 - origin.$1;
    final dy = dest.$2 - origin.$2;
    if (dx == 1 && dy == 0) return 0;
    if (dx == 0 && dy == 1) return 1;
    if (dx == -1 && dy == 0) return 2;
    return 3;
  }
}

double _signedArea(List<_HalfEdge> walk) {
  var sum = 0;
  for (final he in walk) {
    sum += he.origin.$1 * he.dest.$2 - he.dest.$1 * he.origin.$2;
  }
  return sum / 2.0;
}

/// Tile immediately to the left of a positive-area (inner) half-edge.
(int, int)? _interiorTile(_HalfEdge he) {
  final dx = he.dest.$1 - he.origin.$1;
  final dy = he.dest.$2 - he.origin.$2;
  if (dx == 1 && dy == 0) return (he.origin.$1, he.origin.$2);
  if (dx == 0 && dy == 1) return (he.origin.$1 - 1, he.origin.$2);
  if (dx == -1 && dy == 0) return (he.origin.$1 - 1, he.origin.$2 - 1);
  if (dx == 0 && dy == -1) return (he.origin.$1, he.origin.$2 - 1);
  return null;
}

Set<(int, int)> _floodFace(WallStore store, Set<(int, int)> seeds) {
  final out = <(int, int)>{};
  final queue = <(int, int)>[...seeds];
  const deltas = [(1, 0), (-1, 0), (0, 1), (0, -1)];
  while (queue.isNotEmpty) {
    final tile = queue.removeLast();
    if (!out.add(tile)) continue;
    for (final (dx, dy) in deltas) {
      final next = (tile.$1 + dx, tile.$2 + dy);
      if (!store.grid.inBounds(next.$1, next.$2)) continue;
      if (out.contains(next)) continue;
      if (store.separatesTiles(tile, next)) continue;
      queue.add(next);
    }
  }
  return out;
}

bool _reachesMapExterior(WallStore store, Set<(int, int)> tiles) {
  final n = store.grid.tilesSide;
  for (final (tx, ty) in tiles) {
    if (ty == 0 && !store.hasBetweenVertices(tx, 0, tx + 1, 0)) return true;
    if (ty == n - 1 && !store.hasBetweenVertices(tx, n, tx + 1, n)) {
      return true;
    }
    if (tx == 0 && !store.hasBetweenVertices(0, ty, 0, ty + 1)) return true;
    if (tx == n - 1 && !store.hasBetweenVertices(n, ty, n, ty + 1)) {
      return true;
    }
  }
  return false;
}
