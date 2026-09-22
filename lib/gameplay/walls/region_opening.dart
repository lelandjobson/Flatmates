import '../paths/path_store.dart';
import 'wall_edge.dart';
import 'wall_regions.dart';
import 'wall_store.dart';

/// True when the unit wall on this ortho step encloses a [Playground].
bool wouldOpenRegion({
  required WallEdge wall,
  required WallStore walls,
  required Iterable<Playground> regions,
}) {
  if (!walls.contains(wall)) return false;
  return wallBoundsRegion(wall, regions);
}

/// Cut openings whose outdoor approach path is gone.
bool syncRegionOpeningsFromPaths({
  required WallStore walls,
  required PathStore paths,
  required Iterable<Playground> regions,
}) {
  var changed = false;
  for (final edge in List<WallEdge>.from(walls.edges)) {
    if (edge.kind != WallKind.cutFence) continue;
    final pair = edge.separatedTiles;
    if (pair == null) continue;
    final aReg = playgroundContaining(regions, pair.$1.$1, pair.$1.$2);
    final bReg = playgroundContaining(regions, pair.$2.$1, pair.$2.$2);
    final outdoor = aReg == null
        ? pair.$1
        : bReg == null
            ? pair.$2
            : null;
    if (outdoor == null) {
      if (!paths.contains(pair.$1.$1, pair.$1.$2) &&
          !paths.contains(pair.$2.$1, pair.$2.$2)) {
        if (walls.uncut(edge)) changed = true;
      }
      continue;
    }
    if (!paths.contains(outdoor.$1, outdoor.$2)) {
      if (walls.uncut(edge)) changed = true;
    }
  }
  return changed;
}

/// Crossing wall to cut when the path tool aims at [tx],[ty], if any.
WallEdge? regionOpeningWallAt({
  required int tx,
  required int ty,
  required PathStore paths,
  required WallStore walls,
  required Iterable<Playground> regions,
}) {
  return paths.gateWallAt(tx, ty, walls: walls, regions: regions);
}
