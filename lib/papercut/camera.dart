import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math_64.dart';

import '../gridcraft/craft_plane.dart';
import '../rendering/scene/camera.dart';

/// Where the camera looks from. Null angles keep the current ones.
class CameraPose {
  const CameraPose({
    required this.lookAt,
    this.lookAtZ = 0,
    required this.halfHeight,
    this.azimuth,
    this.elevation,
    this.roll,
  });

  final Offset lookAt;
  final double lookAtZ;
  final double halfHeight;
  final double? azimuth;
  final double? elevation;
  final double? roll;

  CameraPose withAngles(({double azimuth, double elevation, double roll}) a) =>
      CameraPose(
        lookAt: lookAt,
        lookAtZ: lookAtZ,
        halfHeight: halfHeight,
        azimuth: a.azimuth,
        elevation: a.elevation,
        roll: a.roll,
      );
}

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

  /// Orbit stops short of the poles so the up vector stays defined.
  static const double maxElevation = 85 * math.pi / 180;

  /// Face focus flight, as in the room editor.
  static const Duration flyDuration = Duration(milliseconds: 650);

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

  /// Height of the look-at point above the sheet. The orbit centers on it.
  double lookAtZ = 0;
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

  CameraPose? _flyFrom;
  CameraPose? _flyTo;

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

  /// Half-height that fits [sheetMm] with the same margin [frameSheet] uses.
  double halfHeightForSheet(Size viewport, {required double sheetMm}) {
    final margin = sheetMm / 2 * 1.35;
    if (viewport.width < 2 || viewport.height < 2) return margin;
    final aspect = viewport.width / viewport.height;
    return math.max(margin, margin / math.max(aspect, 0.05));
  }

  /// Frames the sheet once, with a margin on the tighter axis.
  void ensureFramed(Size viewport, {required double sheetMm}) {
    if (_didFrame) return;
    if (viewport.width < 2 || viewport.height < 2) return;
    framedHalfHeightMm = halfHeightForSheet(viewport, sheetMm: sheetMm);
    _didFrame = true;
    _apply();
  }

  /// Moves the look-at point and, when set, the framed half-height.
  ///
  /// Unlike [panByScreen], this does not clamp. The puzzle advance uses it
  /// to travel off the current sheet, then lands back near the origin.
  void moveLook({required Offset lookAt, double? halfHeight}) {
    final height = halfHeight ?? framedHalfHeightMm;
    if ((this.lookAt - lookAt).distance < 1e-4 &&
        (framedHalfHeightMm - height).abs() < 1e-4) {
      return;
    }
    this.lookAt = lookAt;
    framedHalfHeightMm = height;
    _apply();
    notifyListeners();
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

  /// Changes the lens and keeps the framed half-height, so the eye backs
  /// off as the lens gets longer.
  void setFocal(double mm) {
    if ((focalLengthMm - mm).abs() < 1e-6) return;
    focalLengthMm = mm;
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

  void focusOn(Offset point) {
    if ((lookAt - point).distance < 1e-4) return;
    lookAt = point;
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

  /// Roll at which [direction] points up on screen, kept near [near].
  ///
  /// Screen-up in paper space is `(sin(roll), cos(roll))`. A leftward cut
  /// therefore takes a clockwise sheet turn (negative roll).
  static double rollForScreenUp(Offset direction, {double near = 0}) {
    final length = direction.distance;
    if (length < 1e-8) return near;
    final ray = direction / length;
    return advanceAngle(near, math.atan2(ray.dx, ray.dy));
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

  /// Next quarter turn from [radians].
  ///
  /// Already-canonical angles (0, 90, 180, 270) step a full quarter.
  /// Any other angle lands on the next one of those in [counterclockwise]'s
  /// direction. The result stays continuous with [radians] rather than wrapping.
  static double nextQuarterTurn(
    double radians, {
    required bool counterclockwise,
  }) {
    const quarter = math.pi / 2;
    const tau = math.pi * 2;
    const eps = 1e-4;
    var wrapped = radians % tau;
    if (wrapped < 0) wrapped += tau;
    final steps = counterclockwise
        ? (wrapped / quarter).ceil()
        : (wrapped / quarter).floor();
    var target = steps * quarter;
    if ((target - wrapped).abs() < eps) {
      target += counterclockwise ? quarter : -quarter;
    }
    return radians + (target - wrapped);
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

  CameraPose get pose => CameraPose(
    lookAt: lookAt,
    lookAtZ: lookAtZ,
    halfHeight: framedHalfHeightMm,
    azimuth: azimuth,
    elevation: elevation,
    roll: roll,
  );

  Vector3 get target => Vector3(lookAt.dx, lookAt.dy, lookAtZ);

  /// Unit vector from the look-at point toward the eye.
  Vector3 get viewDirection {
    final away = camera.position - target;
    return away.length2 < 1e-12 ? Vector3(0, 0, 1) : away.normalized();
  }

  /// Angles that put the eye along [direction] from the look-at point, with
  /// [up] toward the top of the view. Kept continuous with the current ones.
  ({double azimuth, double elevation, double roll}) anglesAlong(
    Vector3 direction, {
    Vector3? up,
  }) {
    final n = direction.normalized();
    final elevation = math.asin(n.y.clamp(-1.0, 1.0));
    final azimuth = n.x.abs() < 1e-9 && n.z.abs() < 1e-9
        ? this.azimuth
        : advanceAngle(this.azimuth, math.atan2(n.x, n.z));
    final wanted = up;
    if (wanted == null) {
      return (azimuth: azimuth, elevation: elevation, roll: roll);
    }
    final forward = -n;
    var hint = Vector3(0, 1, 0);
    if (forward.dot(hint).abs() > 0.98) hint = Vector3(1, 0, 0);
    final right = forward.cross(hint).normalized();
    final base = right.cross(forward).normalized();
    final flat = wanted - forward * wanted.dot(forward);
    if (flat.length2 < 1e-12) {
      return (azimuth: azimuth, elevation: elevation, roll: roll);
    }
    flat.normalize();
    final turn = advanceAngle(
      roll,
      math.atan2(flat.dot(right), flat.dot(base)),
    );
    return (azimuth: azimuth, elevation: elevation, roll: turn);
  }

  /// The current up vector, carried by the shortest turn that takes the view
  /// onto [direction], so a turn toward [direction] adds no roll of its own.
  Vector3 upAlong(Vector3 direction) {
    final from = viewDirection;
    final to = direction.normalized();
    final up = camera.up.normalized();
    final axis = from.cross(to);
    final sine = axis.length;
    if (sine < 1e-9) return up;
    final k = axis / sine;
    final cosine = from.dot(to);
    return (up * cosine + k.cross(up) * sine + k * (k.dot(up) * (1 - cosine)))
        .normalized();
  }

  /// Puts the eye along [direction] at once. See [anglesAlong].
  void orbitTo(Vector3 direction, {Vector3? up}) {
    final angles = anglesAlong(direction, up: up);
    azimuth = angles.azimuth;
    elevation = angles.elevation;
    roll = angles.roll;
    _apply();
    notifyListeners();
  }

  /// Turns the orbit around the look-at point.
  void orbitBy(double dAzimuth, double dElevation) {
    if (dAzimuth.abs() < 1e-9 && dElevation.abs() < 1e-9) return;
    azimuth = wrapAngle(azimuth + dAzimuth);
    elevation = (elevation + dElevation).clamp(-maxElevation, maxElevation);
    _apply();
    notifyListeners();
  }

  /// Slides the look-at point across the view, within [limit] of [anchor].
  void panInView(
    Offset delta,
    Size viewport, {
    Vector3? anchor,
    double? limit,
  }) {
    if (delta == Offset.zero || viewport.height < 2) return;
    final perPixel = 2 * framedHalfHeightMm / viewport.height;
    final shift = Vector3.zero()
      ..addScaled(camera.right, -delta.dx * perPixel)
      ..addScaled(camera.up.normalized(), delta.dy * perPixel);
    shiftTarget(shift, anchor: anchor, limit: limit);
  }

  /// Moves the look-at point and the eye together by [shift], keeping the
  /// look-at point within [limit] of [anchor].
  void shiftTarget(Vector3 shift, {Vector3? anchor, double? limit}) {
    if (shift.length2 < 1e-18) return;
    final next = target + shift;
    if (anchor != null && limit != null) {
      final away = next - anchor;
      if (away.length > limit) {
        next.setFrom(anchor + away.normalized() * limit);
      }
    }
    lookAt = Offset(next.x, next.y);
    lookAtZ = next.z;
    _apply();
    notifyListeners();
  }

  /// Pose looking at [target] from [distance] along [normal], with [up]
  /// toward the top of the view when given.
  CameraPose poseFacing(
    Vector3 target,
    Vector3 normal,
    double distance, {
    Vector3? up,
  }) {
    return CameraPose(
      lookAt: Offset(target.x, target.y),
      lookAtZ: target.z,
      halfHeight: distance * math.tan(halfFovRadians),
    ).withAngles(anglesAlong(normal, up: up));
  }

  /// Pose that fits a sphere, keeping the current angles.
  CameraPose frameSphere(Vector3 center, double radius, Size viewport) {
    final aspect = viewport.width < 2 || viewport.height < 2
        ? 1.0
        : viewport.width / viewport.height;
    final margin = radius * 1.35;
    return CameraPose(
      lookAt: Offset(center.x, center.y),
      lookAtZ: center.z,
      halfHeight: math.max(margin, margin / math.max(aspect, 0.05)),
    );
  }

  /// Starts a flight to [target] seen along [normal]. Drive it with [setFly].
  /// With no [up], the view keeps its current up through the shortest turn.
  void flyTo(Vector3 target, Vector3 normal, double distance, {Vector3? up}) =>
      beginFly(
        poseFacing(target, normal, distance, up: up ?? upAlong(normal)),
        turn: true,
      );

  /// With [turn], the view rotates along the shortest arc between the two
  /// orientations instead of easing each angle, so it cannot flip or spin
  /// near the orbit's poles.
  void beginFly(CameraPose to, {bool turn = false}) {
    _flyFrom = pose;
    _flyTo = to;
    _turnFrom = turn ? _orientation(azimuth, elevation, roll) : null;
    _turnTo = turn
        ? _orientation(
            to.azimuth ?? azimuth,
            to.elevation ?? elevation,
            to.roll ?? roll,
          )
        : null;
  }

  Quaternion? _turnFrom;
  Quaternion? _turnTo;

  /// Rotation whose z axis points toward the eye and whose y axis is up.
  /// [Quaternion.rotated] applies the inverse of this rotation.
  Quaternion _orientation(double azimuth, double elevation, double roll) {
    final cp = math.cos(elevation);
    final back = Vector3(
      math.sin(azimuth) * cp,
      math.sin(elevation),
      math.cos(azimuth) * cp,
    );
    final up = _rolledUp(-back, roll);
    final right = up.cross(back).normalized();
    return Quaternion.fromRotation(Matrix3.columns(right, up, back))
      ..normalize();
  }

  static Quaternion _slerp(Quaternion a, Quaternion b, double t) {
    var dot = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
    var end = b;
    if (dot < 0) {
      dot = -dot;
      end = -b;
    }
    if (dot > 0.9995) {
      return Quaternion(
        a.x + (end.x - a.x) * t,
        a.y + (end.y - a.y) * t,
        a.z + (end.z - a.z) * t,
        a.w + (end.w - a.w) * t,
      )..normalize();
    }
    final theta = math.acos(dot);
    final sine = math.sin(theta);
    final wa = math.sin((1 - t) * theta) / sine;
    final wb = math.sin(t * theta) / sine;
    return Quaternion(
      a.x * wa + end.x * wb,
      a.y * wa + end.y * wb,
      a.z * wa + end.z * wb,
      a.w * wa + end.w * wb,
    );
  }

  /// [t] is already eased: 0 is where the flight began, 1 is [beginFly]'s pose.
  void setFly(double t) {
    final from = _flyFrom;
    final to = _flyTo;
    if (from == null || to == null) return;
    final u = t.clamp(0.0, 1.0);
    double mix(double a, double b) => a + (b - a) * u;
    lookAt = Offset.lerp(from.lookAt, to.lookAt, u)!;
    lookAtZ = mix(from.lookAtZ, to.lookAtZ);
    framedHalfHeightMm = mix(from.halfHeight, to.halfHeight);
    final turnFrom = _turnFrom;
    final turnTo = _turnTo;
    if (turnFrom != null && turnTo != null && u < 1) {
      final turn = _slerp(turnFrom, turnTo, u).conjugated();
      final angles = anglesAlong(
        turn.rotated(Vector3(0, 0, 1)),
        up: turn.rotated(Vector3(0, 1, 0)),
      );
      azimuth = angles.azimuth;
      elevation = angles.elevation;
      roll = angles.roll;
      _apply();
      notifyListeners();
      return;
    }
    final toAzimuth = to.azimuth;
    if (toAzimuth != null) azimuth = mix(from.azimuth ?? azimuth, toAzimuth);
    final toElevation = to.elevation;
    if (toElevation != null) {
      elevation = mix(from.elevation ?? elevation, toElevation);
    }
    final toRoll = to.roll;
    if (toRoll != null) {
      final start = from.roll ?? roll;
      roll = start + signedAngleDelta(start, toRoll) * u;
    }
    _apply();
    notifyListeners();
  }

  /// Screen point to plane coordinates of [plane].
  Offset? planePointOn(CraftPlane plane, Offset screen, Size viewport) {
    final ray = camera.unprojectRay(screen, viewport);
    if (ray == null) return null;
    final normal = plane.normal;
    final denom = ray.direction.dot(normal);
    if (denom.abs() < 1e-8) return null;
    final t = (plane.origin - ray.origin).dot(normal) / denom;
    return plane.local(ray.pointAt(t));
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
      lookAtZ + d * math.cos(azimuth) * cp,
    );
    camera.projection = ProjectionType.perspective;
    camera.fovDegrees = fovDegrees;
    camera.near = math.max(0.5, d / 1000);
    camera.far = d * 40 + 1000;
    camera.setPosition(eye);
    camera.setTarget(target);
    camera.setUp(_rolledUp(target - eye, roll));
  }

  /// Rotates the no-twist up vector around the view axis.
  static Vector3 _rolledUp(Vector3 forward, double roll) {
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
