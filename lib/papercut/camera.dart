import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math_64.dart';

import '../rendering/scene/camera.dart';

/// Perspective camera in millimeters. Focal length is a real lens on a 24 mm
/// vertical film, so flat and orbit views can dolly into each other.
class PapercutCamera extends ChangeNotifier {
  PapercutCamera() {
    _apply();
  }

  static const double filmHeightMm = 24;
  static const double flatFocalMm = 2000;
  static const double perspectiveFocalMm = 50;
  static const Duration dollyDuration = Duration(milliseconds: 300);

  /// 3/4 view: yaw off +Z, then a lift above the sheet.
  static const double perspectiveAzimuth = 0.70;
  static const double perspectiveElevation = 0.42;

  /// Released rotations land on this many degrees.
  static const double rollSnapDegrees = 5;

  /// Contacts closer than this have no stable angle.
  static const double rotationMinSpan = 12;

  final Camera camera = Camera(
    name: 'papercut',
    position: Vector3(0, 0, 1),
    projection: ProjectionType.perspective,
    near: 1,
    far: 100000,
  );

  double focalLengthMm = flatFocalMm;
  double framedHalfHeightMm = 150;
  Offset lookAt = Offset.zero;
  double azimuth = 0;
  double elevation = 0;

  /// In-plane roll, in radians. Positive roll turns the sheet counter-clockwise
  /// on screen. Zero keeps world +Y toward the top of the view.
  double roll = 0;

  bool targetFlat = true;
  bool _didFrame = false;

  double _fromFocal = flatFocalMm;
  double _toFocal = flatFocalMm;
  double _fromAzimuth = 0;
  double _toAzimuth = 0;
  double _fromElevation = 0;
  double _toElevation = 0;

  double get halfFovRadians => math.atan(filmHeightMm / (2 * focalLengthMm));

  double get fovDegrees => halfFovRadians * 360 / math.pi;

  /// Visible half-height stays fixed, so distance scales with focal length.
  double get distance {
    final tangent = math.tan(halfFovRadians);
    if (tangent < 1e-8) return framedHalfHeightMm / 1e-8;
    return framedHalfHeightMm / tangent;
  }

  /// Frames [sheetMm] again, looking at [center].
  void frameSheet(
    Size viewport, {
    required double sheetMm,
    Offset center = Offset.zero,
  }) {
    _didFrame = false;
    lookAt = center;
    ensureFramed(viewport, sheetMm: sheetMm);
  }

  /// Frames the sheet once, with a margin on the tighter axis.
  void ensureFramed(Size viewport, {required double sheetMm}) {
    if (_didFrame) return;
    if (viewport.width < 2 || viewport.height < 2) return;
    final aspect = viewport.width / viewport.height;
    final margin = sheetMm / 2 * 1.35;
    framedHalfHeightMm = math.max(margin, margin / math.max(aspect, 0.05));
    _didFrame = true;
    _apply();
  }

  void beginToggle() {
    _fromFocal = focalLengthMm;
    _fromAzimuth = azimuth;
    _fromElevation = elevation;
    targetFlat = !targetFlat;
    _toFocal = targetFlat ? flatFocalMm : perspectiveFocalMm;
    _toAzimuth = targetFlat ? 0 : perspectiveAzimuth;
    _toElevation = targetFlat ? 0 : perspectiveElevation;
  }

  /// [t] is 0 at the start of the dolly and 1 at the end.
  void setBlend(double t) {
    final u = t.clamp(0.0, 1.0);
    final s = u * u * (3 - 2 * u);
    focalLengthMm = _fromFocal + (_toFocal - _fromFocal) * s;
    azimuth = _fromAzimuth + (_toAzimuth - _fromAzimuth) * s;
    elevation = _fromElevation + (_toElevation - _fromElevation) * s;
    _apply();
    notifyListeners();
  }

  void panByScreen(Offset delta, Size viewport) {
    if (delta == Offset.zero) return;
    if (viewport.width < 2 || viewport.height < 2) return;
    final center = Offset(viewport.width / 2, viewport.height / 2);
    final start = planePoint(center, viewport);
    final end = planePoint(center + delta, viewport);
    if (start == null || end == null) return;
    final next = lookAt + (start - end);
    lookAt = Offset(next.dx.clamp(-800, 800), next.dy.clamp(-800, 800));
    _apply();
    notifyListeners();
  }

  /// [scale] > 1 zooms in. The lens stays put; only distance changes.
  void zoomByScale(double scale) {
    if (scale <= 0 || (scale - 1).abs() < 1e-6) return;
    framedHalfHeightMm = (framedHalfHeightMm / scale).clamp(8.0, 8000.0);
    _apply();
    notifyListeners();
  }

  void setRoll(double radians) {
    if ((radians - roll).abs() < 1e-8) return;
    roll = radians;
    _apply();
    notifyListeners();
  }

  /// Shortest signed step from [from] to [to], in (-π, π].
  static double signedAngleDelta(double from, double to) {
    final tau = math.pi * 2;
    var delta = (to - from) % tau;
    if (delta > math.pi) delta -= tau;
    if (delta < -math.pi) delta += tau;
    return delta;
  }

  static double wrapAngle(double radians) {
    final tau = math.pi * 2;
    var wrapped = radians % tau;
    if (wrapped > math.pi) wrapped -= tau;
    if (wrapped < -math.pi) wrapped += tau;
    return wrapped;
  }

  /// Extends an unwrapped angle toward a fresh `atan2` sample without jumping
  /// at the branch cut.
  static double advanceAngle(double unwrapped, double wrappedNext) {
    return unwrapped + signedAngleDelta(wrapAngle(unwrapped), wrappedNext);
  }

  /// Roll after a screen-space sweep. [currentAngle] is unwrapped relative to
  /// [startAngle]. Screen angles use `atan2(dy, dx)` with Y down, so a
  /// clockwise sweep increases the angle and the sheet follows it.
  static double rollAfterScreenSweep({
    required double baseRoll,
    required double startAngle,
    required double currentAngle,
  }) {
    return baseRoll - (currentAngle - startAngle);
  }

  static double snapRoll(double radians) {
    final step = rollSnapDegrees * math.pi / 180;
    return (radians / step).roundToDouble() * step;
  }

  /// Angle of a one-finger ray from [center], or of the line through the first
  /// two contacts. Y points down.
  static double? rotationAngle(List<Offset> points, Offset center) {
    if (points.length >= 2) {
      final delta = points[1] - points[0];
      if (delta.distance < rotationMinSpan) return null;
      return math.atan2(delta.dy, delta.dx);
    }
    if (points.length == 1) {
      final delta = points[0] - center;
      if (delta.distance < rotationMinSpan) return null;
      return math.atan2(delta.dy, delta.dx);
    }
    return null;
  }

  Offset? planePoint(Offset screen, Size viewport) {
    final ray = camera.unprojectRay(screen, viewport);
    if (ray == null) return null;
    final hit = Camera.intersectPlane(
      ray: ray,
      point: Vector3.zero(),
      normal: Vector3(0, 0, 1),
    );
    if (hit == null) return null;
    return Offset(hit.x, hit.y);
  }

  void _apply() {
    final d = distance;
    final cp = math.cos(elevation);
    final eye = Vector3(
      lookAt.dx + d * math.sin(azimuth) * cp,
      lookAt.dy + d * math.sin(elevation),
      d * math.cos(azimuth) * cp,
    );
    camera.projection = ProjectionType.perspective;
    camera.fovDegrees = fovDegrees;
    camera.near = math.max(0.5, d / 1000);
    camera.far = d * 40 + 1000;
    camera.setPosition(eye);
    camera.setTarget(Vector3(lookAt.dx, lookAt.dy, 0));
    camera.setUp(_rolledUp(Vector3(lookAt.dx, lookAt.dy, 0) - eye));
  }

  /// Rotates the no-twist up vector around the view axis.
  Vector3 _rolledUp(Vector3 forward) {
    final axis = forward.length2 == 0
        ? Vector3(0, 0, -1)
        : forward.normalized();
    var hint = Vector3(0, 1, 0);
    if (axis.dot(hint).abs() > 0.98) hint = Vector3(1, 0, 0);
    final right = axis.cross(hint).normalized();
    final up = right.cross(axis).normalized();
    if (roll.abs() < 1e-8) return up;
    return (up * math.cos(roll) + right * math.sin(roll)).normalized();
  }
}
