import 'wall_edge.dart';
import 'wall_regions.dart';
import 'wall_store.dart';

/// Orthogonal neighbors in N, E, S, W order (+Z is south).
const kRegionNeighborDeltas = [
  (0, -1),
  (1, 0),
  (0, 1),
  (-1, 0),
];

/// Preview / result of a region-tool tile fill.
class RegionFillPreview {
  const RegionFillPreview({
    required this.addEdges,
    required this.removeEdges,
    required this.lastSeed,
    required this.changed,
  });

  final List<WallEdge> addEdges;
  final List<WallEdge> removeEdges;
  final (int, int)? lastSeed;
  final bool changed;
}

/// Seed stays if that tile is still enclosed; otherwise last region is gone.
(int, int)? resolvedLastRegionSeed(
  Iterable<Playground> regions,
  (int, int)? seed,
) {
  if (seed == null) return null;
  return playgroundContaining(regions, seed.$1, seed.$2) == null ? null : seed;
}

/// Walls whose [WallEdge.separatedTiles] sit in [a] and [b] (including cuts).
List<WallEdge> wallsDividingRegions(
  Playground a,
  Playground b,
  WallStore store,
) {
  final out = <WallEdge>{};
  for (final tile in a.tiles) {
    for (final (dx, dy) in kRegionNeighborDeltas) {
      final n = (tile.$1 + dx, tile.$2 + dy);
      if (!b.tiles.contains(n)) continue;
      final edge = store.edgeBetween(tile, n);
      if (edge != null && store.contains(edge)) out.add(edge);
    }
  }
  return out.toList();
}

/// Every wall on the shared interface of the two regions [edge] divides.
///
/// Null when [edge] is missing or does not sit between two distinct regions.
List<WallEdge>? dividerMergeEdges(
  WallEdge edge,
  Iterable<Playground> regions,
  WallStore store,
) {
  if (!store.contains(edge)) return null;
  final pair = edge.separatedTiles;
  if (pair == null) return null;
  final a = playgroundContaining(regions, pair.$1.$1, pair.$1.$2);
  final b = playgroundContaining(regions, pair.$2.$1, pair.$2.$2);
  if (a == null || b == null || a == b) return null;
  final walls = wallsDividingRegions(a, b, store);
  if (walls.isEmpty) return null;
  return walls;
}

/// Edges to add/remove and the next last-region seed for a fill at [tx],[ty].
RegionFillPreview previewRegionFill({
  required WallStore walls,
  required Iterable<Playground> regions,
  required int tx,
  required int ty,
  required (int, int)? lastSeed,
}) {
  final tile = (tx, ty);
  final existing = playgroundContaining(regions, tx, ty);
  if (existing != null) {
    return RegionFillPreview(
      addEdges: const [],
      removeEdges: const [],
      lastSeed: lastSeed ?? tile,
      changed: false,
    );
  }

  final last = lastSeed == null
      ? null
      : playgroundContaining(regions, lastSeed.$1, lastSeed.$2);

  Playground? firstNeighbor;
  var touchesLast = false;
  var hasOtherNeighbor = false;
  for (final (dx, dy) in kRegionNeighborDeltas) {
    final n = (tx + dx, ty + dy);
    if (!walls.grid.inBounds(n.$1, n.$2)) continue;
    final region = playgroundContaining(regions, n.$1, n.$2);
    if (region == null) continue;
    firstNeighbor ??= region;
    if (last != null && region == last) {
      touchesLast = true;
    } else {
      hasOtherNeighbor = true;
    }
  }

  Playground? mergeTarget;
  (int, int)? newSeed;
  if (last != null && touchesLast) {
    mergeTarget = last;
    newSeed = lastSeed;
  } else if (last == null && firstNeighbor != null) {
    mergeTarget = firstNeighbor;
    newSeed = tile;
  } else if (last != null && hasOtherNeighbor) {
    mergeTarget = null;
    newSeed = lastSeed;
  } else {
    mergeTarget = null;
    newSeed = tile;
  }

  final remove = <WallEdge>[];
  if (mergeTarget != null) {
    for (final (dx, dy) in kRegionNeighborDeltas) {
      final n = (tx + dx, ty + dy);
      if (!mergeTarget.tiles.contains(n)) continue;
      final edge = walls.edgeBetween(tile, n);
      if (edge != null && walls.contains(edge)) remove.add(edge);
    }
  }

  final add = [
    for (final edge in tileBoundaryEdges(tx, ty))
      if (!walls.contains(edge) && !remove.contains(edge)) edge,
  ];

  return RegionFillPreview(
    addEdges: add,
    removeEdges: remove,
    lastSeed: newSeed,
    changed: add.isNotEmpty || remove.isNotEmpty,
  );
}

/// Applies [preview] wall mutations. Does not update path connections.
void applyRegionFillPreview(WallStore walls, RegionFillPreview preview) {
  for (final edge in preview.addEdges) {
    walls.add(edge);
  }
  for (final edge in preview.removeEdges) {
    walls.remove(edge);
  }
}

/// Preview, then mutate [walls]. Caller severs paths and syncs the world.
RegionFillPreview applyRegionFill({
  required WallStore walls,
  required Iterable<Playground> regions,
  required int tx,
  required int ty,
  required (int, int)? lastSeed,
}) {
  final preview = previewRegionFill(
    walls: walls,
    regions: regions,
    tx: tx,
    ty: ty,
    lastSeed: lastSeed,
  );
  applyRegionFillPreview(walls, preview);
  return preview;
}
