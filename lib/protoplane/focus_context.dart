import 'dart:math' as math;
import 'package:vector_math/vector_math_64.dart';
import '../rendering/world_crop_box.dart';
import 'models.dart';

/// Surfaces within fifteen degrees of level belong to the floor category.
/// Every other orientation, including ramps, belongs to the wall category.
bool isFloorOrientation(CraftPlane plane) =>
    plane.normal.normalized().y.abs() >= math.cos(math.pi / 12);

bool sameFocusOrientation(
  CraftPlane active,
  CraftPlane other, {
  bool upright = false,
}) => isFloorOrientation(active) == (!upright && isFloorOrientation(other));

WorldCropBox focusCropBox(
  CraftPlane plane, {
  required double xPadding,
  required double zPadding,
  required double above,
  required double below,
}) {
  final points = plane.region.outer.map((p) => plane.point(p)).toList();
  final min = points.first.clone(), max = points.first.clone();
  for (final point in points.skip(1)) {
    for (var axis = 0; axis < 3; axis++) {
      min[axis] = math.min(min[axis], point[axis]);
      max[axis] = math.max(max[axis], point[axis]);
    }
  }
  return WorldCropBox(
    min - Vector3(xPadding, below, zPadding),
    max + Vector3(xPadding, above, zPadding),
  );
}
