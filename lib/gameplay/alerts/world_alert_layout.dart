import 'dart:math' as math;
import 'dart:ui';

import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../../rendering/scene/camera.dart';
import 'world_alert.dart';

const kWorldAlertVisualSize = 32.0;
const kWorldAlertHitScale = 1.5;
const kWorldAlertBubbleGap = 4.0;
const kWorldAlertPillPad = 4.0;
const kWorldAlertBorder = 2.5;
const kWorldAlertWaypointHalfTiles = 50.0;
const kWorldAlertGrow = 1.28;

double worldAlertHitSize(double visual) => visual * kWorldAlertHitScale;

/// Pill width. One issue stays a circle; several stretch into a sandwich.
double sandwichVisualWidth({
  required int issueCount,
  required bool expanded,
}) {
  if (!expanded || issueCount <= 1) return kWorldAlertVisualSize;
  return kWorldAlertBorder * 2 +
      kWorldAlertPillPad * 2 +
      issueCount * kWorldAlertVisualSize +
      (issueCount - 1) * kWorldAlertBubbleGap;
}

Rect worldAlertHitRect({
  required Offset screen,
  required int issueCount,
  required bool expanded,
  double scale = 1,
}) {
  final visualW = sandwichVisualWidth(
        issueCount: issueCount,
        expanded: expanded,
      ) *
      scale;
  final visualH = kWorldAlertVisualSize * scale;
  return Rect.fromCenter(
    center: screen,
    width: visualW * kWorldAlertHitScale,
    height: visualH * kWorldAlertHitScale,
  );
}

List<Offset> sandwichBubbleCenters({
  required Offset screen,
  required int issueCount,
  required bool expanded,
  double scale = 1,
}) {
  if (issueCount <= 0) return const [];
  if (!expanded || issueCount == 1) return [screen];
  final visualW = sandwichVisualWidth(
        issueCount: issueCount,
        expanded: true,
      ) *
      scale;
  final start = screen.dx -
      visualW * 0.5 +
      (kWorldAlertPillPad + kWorldAlertVisualSize * 0.5) * scale;
  final step = (kWorldAlertVisualSize + kWorldAlertBubbleGap) * scale;
  return [
    for (var i = 0; i < issueCount; i++) Offset(start + i * step, screen.dy),
  ];
}

int nearestSandwichBubble({
  required Offset pointer,
  required List<Offset> centers,
}) {
  if (centers.isEmpty) return 0;
  var best = 0;
  var bestDist = double.infinity;
  for (var i = 0; i < centers.length; i++) {
    final d = (pointer - centers[i]).distanceSquared;
    if (d < bestDist) {
      best = i;
      bestDist = d;
    }
  }
  return best;
}

/// Linear 1 → 0.5 over [kWorldAlertWaypointHalfTiles] ground tiles.
double waypointDistanceScale({
  required Vector3 world,
  required Vector3 lookAt,
  required double tileSize,
}) {
  if (tileSize <= 0) return 1;
  final dx = world.x - lookAt.x;
  final dz = world.z - lookAt.z;
  final tiles = math.sqrt(dx * dx + dz * dz) / tileSize;
  return 1 - 0.5 * (tiles / kWorldAlertWaypointHalfTiles).clamp(0.0, 1.0);
}

class WorldAlertPlacement {
  const WorldAlertPlacement({
    required this.alert,
    required this.screen,
    required this.raw,
    required this.waypoint,
    required this.scale,
  });

  final WorldAlert alert;
  final Offset screen;
  final Offset raw;
  final bool waypoint;
  final double scale;
}

WorldAlertPlacement? placeWorldAlert({
  required WorldAlert alert,
  required Camera camera,
  required Size viewport,
  required Vector3 lookAt,
  required double tileSize,
}) {
  final projected = camera.projectToScreenOrEdge(alert.world, viewport);
  if (projected == null) return null;
  final scale = projected.onScreen
      ? 1.0
      : waypointDistanceScale(
          world: alert.world,
          lookAt: lookAt,
          tileSize: tileSize,
        );
  return WorldAlertPlacement(
    alert: alert,
    screen: projected.position,
    raw: projected.raw,
    waypoint: !projected.onScreen,
    scale: scale,
  );
}

/// Issue under the game pointer, if any.
WorldAlertIssue? hitWorldAlertIssue({
  required List<WorldAlert> alerts,
  required Camera camera,
  required Size viewport,
  required Offset pointer,
  required Vector3 lookAt,
  required double tileSize,
}) {
  for (final alert in alerts) {
    if (alert.issues.isEmpty) continue;
    final placed = placeWorldAlert(
      alert: alert,
      camera: camera,
      viewport: viewport,
      lookAt: lookAt,
      tileSize: tileSize,
    );
    if (placed == null) continue;
    final count = alert.issues.length;
    final collapsed = worldAlertHitRect(
      screen: placed.screen,
      issueCount: count,
      expanded: false,
      scale: placed.scale,
    );
    final expanded = worldAlertHitRect(
      screen: placed.screen,
      issueCount: count,
      expanded: true,
      scale: placed.scale,
    );
    if (!collapsed.contains(pointer) && !expanded.contains(pointer)) {
      continue;
    }
    if (count == 1 || placed.waypoint || !expanded.contains(pointer)) {
      return alert.issues.first;
    }
    final centers = sandwichBubbleCenters(
      screen: placed.screen,
      issueCount: count,
      expanded: true,
      scale: placed.scale,
    );
    return alert.issues[nearestSandwichBubble(
      pointer: pointer,
      centers: centers,
    )];
  }
  return null;
}

bool pointerExpandsAlert({
  required Offset pointer,
  required Offset screen,
  required int issueCount,
  required bool currentlyExpanded,
  double scale = 1,
}) {
  return worldAlertHitRect(
    screen: screen,
    issueCount: issueCount,
    expanded: currentlyExpanded,
    scale: scale,
  ).contains(pointer);
}
