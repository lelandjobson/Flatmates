import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:vector_math/vector_math_64.dart';

import 'camera.dart';

/// Locked down-looking perspective camera: diagonal yaw, look-at pitch, XZ pan.
/// Zoom is either a ladder that springs to stops, or smooth between min/max.
/// Two-finger vertical drag can peek pitch around the look-at, then spring back.
class MapLookCameraController extends ChangeNotifier {
  MapLookCameraController({
    required this.camera,
    required TickerProvider vsync,
    Vector3? lookAt,
    double? distance,
    double minDistance = 24,
    double maxDistance = 400,
    int zoomStepCount = 3,
    this.ladderZoom = true,
    double pitch = defaultPitch,
    this.minPitch = defaultMinPitch,
    this.maxPitch = defaultMaxPitch,
    this.pitchPeekSensitivity = defaultPitchPeekSensitivity,
    double yaw = defaultYaw,
    this.zoomSensitivity = 0.0009,
    Vector3? boundsMin,
    Vector3? boundsMax,
  })  : zoomStepCount = math.max(2, zoomStepCount),
        _lookAt = Vector3(lookAt?.x ?? 0, 0, lookAt?.z ?? 0),
        _boundsMin = boundsMin,
        _boundsMax = boundsMax,
        _minDistance = minDistance,
        _maxDistance = math.max(maxDistance, minDistance + 1),
        restPitch = pitch,
        _pitch = pitch,
        _yaw = yaw,
        _yawTo = yaw {
    _steps = ladderZoom ? _buildSteps() : const [];
    final start = distance ??
        (ladderZoom
            ? _steps[_steps.length ~/ 2]
            : math.sqrt(minDistance * maxDistance));
    _distance = ladderZoom
        ? nearestStepDistance(start)
        : start.clamp(minDistance, maxDistance);
    _targetDistance = _distance;
    _zoomAnim = AnimationController.unbounded(vsync: vsync)
      ..addListener(_onZoomTick);
    _yawAnim = AnimationController.unbounded(vsync: vsync)
      ..addListener(_onYawTick)
      ..addStatusListener(_onYawStatus);
    _lookAtAnim = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 280),
    )..addListener(_onLookAtTick);
    _pitchAnim = AnimationController.unbounded(vsync: vsync)
      ..addListener(_onPitchTick);
    _applyPose(notify: false);
  }

  /// Pitch down from horizontal (radians). ~52° looks down along a diagonal.
  static const double defaultPitch = 52 * math.pi / 180;

  /// Lowest peek: still above the horizon so the camera stays off the ground.
  static const double defaultMinPitch = 16 * math.pi / 180;

  /// Highest peek: just shy of a true top-down so the view never inverts.
  static const double defaultMaxPitch = 86 * math.pi / 180;

  static const double defaultPitchPeekSensitivity = 0.0035;

  /// Yaw so the camera looks along +X/+Z.
  static const double defaultYaw = math.pi / 4;

  static const SpringDescription zoomSpring = SpringDescription(
    mass: 1,
    stiffness: 90,
    damping: 14,
  );

  static const SpringDescription yawSpring = SpringDescription(
    mass: 1,
    stiffness: 140,
    damping: 24,
  );

  static const SpringDescription pitchSpring = SpringDescription(
    mass: 1,
    stiffness: 80,
    damping: 13,
  );

  static const _kStepLabels3 = ['close', 'medium', 'far'];

  final Camera camera;
  double _minDistance;
  double _maxDistance;
  double get minDistance => _minDistance;
  double get maxDistance => _maxDistance;

  /// Ladder stops between [minDistance] and [maxDistance], inclusive. ≥ 2.
  final int zoomStepCount;

  /// When false, pinch/scroll zoom is continuous and only clamps to min/max.
  final bool ladderZoom;
  final double restPitch;
  final double minPitch;
  final double maxPitch;
  final double pitchPeekSensitivity;
  final double zoomSensitivity;

  double _yaw;
  double get yaw => _yaw;
  double get pitch => _pitch;

  final Vector3 _lookAt;
  final Vector3? _boundsMin;
  final Vector3? _boundsMax;

  late final AnimationController _zoomAnim;
  late final AnimationController _yawAnim;
  late final AnimationController _lookAtAnim;
  late final AnimationController _pitchAnim;
  Vector3? _lookAtFrom;
  Vector3? _lookAtTo;
  late List<double> _steps;
  late double _distance;
  late double _targetDistance;
  double _yawTo;
  bool _yawQueued = false;
  double _pitch;
  double _pitchEffort = 0;
  bool _pitchPeeking = false;
  Size _viewportSize = Size.zero;
  bool _gestureZooming = false;
  Timer? _scrollSnap;

  Vector3 get lookAt => Vector3.copy(_lookAt);
  double get distance => _distance;
  double get targetDistance => _targetDistance;
  double get targetYaw => _yawTo;
  List<double> get steps => List.unmodifiable(_steps);

  int get nearestStepIndex => _nearestStepIndex(_distance);

  String get zoomLabel {
    if (!ladderZoom) {
      final span = maxDistance - minDistance;
      if (span.abs() < 1e-6) return '100%';
      final t = ((_distance - minDistance) / span).clamp(0.0, 1.0);
      return '${(t * 100).round()}%';
    }
    final i = nearestStepIndex;
    if (zoomStepCount == 3) return _kStepLabels3[i];
    return '${i + 1}/$zoomStepCount';
  }

  void setViewportSize(Size size) {
    _viewportSize = size;
  }

  /// Orbit 90° clockwise around the look-at, as seen from above.
  void rotateClockwise() => _requestYawTurn(-math.pi / 2);

  /// Orbit 90° counter-clockwise around the look-at, as seen from above.
  void rotateCounterClockwise() => _requestYawTurn(math.pi / 2);

  /// One extra 90° can be queued. A second click extends the target and
  /// keeps velocity; further clicks do nothing until that extra is consumed.
  void _requestYawTurn(double step) {
    if (_yawAnim.isAnimating) {
      final remaining = _yawTo - _yaw;
      final sameDir = remaining * step > 1e-6;
      if (sameDir) {
        if (_yawQueued) return;
        _yawQueued = true;
        _yawTo = mapLookNextCornerYaw(_yawTo, step);
      } else {
        _yawQueued = false;
        _yawTo = mapLookNextCornerYaw(_yaw, step);
      }
    } else {
      _yawQueued = false;
      _yawTo = mapLookNextCornerYaw(_yaw, step);
    }
    _restartYawSpring();
  }

  void _onYawTick() {
    _yaw = _yawAnim.value;
    if (_yawQueued && (_yawTo - _yaw).abs() <= math.pi / 2 + 1e-3) {
      _yawQueued = false;
    }
    _applyPose();
  }

  void _onYawStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _yaw = _yawTo;
    _yawQueued = false;
    _applyPose();
  }

  void _restartYawSpring() {
    final velocity = _yawAnim.isAnimating ? _yawAnim.velocity : 0.0;
    _yawAnim
      ..stop()
      ..animateWith(SpringSimulation(yawSpring, _yaw, _yawTo, velocity));
  }

  /// Spring distance to [distance], clamped to min/max.
  void animateDistance(double distance) {
    _scrollSnap?.cancel();
    _scrollSnap = null;
    _gestureZooming = false;
    _pushingPastCloseLimit = false;
    final target = distance.clamp(minDistance, maxDistance);
    if ((target - _distance).abs() < 1e-4) {
      _distance = target;
      _targetDistance = target;
      _applyPose();
      return;
    }
    _targetDistance = target;
    _restartZoomSpring();
  }

  /// Ease the look-at to [target] on the ground plane.
  void animateLookAt(Vector3 target) {
    _lookAtAnim.stop();
    _lookAtFrom = Vector3.copy(_lookAt);
    _lookAtTo = Vector3(target.x, 0, target.z);
    _lookAtAnim.forward(from: 0);
  }

  void _onLookAtTick() {
    final from = _lookAtFrom;
    final to = _lookAtTo;
    if (from == null || to == null) return;
    final t = Curves.easeInOut.transform(_lookAtAnim.value);
    _lookAt.setValues(
      from.x + (to.x - from.x) * t,
      0,
      from.z + (to.z - from.z) * t,
    );
    _clampLookAt();
    _applyPose();
  }

  /// Screen-pixel drag moves the look-at on the ground plane (Y = 0).
  void pan(Offset delta) {
    if (delta == Offset.zero) return;
    if (_lookAtAnim.isAnimating) _lookAtAnim.stop();
    var right = Vector3(camera.right.x, 0, camera.right.z);
    if (right.length2 < 1e-10) {
      right = Vector3(1, 0, 0);
    } else {
      right.normalize();
    }
    var forward = Vector3(camera.forward.x, 0, camera.forward.z);
    if (forward.length2 < 1e-10) {
      forward = Vector3(0, 0, 1);
    } else {
      forward.normalize();
    }

    final wpp = _worldUnitsPerPixel();
    // Screen Y is down-positive; flip it so the map tracks the finger.
    _lookAt.add(right * (-delta.dx * wpp));
    _lookAt.add(forward * (delta.dy * wpp));
    _lookAt.y = 0;
    _clampLookAt();
    _applyPose();
  }

  bool get isPitchPeeking => _pitchPeeking;

  /// Two-finger vertical drag: orbit pitch around [lookAt] at a fixed
  /// distance. Screen Y is down-positive; dragging down raises the camera
  /// (more top-down).
  void peekPitchByDeltaY(double dy) {
    if (dy == 0) return;
    if (!_pitchPeeking) beginPitchPeek();
    _pitchEffort += dy * pitchPeekSensitivity;
    _pitch = mapLookPitchFromEffort(
      rest: restPitch,
      min: minPitch,
      max: maxPitch,
      effort: _pitchEffort,
    );
    _applyPose();
  }

  void beginPitchPeek() {
    if (_pitchAnim.isAnimating) _pitchAnim.stop();
    _pitchPeeking = true;
    _pitchEffort = lookPitchEffortFromPitch(
      rest: restPitch,
      min: minPitch,
      max: maxPitch,
      pitch: _pitch,
    );
  }

  /// Release the peek and spring pitch back to [restPitch].
  void endPitchPeek() {
    _pitchPeeking = false;
    _pitchEffort = 0;
    if ((_pitch - restPitch).abs() < 1e-4) {
      _pitch = restPitch;
      _applyPose();
      return;
    }
    final velocity = _pitchAnim.isAnimating ? _pitchAnim.velocity : 0.0;
    _pitchAnim
      ..stop()
      ..animateWith(SpringSimulation(pitchSpring, _pitch, restPitch, velocity));
  }

  void restorePose({
    required Vector3 lookAt,
    required double distance,
    required double yaw,
  }) {
    _lookAt.setValues(lookAt.x, 0, lookAt.z);
    _distance = distance.clamp(minDistance, maxDistance);
    _targetDistance = _distance;
    _yaw = yaw;
    _yawTo = yaw;
    _yawQueued = false;
    if (_yawAnim.isAnimating) _yawAnim.stop();
    _pitch = restPitch;
    _pitchEffort = 0;
    _pitchPeeking = false;
    if (_pitchAnim.isAnimating) _pitchAnim.stop();
    _clampLookAt();
    _applyPose();
  }

  void pauseForHandoff() {
    _scrollSnap?.cancel();
    _scrollSnap = null;
    _gestureZooming = false;
    _pushingPastCloseLimit = false;
    if (_zoomAnim.isAnimating) _zoomAnim.stop();
    if (_yawAnim.isAnimating) _yawAnim.stop();
    _yawQueued = false;
    if (_lookAtAnim.isAnimating) _lookAtAnim.stop();
    if (_pitchAnim.isAnimating) _pitchAnim.stop();
    _pitchPeeking = false;
    _pitchEffort = 0;
    _pitch = restPitch;
  }

  /// Start a live pinch/scroll zoom. Distance can pass min/max with resistance.
  void beginZoom() {
    _scrollSnap?.cancel();
    if (_zoomAnim.isAnimating) _zoomAnim.stop();
    _gestureZooming = true;
  }

  void zoomByScroll(double scrollDelta) {
    if (scrollDelta == 0) return;
    if (!_gestureZooming) beginZoom();
    final factor = math.exp(scrollDelta * zoomSensitivity);
    _setLiveDistance(_distance * factor);
    _scrollSnap?.cancel();
    _scrollSnap = Timer(const Duration(milliseconds: 100), endZoom);
  }

  void zoomByScale(double scaleChange) {
    if (scaleChange == 0 || scaleChange == 1) return;
    if (!_gestureZooming) beginZoom();
    _setLiveDistance(_distance / scaleChange);
  }

  /// End a pinch/scroll zoom. Ladder mode springs to the nearest stop;
  /// smooth mode only springs back if the gesture overshot min/max.
  void endZoom() {
    _scrollSnap?.cancel();
    _scrollSnap = null;
    _gestureZooming = false;
    _pushingPastCloseLimit = false;
    final target = ladderZoom
        ? nearestStepDistance(_distance)
        : _distance.clamp(minDistance, maxDistance);
    if ((target - _distance).abs() < 1e-4) {
      _distance = target;
      _targetDistance = target;
      _applyPose();
      return;
    }
    _targetDistance = target;
    _restartZoomSpring();
  }

  double nearestStepDistance(double value) {
    return _steps[_nearestStepIndex(value)];
  }

  /// Tile under the look-at, assuming a centered map of [tilesSide] tiles.
  (int tx, int ty) lookAtTile({
    required double tileSize,
    required int tilesSide,
  }) {
    final origin = -(tilesSide ~/ 2);
    final last = origin + tilesSide - 1;
    final tx = (_lookAt.x / tileSize).floor().clamp(origin, last);
    final ty = (_lookAt.z / tileSize).floor().clamp(origin, last);
    return (tx, ty);
  }

  /// Conservative tile radius visible at the current distance (no frustum).
  int tileRadius({
    required double tileSize,
    required Size viewport,
    int prefetchBuffer = 1,
  }) {
    final halfFov = camera.fovDegrees * math.pi / 360;
    final cosPitch = math.max(math.cos(pitch), 1e-3);
    var groundSpan = 2 * _distance * math.tan(halfFov) / cosPitch;
    if (viewport.width > 1 && viewport.height > 1) {
      final aspect = viewport.width / viewport.height;
      groundSpan *= math.max(aspect, 1.0);
    }
    return (groundSpan / tileSize / 2).ceil() + prefetchBuffer;
  }

  List<double> _buildSteps() {
    final n = zoomStepCount;
    if (n <= 1 || (maxDistance - minDistance).abs() < 1e-6) {
      return [minDistance];
    }
    final ratio = maxDistance / minDistance;
    return [
      for (var i = 0; i < n; i++)
        minDistance * math.pow(ratio, i / (n - 1)),
    ];
  }

  int _nearestStepIndex(double value) {
    final clamped = value.clamp(minDistance, maxDistance);
    var best = 0;
    var bestDist = (clamped - _steps[0]).abs();
    for (var i = 1; i < _steps.length; i++) {
      final d = (clamped - _steps[i]).abs();
      if (d < bestDist) {
        best = i;
        bestDist = d;
      }
    }
    return best;
  }

  void _setLiveDistance(double proposed) {
    _pushingPastCloseLimit = proposed < minDistance;
    _distance = _rubberBand(proposed);
    _targetDistance = _distance;
    _applyPose();
  }

  /// Live-update the nearest zoom. Clamps the current distance and pose.
  void setMinDistance(double value) {
    _minDistance = value.clamp(8.0, _maxDistance - 1);
    _distance = _distance.clamp(_minDistance, _maxDistance);
    _targetDistance = _targetDistance.clamp(_minDistance, _maxDistance);
    if (ladderZoom) _steps = _buildSteps();
    _applyPose();
  }

  /// Soft close overshoot as a fraction of [minDistance].
  static const double closeOvershootSoft = 0.06;

  /// Hard close overshoot. At game min 22 this stops at 18.92.
  static const double closeOvershootHard = 0.14;

  /// Closest live distance the rubber-band will allow.
  double get closeLimitDistance =>
      minDistance * (1.0 - closeOvershootHard);

  /// True while a live zoom wants to go closer than [minDistance].
  bool get isPushingPastCloseLimit => _pushingPastCloseLimit;
  bool _pushingPastCloseLimit = false;

  /// Allow passing min/max, with increasing resistance (assembly-style).
  ///
  /// Close-side overshoot is a fraction of [minDistance], not the full zoom
  /// span — otherwise a wide far-range lets the camera pass through the
  /// look-at and invert the projection.
  double _rubberBand(double proposed) {
    if (proposed >= minDistance && proposed <= maxDistance) return proposed;
    if (proposed < minDistance) {
      final soft = minDistance * closeOvershootSoft;
      final hard = minDistance * closeOvershootHard;
      final extra = minDistance - proposed;
      if (extra >= hard) return minDistance - hard;
      if (extra <= soft) return proposed;
      final t = ((extra - soft) / (hard - soft)).clamp(0.0, 1.0);
      final resisted = soft + (hard - soft) * (1 - (1 - t) * (1 - t));
      return minDistance - resisted;
    }
    final span = math.max(maxDistance - minDistance, 1.0);
    final soft = span * 0.15;
    final hard = span * 0.4;
    final extra = proposed - maxDistance;
    if (extra >= hard) return maxDistance + hard;
    if (extra <= soft) return proposed;
    final t = ((extra - soft) / (hard - soft)).clamp(0.0, 1.0);
    final resisted = soft + (hard - soft) * (1 - (1 - t) * (1 - t));
    return maxDistance + resisted;
  }

  void _restartZoomSpring() {
    final velocity = _zoomAnim.isAnimating ? _zoomAnim.velocity : 0.0;
    _zoomAnim
      ..stop()
      ..animateWith(
        SpringSimulation(zoomSpring, _distance, _targetDistance, velocity),
      );
  }

  void _onZoomTick() {
    _distance = _zoomAnim.value;
    _applyPose();
  }

  void _onPitchTick() {
    _pitch = _pitchAnim.value;
    _applyPose();
  }

  void _clampLookAt() {
    final min = _boundsMin;
    final max = _boundsMax;
    if (min != null) {
      _lookAt.x = math.max(_lookAt.x, min.x);
      _lookAt.z = math.max(_lookAt.z, min.z);
    }
    if (max != null) {
      _lookAt.x = math.min(_lookAt.x, max.x);
      _lookAt.z = math.min(_lookAt.z, max.z);
    }
  }

  void _applyPose({bool notify = true}) {
    final h = _distance * math.cos(pitch);
    final x = _lookAt.x - h * math.cos(yaw);
    final y = _lookAt.y + _distance * math.sin(pitch);
    final z = _lookAt.z - h * math.sin(yaw);
    camera.setPosition(Vector3(x, y, z));
    camera.setTarget(_lookAt);
    if (notify) notifyListeners();
  }

  double _worldUnitsPerPixel() {
    final h = _viewportSize.height;
    if (h > 1) {
      final halfFovY = camera.fovDegrees * math.pi / 360;
      return (2 * _distance * math.tan(halfFovY)) / h;
    }
    return (_distance * 0.003).clamp(0.01, 100.0);
  }

  @override
  void dispose() {
    _scrollSnap?.cancel();
    _zoomAnim
      ..removeListener(_onZoomTick)
      ..dispose();
    _yawAnim
      ..removeListener(_onYawTick)
      ..removeStatusListener(_onYawStatus)
      ..dispose();
    _lookAtAnim
      ..removeListener(_onLookAtTick)
      ..dispose();
    _pitchAnim
      ..removeListener(_onPitchTick)
      ..dispose();
    super.dispose();
  }
}

/// Maps unbounded drag [effort] (radians of requested offset from [rest])
/// toward [min]/[max] with a tanh squash so the limits are only approached.
double mapLookPitchFromEffort({
  required double rest,
  required double min,
  required double max,
  required double effort,
}) {
  final hi = math.max(max - rest, 1e-6);
  final lo = math.min(min - rest, -1e-6);
  if (effort >= 0) return rest + hi * _tanh(effort / hi);
  return rest + lo * _tanh(effort / lo);
}

/// Inverse of [mapLookPitchFromEffort] so a mid-spring grab stays continuous.
double lookPitchEffortFromPitch({
  required double rest,
  required double min,
  required double max,
  required double pitch,
}) {
  final delta = pitch - rest;
  if (delta >= 0) {
    final hi = math.max(max - rest, 1e-6);
    final t = (delta / hi).clamp(-0.999, 0.999);
    return hi * _atanh(t);
  }
  final lo = math.min(min - rest, -1e-6);
  final t = (delta / lo).clamp(-0.999, 0.999);
  return lo * _atanh(t);
}

/// Next traditional corner (π/4 + n·π/2) in the sign of [direction].
double mapLookNextCornerYaw(
  double yaw,
  double direction, {
  double rest = MapLookCameraController.defaultYaw,
}) {
  final step = math.pi / 2;
  final idx = (yaw - rest) / step;
  final onCorner = (idx - idx.round()).abs() < 1e-4;
  if (direction >= 0) {
    final next = onCorner ? idx.round() + 1 : idx.ceil();
    return rest + next * step;
  }
  final next = onCorner ? idx.round() - 1 : idx.floor();
  return rest + next * step;
}

double _atanh(double x) => 0.5 * math.log((1 + x) / (1 - x));

double _tanh(double x) {
  final e = math.exp(2 * x);
  return (e - 1) / (e + 1);
}
