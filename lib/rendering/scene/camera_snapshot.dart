import 'package:vector_math/vector_math_64.dart';

import 'camera.dart';

class CameraSnapshot {
  const CameraSnapshot({
    required this.position,
    required this.target,
    required this.up,
    required this.projection,
    required this.fovDegrees,
    required this.orthographicScale,
  });

  final Vector3 position;
  final Vector3 target;
  final Vector3 up;
  final ProjectionType projection;
  final double fovDegrees;
  final double orthographicScale;
}

