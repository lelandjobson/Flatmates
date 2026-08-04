import 'dart:ui';

import '../geometry/polygon_union.dart';

/// Splits a polygon into faces using cut segments via planar face detection.
///
/// Returns a list of polygons (vertex lists). If the cuts don't form a
/// complete boundary that divides the polygon, returns a single-element list
/// containing the original polygon unchanged.
List<List<Offset>> splitPolygonByCuts(
  List<Offset> polygon,
  List<(Offset, Offset)> cutSegments,
) {
  if (polygon.length < 3 || cutSegments.isEmpty) return [polygon];

  // 1. Clip cut lines to the polygon boundary.  Each cut segment is
  //    treated as an infinite line so that cuts drawn inside the paper
  //    automatically extend to the polygon edges, producing a complete
  //    partition rather than a floating interior chord.
  final clipped = <(Offset, Offset)>[];
  for (final seg in cutSegments) {
    final inside = _clipLineToPolygon(seg.$1, seg.$2, polygon);
    clipped.addAll(inside);
  }
  if (clipped.isEmpty) return [polygon];

  // 2. Collect all segments: polygon edges + clipped cuts.
  final allSegments = <(Offset, Offset)>[];
  for (var i = 0; i < polygon.length; i++) {
    allSegments.add((polygon[i], polygon[(i + 1) % polygon.length]));
  }
  allSegments.addAll(clipped);

  // 3. Find all intersection points between every pair of segments and
  //    split segments at those points.
  final atomicSegments = splitAllAtIntersections(allSegments);

  // 4. Build adjacency graph with vertices merged by proximity.
  final graph = PlanarGraph(atomicSegments);

  // 5. Traverse faces using rightmost-turn walk.
  final faces = graph.findFaces();

  if (faces.length <= 1) return [polygon];

  // 6. Discard the unbounded face (largest absolute signed area).
  double maxArea = -1;
  int unboundedIdx = 0;
  for (var i = 0; i < faces.length; i++) {
    final area = polygonSignedArea(faces[i]).abs();
    if (area > maxArea) {
      maxArea = area;
      unboundedIdx = i;
    }
  }

  final result = <List<Offset>>[];
  for (var i = 0; i < faces.length; i++) {
    if (i == unboundedIdx) continue;
    final face = faces[i];
    if (face.length >= 3 && polygonSignedArea(face).abs() > planarEpsilon) {
      result.add(face);
    }
  }
  return result.isEmpty ? [polygon] : result;
}

// ---------------------------------------------------------------------------
// Line clipping (specific to paper splitting)
// ---------------------------------------------------------------------------

/// Clips the **line** through (a,b) to the interior of a simple polygon,
/// returning the sub-segments that lie inside.
///
/// Unlike segment clipping, this treats the cut as an infinite line so that
/// a short cut drawn inside the paper extends to the polygon boundary on
/// both sides, producing a complete edge-to-edge partition.
List<(Offset, Offset)> _clipLineToPolygon(
  Offset a,
  Offset b,
  List<Offset> polygon,
) {
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  if (dx * dx + dy * dy < planarEpsilon * planarEpsilon) return [];

  final hits = <double>[];

  for (var i = 0; i < polygon.length; i++) {
    final p = polygon[i];
    final q = polygon[(i + 1) % polygon.length];
    final t = _lineSegmentIntersectionT(a, b, p, q);
    if (t != null) {
      hits.add(t);
    }
  }

  if (hits.length < 2) return [];
  hits.sort();

  final result = <(Offset, Offset)>[];
  for (var i = 0; i < hits.length - 1; i++) {
    final t0 = hits[i];
    final t1 = hits[i + 1];
    if ((t1 - t0) < planarEpsilon) continue;
    final mid = (t0 + t1) / 2;
    final midPt = Offset(a.dx + dx * mid, a.dy + dy * mid);
    if (isInsidePolygon(midPt, polygon)) {
      result.add((
        Offset(a.dx + dx * t0, a.dy + dy * t0),
        Offset(a.dx + dx * t1, a.dy + dy * t1),
      ));
    }
  }
  return result;
}

/// Intersects the infinite line through (a,b) with the segment (p,q).
///
/// Returns the parameter `t` along the line (P = a + t*(b-a)), or null if
/// the line and segment are parallel / don't meet.  Only the segment bounds
/// on (p,q) are enforced; `t` is unbounded.
double? _lineSegmentIntersectionT(Offset a, Offset b, Offset p, Offset q) {
  final dxa = b.dx - a.dx;
  final dya = b.dy - a.dy;
  final dxb = q.dx - p.dx;
  final dyb = q.dy - p.dy;

  final denom = dxa * dyb - dya * dxb;
  if (denom.abs() < planarEpsilon) return null;

  final wx = a.dx - p.dx;
  final wy = a.dy - p.dy;

  final u = (dxa * wy - dya * wx) / denom;
  if (u < -planarEpsilon || u > 1 + planarEpsilon) return null;

  return (dxb * wy - dyb * wx) / denom;
}
