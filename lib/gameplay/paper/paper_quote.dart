import 'package:vector_math/vector_math_64.dart';

import '../paths/path_store.dart';
import '../volumes/volume_door_sync.dart';
import '../volumes/volume_solid_sync.dart';
import '../volumes/volume_store.dart';
import '../walls/wall_edge.dart';
import '../walls/wall_store.dart';
import 'paper_cost.dart';
import 'paper_wallet.dart';

/// Sheets this world would settle to, minus what is already committed.
/// Positive spends, negative refunds.
int quoteWorld(
  PaperWallet paper, {
  required VolumeStore volumes,
  required PathStore paths,
  required WallStore walls,
}) {
  final volumeCosts = <int, int>{
    for (final volume in volumes.visibleVolumes)
      volume.id: volumePaperCost(volume, volumes.grid),
  };
  var need = 0;
  var refund = 0;
  for (final entry in volumeCosts.entries) {
    final prior = paper.volumeCommitted[entry.key] ?? 0;
    if (entry.value > prior) {
      need += entry.value - prior;
    } else {
      refund += prior - entry.value;
    }
  }
  for (final entry in paper.volumeCommitted.entries) {
    if (!volumeCosts.containsKey(entry.key)) refund += entry.value;
  }
  final pathCost = pathPaperCost(
    paths,
    subtilesPerTile: volumes.grid.subtilesPerTile,
  );
  if (pathCost > paper.pathCommitted) {
    need += pathCost - paper.pathCommitted;
  } else {
    refund += paper.pathCommitted - pathCost;
  }
  final wallCost = wallPaperCost(walls.edges.length);
  if (wallCost > paper.wallCommitted) {
    need += wallCost - paper.wallCommitted;
  } else {
    refund += paper.wallCommitted - wallCost;
  }
  return need - refund;
}

VolumeStore copyVolumeStore(VolumeStore src) {
  final dst = VolumeStore(grid: src.grid);
  dst.restore(
    volumes: [for (final volume in src.volumes) volume.clone()],
    draftVolume: null,
    draftCell: null,
    draftIsGrow: false,
    phase: VolumeEditPhase.idle,
    nextId: src.nextId,
  );
  return dst;
}

PathStore copyPathStore(PathStore src) {
  final dst = PathStore(grid: src.grid);
  dst.restore(
    tiles: Set<(int, int)>.from(src.tiles),
    edges: Set<PathEdge>.from(src.edges),
  );
  return dst;
}

WallStore copyWallStore(WallStore src) {
  final dst = WallStore(grid: src.grid);
  dst.restore(Set<WallEdge>.from(src.edges));
  return dst;
}

/// Paper delta for painting a volume cell, or `null` if that is a no-op.
int? quoteVolumePaintAt({
  required PaperWallet paper,
  required VolumeStore volumes,
  required PathStore paths,
  required WallStore walls,
  required int tx,
  required int ty,
}) {
  if (!volumes.grid.inBounds(tx, ty) || volumes.isOccupied(tx, ty)) {
    return null;
  }
  final nextVolumes = copyVolumeStore(volumes);
  if (!nextVolumes.paintAt(tx, ty)) return null;
  final nextWalls = copyWallStore(walls);
  stripSharedVolumeWalls(nextWalls, nextVolumes);
  return quoteWorld(
    paper,
    volumes: nextVolumes,
    paths: paths,
    walls: nextWalls,
  );
}

/// Paper delta for placing / joining a path tile.
int? quotePathPlaceAt({
  required PaperWallet paper,
  required VolumeStore volumes,
  required PathStore paths,
  required WallStore walls,
  required int tx,
  required int ty,
}) {
  if (!paths.grid.inBounds(tx, ty)) return null;
  if (!canPaintPathAt(volumes: volumes, paths: paths, tx: tx, ty: ty)) {
    return null;
  }
  final nextPaths = copyPathStore(paths);
  final nextWalls = copyWallStore(walls);
  if (!nextPaths.placeAndJoin(tx, ty, walls: nextWalls)) return null;
  return quoteWorld(
    paper,
    volumes: volumes,
    paths: nextPaths,
    walls: nextWalls,
  );
}

/// Paper delta for a wall midpoint toggle (add, remove, or path-only sever).
int? quoteWallToggleAt({
  required PaperWallet paper,
  required VolumeStore volumes,
  required PathStore paths,
  required WallStore walls,
  required Vector3 hit,
}) {
  final nextPaths = copyPathStore(paths);
  final nextWalls = copyWallStore(walls);
  bool insteadOfAdd(WallEdge edge) {
    final cutPath = nextPaths.severAcross(edge);
    if (isVolumePathBoundary(edge, volumes)) return false;
    return cutPath;
  }

  if (!nextWalls.toggleAtMidpoint(hit, insteadOfAdd: insteadOfAdd)) {
    return null;
  }
  return quoteWorld(
    paper,
    volumes: volumes,
    paths: nextPaths,
    walls: nextWalls,
  );
}
