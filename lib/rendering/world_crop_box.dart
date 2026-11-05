import 'package:vector_math/vector_math_64.dart';

/// Six world-space half-spaces. Clips faces rather than dropping whole objects.
class WorldCropBox {
  WorldCropBox(Vector3 min, Vector3 max) : min = min.clone(), max = max.clone();

  final Vector3 min, max;

  bool contains(Vector3 point) =>
      point.x >= min.x &&
      point.x <= max.x &&
      point.y >= min.y &&
      point.y <= max.y &&
      point.z >= min.z &&
      point.z <= max.z;

  /// Sutherland–Hodgman, matching the renderer's near-plane clipper. The
  /// crossing parameter uses the bounded parametric segment approach in
  /// Boost.Geometry's overlay/clip_linestring.hpp, extended to three axes.
  /// Render faces are convex (concave paper has already been tessellated).
  List<Vector3> clip(List<Vector3> polygon) {
    var result = polygon;
    for (var axis = 0; axis < 3 && result.isNotEmpty; axis++) {
      for (final lower in [true, false]) {
        final boundary = lower ? min[axis] : max[axis];
        double distance(Vector3 p) =>
            lower ? p[axis] - boundary : boundary - p[axis];
        final output = <Vector3>[];
        for (var i = 0; i < result.length; i++) {
          final a = result[i], b = result[(i + 1) % result.length];
          final da = distance(a), db = distance(b);
          final insideA = da >= 0, insideB = db >= 0;
          if (insideA != insideB) {
            // Opposite half-spaces guarantee a nonzero denominator.
            final t = (da / (da - db)).clamp(0.0, 1.0);
            final hit = a + (b - a) * t;
            hit[axis] = boundary;
            output.add(hit);
          }
          if (insideB) output.add(b);
        }
        result = output;
        if (result.isEmpty) break;
      }
    }
    return result;
  }
}
