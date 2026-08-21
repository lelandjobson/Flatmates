import '../landscape/landscape_generator.dart';
import '../landscape/landscape_grid.dart';
import 'paths/path_shape.dart';
import 'paths/path_store.dart';
import 'volumes/volume_store.dart';

/// Landscape-pixel indices covered by volume boxes and path footprints.
Set<(int, int)> coveredGroundPixels({
  required VolumeStore volumes,
  required PathStore paths,
}) {
  final covered = <(int, int)>{};
  final n = volumes.grid.subtilesPerTile;
  for (final volume in volumes.visibleVolumes) {
    for (final cell in volume.cells) {
      final box = cell.box;
      _addRect(
        covered,
        tx: cell.tx,
        ty: cell.ty,
        ox: box.originXSubtiles,
        oz: box.originZSubtiles,
        width: box.widthSubtiles,
        depth: box.depthSubtiles,
        subtilesPerTile: n,
      );
    }
  }
  for (final entry in pathFootprintsByTile(volumes: volumes, paths: paths).entries) {
    final (tx, ty) = entry.key;
    for (final piece in entry.value) {
      _addRect(
        covered,
        tx: tx,
        ty: ty,
        ox: piece.originXSubtiles,
        oz: piece.originZSubtiles,
        width: piece.widthSubtiles,
        depth: piece.depthSubtiles,
        subtilesPerTile: n,
      );
    }
  }
  return covered;
}

void _addRect(
  Set<(int, int)> out, {
  required int tx,
  required int ty,
  required int ox,
  required int oz,
  required int width,
  required int depth,
  required int subtilesPerTile,
}) {
  for (var z = 0; z < depth; z++) {
    for (var x = 0; x < width; x++) {
      out.add((
        tx * subtilesPerTile + ox + x,
        ty * subtilesPerTile + oz + z,
      ));
    }
  }
}

/// Punch void under volumes/paths and restore generator material where
/// coverage was removed. Returns true if the atlas needs a rebake.
bool syncGroundCoverage({
  required LandscapeGrid grid,
  required VolumeStore volumes,
  required PathStore paths,
  required LandscapeGenerator generator,
}) {
  return grid.applyCoverage(
    coveredGroundPixels(volumes: volumes, paths: paths),
    generator,
  );
}
