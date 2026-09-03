import 'package:flutter/material.dart';

import '../../rendering/scene/camera.dart';
import 'outline_edges.dart';

const kWorldOutlineColor = Color(0xB3808080);
const kWorldOutlineStrokeWidth = 1.6;

/// Thinner, lighter stroke for door / face paper on top of volume fills.
const kAppliqueOutlineColor = Color(0xB3A8A8A8);
const kAppliqueOutlineStrokeWidth = 1.0;

/// Where an outline stroke is composited relative to elevated scene geo.
enum OutlineDrawPass {
  /// After ground fills, before volumes / structures / friends.
  underVolumes,

  /// After the 3D scene (volume silhouettes sit on their fills).
  overScene,
}

OutlineDrawPass outlineDrawPass({required bool groundPlane}) =>
    groundPlane ? OutlineDrawPass.underVolumes : OutlineDrawPass.overScene;

/// Stable-split [items] into ground then elevated. Order inside each group is kept.
({List<T> ground, List<T> elevated}) splitGroundPass<T>(
  Iterable<T> items,
  bool Function(T item) isGround,
) {
  final ground = <T>[];
  final elevated = <T>[];
  for (final item in items) {
    (isGround(item) ? ground : elevated).add(item);
  }
  return (ground: ground, elevated: elevated);
}

/// Project camera-facing outline edges and stroke them in screen space.
int paintOutlineEdges({
  required Canvas canvas,
  required Iterable<OutlineEdge> edges,
  required Camera camera,
  required Size viewport,
  Color color = kWorldOutlineColor,
  double strokeWidth = kWorldOutlineStrokeWidth,
  double Function(OutlineEdge edge)? opacityFor,
}) {
  final stroke = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = strokeWidth
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final eye = camera.position;
  var drawn = 0;
  for (final edge in edges) {
    final opacity = (opacityFor?.call(edge) ?? 1.0).clamp(0.0, 1.0);
    if (opacity <= 0.02) continue;
    if (!outlineEdgeVisible(edge, eye)) continue;
    final a = camera.projectToScreen(edge.a, viewport);
    final b = camera.projectToScreen(edge.b, viewport);
    if (a == null || b == null) continue;
    stroke.color = opacity < 0.999
        ? color.withValues(alpha: (color.a * opacity).clamp(0.0, 1.0))
        : color;
    canvas.drawLine(a, b, stroke);
    drawn++;
  }
  return drawn;
}
