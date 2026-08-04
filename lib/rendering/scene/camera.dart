import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import '../../geometry/transformable.dart';

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
