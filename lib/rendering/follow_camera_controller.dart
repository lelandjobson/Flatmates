import 'dart:math' as math;
import 'dart:ui';

/// Reusable follow-camera controller with inertia-based smoothing.
///
/// The controller maintains an internal velocity and applies
/// acceleration-capped spring logic so the camera smoothly chases
/// a target position rather than snapping pixel-for-pixel.
///
/// Usage (any 2D view):
/// ```dart
/// final follow = FollowCameraController();
/// // Each frame:
/// camera.position = follow.update(camera.position, targetWorldPos, dt);
/// ```
class FollowCameraController {
  FollowCameraController({
    this.enabled = true,
    double maxAcceleration = 1200.0,
    double damping = 8.0,
  }) : _maxAcceleration = maxAcceleration,
       _damping = damping;

  /// Master on/off toggle.
  bool enabled;

  /// Maximum change in velocity per second (pixels/s^2) for normal following.
  /// Lower values produce a floatier, more cinematic follow;
  /// higher values make the camera stick tighter to the target.
  double _maxAcceleration;
  double get maxAcceleration => _maxAcceleration;
  set maxAcceleration(double value) {
    _maxAcceleration = value.clamp(100.0, 20000.0);
  }

  /// Velocity decay factor (units: 1/s) for normal following.
  /// Higher = more aggressive braking near the target.
  double _damping;
  double get damping => _damping;
  set damping(double value) {
    _damping = value.clamp(1.0, 30.0);
  }

  /// Acceleration (px/s^2) used during snap-back after a rubber-band pan.
  /// Controls both how fast the camera ramps up and how smoothly it
  /// decelerates to a stop at the target (kinematic braking).
  double snapBackAcceleration = 2000.0;

  /// Ease exponent for the snap-back braking curve.
  ///
  /// - 0.5 = constant deceleration (linear braking, subtle ease)
  /// - 1.0 = speed proportional to distance (dramatic slow-down near target)
  /// - 1.5 = very steep ease, crawls for the last stretch
  double snapBackEase = 1.5;

  bool _snappingBack = false;
  bool get isSnappingBack => _snappingBack;
  double _snapBackInitialDist = 0.0;

  /// Engage snap-back mode. Call when re-engaging follow after a manual pan.
  void startSnapBack() {
    _snappingBack = true;
    _snapBackInitialDist = 0.0; // captured on first update tick
  }

  /// Internal velocity vector (world-space pixels/s).
  Offset _velocity = Offset.zero;
  Offset get velocity => _velocity;

  /// Maps a normalized inertia value (0.0 = tight/responsive, 1.0 = loose/floaty)
  /// to the internal [maxAcceleration]. Call this when the user adjusts the
  /// inertia slider so the view doesn't need to know the accel range.
  void setInertiaFromNormalized(double t) {
    final clamped = t.clamp(0.0, 1.0);
    // 0.0 → 8000 px/s² (snappy),  1.0 → 200 px/s² (floaty)
    _maxAcceleration = _lerpDouble(8000.0, 200.0, clamped);
    _damping = _lerpDouble(12.0, 4.0, clamped);
  }

  /// Reset internal velocity. Call after view rotation, teleport,
  /// or re-engaging follow after a manual pan so the camera doesn't lurch.
  void resetVelocity() {
    _velocity = Offset.zero;
  }

  /// Compute the next camera position.
  ///
  /// [cameraPos] – current camera center (world space).
  /// [targetPos] – desired camera center (world space, e.g. friend position).
  /// [dt]        – elapsed seconds since last frame (clamped externally).
  ///
  /// Returns the updated camera position.
  Offset update(Offset cameraPos, Offset targetPos, double dt) {
    if (!enabled || dt <= 0) return cameraPos;

    if (_snappingBack) {
      return _updateSnapBack(cameraPos, targetPos, dt);
    }
    return _updateFollow(cameraPos, targetPos, dt);
  }

  /// Normal spring-based follow with acceleration capping.
  Offset _updateFollow(Offset cameraPos, Offset targetPos, double dt) {
    final displacement = targetPos - cameraPos;
    final distance = displacement.distance;

    if (distance < 0.01) {
      _velocity = Offset.zero;
      return targetPos;
    }

    final desiredVelocity = displacement * _damping;
    final accel = desiredVelocity - _velocity;
    final accelMag = accel.distance;

    final Offset clampedAccel;
    if (accelMag > _maxAcceleration * dt) {
      clampedAccel = accel * (_maxAcceleration * dt / accelMag);
    } else {
      clampedAccel = accel;
    }

    _velocity = _velocity + clampedAccel;
    return cameraPos + _velocity * dt;
  }

  /// Kinematic braking snap-back: accelerates toward target, then
  /// decelerates smoothly so it eases to a stop with no overshoot.
  ///
  /// The braking speed is derived from `sqrt(2*a*d_eff)` where `d_eff`
  /// is a reshaped distance: `d_eff = D * (d/D)^(2*ease)`, with D being
  /// the initial snap-back distance. At ease=0.5 this equals the classic
  /// constant-deceleration formula. Higher ease values compress the speed
  /// curve near the target, producing a visible crawl in the last stretch.
  Offset _updateSnapBack(Offset cameraPos, Offset targetPos, double dt) {
    final displacement = targetPos - cameraPos;
    final distance = displacement.distance;

    if (distance < 0.1) {
      _velocity = Offset.zero;
      _snappingBack = false;
      return targetPos;
    }

    // Capture initial distance on the first tick.
    if (_snapBackInitialDist <= 0.0) {
      _snapBackInitialDist = distance;
    }

    final direction = displacement / distance;
    final a = snapBackAcceleration;

    // Reshape the effective distance so speed drops off more steeply
    // near the target. The ratio (d / D) is in [0, 1] during normal
    // approach, so raising it to a power > 1 compresses small distances.
    final ratio = distance / _snapBackInitialDist;
    final effectiveDist =
        _snapBackInitialDist * math.pow(ratio, 2.0 * snapBackEase);
    final brakingSpeed = math.sqrt(2.0 * a * effectiveDist);

    // Current speed projected onto the target direction.
    final currentSpeed =
        _velocity.dx * direction.dx + _velocity.dy * direction.dy;

    // Accelerate toward target, but never exceed the braking speed.
    final speedDiff = brakingSpeed - currentSpeed;
    final maxChange = a * dt;
    final speedChange = speedDiff.clamp(-maxChange, maxChange);
    final newSpeed = currentSpeed + speedChange;

    _velocity = direction * newSpeed;

    // Overshoot guard: if the step would pass the target, snap.
    final step = _velocity * dt;
    if (step.distance >= distance) {
      _velocity = Offset.zero;
      _snappingBack = false;
      return targetPos;
    }

    return cameraPos + step;
  }

  static double _lerpDouble(double a, double b, double t) => a + (b - a) * t;
}
