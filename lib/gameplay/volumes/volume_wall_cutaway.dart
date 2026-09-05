import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../viewers/world_plane.dart';

/// Fully hide a wall when the camera is at least this aligned with its outward
/// normal (about 75° off the wall plane).
const double kWallCutawayHiddenFacing = 0.25;

/// Fully show a wall once the camera is no longer in front of it.
const double kWallCutawayVisibleFacing = 0.0;

/// Horizontal alignment of [camera] with a wall's outward [normal], in [-1, 1].
double wallFacing({
  required Vector3 camera,
  required Vector3 cellCenter,
  required Vector3 outwardNormal,
}) {
  final dx = camera.x - cellCenter.x;
  final dz = camera.z - cellCenter.z;
  final len = math.sqrt(dx * dx + dz * dz);
  if (len < 1e-8) return 0;
  return outwardNormal.x * (dx / len) + outwardNormal.z * (dz / len);
}

/// Soft cutaway: 0 when the wall faces the camera, 1 when it does not.
double wallCutawayOpacity(double facing) {
  if (facing >= kWallCutawayHiddenFacing) return 0;
  if (facing <= kWallCutawayVisibleFacing) return 1;
  final span = kWallCutawayHiddenFacing - kWallCutawayVisibleFacing;
  return 1 - (facing - kWallCutawayVisibleFacing) / span;
}

/// Mix cutaway with how open the ceiling already is.
double wallOpacityForReveal({
  required double ceilingOpacity,
  required double cutaway,
}) {
  return 1 + (cutaway - 1) * (1 - ceilingOpacity);
}

double wallOpacityForFace({
  required VolumeFace face,
  required Vector3 camera,
  required Vector3 cellCenter,
  required double ceilingOpacity,
}) {
  switch (face) {
    case VolumeFace.posY:
    case VolumeFace.negY:
      return 1;
    case VolumeFace.posX:
    case VolumeFace.negX:
    case VolumeFace.posZ:
    case VolumeFace.negZ:
      final facing = wallFacing(
        camera: camera,
        cellCenter: cellCenter,
        outwardNormal: face.worldNormal,
      );
      return wallOpacityForReveal(
        ceilingOpacity: ceilingOpacity,
        cutaway: wallCutawayOpacity(facing),
      );
  }
}
