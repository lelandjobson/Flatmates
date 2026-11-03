import 'dart:math' as math;
import 'dart:ui';
import 'package:vector_math/vector_math_64.dart';
import '../rendering/scene/camera.dart';
import 'models.dart';
import 'bedrooms.dart';

class PlaneFocusPose {
  const PlaneFocusPose(this.position, this.target, this.up, this.fov);
  final Vector3 position, target, up;
  final double fov;
}

/// Like GameView focus, keep the perspective lens and incoming azimuth.
/// Only tip toward the plane enough to make its grid readable. In particular,
/// don't adopt the plane's own UV 'up', which can roll the world by 90°.
PlaneFocusPose focusPlanePose(
  Camera camera,
  CraftPlane plane,
  Size viewport, {
  bool preview = false,
  bool fullFocus = false,
}) {
  final target = plane.point(plane.region.bounds.center);
  final width = math.max(120.0, viewport.width - 150),
      height = math.max(160.0, viewport.height - 280);
  final offsets = plane.region.outer
      .map((p) => plane.point(p) - target)
      .toList();
  double fittedSpan(Vector3 up, Vector3 direction) {
    final right = up.cross(direction).normalized();
    double extent(Vector3 axis) {
      final values = offsets.map((p) => p.dot(axis));
      return values.reduce(math.max) - values.reduce(math.min);
    }

    return math.max(
      extent(up) * viewport.height / height,
      extent(right) * viewport.height / width,
    );
  }

  final incoming = (camera.position - camera.target).normalized();
  final normal = plane.normal * (incoming.dot(plane.normal) < 0 ? -1.0 : 1.0);
  var tangent = incoming - normal * incoming.dot(normal);
  if (tangent.length2 < 1e-8) tangent = -plane.v;
  tangent.normalize();
  final cosine = fullFocus
      ? 1.0
      : preview
      ? .72
      : math.max(.84, incoming.dot(normal)).clamp(.84, .96);
  final direction = normal * cosine + tangent * math.sqrt(1 - cosine * cosine);
  var up = camera.up - direction * camera.up.dot(direction);
  if (up.length2 < 1e-8) up = plane.v - direction * plane.v.dot(direction);
  up.normalize();
  if (fullFocus) {
    // Carry the screen's actual up through the shortest look-direction turn.
    // Projecting world-up straight onto a horizontal plane is degenerate.
    var screenUp = camera.up - incoming * camera.up.dot(incoming);
    if (screenUp.length2 < 1e-8) screenUp = plane.v;
    screenUp.normalize();
    final axis = incoming.cross(normal);
    final cosine = incoming.dot(normal).clamp(-1.0, 1.0);
    var transported = screenUp;
    if (axis.length2 > 1e-8) {
      final sine = axis.length;
      axis.normalize();
      transported =
          screenUp * cosine +
          axis.cross(screenUp) * sine +
          axis * axis.dot(screenUp) * (1 - cosine);
    }
    final choices = [
      plane.u.normalized(),
      plane.v.normalized(),
      -plane.u.normalized(),
      -plane.v.normalized(),
    ];
    final bestSpan = choices
        .map((candidate) => fittedSpan(candidate, direction))
        .reduce(math.min);
    // A small fit tie band avoids needless quarter-turns for almost-square
    // pieces/windows. Opposite orientations always tie and use the least roll.
    final fitting = choices.where(
      (candidate) => fittedSpan(candidate, direction) <= bestSpan * 1.02,
    );
    up = fitting.reduce(
      (a, b) => a.dot(transported) >= b.dot(transported) ? a : b,
    );
  }

  final bounds = plane.region.bounds;
  final span = fittedSpan(up, direction);
  final fov = camera.fovDegrees.clamp(38.0, 55.0);
  final distance = math.max(
    span * .58 / math.tan(fov * math.pi / 360),
    fullFocus ? .1 : math.max(bounds.width, bounds.height) * 2.5,
  );
  return PlaneFocusPose(target + direction * distance, target, up, fov);
}

Vector3 contextAnchor(
  CraftPlane p,
  Map<String, CraftObject> objects,
  Map<String, CraftPlane> planes,
) {
  final id = supportingFloor(p.owner, objects, planes);
  final floor = objects[id];
  final source = floor == null ? null : planes[floor.planeId];
  if (floor == null || source == null) return p.point(p.region.bounds.center);
  final center = source.point(floor.region.bounds.center, floor.depth);
  // An unlocked upper candidate belongs to the floor below, but is on the
  // next story; never leave it visible as same-level ground context.
  if (p.id.startsWith('upper-')) center.y = p.origin.y;
  return center;
}

bool adjacentFocusContext(
  CraftPlane active,
  CraftPlane other,
  Map<String, CraftObject> objects,
  Map<String, CraftPlane> planes,
) {
  final a = contextAnchor(active, objects, planes),
      b = contextAnchor(other, objects, planes);
  return (a.y - b.y).abs() < .05 &&
      ((a.x + 4).floor() - (b.x + 4).floor()).abs() <= 1 &&
      ((4 - a.z).floor() - (4 - b.z).floor()).abs() <= 1;
}
