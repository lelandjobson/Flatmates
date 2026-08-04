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
  }) : _target = Vector3.copy(target ?? camera.target) {
    camera.setTarget(_target);
    _updateSphericalFromCamera();
    _updateCameraFromSpherical(notify: false);
  }

  final Camera camera;
  final double minDistance;
  final double maxDistance;
  final double minOrthographicScale;
  final double maxOrthographicScale;
  final double orbitSensitivity;
  final double panSensitivity;
  final double zoomSensitivity;
  bool allowOrbiting;

  final Vector3 _target;
  double _radius = 1;
  double _theta = 0;
  double _phi = 0;

  void focusOn(Vector3 point) {
    _target.setFrom(point);
    _updateCameraFromSpherical();
  }

  void orbit(Offset delta) {
    if (!allowOrbiting || delta == Offset.zero) return;
    _theta -= delta.dx * orbitSensitivity;
    _phi += delta.dy * orbitSensitivity;
    const double epsilon = 0.01;
    _phi = _phi.clamp(-math.pi / 2 + epsilon, math.pi / 2 - epsilon);
    _updateCameraFromSpherical();
  }

  void pan(Offset delta) {
    if (delta == Offset.zero) return;
    final forward = camera.forward;
    var planeRight = _projectOntoPlane(Vector3(1, 0, 0), forward);
    if (planeRight.length2 == 0) {
      planeRight = _projectOntoPlane(Vector3(0, 0, 1), forward);
    }
    if (planeRight.length2 == 0) {
      planeRight = Vector3(1, 0, 0);
    } else {
      planeRight.normalize();
    }

    var planeUp = forward.cross(planeRight);
    if (planeUp.length2 == 0) {
      planeUp = Vector3(0, 1, 0);
    } else {
      planeUp.normalize();
    }
    final double scale = (_radius * panSensitivity).clamp(0.01, 100.0);
    final translation =
        (planeRight * (-delta.dx * scale)) + (planeUp * (delta.dy * scale));

    _target.add(translation);
    camera.position.add(translation);
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

  void jumpTo({required Vector3 position, required Vector3 target}) {
    camera.setPosition(position);
    camera.setTarget(target);
    _target.setFrom(target);
    _updateSphericalFromCamera();
    notifyListeners();
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
