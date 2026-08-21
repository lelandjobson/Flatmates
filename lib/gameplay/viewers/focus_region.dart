import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../paths/path_mesh.dart';
import '../paths/path_store.dart';
import '../volumes/volume.dart';
import '../volumes/volume_store.dart';

/// Inclusive tile rectangle the focus3d viewer keeps on screen.
class FocusRegion {
  const FocusRegion({
    required this.minTx,
    required this.minTy,
    required this.maxTx,
    required this.maxTy,
  });

  final int minTx;
  final int minTy;
  final int maxTx;
  final int maxTy;

  bool contains(int tx, int ty) =>
      tx >= minTx && tx <= maxTx && ty >= minTy && ty <= maxTy;

  Iterable<(int, int)> get tiles sync* {
    for (var ty = minTy; ty <= maxTy; ty++) {
      for (var tx = minTx; tx <= maxTx; tx++) {
        yield (tx, ty);
      }
    }
  }

  /// 3×3 (clamped) with [tx],[ty] at the center.
  factory FocusRegion.aroundTile({
    required VolumeGrid grid,
    required int tx,
    required int ty,
    int radius = 1,
  }) {
    return FocusRegion(
      minTx: (tx - radius).clamp(0, grid.tilesSide - 1),
      minTy: (ty - radius).clamp(0, grid.tilesSide - 1),
      maxTx: (tx + radius).clamp(0, grid.tilesSide - 1),
      maxTy: (ty + radius).clamp(0, grid.tilesSide - 1),
    );
  }

  /// Volume cell bounds plus [pad] tiles of context on every side.
  factory FocusRegion.aroundVolume({
    required VolumeGrid grid,
    required Volume volume,
    int pad = 1,
  }) {
    var minTx = grid.tilesSide - 1;
    var minTy = grid.tilesSide - 1;
    var maxTx = 0;
    var maxTy = 0;
    for (final cell in volume.cells) {
      if (cell.tx < minTx) minTx = cell.tx;
      if (cell.ty < minTy) minTy = cell.ty;
      if (cell.tx > maxTx) maxTx = cell.tx;
      if (cell.ty > maxTy) maxTy = cell.ty;
    }
    return FocusRegion(
      minTx: (minTx - pad).clamp(0, grid.tilesSide - 1),
      minTy: (minTy - pad).clamp(0, grid.tilesSide - 1),
      maxTx: (maxTx + pad).clamp(0, grid.tilesSide - 1),
      maxTy: (maxTy + pad).clamp(0, grid.tilesSide - 1),
    );
  }

  /// World AABB of focused tiles plus volumes/paths on them.
  (Vector3 min, Vector3 max) contentAabb({
    required VolumeGrid grid,
    required VolumeStore volumes,
    required PathStore paths,
  }) {
    final origin = grid.tileOrigin(minTx, minTy);
    final far = grid.tileOrigin(maxTx, maxTy);
    var min = Vector3(origin.x, 0, origin.z);
    var max = Vector3(
      far.x + grid.tileSize,
      grid.subtileSize,
      far.z + grid.tileSize,
    );

    void expand(Vector3 a, Vector3 b) {
      min = Vector3(
        math.min(min.x, a.x),
        math.min(min.y, a.y),
        math.min(min.z, a.z),
      );
      max = Vector3(
        math.max(max.x, b.x),
        math.max(max.y, b.y),
        math.max(max.z, b.z),
      );
    }

    for (final volume in volumes.visibleVolumes) {
      for (final cell in volume.cells) {
        if (!contains(cell.tx, cell.ty)) continue;
        expand(
          cell.box.worldMin(grid, cell.tx, cell.ty),
          cell.box.worldMax(grid, cell.tx, cell.ty),
        );
      }
    }
    for (final (tx, ty) in paths.tiles) {
      if (!contains(tx, ty)) continue;
      final (tileMin, tileMax) = grid.tileAabb(tx, ty);
      expand(tileMin, Vector3(tileMax.x, kPathHeight, tileMax.z));
    }
    return (min, max);
  }

  Vector3 contentCenter({
    required VolumeGrid grid,
    required VolumeStore volumes,
    required PathStore paths,
  }) {
    final (min, max) = contentAabb(
      grid: grid,
      volumes: volumes,
      paths: paths,
    );
    return Vector3(
      (min.x + max.x) * 0.5,
      (min.y + max.y) * 0.5,
      (min.z + max.z) * 0.5,
    );
  }
}
