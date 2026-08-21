import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../volumes/volume.dart';
import 'focus_region.dart';

enum CropHandle { posX, negX, posY, negY, posZ, negZ }

extension CropHandleX on CropHandle {
  Vector3 get axis => switch (this) {
        CropHandle.posX => Vector3(1, 0, 0),
        CropHandle.negX => Vector3(-1, 0, 0),
        CropHandle.posY => Vector3(0, 1, 0),
        CropHandle.negY => Vector3(0, -1, 0),
        CropHandle.posZ => Vector3(0, 0, 1),
        CropHandle.negZ => Vector3(0, 0, -1),
      };

  bool get isHeight => this == CropHandle.posY || this == CropHandle.negY;
}

/// Inclusive-min, exclusive-max subtile AABB used to crop focus3d isolation.
class FocusCrop {
  const FocusCrop({
    required this.minSx,
    required this.minSy,
    required this.minSz,
    required this.maxSx,
    required this.maxSy,
    required this.maxSz,
  });

  final int minSx;
  final int minSy;
  final int minSz;
  final int maxSx;
  final int maxSy;
  final int maxSz;

  static const int minExtent = 1;

  int get width => maxSx - minSx;
  int get height => maxSy - minSy;
  int get depth => maxSz - minSz;

  bool sameAs(FocusCrop other) =>
      minSx == other.minSx &&
      minSy == other.minSy &&
      minSz == other.minSz &&
      maxSx == other.maxSx &&
      maxSy == other.maxSy &&
      maxSz == other.maxSz;

  bool get includesGround => minSy <= 0;

  factory FocusCrop.fromIsolation({
    required FocusRegion region,
    required VolumeGrid grid,
    required double contentMaxY,
  }) {
    final n = grid.subtilesPerTile;
    final s = grid.subtileSize;
    final maxSy = math.max(1, ((contentMaxY / s) - 1e-9).ceil());
    return FocusCrop(
      minSx: region.minTx * n,
      minSy: 0,
      minSz: region.minTy * n,
      maxSx: (region.maxTx + 1) * n,
      maxSy: maxSy,
      maxSz: (region.maxTy + 1) * n,
    );
  }

  Vector3 worldMin(VolumeGrid grid) {
    final s = grid.subtileSize;
    return Vector3(
      -grid.mapHalf + minSx * s,
      minSy * s,
      -grid.mapHalf + minSz * s,
    );
  }

  Vector3 worldMax(VolumeGrid grid) {
    final s = grid.subtileSize;
    return Vector3(
      -grid.mapHalf + maxSx * s,
      maxSy * s,
      -grid.mapHalf + maxSz * s,
    );
  }

  Vector3 faceCenter(VolumeGrid grid, CropHandle handle) {
    final min = worldMin(grid);
    final max = worldMax(grid);
    final midX = (min.x + max.x) * 0.5;
    final midY = (min.y + max.y) * 0.5;
    final midZ = (min.z + max.z) * 0.5;
    return switch (handle) {
      CropHandle.posX => Vector3(max.x, midY, midZ),
      CropHandle.negX => Vector3(min.x, midY, midZ),
      CropHandle.posY => Vector3(midX, max.y, midZ),
      CropHandle.negY => Vector3(midX, min.y, midZ),
      CropHandle.posZ => Vector3(midX, midY, max.z),
      CropHandle.negZ => Vector3(midX, midY, min.z),
    };
  }

  bool intersectsWorld(Vector3 min, Vector3 max, VolumeGrid grid) {
    final a = worldMin(grid);
    final b = worldMax(grid);
    return a.x < max.x &&
        b.x > min.x &&
        a.y < max.y &&
        b.y > min.y &&
        a.z < max.z &&
        b.z > min.z;
  }

  bool intersectsTile(VolumeGrid grid, int tx, int ty) {
    final n = grid.subtilesPerTile;
    final tMinSx = tx * n;
    final tMaxSx = (tx + 1) * n;
    final tMinSz = ty * n;
    final tMaxSz = (ty + 1) * n;
    return minSx < tMaxSx && maxSx > tMinSx && minSz < tMaxSz && maxSz > tMinSz;
  }

  /// Move [handle]'s face by [delta] world units, snapping to subtles.
  /// The opposite face stays fixed. Cannot grow past [bounds] or below
  /// [minExtent].
  FocusCrop applyHandleDelta({
    required CropHandle handle,
    required double delta,
    required VolumeGrid grid,
    required FocusCrop bounds,
  }) {
    final steps = (delta / grid.subtileSize).round();
    if (steps == 0) return this;
    var nMinSx = minSx;
    var nMinSy = minSy;
    var nMinSz = minSz;
    var nMaxSx = maxSx;
    var nMaxSy = maxSy;
    var nMaxSz = maxSz;
    switch (handle) {
      case CropHandle.posX:
        nMaxSx = (maxSx + steps).clamp(minSx + minExtent, bounds.maxSx);
      case CropHandle.negX:
        nMinSx = (minSx - steps).clamp(bounds.minSx, maxSx - minExtent);
      case CropHandle.posY:
        nMaxSy = (maxSy + steps).clamp(minSy + minExtent, bounds.maxSy);
      case CropHandle.negY:
        nMinSy = (minSy - steps).clamp(bounds.minSy, maxSy - minExtent);
      case CropHandle.posZ:
        nMaxSz = (maxSz + steps).clamp(minSz + minExtent, bounds.maxSz);
      case CropHandle.negZ:
        nMinSz = (minSz - steps).clamp(bounds.minSz, maxSz - minExtent);
    }
    return FocusCrop(
      minSx: nMinSx,
      minSy: nMinSy,
      minSz: nMinSz,
      maxSx: nMaxSx,
      maxSy: nMaxSy,
      maxSz: nMaxSz,
    );
  }
}
