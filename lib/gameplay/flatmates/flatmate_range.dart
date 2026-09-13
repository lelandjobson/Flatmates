import 'dart:math' as math;
import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

import 'day_action.dart';

/// Chebyshev distance in tiles.
int chebyshevTiles((int, int) a, (int, int) b) =>
    math.max((a.$1 - b.$1).abs(), (a.$2 - b.$2).abs());

bool inFlatmateRange((int, int) tile, (int, int) home) =>
    chebyshevTiles(tile, home) <= kFlatmateActionRange;

/// Inclusive 9×9 square around [home] (4 tiles in every direction).
Iterable<(int, int)> flatmateRangeTiles((int, int) home) sync* {
  for (var dx = -kFlatmateActionRange; dx <= kFlatmateActionRange; dx++) {
    for (var dy = -kFlatmateActionRange; dy <= kFlatmateActionRange; dy++) {
      yield (home.$1 + dx, home.$2 + dy);
    }
  }
}

/// Outer ground corners of the range square, clockwise from min xz.
List<Vector3> flatmateRangeWorldCorners(
  (int, int) home, {
  required double tileSize,
  double y = 0,
}) {
  final r = kFlatmateActionRange;
  final minX = (home.$1 - r) * tileSize;
  final minZ = (home.$2 - r) * tileSize;
  final maxX = (home.$1 + r + 1) * tileSize;
  final maxZ = (home.$2 + r + 1) * tileSize;
  return [
    Vector3(minX, y, minZ),
    Vector3(maxX, y, minZ),
    Vector3(maxX, y, maxZ),
    Vector3(minX, y, maxZ),
  ];
}

/// Viewport minus the projected range quad, so the outside can be dimmed.
Path? flatmateRangeOutsidePath({
  required Size viewport,
  required List<Offset> quad,
}) {
  if (quad.length != 4 || viewport.isEmpty) return null;
  return Path()
    ..fillType = PathFillType.evenOdd
    ..addRect(Offset.zero & viewport)
    ..addPolygon(quad, true);
}

/// Perimeter of the Chebyshev range square, clockwise from NW.
List<(int, int)> flatmateRangePerimeter((int, int) home) {
  final r = kFlatmateActionRange;
  final tiles = <(int, int)>[];
  for (var dx = -r; dx <= r; dx++) {
    tiles.add((home.$1 + dx, home.$2 - r));
  }
  for (var dy = -r + 1; dy <= r; dy++) {
    tiles.add((home.$1 + r, home.$2 + dy));
  }
  for (var dx = r - 1; dx >= -r; dx--) {
    tiles.add((home.$1 + dx, home.$2 + r));
  }
  for (var dy = r - 1; dy >= -r + 1; dy--) {
    tiles.add((home.$1 - r, home.$2 + dy));
  }
  return tiles;
}

(int, int) centroidTile(Iterable<(int, int)> tiles) {
  final list = tiles.toList();
  if (list.isEmpty) return (0, 0);
  var sx = 0;
  var sy = 0;
  for (final tile in list) {
    sx += tile.$1;
    sy += tile.$2;
  }
  final cx = sx / list.length;
  final cy = sy / list.length;
  var best = list.first;
  var bestDist = double.infinity;
  for (final tile in list) {
    final dx = tile.$1 - cx;
    final dy = tile.$2 - cy;
    final d = dx * dx + dy * dy;
    if (d < bestDist) {
      bestDist = d;
      best = tile;
    }
  }
  return best;
}

bool isPathAdjacent({
  required (int, int) tile,
  required bool Function(int tx, int ty) isPath,
}) {
  if (isPath(tile.$1, tile.$2)) return true;
  const deltas = [(1, 0), (-1, 0), (0, 1), (0, -1)];
  for (final (dx, dy) in deltas) {
    if (isPath(tile.$1 + dx, tile.$2 + dy)) return true;
  }
  return false;
}