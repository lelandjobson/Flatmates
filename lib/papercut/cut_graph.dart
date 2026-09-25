import 'dart:ui';

import '../geometry/geometry_algorithms.dart';
import 'paper.dart';
import 'safe_zone.dart';

/// Intersection of two infinite lines.
///
/// [tOnFirst] is 0 at [a0] and 1 at [a1]. [tOnSecond] is the same for
/// [b0] to [b1]. Null when the lines are parallel.
///
/// This is the Cartesian Cramer's rule used by Boost.Geometry
/// `cartesian_segments` in `strategies/cartesian/intersection.hpp`.
class LineHit {
  const LineHit({
    required this.point,
    required this.tOnFirst,
    required this.tOnSecond,
  });

  final Offset point;
  final double tOnFirst;
  final double tOnSecond;
}

LineHit? lineLineIntersection(Offset a0, Offset a1, Offset b0, Offset b1) {
  final dxA = a1.dx - a0.dx;
  final dyA = a1.dy - a0.dy;
  final dxB = b1.dx - b0.dx;
  final dyB = b1.dy - b0.dy;
  final denomA = dxA * dyB - dyA * dxB;
  if (denomA.abs() < 1e-8) return null;

  final wxA = a0.dx - b0.dx;
  final wyA = a0.dy - b0.dy;
  final tA = (dxB * wyA - dyB * wxA) / denomA;

  final wxB = b0.dx - a0.dx;
  final wyB = b0.dy - a0.dy;
  final denomB = dxB * dyA - dyB * dxA;
  if (denomB.abs() < 1e-8) return null;
  final tB = (dxA * wyB - dyA * wxB) / denomB;

  return LineHit(
    point: Offset(a0.dx + tA * dxA, a0.dy + tA * dyA),
    tOnFirst: tA,
    tOnSecond: tB,
  );
}

/// Where committed cuts meet. The old strokes are kept; joints are derived.
class PapercutCutGraph {
  const PapercutCutGraph({this.joints = const []});

  final List<Offset> joints;
}

PapercutCutGraph buildCutGraph(List<List<Offset>> strokes) {
  final joints = <Offset>[];
  void add(Offset point) {
    for (final joint in joints) {
      if ((joint - point).distance < 0.5) return;
    }
    joints.add(point);
  }

  for (var i = 0; i < strokes.length; i++) {
    for (var j = i + 1; j < strokes.length; j++) {
      _collectJoints(strokes[i], strokes[j], add);
    }
  }
  return PapercutCutGraph(joints: joints);
}

/// Pull a new stroke's ends onto nearby existing cuts. The existing strokes
/// are not changed. A gap inside the safe zone is closed by extending the
/// new end; an overshoot is trimmed back to the line hit.
List<Offset> connectNewCut(List<Offset> stroke, List<List<Offset>> existing) {
  if (stroke.length < 2 || existing.isEmpty) return stroke;
  final next = List<Offset>.of(stroke);
  _snapEnd(next, atStart: true, existing: existing);
  _snapEnd(next, atStart: false, existing: existing);
  return next;
}

/// Scissor plan. [segment] is tail then tip (bottom of the screen, then center).
///
/// When the blade meets an existing cut, the committed stroke runs only from
/// the tip to that hit. Hits further toward the tail are ignored. The old cut
/// is left as it was.
class ScissorCutPlan {
  const ScissorCutPlan({required this.stroke, this.joint});

  final List<Offset> stroke;
  final Offset? joint;
}

ScissorCutPlan? planScissorCut(List<Offset> segment, PapercutSheet sheet) {
  if (segment.length < 2) return null;
  final tail = segment.first;
  final tip = segment.last;
  final joint = _scissorJoint(tip, tail, sheet.cutStrokes);
  if (joint != null) {
    return ScissorCutPlan(stroke: [tip, joint], joint: joint);
  }
  if (!scissorReachesPaperEdge(segment, sheet)) return null;
  return ScissorCutPlan(stroke: [tail, tip]);
}

Offset? _scissorJoint(Offset tip, Offset tail, List<List<Offset>> strokes) {
  final blade = [tip, tail];
  LineHit? onBlade;
  LineHit? extension;
  ZoneCrossing? boundary;
  for (final stroke in strokes) {
    for (var i = 0; i < stroke.length - 1; i++) {
      final a = stroke[i];
      final b = stroke[i + 1];
      final segment = [a, b];
      final entry = firstSafeZoneEntry(tip, tail, segment);
      if (entry != null && (boundary == null || entry.t < boundary.t)) {
        boundary = entry;
      }
      final hit = lineLineIntersection(tip, tail, a, b);
      if (hit == null) continue;
      if (hit.tOnSecond < -1e-4 || hit.tOnSecond > 1 + 1e-4) continue;
      final crosses = hit.tOnFirst >= -1e-4 && hit.tOnFirst <= 1 + 1e-4;
      final extendsTip =
          hit.tOnFirst < 0 && (hit.point - tip).distance <= kPapercutLateralMm;
      if (!crosses && !extendsTip) continue;
      if (!crosses && !safeZonesOverlap(blade, segment)) continue;
      if (hit.tOnFirst >= 0) {
        if (onBlade == null || hit.tOnFirst < onBlade.tOnFirst) onBlade = hit;
      } else if (extension == null || hit.tOnFirst > extension.tOnFirst) {
        extension = hit;
      }
    }
  }
  final lineHit = onBlade ?? extension;
  if (lineHit != null) return lineHit.point;
  return boundary?.point;
}

void _snapEnd(
  List<Offset> stroke, {
  required bool atStart,
  required List<List<Offset>> existing,
}) {
  final endIndex = atStart ? 0 : stroke.length - 1;
  final innerIndex = atStart ? 1 : stroke.length - 2;
  final end = stroke[endIndex];
  final inner = stroke[innerIndex];
  if ((end - inner).distance < 1e-6) return;

  LineHit? best;
  var bestDistance = double.infinity;
  for (final other in existing) {
    for (var i = 0; i < other.length - 1; i++) {
      if (!safeZonesOverlap([end, inner], [other[i], other[i + 1]])) continue;
      final hit = lineLineIntersection(end, inner, other[i], other[i + 1]);
      if (hit == null) continue;
      if (hit.tOnSecond < -1e-4 || hit.tOnSecond > 1 + 1e-4) continue;
      if (hit.tOnFirst > 1 + 1e-4) continue;
      final distance = (hit.point - end).distance;
      if (distance > kPapercutLateralMm || distance >= bestDistance) continue;
      best = hit;
      bestDistance = distance;
    }
  }
  if (best != null) stroke[endIndex] = best.point;
}

void _collectJoints(
  List<Offset> a,
  List<Offset> b,
  void Function(Offset point) add,
) {
  if (a.length < 2 || b.length < 2) return;
  for (final end in [a.first, a.last, b.first, b.last]) {
    final host = identical(end, a.first) || identical(end, a.last) ? b : a;
    final hit = closestPointOnPolyline(end, host);
    if (hit.distance <= 0.5) add(hit.point);
  }
  for (var i = 0; i < a.length - 1; i++) {
    for (var j = 0; j < b.length - 1; j++) {
      final hit = lineLineIntersection(a[i], a[i + 1], b[j], b[j + 1]);
      if (hit == null) continue;
      if (hit.tOnFirst < -1e-4 || hit.tOnFirst > 1 + 1e-4) continue;
      if (hit.tOnSecond < -1e-4 || hit.tOnSecond > 1 + 1e-4) continue;
      add(hit.point);
    }
  }
}

bool safeZonesOverlap(List<Offset> a, List<Offset> b) {
  if (a.length < 2 || b.length < 2) return false;
  for (final point in _samples(a)) {
    if (pointInSafeZone(point, b, closed: false)) return true;
  }
  for (final point in _samples(b)) {
    if (pointInSafeZone(point, a, closed: false)) return true;
  }
  return false;
}

List<Offset> _samples(List<Offset> points) {
  final out = <Offset>[points.first];
  for (var i = 0; i < points.length - 1; i++) {
    final start = points[i];
    final end = points[i + 1];
    final dist = (end - start).distance;
    if (dist < 1e-6) continue;
    var traveled = 2.0;
    while (traveled < dist) {
      final t = traveled / dist;
      out.add(
        Offset(
          start.dx + (end.dx - start.dx) * t,
          start.dy + (end.dy - start.dy) * t,
        ),
      );
      traveled += 2;
    }
    out.add(end);
  }
  return out;
}
