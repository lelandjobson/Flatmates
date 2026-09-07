import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../viewers/world_plane.dart';
import 'stuff_catalog.dart';

/// One placed interior object, anchored to a volume floor or wall.
class StuffInstance {
  StuffInstance({
    required this.id,
    required this.specId,
    required this.volumeId,
    required this.tx,
    required this.ty,
    required this.face,
    required Vector3 origin,
    this.yaw = 0,
  }) : origin = Vector3.copy(origin);

  final String id;
  final String specId;
  int volumeId;
  int tx;
  int ty;
  VolumeFace face;
  final Vector3 origin;
  double yaw;

  StuffSpec? get spec => stuffById(specId);

  StuffInstance clone() => StuffInstance(
        id: id,
        specId: specId,
        volumeId: volumeId,
        tx: tx,
        ty: ty,
        face: face,
        origin: origin,
        yaw: yaw,
      );
}

/// Into the room from [face] (opposite the outward geometric normal).
Vector3 stuffInwardNormal(VolumeFace face) => -face.worldNormal;

/// Sit [onPlane] slightly into the room so the hull does not start in the solid.
Vector3 stuffOriginOnPlane(Vector3 onPlane, VolumeFace face) {
  return onPlane + stuffInwardNormal(face) * kStuffPlaneEpsilon;
}

/// Euler for [Transformable]: yaw only around the anchor-plane normal.
Vector3 stuffEuler(VolumeFace face, double yaw) {
  return switch (face) {
    VolumeFace.negY => Vector3(0, yaw, 0),
    VolumeFace.posY => Vector3(math.pi, yaw, 0),
    VolumeFace.posX => Vector3(yaw, -math.pi / 2, 0),
    VolumeFace.negX => Vector3(-yaw, math.pi / 2, 0),
    VolumeFace.posZ => Vector3(0, math.pi, yaw),
    VolumeFace.negZ => Vector3(0, 0, yaw),
  };
}

bool stuffFaceMatchesAnchor(VolumeFace face, StuffAnchor anchor) {
  return switch (anchor) {
    StuffAnchor.floor => face == VolumeFace.negY,
    StuffAnchor.wall =>
      face == VolumeFace.posX ||
          face == VolumeFace.negX ||
          face == VolumeFace.posZ ||
          face == VolumeFace.negZ,
  };
}
