import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math_64.dart';

import 'camera.dart';

class OrbitCameraController extends ChangeNotifier {
  OrbitCameraController({
    required this.camera,
    Vector3? target,
    this.minDistance = 80,
    this.maxDistance = 2000,
    this.minOrthographicScale = 40,
    this.maxOrthographicScale = 1200,
    this.orbitSensitivity = 0.008,
    this.panSensitivity = 0.003,
    this.zoomSensitivity = 0.0025,
    this.allowOrbiting = true,
    this.constrainPan = false,
  }) : _target = Vector3.copy(target ?? camera.target) {
    camera.setTarget(_target);
    _focusAnchor.setFrom(_target);
    _updateSphericalFromCamera();
    _updateCameraFromSpherical(notify: false);
  }

  final Camera camera;
  double minDistance;
  double maxDistance;
  final double minOrthographicScale;
  final double maxOrthographicScale;
  final double orbitSensitivity;
  final double panSensitivity;
  final double zoomSensitivity;
  bool allowOrbiting;

  /// When true, pan rubber-bands away from [focusAnchor] and should spring
  /// home on release (see [setTargetKeepingOrbit]).
  bool constrainPan;

  /// Hard pan radius as a fraction of the focused geometry's world diagonal.
  double panLimitRatio = 0.6;

  final Vector3 _target;
  final Vector3 _focusAnchor = Vector3.zero();
  double _focusExtent = 1;
  double _focusDiagonal = 1;
  double _radius = 1;
  double _theta = 0;
  double _phi = 0;
  Size _viewportSize = Size.zero;

  void setViewportSize(Size size) {
    _viewportSize = size;
  }

  Vector3 get target => Vector3.copy(_target);
  Vector3 get focusAnchor => Vector3.copy(_focusAnchor);
  double get radius => _radius;

  /// 0 = fully zoomed in, 1 = fully zoomed out.
  double get zoomOutT {
    final span = maxDistance - minDistance;
    if (span <= 1e-6) return 0;
    return ((_radius - minDistance) / span).clamp(0.0, 1.0);
  }

  /// World-space pan lock. Shrinks to 50% at full zoom-out.
  double get panHardLimit {
    final diag = _focusDiagonal > 1e-4 ? _focusDiagonal : _focusExtent * 2;
    final base = math.max(diag * panLimitRatio, 1e-4);
    return base * (1.0 - 0.5 * zoomOutT);
  }

  double get panSoftLimit => panHardLimit * 0.4;

  void setFocusAnchor(Vector3 point, {double? extent, double? diagonal}) {
    _focusAnchor.setFrom(point);
    if (extent != null && extent > 1e-4) {
      _focusExtent = extent;
    }
    if (diagonal != null && diagonal > 1e-4) {
      _focusDiagonal = diagonal;
    }
  }

  void setDistanceLimits(double min, double max) {
    minDistance = math.max(min, 1e-3);
    maxDistance = math.max(max, minDistance + 1e-3);
    final clamped = _radius.clamp(minDistance, maxDistance);
    if ((clamped - _radius).abs() > 1e-6) {
      _radius = clamped;
      _updateCameraFromSpherical();
    }
  }

  void clampPanToLimit() {
    if (!constrainPan) return;
    final current = _target - _focusAnchor;
    final hard = panHardLimit;
    if (current.length <= hard + 1e-6) return;
    if (current.length2 < 1e-12) return;
    current.normalize();
    current.scale(hard);
    setTargetKeepingOrbit(_focusAnchor + current);
  }

  void focusOn(Vector3 point) {
    _target.setFrom(point);
    _focusAnchor.setFrom(point);
    _updateCameraFromSpherical();
  }

  /// Move the look-at point without changing orbit angles or distance.
  void setTargetKeepingOrbit(Vector3 newTarget) {
    final delta = newTarget - _target;
    if (delta.length2 < 1e-12) return;
    _target.setFrom(newTarget);
    camera.position.add(delta);
    camera.setTarget(_target);
    _updateSphericalFromCamera();
    notifyListeners();
  }

  void orbit(Offset delta) {
    if (!allowOrbiting || delta == Offset.zero) return;
    _theta -= delta.dx * orbitSensitivity;
    _phi += delta.dy * orbitSensitivity;
    const double epsilon = 0.01;
    _phi = _phi.clamp(-math.pi / 2 + epsilon, math.pi / 2 - epsilon);
    _updateCameraFromSpherical();
  }

  /// Yaw around the look-at point, keeping pitch and distance.
  void addYaw(double radians) {
    if (radians.abs() < 1e-8) return;
    _theta -= radians;
    _updateCameraFromSpherical();
  }

  /// Move look-at and distance without changing orbit angles.
  void setPose({Vector3? target, double? radius}) {
    if (target != null) {
      _target.setFrom(target);
    }
    if (radius != null) {
      _radius = radius.clamp(minDistance, maxDistance);
    }
    _updateCameraFromSpherical();
  }

  void pan(Offset delta) {
    if (delta == Offset.zero) return;
    final forward = camera.forward;
    var planeRight = camera.right;
    if (planeRight.length2 == 0) {
      planeRight = _projectOntoPlane(Vector3(1, 0, 0), forward);
      if (planeRight.length2 == 0) {
        planeRight = _projectOntoPlane(Vector3(0, 0, 1), forward);
      }
      if (planeRight.length2 == 0) {
        planeRight = Vector3(1, 0, 0);
      } else {
        planeRight.normalize();
      }
    }

    // Screen-up in the view plane (perpendicular to look and right).
    var planeUp = planeRight.cross(forward);
    if (planeUp.length2 == 0) {
      planeUp = Vector3(0, 1, 0);
    } else {
      planeUp.normalize();
    }

    // 1:1: a screen-pixel drag moves the look-at plane by that many
    // projected world units, so the point under a finger stays under it.
    final worldPerPixel = _worldUnitsPerPixel();
    var translation = (planeRight * (-delta.dx * worldPerPixel)) +
        (planeUp * (delta.dy * worldPerPixel));
    if (constrainPan) {
      translation = _constrainPanTranslation(translation);
    }

    _target.add(translation);
    camera.position.add(translation);
    camera.setTarget(_target);
    _updateSphericalFromCamera();
    notifyListeners();
  }

  void zoomByScale(double scaleChange) {
    if (scaleChange == 0 || scaleChange == 1) return;
    if (_isOrthographic) {
      final newScale = (camera.orthographicScale / scaleChange).clamp(
        minOrthographicScale,
        maxOrthographicScale,
      );
      camera.orthographicScale = newScale;
      notifyListeners();
      return;
    }
    _radius = (_radius / scaleChange).clamp(minDistance, maxDistance);
    _updateCameraFromSpherical();
  }

  void zoomByScroll(double delta) {
    if (delta == 0) return;
    if (_isOrthographic) {
      final factor = math.exp(delta * zoomSensitivity);
      final newScale = (camera.orthographicScale * factor).clamp(
        minOrthographicScale,
        maxOrthographicScale,
      );
      camera.orthographicScale = newScale;
      notifyListeners();
      return;
    }
    final factor = math.exp(delta * zoomSensitivity);
    _radius = (_radius * factor).clamp(minDistance, maxDistance);
    _updateCameraFromSpherical();
  }

  void jumpTo({
    required Vector3 position,
    required Vector3 target,
    bool setFocus = true,
    double? focusExtent,
  }) {
    camera.setPosition(position);
    camera.setTarget(target);
    _target.setFrom(target);
    if (setFocus) {
      _focusAnchor.setFrom(target);
      if (focusExtent != null && focusExtent > 1e-4) {
        _focusExtent = focusExtent;
      }
    }
    _updateSphericalFromCamera();
    notifyListeners();
  }

  Vector3 _constrainPanTranslation(Vector3 translation) {
    final current = _target - _focusAnchor;
    final soft = panSoftLimit;
    final hard = math.max(panHardLimit, soft + 1e-4);
    final d0 = current.length;

    if (d0 >= hard - 1e-6) {
      final radial = d0 > 1e-8 ? (current / d0) : Vector3.zero();
      final outward = radial.length2 > 0 ? translation.dot(radial) : 0.0;
      if (outward > 0) {
        translation = translation - radial * outward;
      }
      final next = current + translation;
      if (next.length > hard && next.length2 > 1e-12) {
        next.normalize();
        next.scale(hard);
        return next - current;
      }
      return translation;
    }

    if (d0 > soft) {
      final t = ((d0 - soft) / (hard - soft)).clamp(0.0, 1.0);
      final resistance = (1 - t) * (1 - t);
      final radial = current / d0;
      final outward = translation.dot(radial);
      if (outward > 0) {
        translation = translation - radial * outward * (1 - resistance);
      }
    }

    final next = current + translation;
    if (next.length > hard && next.length2 > 1e-12) {
      next.normalize();
      next.scale(hard);
      return next - current;
    }
    return translation;
  }

  void translateBy(Vector3 delta) {
    if (delta.length2 == 0) {
      return;
    }
    _target.add(delta);
    camera.position.add(delta);
    camera.setTarget(_target);
    _updateSphericalFromCamera();
    notifyListeners();
  }

  void _updateCameraFromSpherical({bool notify = true}) {
    final offset = _offsetFromAngles();
    final newPosition = Vector3.copy(_target)..add(offset);
    camera.setPosition(newPosition);
    camera.setTarget(_target);
    if (notify) {
      notifyListeners();
    }
  }

  void _updateSphericalFromCamera() {
    final offset = camera.position - _target;
    final planar = math.max(
      1e-5,
      math.sqrt(offset.x * offset.x + offset.z * offset.z),
    );
    _radius = offset.length.clamp(minDistance, maxDistance);
    _theta = math.atan2(offset.x, offset.z);
    _phi = math.atan2(offset.y, planar);
  }

  Vector3 _offsetFromAngles() {
    final cosPhi = math.cos(_phi);
    final sinPhi = math.sin(_phi);
    final sinTheta = math.sin(_theta);
    final cosTheta = math.cos(_theta);
    final x = _radius * cosPhi * sinTheta;
    final y = _radius * sinPhi;
    final z = _radius * cosPhi * cosTheta;
    return Vector3(x, y, z);
  }

  bool get _isOrthographic => camera.projection == ProjectionType.orthographic;

  double _worldUnitsPerPixel() {
    final h = _viewportSize.height;
    if (h > 1) {
      if (_isOrthographic) {
        return (2 * camera.orthographicScale) / h;
      }
      final halfFovY = camera.fovDegrees * math.pi / 360;
      return (2 * _radius * math.tan(halfFovY)) / h;
    }
    return (_radius * panSensitivity).clamp(0.01, 100.0);
  }

  Vector3 _projectOntoPlane(Vector3 vector, Vector3 normal) {
    Vector3 n;
    if (normal.length2 == 0) {
      n = Vector3(0, 0, 1);
    } else {
      n = Vector3.copy(normal)..normalize();
    }
    final projection = vector - n * vector.dot(n);
    if (projection.length2 == 0) {
      return Vector3.zero();
    }
    return projection;
  }
}
