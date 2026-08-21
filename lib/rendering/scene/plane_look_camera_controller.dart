import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../gameplay/viewers/world_plane.dart';
import 'camera.dart';

const double kPlane2dMinDistance = 8;
const double kPlane2dMaxDistance = 40;
const double kPlane2dDefaultDistance = 16;
const double kPlane2dPerspectiveFov = 50;
const double kPlane2dTelephotoLens = 10000;
const double kPlane2dFilmHeight = 24;

/// Head-on look at a [WorldPlane]. Pan stays in the plane; zoom is distance.
class PlaneLookCameraController extends ChangeNotifier {
  PlaneLookCameraController({
    required this.camera,
    required WorldPlane plane,
    double? distance,
    this.minDistance = kPlane2dMinDistance,
    this.maxDistance = kPlane2dMaxDistance,
    this.perspectiveFov = kPlane2dPerspectiveFov,
    this.zoomSensitivity = 0.0025,
    bool telephoto = false,
  })  : _plane = plane,
        _u = 0,
        _v = 0,
        _telephoto = telephoto {
    _distance = (distance ?? kPlane2dDefaultDistance).clamp(
      minDistance,
      maxDistance,
    );
    camera.projection = ProjectionType.perspective;
    _applyFov();
    _applyPose(notify: false);
  }

  final Camera camera;
  final double minDistance;
  final double maxDistance;
  final double perspectiveFov;
  final double zoomSensitivity;

  WorldPlane _plane;
  WorldPlane get plane => _plane;

  double _u;
  double _v;
  double _distance = kPlane2dDefaultDistance;
  bool _telephoto;
  Size _viewportSize = Size.zero;
  bool _gestureZooming = false;

  double get distance => _distance;
  bool get telephoto => _telephoto;
  double get u => _u;
  double get v => _v;

  Vector3 get lookAt => _plane.point(_u, _v);

  void setViewportSize(Size size) => _viewportSize = size;

  void attachPlane(WorldPlane plane, {double u = 0, double v = 0}) {
    _plane = plane;
    _u = u;
    _v = v;
    _applyPose();
  }

  /// Screen-pixel drag moves the look-at on the plane.
  void pan(Offset delta) {
    if (delta == Offset.zero) return;
    final wpp = _worldUnitsPerPixel();
    _u += -delta.dx * wpp;
    _v += delta.dy * wpp;
    _applyPose();
  }

  void beginZoom() {
    _gestureZooming = true;
  }

  /// Returns true when a zoom-out has passed [maxDistance] (exit plane2d).
  bool zoomByScale(double scaleChange) {
    if (scaleChange == 0 || scaleChange == 1) return false;
    if (!_gestureZooming) beginZoom();
    final proposed = _distance / scaleChange;
    if (proposed > maxDistance) {
      _distance = maxDistance;
      _applyPose();
      return true;
    }
    _distance = proposed.clamp(minDistance, maxDistance);
    _applyPose();
    return false;
  }

  /// Returns true when scroll zoom-out has passed [maxDistance].
  bool zoomByScroll(double scrollDelta) {
    if (scrollDelta == 0) return false;
    if (!_gestureZooming) beginZoom();
    final factor = math.exp(scrollDelta * zoomSensitivity);
    return zoomByScale(1 / factor);
  }

  void endZoom() {
    _gestureZooming = false;
    _distance = _distance.clamp(minDistance, maxDistance);
    _applyPose();
  }

  void setTelephoto(bool value) {
    if (_telephoto == value) return;
    final oldFov = _currentFovRad();
    _telephoto = value;
    final newFov = _currentFovRad();
    final framing = math.tan(oldFov * 0.5) * _distance;
    final denom = math.tan(newFov * 0.5);
    if (denom > 1e-12) {
      _distance = framing / denom;
    }
    _applyFov();
    _applyPose();
  }

  static double telephotoFovDegrees({
    double lens = kPlane2dTelephotoLens,
    double filmHeight = kPlane2dFilmHeight,
  }) {
    return 2 * math.atan(filmHeight / (2 * lens)) * 180 / math.pi;
  }

  double _currentFovRad() {
    final deg = _telephoto ? telephotoFovDegrees() : perspectiveFov;
    return deg * math.pi / 180;
  }

  void _applyFov() {
    camera.fovDegrees =
        _telephoto ? telephotoFovDegrees() : perspectiveFov;
  }

  void applyPoseNow() => _applyPose();

  void _applyPose({bool notify = true}) {
    final at = lookAt;
    camera.setTarget(at);
    camera.setPosition(at + _plane.normal * _distance);
    camera.setUp(_plane.up);
    camera.projection = ProjectionType.perspective;
    _applyFov();
    if (notify) notifyListeners();
  }

  double _worldUnitsPerPixel() {
    final h = _viewportSize.height;
    if (h > 1) {
      return (2 * _distance * math.tan(_currentFovRad() * 0.5)) / h;
    }
    return (_distance * 0.003).clamp(0.01, 100.0);
  }
}
