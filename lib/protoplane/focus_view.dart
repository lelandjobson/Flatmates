import 'dart:math' as math;
import 'dart:ui';
import 'package:vector_math/vector_math_64.dart';
import '../rendering/scene/camera.dart';
import 'models.dart';
import 'bedrooms.dart';
import 'layered_terrain.dart';
import 'focus_context.dart';

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
  int contextTiles = 0,
  Rect? safeZone,
  double safeZoneFill = 1,
}) {
  if (!safeZoneFill.isFinite || safeZoneFill < .5 || safeZoneFill > 1) {
    throw RangeError.value(
      safeZoneFill,
      'safeZoneFill',
      'Must be between 0.5 and 1',
    );
  }
  if (safeZone != null && safeZoneFill != 1) {
    safeZone = Rect.fromCenter(
      center: safeZone.center,
      width: safeZone.width * safeZoneFill,
      height: safeZone.height * safeZoneFill,
    );
  }
  final target = plane.point(plane.region.bounds.center);
  final width =
          safeZone?.width ??
          math.max(120.0, viewport.width - 150) * safeZoneFill,
      height =
          safeZone?.height ??
          math.max(160.0, viewport.height - 280) * safeZoneFill;
  final contextBounds = plane.region.bounds.inflate(contextTiles.toDouble());
  final outline = contextTiles > 0
      ? [
          contextBounds.topLeft,
          contextBounds.topRight,
          contextBounds.bottomRight,
          contextBounds.bottomLeft,
        ]
      : plane.region.outer;
  final offsets = plane.region.outer
      .map((p) => plane.point(p) - target)
      .toList();
  final contextOffsets = outline.map((p) => plane.point(p) - target).toList();
  double fittedSpan(Vector3 up, Vector3 direction) {
    final right = up.cross(direction).normalized();
    double extent(List<Vector3> points, Vector3 axis) {
      final values = points.map((p) => p.dot(axis));
      return values.reduce(math.max) - values.reduce(math.min);
    }

    final activeSpan = math.max(
      extent(offsets, up) * viewport.height / height,
      extent(offsets, right) * viewport.height / width,
    );
    // The editable surface fits between the controls. Context may extend behind
    // those controls, using the full viewport rather than shrinking the active
    // grid into a third of the already-small editing area on a phone.
    final contextSpan = math.max(
      extent(contextOffsets, up) *
          viewport.height /
          math.max(1, viewport.height - 24),
      extent(contextOffsets, right) *
          viewport.height /
          math.max(1, viewport.width - 24),
    );
    return contextTiles > 0 && !(fullFocus && safeZone != null)
        ? math.max(activeSpan, contextSpan)
        : activeSpan;
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
  if (safeZone != null && safeZone.width > 0 && safeZone.height > 0) {
    final focal = viewport.height / (2 * math.tan(fov * math.pi / 360));
    final right = up.cross(direction).normalized();
    // Translate the optical target so the plane is centered in the actual
    // unobscured rectangle, which need not be centered in the viewport.
    final kx = (viewport.width / 2 - safeZone.center.dx) / focal;
    final ky = (safeZone.center.dy - viewport.height / 2) / focal;
    double fit(List<Vector3> points, Rect rect) {
      final left = (rect.left - viewport.width / 2) / focal;
      final rightEdge = (rect.right - viewport.width / 2) / focal;
      final bottom = (viewport.height / 2 - rect.bottom) / focal;
      final top = (viewport.height / 2 - rect.top) / focal;
      var distance = .1;
      for (final p in points) {
        final x = p.dot(right), y = p.dot(up), z = p.dot(direction);
        distance = [
          distance,
          z + .01,
          (x + rightEdge * z) / (rightEdge + kx),
          (-x - left * z) / (-left - kx),
          (y + top * z) / (top + ky),
          (-y - bottom * z) / (-bottom - ky),
        ].reduce(math.max);
      }
      return distance;
    }

    var distance = fit(offsets, safeZone);
    if (!fullFocus) {
      distance = math.max(
        distance,
        math.max(bounds.width, bounds.height) * 2.5 / safeZoneFill,
      );
      if (contextTiles > 0) {
        distance = math.max(
          distance,
          fit(contextOffsets, (Offset.zero & viewport).deflate(12)) /
              safeZoneFill,
        );
      }
    }
    final aim = target + (right * kx + up * ky) * distance;
    return PlaneFocusPose(aim + direction * distance, aim, up, fov);
  }
  final distance = math.max(
    span * .58 / math.tan(fov * math.pi / 360),
    fullFocus ? .1 : math.max(bounds.width, bounds.height) * 2.5 / safeZoneFill,
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
  if (floor == null || source == null) {
    final center = p.point(p.region.bounds.center);
    // A freestanding wall is contextual to the level it stands on, rather
    // than the elevation halfway up its face. This also works for slopes.
    if (!isFloorOrientation(p)) {
      center.y = p.region.outer.map((v) => p.point(v).y).reduce(math.min);
    }
    return center;
  }
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
  Map<String, CraftPlane> planes, {
  int tiles = 1,
  LayeredTerrain? terrain,
}) {
  final a = contextAnchor(active, objects, planes),
      b = contextAnchor(other, objects, planes);
  final activeTile = terrain?.tiles[active.id];
  final otherTile = terrain?.tiles[other.id];
  final sameStack =
      activeTile != null &&
      otherTile != null &&
      activeTile.sheet.island == otherTile.sheet.island;
  // Landscape context is a tile column, not a single elevation. Keep the
  // story-height filter for constructed surfaces and legacy ground.
  if (!sameStack && (a.y - b.y).abs() >= .05) return false;
  Rect footprint(CraftPlane p) {
    final floor = objects[supportingFloor(p.owner, objects, planes)];
    final source = floor == null ? null : planes[floor.planeId];
    final useFloor = source != null && !p.id.startsWith('surface-');
    final points = (useFloor ? floor!.region.outer : p.region.outer)
        .map((point) => (useFloor ? source : p).point(point))
        .map((point) => Offset(point.x, point.z))
        .toList();
    return Rect.fromLTRB(
      points.map((p) => p.dx).reduce(math.min),
      points.map((p) => p.dy).reduce(math.min),
      points.map((p) => p.dx).reduce(math.max),
      points.map((p) => p.dy).reduce(math.max),
    );
  }

  // Compare footprints, so a fused work surface gets the requested border
  // around every constituent, not merely around the union's center tile.
  return footprint(
    active,
  ).inflate(tiles.toDouble() + 1e-6).overlaps(footprint(other).deflate(1e-5));
}
