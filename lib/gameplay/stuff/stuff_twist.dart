import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:vector_math/vector_math_64.dart';

import '../../rendering/scene/camera.dart';

/// Signed screen-space twist from two finger samples, in radians.
///
/// Positive when the finger pair rotates clockwise on screen.
double stuffScreenTwist({
  required Offset a0,
  required Offset b0,
  required Offset a1,
  required Offset b1,
}) {
  final from = b0 - a0;
  final to = b1 - a1;
  if (from.distance < 1e-4 || to.distance < 1e-4) return 0;
  return math.atan2(to.dy, to.dx) - math.atan2(from.dy, from.dx);
}

/// Map a clockwise-on-screen delta onto yaw around [planeNormal].
///
/// Looking along the plane normal (e.g. down at a floor), clockwise screen
/// motion increases yaw.
double stuffYawDeltaFromScreenTwist({
  required double screenTwist,
  required Vector3 planeNormal,
  required Camera camera,
}) {
  final facing = camera.forward.dot(planeNormal);
  final sign = facing >= 0 ? 1.0 : -1.0;
  return screenTwist * sign;
}
