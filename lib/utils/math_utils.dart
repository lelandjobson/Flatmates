import 'package:vector_math/vector_math_64.dart';

class MathUtils {
  const MathUtils._();

  static Vector3 lerpVector(Vector3 a, Vector3 b, double t) {
    return Vector3(
      a.x + (b.x - a.x) * t,
      a.y + (b.y - a.y) * t,
      a.z + (b.z - a.z) * t,
    );
  }

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;
}

