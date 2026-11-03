import 'dart:ui';
import 'models.dart';

/// A transient prefix of a permitted grid connection. Projection is supplied
/// by the view, so snapping follows the visible curved edge in perspective.
/// This never appends nodes or creates history/material transactions.
List<Offset> liveStrokePreview({
  required CraftGrid grid,
  required List<int> path,
  required Offset pointer,
  required Offset? Function(Offset) project,
}) {
  if (path.isEmpty || (path.length > 2 && path.first == path.last)) return [];
  final last = path.last;
  var bestDistance = double.infinity;
  var best = <Offset>[];
  for (final edge in grid.edges) {
    if (edge.a != last && edge.b != last) continue;
    final next = edge.a == last ? edge.b : edge.a;
    if (path.contains(next) && !(next == path.first && path.length >= 3)) {
      continue;
    }
    final points = edge.points(grid.nodes, reversed: edge.a != last);
    for (var i = 1; i < points.length; i++) {
      final a = project(points[i - 1]), b = project(points[i]);
      if (a == null || b == null) continue;
      final d = b - a;
      if (d.distanceSquared < 1e-8) continue;
      final t =
          (((pointer - a).dx * d.dx + (pointer - a).dy * d.dy) /
                  d.distanceSquared)
              .clamp(0.0, 1.0);
      final distance = (pointer - a - d * t).distanceSquared;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = [
          ...points.take(i),
          points[i - 1] + (points[i] - points[i - 1]) * t,
        ];
      }
    }
  }
  return best;
}
