import 'package:vector_math/vector_math_64.dart';

/// Transforms a Vector4 by a Matrix4.
Vector4 transformVector4(Matrix4 matrix, Vector4 vector) {
  final storage = matrix.storage;
  final x = vector.x;
  final y = vector.y;
  final z = vector.z;
  final w = vector.w;
  return Vector4(
    storage[0] * x + storage[4] * y + storage[8] * z + storage[12] * w,
    storage[1] * x + storage[5] * y + storage[9] * z + storage[13] * w,
    storage[2] * x + storage[6] * y + storage[10] * z + storage[14] * w,
    storage[3] * x + storage[7] * y + storage[11] * z + storage[15] * w,
  );
}

