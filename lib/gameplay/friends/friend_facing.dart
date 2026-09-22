import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

const double kFacePauseMin = 0.5;
const double kFacePauseMax = 2.0;
const double kFaceTurnSpeed = 10;
const double kFaceRetrigger = 25 * math.pi / 180;

/// Body yaw follows the path tangent while moving, then faces the camera after a stop pause.
class FriendFacing {
  FriendFacing({required this.seed, this.yaw = 0})
      : _rng = math.Random(seed.hashCode);

  final String seed;
  final math.Random _rng;

  double yaw;
  bool _wasMoving = false;
  double _pause = 0;
  double? _target;
  double? _aimedCameraYaw;

  bool get isTurning => _target != null;
  bool get isWaitingToFaceCamera => _pause > 0;

  /// Smallest-arc candidate among [travelYaw] + k·90°.
  static double nearestPathAlign(double yaw, double travelYaw) {
    var best = wrapYaw(travelYaw);
    var bestAbs = double.infinity;
    for (var k = 0; k < 4; k++) {
      final cand = wrapYaw(travelYaw + k * (math.pi / 2));
      final delta = shortestDelta(yaw, cand).abs();
      if (delta < bestAbs) {
        bestAbs = delta;
        best = cand;
      }
    }
    return best;
  }

  /// Yaw in (−π, π].
  static double wrapYaw(double yaw) {
    var w = yaw % (math.pi * 2);
    if (w > math.pi) w -= math.pi * 2;
    if (w <= -math.pi) w += math.pi * 2;
    return w;
  }

  /// Yaw so +Z points toward [camera] on the XZ plane. Null if overhead.
  static double? cameraFacingYaw(Vector3 from, Vector3 camera) {
    final dx = camera.x - from.x;
    final dz = camera.z - from.z;
    if (dx.abs() < 1e-5 && dz.abs() < 1e-5) return null;
    return math.atan2(dx, dz);
  }

  /// Signed delta in (−π, π].
  static double shortestDelta(double from, double to) {
    var d = (to - from) % (math.pi * 2);
    if (d > math.pi) d -= math.pi * 2;
    if (d <= -math.pi) d += math.pi * 2;
    return d;
  }

  /// Steer [yaw] toward [target]. [inertia] 0 snaps; 1 is 90° per second.
  static double steerToward(
    double yaw,
    double target,
    double dt,
    double inertia,
  ) {
    if (inertia <= 0) return wrapYaw(target);
    if (dt <= 0) return wrapYaw(yaw);
    final delta = shortestDelta(yaw, target);
    final rate = (math.pi / 2) / inertia;
    final step = rate * dt;
    if (delta.abs() <= step || delta.abs() < 1e-6) return wrapYaw(target);
    return wrapYaw(yaw + delta.sign * step);
  }

  void tick(
    double dt, {
    required bool moving,
    required double travelYaw,
    double? cameraYaw,
    double rotationInertia = 0,
  }) {
    if (moving && !_wasMoving) {
      _target = null;
      _pause = 0;
    } else if (!moving && _wasMoving) {
      _scheduleCameraFace(cameraYaw);
    } else if (!moving && cameraYaw != null) {
      final aimed = _aimedCameraYaw;
      if (aimed == null) {
        _aimedCameraYaw = cameraYaw;
      } else if (shortestDelta(aimed, cameraYaw).abs() > kFaceRetrigger) {
        _scheduleCameraFace(cameraYaw);
      }
    }
    _wasMoving = moving;

    if (moving) {
      yaw = steerToward(yaw, travelYaw, dt, rotationInertia);
      return;
    }

    if (_pause > 0) {
      _pause -= dt;
      if (_pause <= 0) {
        _pause = 0;
        _target = cameraYaw;
      }
    } else if (_target != null && cameraYaw != null) {
      _target = cameraYaw;
    }

    final target = _target;
    if (target == null || dt <= 0) return;
    final delta = shortestDelta(yaw, target);
    final step = kFaceTurnSpeed * dt;
    if (delta.abs() <= step || delta.abs() < 1e-3) {
      yaw = wrapYaw(target);
      _target = null;
      _aimedCameraYaw = yaw;
      return;
    }
    yaw = wrapYaw(yaw + delta.sign * step);
  }

  void _scheduleCameraFace(double? cameraYaw) {
    _target = null;
    _pause = kFacePauseMin + _rng.nextDouble() * (kFacePauseMax - kFacePauseMin);
    if (cameraYaw != null) _aimedCameraYaw = cameraYaw;
  }
}
