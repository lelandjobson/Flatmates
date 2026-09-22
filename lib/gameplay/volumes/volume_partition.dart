import 'dart:math' as math;

import 'volume.dart';
import 'volume_door.dart';
import 'volume_program.dart';
import 'volume_store.dart';

/// Interior program walls sit one subtile under the default 6-high volume.
const int kPartitionHeightSubtiles = 5;

/// 50% ghost so partitions never camera-hide like outer walls.
const double kPartitionOpacity = 0.5;

/// One undirected interior wall between two cells of the same volume.
class ProgramPartition {
  const ProgramPartition({
    required this.volumeId,
    required this.tx0,
    required this.ty0,
    required this.tx1,
    required this.ty1,
    required this.side,
    required this.u0,
    required this.u1,
    this.door,
  });

  final int volumeId;

  /// Canonical lesser tile (west or north).
  final int tx0;
  final int ty0;

  /// Neighbor tile (east or south of [tx0],[ty0]).
  final int tx1;
  final int ty1;

  /// Direction from (tx0, ty0) toward (tx1, ty1). East or south.
  final VolumeSide side;

  /// Tile-local subtile span along the shared edge, half-open `[u0, u1)`.
  final int u0;
  final int u1;

  final VolumeDoor? door;

  int get widthSubtiles => u1 - u0;

  int get wallArea => widthSubtiles * kPartitionHeightSubtiles;

  /// Door pixels that actually sit on this wall.
  int get doorArea {
    final opening = door;
    if (opening == null) return 0;
    final lo = math.max(u0, opening.originU);
    final hi = math.min(u1, opening.originU + opening.width);
    if (hi <= lo) return 0;
    final h = math.min(opening.height, kPartitionHeightSubtiles);
    return (hi - lo) * h;
  }

  int get netArea {
    final net = wallArea - doorArea;
    return net < 0 ? 0 : net;
  }

  String get meshId => partitionMeshId(tx0, ty0, tx1, ty1);

  (int, int) get tile0 => (tx0, ty0);

  (int, int) get tile1 => (tx1, ty1);
}

String partitionMeshId(int tx0, int ty0, int tx1, int ty1) =>
    'partition_${tx0}_${ty0}_${tx1}_$ty1';

/// Tiles touching a `partition_tx0_ty0_tx1_ty1` mesh, or null if the id is bad.
((int, int), (int, int))? partitionTilesFromMeshId(String id) {
  if (!id.startsWith('partition_')) return null;
  final parts = id.split('_');
  if (parts.length != 5) return null;
  final tx0 = int.tryParse(parts[1]);
  final ty0 = int.tryParse(parts[2]);
  final tx1 = int.tryParse(parts[3]);
  final ty1 = int.tryParse(parts[4]);
  if (tx0 == null || ty0 == null || tx1 == null || ty1 == null) return null;
  return ((tx0, ty0), (tx1, ty1));
}

/// Interior program-boundary edges across every visible volume.
List<ProgramPartition> collectProgramPartitions(
  VolumeStore volumes,
  VolumeProgramStore programs,
) {
  final out = <ProgramPartition>[];
  for (final volume in volumes.visibleVolumes) {
    out.addAll(collectVolumeProgramPartitions(volume, programs));
  }
  return out;
}

/// Interior walls that bound a program inside [volume].
List<ProgramPartition> collectVolumeProgramPartitions(
  Volume volume,
  VolumeProgramStore programs,
) {
  const sides = [VolumeSide.east, VolumeSide.south];
  final out = <ProgramPartition>[];
  for (final cell in volume.cells) {
    for (final side in sides) {
      final (dx, dy) = side.tileDelta;
      final next = volume.cellAt(cell.tx + dx, cell.ty + dy);
      if (next == null) continue;
      final a = programs.indoorAt(cell.tx, cell.ty);
      final b = programs.indoorAt(next.tx, next.ty);
      if (a == b) continue;
      final span = _overlapAlongSharedEdge(cell, next, side);
      if (span == null) continue;
      final (u0, u1) = span;
      out.add(
        ProgramPartition(
          volumeId: volume.id,
          tx0: cell.tx,
          ty0: cell.ty,
          tx1: next.tx,
          ty1: next.ty,
          side: side,
          u0: u0,
          u1: u1,
          door: partitionDoorForSpan(
            side: side,
            u0: u0,
            u1: u1,
          ),
        ),
      );
    }
  }
  return out;
}

/// Tile-centered 2×4 opening, clamped into `[u0, u1)`.
VolumeDoor? partitionDoorForSpan({
  required VolumeSide side,
  required int u0,
  required int u1,
  int subtilesPerTile = VolumeGrid.defaultSubtilesPerTile,
}) {
  final faceW = u1 - u0;
  final w = math.min(kDoorWidthSubtiles, faceW);
  final h = math.min(kDoorHeightSubtiles, kPartitionHeightSubtiles);
  if (w < 1 || h < 1) return null;
  final tileU = (subtilesPerTile - w) ~/ 2;
  return VolumeDoor(
    side: side,
    originU: tileU.clamp(u0, u1 - w),
    originY: 0,
    width: w,
    height: h,
  );
}

(int, int)? _overlapAlongSharedEdge(
  VolumeCell a,
  VolumeCell b,
  VolumeSide side,
) {
  final (a0, a1, b0, b1) = switch (side) {
    VolumeSide.east || VolumeSide.west => (
        a.box.originZSubtiles,
        a.box.originZSubtiles + a.box.depthSubtiles,
        b.box.originZSubtiles,
        b.box.originZSubtiles + b.box.depthSubtiles,
      ),
    VolumeSide.north || VolumeSide.south => (
        a.box.originXSubtiles,
        a.box.originXSubtiles + a.box.widthSubtiles,
        b.box.originXSubtiles,
        b.box.originXSubtiles + b.box.widthSubtiles,
      ),
  };
  final u0 = a0 > b0 ? a0 : b0;
  final u1 = a1 < b1 ? a1 : b1;
  if (u1 <= u0) return null;
  return (u0, u1);
}
