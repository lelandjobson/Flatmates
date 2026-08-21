import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:vector_math/vector_math_64.dart';

import '../../geometry/transformable.dart';

class CameraRay {
  const CameraRay({required this.origin, required this.direction});

  final Vector3 origin;
  final Vector3 direction;

  Vector3 pointAt(double t) => origin + direction * t;
}

enum ProjectionType { perspective, orthographic }

class Camera extends Transformable {
  Camera({
    required this.name,
    required Vector3 position,
    Vector3? target,
    Vector3? up,
    this.projection = ProjectionType.perspective,
    this.fovDegrees = 60,
    this.near = 0.1,
    this.far = 1000,
    this.orthographicScale = 200,
  }) : _target = Vector3.copy(target ?? Vector3.zero()),
       _up = Vector3.copy(up ?? Vector3(0, 1, 0)),
       super(position: position);

  final String name;
  final Vector3 _target;
  final Vector3 _up;
  ProjectionType projection;
  double fovDegrees;
  double near;
  double far;
  double orthographicScale;

  Vector3 get target => Vector3.copy(_target);
  void setTarget(Vector3 value) => _target.setFrom(value);

  Vector3 get up => Vector3.copy(_up);
  void setUp(Vector3 value) => _up.setFrom(value);

  Vector3 get forward {
    final dir = _target - position;
    if (dir.length2 == 0) {
      return Vector3(0, 0, -1);
    }
    return dir.normalized();
  }

  Vector3 get right {
    final upVector = _up.length2 == 0 ? Vector3(0, 1, 0) : _up.normalized();
    final dir = forward;
    final cross = dir.cross(upVector);
    if (cross.length2 == 0) {
      return Vector3(1, 0, 0);
    }
    return cross.normalized();
  }

  Matrix4 get viewMatrix {
    final upVector = _up.length2 == 0 ? Vector3(0, 1, 0) : _up.normalized();
    return makeViewMatrix(position, _target, upVector);
  }

  Matrix4 projectionMatrix(double aspect) {
    switch (projection) {
      case ProjectionType.orthographic:
        final scale = orthographicScale;
        return makeOrthographicMatrix(
          -scale * aspect,
          scale * aspect,
          -scale,
          scale,
          near,
          far,
        );
      case ProjectionType.perspective:
        final fovRadians = fovDegrees * math.pi / 180;
        return makePerspectiveMatrix(fovRadians, aspect, near, far);
    }
  }

  Matrix4 viewProjectionMatrix(Size viewport) {
    final aspect = viewport.width <= 0 || viewport.height <= 0
        ? 1.0
        : viewport.width / viewport.height;
    return projectionMatrix(aspect) * viewMatrix;
  }

  /// World point to Flutter screen space, or null if behind the camera.
  Offset? projectToScreen(Vector3 worldPos, Size viewport) {
    if (viewport.width <= 0 || viewport.height <= 0) return null;
    final clip = Vector4(worldPos.x, worldPos.y, worldPos.z, 1);
    viewProjectionMatrix(viewport).transform(clip);
    if (!clip.storage.every((v) => v.isFinite) || clip.w < 1e-3) return null;
    final ndcX = clip.x / clip.w;
    final ndcY = clip.y / clip.w;
    if (!ndcX.isFinite || !ndcY.isFinite) return null;
    return Offset(
      (ndcX * 0.5 + 0.5) * viewport.width,
      (1 - (ndcY * 0.5 + 0.5)) * viewport.height,
    );
  }

  /// Screen pixel to a world-space ray, or null if the viewport / matrix is degenerate.
  CameraRay? unprojectRay(Offset screen, Size viewport) {
    if (viewport.width <= 0 || viewport.height <= 0) return null;
    final inverted = Matrix4.copy(viewProjectionMatrix(viewport));
    if (inverted.invert().abs() < 1e-10) return null;

    final ndcX = (screen.dx / viewport.width) * 2 - 1;
    final ndcY = 1 - (screen.dy / viewport.height) * 2;
    final nearPoint = _unproject(inverted, ndcX, ndcY, -1);
    final farPoint = _unproject(inverted, ndcX, ndcY, 1);
    if (nearPoint == null || farPoint == null) return null;
    final direction = farPoint - nearPoint;
    if (direction.length2 < 1e-12) return null;
    direction.normalize();
    return CameraRay(origin: Vector3.copy(position), direction: direction);
  }

  /// Intersect [unprojectRay] with the Y = 0 ground plane.
  Vector3? intersectGround(Offset screen, Size viewport) {
    final ray = unprojectRay(screen, viewport);
    if (ray == null || ray.direction.y.abs() < 1e-8) return null;
    final t = -ray.origin.y / ray.direction.y;
    if (t < 0) return null;
    return ray.pointAt(t);
  }

  /// Intersect [ray] with the plane through [point] with [normal].
  static Vector3? intersectPlane({
    required CameraRay ray,
    required Vector3 point,
    required Vector3 normal,
  }) {
    final denom = ray.direction.dot(normal);
    if (denom.abs() < 1e-8) return null;
    final t = (point - ray.origin).dot(normal) / denom;
    if (t < 0) return null;
    return ray.pointAt(t);
  }

  static Vector3? _unproject(
    Matrix4 invMvp,
    double ndcX,
    double ndcY,
    double ndcZ,
  ) {
    final clip = Vector4(ndcX, ndcY, ndcZ, 1);
    invMvp.transform(clip);
    if (!clip.storage.every((v) => v.isFinite) || clip.w.abs() < 1e-8) {
      return null;
    }
    return Vector3(clip.x / clip.w, clip.y / clip.w, clip.z / clip.w);
  }
}

Matrix4 makeOrthographicMatrix(
  double left,
  double right,
  double bottom,
  double top,
  double near,
  double far,
) {
  final matrix = Matrix4.zero();
  matrix.setEntry(0, 0, 2 / (right - left));
  matrix.setEntry(1, 1, 2 / (top - bottom));
  matrix.setEntry(2, 2, -2 / (far - near));
  matrix.setEntry(3, 3, 1);
  matrix.setEntry(0, 3, -(right + left) / (right - left));
  matrix.setEntry(1, 3, -(top + bottom) / (top - bottom));
  matrix.setEntry(2, 3, -(far + near) / (far - near));
  return matrix;
}

Matrix4 makePerspectiveMatrix(
  double fovYRadians,
  double aspect,
  double near,
  double far,
) {
  final f = 1 / math.tan(fovYRadians / 2);
  final matrix = Matrix4.zero();
  matrix.setEntry(0, 0, f / aspect);
  matrix.setEntry(1, 1, f);
  matrix.setEntry(2, 2, (far + near) / (near - far));
  matrix.setEntry(2, 3, (2 * far * near) / (near - far));
  matrix.setEntry(3, 2, -1);
  return matrix;
}
