import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';
import 'package:vector_math/vector_math_64.dart';

import 'camera.dart';

/// Locked down-looking perspective camera: diagonal yaw, fixed pitch, XZ pan.
/// Zoom is either a ladder that springs to stops, or smooth between min/max.
class MapLookCameraController extends ChangeNotifier {
  MapLookCameraController({
    required this.camera,
    required TickerProvider vsync,
    Vector3? lookAt,
    double? distance,
    this.minDistance = 24,
    this.maxDistance = 400,
    int zoomStepCount = 3,
    this.ladderZoom = true,
    this.pitch = defaultPitch,
    double yaw = defaultYaw,
    this.zoomSensitivity = 0.0025,
    Vector3? boundsMin,
    Vector3? boundsMax,
  })  : zoomStepCount = math.max(2, zoomStepCount),
        _lookAt = Vector3(lookAt?.x ?? 0, 0, lookAt?.z ?? 0),
        _boundsMin = boundsMin,
        _boundsMax = boundsMax,
        _yaw = yaw {
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
    _yawAnim = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 280),
    )..addListener(_onYawTick);
    _applyPose(notify: false);
  }

  /// Pitch down from horizontal (radians). ~52° looks down along a diagonal.
  static const double defaultPitch = 52 * math.pi / 180;

  /// Yaw so the camera looks along +X/+Z.
  static const double defaultYaw = math.pi / 4;

  static const SpringDescription zoomSpring = SpringDescription(
    mass: 1,
    stiffness: 90,
    damping: 14,
  );

  static const _kStepLabels3 = ['close', 'medium', 'far'];

  final Camera camera;
  final double minDistance;
  final double maxDistance;

  /// Ladder stops between [minDistance] and [maxDistance], inclusive. ≥ 2.
  final int zoomStepCount;

  /// When false, pinch/scroll zoom is continuous and only clamps to min/max.
  final bool ladderZoom;
  final double pitch;
  final double zoomSensitivity;

  double _yaw;
  double get yaw => _yaw;

  final Vector3 _lookAt;
  final Vector3? _boundsMin;
  final Vector3? _boundsMax;

  late final AnimationController _zoomAnim;
  late final AnimationController _yawAnim;
  late final List<double> _steps;
  late double _distance;
  late double _targetDistance;
  double _yawFrom = 0;
  double _yawTo = 0;
  Size _viewportSize = Size.zero;
  bool _gestureZooming = false;
  Timer? _scrollSnap;

  Vector3 get lookAt => Vector3.copy(_lookAt);
  double get distance => _distance;
  double get targetDistance => _targetDistance;
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
  void rotateClockwise() => _animateYaw(-math.pi / 2);

  /// Orbit 90° counter-clockwise around the look-at, as seen from above.
  void rotateCounterClockwise() => _animateYaw(math.pi / 2);

  void _animateYaw(double delta) {
    _yawAnim.stop();
    _yawFrom = _yaw;
    _yawTo = _yaw + delta;
    _yawAnim.forward(from: 0);
  }

  void _onYawTick() {
    final t = Curves.easeInOut.transform(_yawAnim.value);
    _yaw = _yawFrom + (_yawTo - _yawFrom) * t;
    _applyPose();
  }

  /// Screen-pixel drag moves the look-at on the ground plane (Y = 0).
  void pan(Offset delta) {
    if (delta == Offset.zero) return;
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

  void restorePose({
    required Vector3 lookAt,
    required double distance,
    required double yaw,
  }) {
    _lookAt.setValues(lookAt.x, 0, lookAt.z);
    _distance = distance.clamp(minDistance, maxDistance);
    _targetDistance = _distance;
    _yaw = yaw;
    _clampLookAt();
    _applyPose();
  }

  void pauseForHandoff() {
    _scrollSnap?.cancel();
    _scrollSnap = null;
    _gestureZooming = false;
    if (_zoomAnim.isAnimating) _zoomAnim.stop();
    if (_yawAnim.isAnimating) _yawAnim.stop();
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
    final half = tilesSide * tileSize * 0.5;
    final tx = ((_lookAt.x + half) / tileSize).floor().clamp(0, tilesSide - 1);
    final ty = ((_lookAt.z + half) / tileSize).floor().clamp(0, tilesSide - 1);
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
    _distance = _rubberBand(proposed);
    _targetDistance = _distance;
    _applyPose();
  }

  /// Allow passing min/max, with increasing resistance (assembly-style).
  double _rubberBand(double proposed) {
    if (proposed >= minDistance && proposed <= maxDistance) return proposed;
    final span = math.max(maxDistance - minDistance, 1.0);
    final soft = span * 0.15;
    final hard = span * 0.4;
    if (proposed < minDistance) {
      final extra = minDistance - proposed;
      if (extra >= hard) return minDistance - hard;
      if (extra <= soft) return proposed;
      final t = ((extra - soft) / (hard - soft)).clamp(0.0, 1.0);
      final resisted = soft + (hard - soft) * (1 - (1 - t) * (1 - t));
      return minDistance - resisted;
    }
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
      ..dispose();
    super.dispose();
  }
}
