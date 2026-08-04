import 'package:vector_math/vector_math_64.dart';

class Transformable {
  Transformable({Vector3? position, Vector3? rotation, Vector3? scale})
    : position = position ?? Vector3.zero(),
      rotation = rotation ?? Vector3.zero(),
      scale = scale ?? Vector3.all(1);

  final Vector3 position;
  final Vector3 rotation;
  final Vector3 scale;

  void setPosition(Vector3 value) => position.setFrom(value);
  void setRotation(Vector3 value) => rotation.setFrom(value);
  void setScale(Vector3 value) => scale.setFrom(value);

  Matrix4 get transformMatrix {
    final matrix = Matrix4.identity();
    matrix.translate(Vector3(position.x, position.y, position.z));
    matrix.rotateX(rotation.x);
    matrix.rotateY(rotation.y);
    matrix.rotateZ(rotation.z);
    matrix.scale(scale.x, scale.y, scale.z);
    return matrix;
  }
}
