import 'package:vector_math/vector_math_64.dart';

import '../paths/path_store.dart';
import '../volumes/volume.dart';
import '../volumes/volume_store.dart';
import '../walls/wall_store.dart';
import 'eraser_filter.dart';

/// Delete enabled gameplay objects whose ground footprint meets the brush.
bool eraseWorld({
  required Vector3 world,
  required double radius,
  required EraserFilter filter,
  required WallStore walls,
  required PathStore paths,
  required VolumeStore volumes,
}) {
  if (radius <= 0) return false;
  var changed = false;
  if (filter.walls && walls.eraseNear(world, radius)) {
    changed = true;
  }
  if (filter.paths) {
    for (final tile in List<(int, int)>.from(paths.tiles)) {
      if (!_tileHits(paths.grid, tile.$1, tile.$2, world, radius)) continue;
      if (paths.removeTile(tile.$1, tile.$2)) changed = true;
    }
  }
  if (filter.volumes && !volumes.isEditing) {
    for (final volume in List<Volume>.from(volumes.volumes)) {
      for (final cell in List<VolumeCell>.from(volume.cells)) {
        if (!_boxHits(volumes.grid, cell, world, radius)) continue;
        if (volumes.removeCellAt(cell.tx, cell.ty)) changed = true;
      }
    }
  }
  return changed;
}

bool _tileHits(VolumeGrid grid, int tx, int ty, Vector3 world, double radius) {
  final origin = grid.tileOrigin(tx, ty);
  return _aabbHits(
    world,
    radius,
    origin.x,
    origin.z,
    origin.x + grid.tileSize,
    origin.z + grid.tileSize,
  );
}

bool _boxHits(VolumeGrid grid, VolumeCell cell, Vector3 world, double radius) {
  final min = cell.box.worldMin(grid, cell.tx, cell.ty);
  final max = cell.box.worldMax(grid, cell.tx, cell.ty);
  return _aabbHits(world, radius, min.x, min.z, max.x, max.z);
}

bool _aabbHits(
  Vector3 world,
  double radius,
  double minX,
  double minZ,
  double maxX,
  double maxZ,
) {
  final cx = world.x.clamp(minX, maxX);
  final cz = world.z.clamp(minZ, maxZ);
  final dx = world.x - cx;
  final dz = world.z - cz;
  return dx * dx + dz * dz <= radius * radius;
}
