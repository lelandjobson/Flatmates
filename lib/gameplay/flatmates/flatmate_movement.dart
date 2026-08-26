import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../volumes/volume.dart';
import 'flatmate_pathfinder.dart';

/// Session-only walk along a tile polyline.
class FlatmateMovement {
  List<(int, int)> tiles = [];
  double progress = 0;

  bool get isMoving => tiles.length >= 2 && progress < tiles.length - 1;

  void start(List<(int, int)> path) {
    tiles = List<(int, int)>.from(path);
    progress = 0;
  }

  void clear() {
    tiles = [];
    progress = 0;
  }

  /// Advance [dt] seconds. Speed is [baseTilesPerSecond], ×1.5 on path tiles.
  bool advance({
    required double dt,
    required double baseTilesPerSecond,
    required bool Function(int tx, int ty) onPath,
  }) {
    if (!isMoving) return false;
    final i = progress.floor().clamp(0, tiles.length - 2);
    final tile = tiles[i];
    final speed = onPath(tile.$1, tile.$2)
        ? baseTilesPerSecond * FlatmatePathfinder.pathSpeedMultiplier
        : baseTilesPerSecond;
    progress += dt * speed;
    if (progress >= tiles.length - 1) {
      progress = (tiles.length - 1).toDouble();
      return false;
    }
    return true;
  }

  Vector3 worldPosition(VolumeGrid grid, double sitY) {
    if (tiles.isEmpty) return Vector3(0, sitY, 0);
    if (tiles.length == 1) {
      final c = grid.tileCenter(tiles.first.$1, tiles.first.$2);
      return Vector3(c.x, sitY, c.z);
    }
    final max = tiles.length - 1;
    final t = progress.clamp(0.0, max.toDouble());
    final i = t.floor().clamp(0, max - 1);
    final frac = t - i;
    final a = grid.tileCenter(tiles[i].$1, tiles[i].$2);
    final b = grid.tileCenter(tiles[i + 1].$1, tiles[i + 1].$2);
    return Vector3(
      a.x + (b.x - a.x) * frac,
      sitY,
      a.z + (b.z - a.z) * frac,
    );
  }

  /// Yaw in radians so +Z is south (tile +Y).
  double facingYaw() {
    if (tiles.length < 2) return 0;
    final max = tiles.length - 1;
    final i = progress.floor().clamp(0, max - 1);
    final a = tiles[i];
    final b = tiles[i + 1];
    final dx = (b.$1 - a.$1).toDouble();
    final dz = (b.$2 - a.$2).toDouble();
    if (dx.abs() < 1e-8 && dz.abs() < 1e-8) return 0;
    return math.atan2(dx, dz);
  }
}
