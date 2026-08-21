import '../volumes/volume.dart';
import '../volumes/volume_store.dart';
import '../graph/connection_graph.dart';
import 'path_store.dart';

/// Axis-aligned subtile footprint of one path mesh piece on a tile.
class PathFootprint {
  const PathFootprint({
    required this.originXSubtiles,
    required this.originZSubtiles,
    required this.widthSubtiles,
    required this.depthSubtiles,
  });

  final int originXSubtiles;
  final int originZSubtiles;
  final int widthSubtiles;
  final int depthSubtiles;

  @override
  bool operator ==(Object other) =>
      other is PathFootprint &&
      other.originXSubtiles == originXSubtiles &&
      other.originZSubtiles == originZSubtiles &&
      other.widthSubtiles == widthSubtiles &&
      other.depthSubtiles == depthSubtiles;

  @override
  int get hashCode => Object.hash(
        originXSubtiles,
        originZSubtiles,
        widthSubtiles,
        depthSubtiles,
      );
}

const kPathWidthSubtiles = 4;

/// 4-wide centered corridors from an edge mask (N=1, E=2, S=4, W=8).
///
/// 0: island, 1: stub, 2 opposite: straight, 2 adjacent: L, 3: T, 4: X.
List<PathFootprint> pathFootprints(
  int mask, {
  int subtilesPerTile = VolumeGrid.defaultSubtilesPerTile,
}) {
  final wide = kPathWidthSubtiles;
  final origin = (subtilesPerTile - wide) ~/ 2;
  final end = origin + wide;
  final pieces = <PathFootprint>[
    PathFootprint(
      originXSubtiles: origin,
      originZSubtiles: origin,
      widthSubtiles: wide,
      depthSubtiles: wide,
    ),
  ];

  if (mask & VolumeSide.east.maskBit != 0) {
    pieces.add(
      PathFootprint(
        originXSubtiles: end,
        originZSubtiles: origin,
        widthSubtiles: subtilesPerTile - end,
        depthSubtiles: wide,
      ),
    );
  }
  if (mask & VolumeSide.west.maskBit != 0) {
    pieces.add(
      PathFootprint(
        originXSubtiles: 0,
        originZSubtiles: origin,
        widthSubtiles: origin,
        depthSubtiles: wide,
      ),
    );
  }
  if (mask & VolumeSide.south.maskBit != 0) {
    pieces.add(
      PathFootprint(
        originXSubtiles: origin,
        originZSubtiles: end,
        widthSubtiles: wide,
        depthSubtiles: subtilesPerTile - end,
      ),
    );
  }
  if (mask & VolumeSide.north.maskBit != 0) {
    pieces.add(
      PathFootprint(
        originXSubtiles: origin,
        originZSubtiles: 0,
        widthSubtiles: wide,
        depthSubtiles: origin,
      ),
    );
  }
  return pieces;
}

/// 4-wide strip on [cell]'s tile from the door face to the tile edge.
///
/// Null when the box is flush with that edge — the dest-tile stub meets the
/// volume. Never overlaps the box.
PathFootprint? inOutGapFootprint(
  VolumeCell cell,
  VolumeSide side, {
  int subtilesPerTile = VolumeGrid.defaultSubtilesPerTile,
}) {
  final wide = kPathWidthSubtiles;
  final corridor = (subtilesPerTile - wide) ~/ 2;
  final box = cell.box;
  switch (side) {
    case VolumeSide.east:
      {
        final face = box.originXSubtiles + box.widthSubtiles;
        if (face >= subtilesPerTile) return null;
        return PathFootprint(
          originXSubtiles: face,
          originZSubtiles: corridor,
          widthSubtiles: subtilesPerTile - face,
          depthSubtiles: wide,
        );
      }
    case VolumeSide.west:
      {
        final face = box.originXSubtiles;
        if (face <= 0) return null;
        return PathFootprint(
          originXSubtiles: 0,
          originZSubtiles: corridor,
          widthSubtiles: face,
          depthSubtiles: wide,
        );
      }
    case VolumeSide.south:
      {
        final face = box.originZSubtiles + box.depthSubtiles;
        if (face >= subtilesPerTile) return null;
        return PathFootprint(
          originXSubtiles: corridor,
          originZSubtiles: face,
          widthSubtiles: wide,
          depthSubtiles: subtilesPerTile - face,
        );
      }
    case VolumeSide.north:
      {
        final face = box.originZSubtiles;
        if (face <= 0) return null;
        return PathFootprint(
          originXSubtiles: corridor,
          originZSubtiles: 0,
          widthSubtiles: wide,
          depthSubtiles: face,
        );
      }
  }
}

/// User paths plus derived in_out door paths, keyed by tile.
///
/// Outdoor dest tiles get a centered island and a stub facing the volume.
/// Inset volumes also get a gap strip on the volume tile that stops at the box.
Map<(int, int), List<PathFootprint>> pathFootprintsByTile({
  required VolumeStore volumes,
  required PathStore paths,
}) {
  final n = volumes.grid.subtilesPerTile;
  final masks = <(int, int), int>{};
  for (final (tx, ty) in paths.tiles) {
    masks[(tx, ty)] = paths.neighborMask(tx, ty);
  }
  final gaps = <(int, int), List<PathFootprint>>{};
  for (final link in ConnectionGraph.inOutLinks(volumes)) {
    final dest = (link.outTx, link.outTy);
    masks[dest] = (masks[dest] ?? 0) | link.side.opposite.maskBit;
    final gap = inOutGapFootprint(link.cell, link.side, subtilesPerTile: n);
    if (gap != null) {
      gaps.putIfAbsent((link.cell.tx, link.cell.ty), () => []).add(gap);
    }
  }
  final out = <(int, int), List<PathFootprint>>{};
  for (final entry in masks.entries) {
    out[entry.key] = pathFootprints(entry.value, subtilesPerTile: n);
  }
  for (final entry in gaps.entries) {
    out.putIfAbsent(entry.key, () => []).addAll(entry.value);
  }
  return out;
}
