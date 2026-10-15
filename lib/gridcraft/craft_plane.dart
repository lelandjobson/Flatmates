import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

/// A flat crafting surface in 3D. Plane coordinates are level coordinates:
/// [toWorld] carries (x, y, 0) to the world. The sheet is the identity plane.
class CraftPlane {
  CraftPlane(Matrix4 toWorld)
    : toWorld = toWorld.clone(),
      _fromWorld = Matrix4.inverted(toWorld);

  static final CraftPlane sheet = CraftPlane(Matrix4.identity());

  final Matrix4 toWorld;
  final Matrix4 _fromWorld;

  Vector3 world(Offset point) =>
      toWorld.transformed3(Vector3(point.dx, point.dy, 0));

  Offset local(Vector3 world) {
    final point = _fromWorld.transformed3(world);
    return Offset(point.x, point.y);
  }

  Vector3 get origin => toWorld.getTranslation();

  Vector3 get normal =>
      toWorld.getRotation().transformed(Vector3(0, 0, 1)).normalized();

  bool get isSheet {
    final storage = toWorld.storage;
    for (var i = 0; i < 16; i++) {
      final identity = i % 5 == 0 ? 1.0 : 0.0;
      if ((storage[i] - identity).abs() > 1e-9) return false;
    }
    return true;
  }

  /// This plane pushed [distance] along its normal.
  CraftPlane lifted(double distance) {
    final n = normal..scale(distance);
    return CraftPlane(Matrix4.translation(n).multiplied(toWorld));
  }
}
