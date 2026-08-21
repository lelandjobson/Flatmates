import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../viewers/world_plane.dart';
import 'volume.dart';

const kDoorWidthSubtiles = 2;
const kDoorHeightSubtiles = 4;

/// 2×4 (4 high) opening on an accessible wall, seated on the floor.
class VolumeDoor {
  const VolumeDoor({
    required this.side,
    required this.originU,
    required this.originY,
    required this.width,
    required this.height,
  });

  final VolumeSide side;
  final int originU;
  final int originY;
  final int width;
  final int height;

  VolumeFace get face => side.volumeFace;

  bool containsFacePixel(int u, int v) {
    return u >= originU &&
        u < originU + width &&
        v >= originY &&
        v < originY + height;
  }
}

extension VolumeSideFace on VolumeSide {
  VolumeFace get volumeFace => switch (this) {
        VolumeSide.east => VolumeFace.posX,
        VolumeSide.west => VolumeFace.negX,
        VolumeSide.south => VolumeFace.posZ,
        VolumeSide.north => VolumeFace.negZ,
      };
}

/// Centered 2×4 door on [side], clamped to the box. Null if the face is gone.
VolumeDoor? volumeDoorForSide(BoxPrimitive box, VolumeSide side) {
  final faceW = switch (side) {
    VolumeSide.east || VolumeSide.west => box.depthSubtiles,
    VolumeSide.north || VolumeSide.south => box.widthSubtiles,
  };
  final w = math.min(kDoorWidthSubtiles, faceW);
  final h = math.min(kDoorHeightSubtiles, box.heightSubtiles);
  if (w < 1 || h < 1) return null;
  return VolumeDoor(
    side: side,
    originU: (faceW - w) ~/ 2,
    originY: 0,
    width: w,
    height: h,
  );
}

bool volumeDoorContainsFacePixel({
  required BoxPrimitive box,
  required VolumeFace face,
  required int u,
  required int v,
  required Set<VolumeSide> accessibleSides,
}) {
  for (final side in accessibleSides) {
    if (side.volumeFace != face) continue;
    final door = volumeDoorForSide(box, side);
    if (door != null && door.containsFacePixel(u, v)) return true;
  }
  return false;
}

/// Exterior accessible doors on [cell] (skips sides shared with [volume]).
Iterable<VolumeDoor> exteriorDoors(Volume volume, VolumeCell cell) sync* {
  for (final side in cell.accessibleSides) {
    final (dx, dy) = side.tileDelta;
    if (volume.cellAt(cell.tx + dx, cell.ty + dy) != null) continue;
    final door = volumeDoorForSide(cell.box, side);
    if (door != null) yield door;
  }
}

/// Four world corners of the door quad, CCW when viewed from outside.
List<Vector3> doorWorldCorners({
  required VolumeGrid grid,
  required int tx,
  required int ty,
  required BoxPrimitive box,
  required VolumeDoor door,
}) {
  final min = box.worldMin(grid, tx, ty);
  final max = box.worldMax(grid, tx, ty);
  final s = grid.subtileSize;
  final y0 = min.y + door.originY * s;
  final y1 = y0 + door.height * s;
  switch (door.side) {
    case VolumeSide.east:
      {
        final x = max.x;
        final z0 = min.z + door.originU * s;
        final z1 = z0 + door.width * s;
        return [
          Vector3(x, y0, z0),
          Vector3(x, y0, z1),
          Vector3(x, y1, z1),
          Vector3(x, y1, z0),
        ];
      }
    case VolumeSide.west:
      {
        final x = min.x;
        final z0 = min.z + door.originU * s;
        final z1 = z0 + door.width * s;
        return [
          Vector3(x, y0, z1),
          Vector3(x, y0, z0),
          Vector3(x, y1, z0),
          Vector3(x, y1, z1),
        ];
      }
    case VolumeSide.south:
      {
        final z = max.z;
        final x0 = min.x + door.originU * s;
        final x1 = x0 + door.width * s;
        return [
          Vector3(x1, y0, z),
          Vector3(x0, y0, z),
          Vector3(x0, y1, z),
          Vector3(x1, y1, z),
        ];
      }
    case VolumeSide.north:
      {
        final z = min.z;
        final x0 = min.x + door.originU * s;
        final x1 = x0 + door.width * s;
        return [
          Vector3(x0, y0, z),
          Vector3(x1, y0, z),
          Vector3(x1, y1, z),
          Vector3(x0, y1, z),
        ];
      }
  }
}
