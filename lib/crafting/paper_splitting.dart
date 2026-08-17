import 'dart:math' as math;
import 'dart:ui';

import '../geometry/polygon_union.dart';

/// Splits a polygon into faces using cut segments via planar face detection.
///
/// Returns a list of polygons (vertex lists). If the cuts don't form a
/// complete boundary that divides the polygon, returns a single-element list
/// containing the original polygon unchanged.
///
/// When [holes] are provided, cut lines are clipped to the solid region
/// (exterior minus holes) and hole boundaries are treated as paper edges,
/// not as infinite cutting lines.
List<List<Offset>> splitPolygonByCuts(
  List<Offset> polygon,
  List<(Offset, Offset)> cutSegments, {
  List<List<Offset>> holes = const [],
}) {
  return [
    for (final piece in splitPaperByCuts(polygon, cutSegments, holes: holes))
      piece.$1,
  ];
}

/// Like [splitPolygonByCuts], but keeps hole rings on each resulting piece.
///
/// A hole that a cut opens becomes part of that piece's exterior. Untouched
/// holes stay attached to the piece that still contains them.
List<(List<Offset> exterior, List<List<Offset>> holes)> splitPaperByCuts(
  List<Offset> polygon,
  List<(Offset, Offset)> cutSegments, {
  List<List<Offset>> holes = const [],
}) {
  if (polygon.length < 3) return [(polygon, holes)];
  final validHoles = [
    for (final hole in holes)
      if (hole.length >= 3) hole,
  ];
  if (cutSegments.isEmpty) return [(polygon, validHoles)];

  final clipped = <(Offset, Offset)>[];
  for (final seg in cutSegments) {
    clipped.addAll(_clipLineToSolid(seg.$1, seg.$2, polygon, validHoles));
  }
  if (clipped.isEmpty) return [(polygon, validHoles)];

  final solid = _solidFacesFromGraph(polygon, validHoles, clipped);
  if (solid.isEmpty) {
    final exteriors = _splitExteriorOnly(polygon, cutSegments);
    return _attachHoles(exteriors, validHoles);
  }
  return _attachHoles(solid, validHoles);
}

List<List<Offset>> _solidFacesFromGraph(
  List<Offset> polygon,
  List<List<Offset>> holes,
  List<(Offset, Offset)> clippedCuts,
) {
  final allSegments = <(Offset, Offset)>[];
  for (var i = 0; i < polygon.length; i++) {
    allSegments.add((polygon[i], polygon[(i + 1) % polygon.length]));
  }
  for (final hole in holes) {
    for (var i = 0; i < hole.length; i++) {
      allSegments.add((hole[i], hole[(i + 1) % hole.length]));
    }
  }
  allSegments.addAll(clippedCuts);

  final faces = PlanarGraph(splitAllAtIntersections(allSegments)).findFaces();
  final solid = <List<Offset>>[];
  for (final face in faces) {
    if (face.length < 3) continue;
    if (polygonSignedArea(face).abs() <= planarEpsilon) continue;
    // Sample just inside the face, not the centroid: a C-shaped piece's
    // centroid often lands in the hole, which would drop a real half.
    // The unbounded outer walk and the "outside" of a disconnected hole
    // have their interior outside the face polygon.
    final sample = _faceInteriorPoint(face);
    if (!isInsidePolygon(sample, face)) continue;
    if (_isInSolid(sample, polygon, holes)) {
      solid.add(face);
    }
  }
  return solid;
}

/// Point just to the right of the first usable edge. Rightmost-turn faces
/// have their interior on the right, so this sits inside the face even when
/// the centroid does not.
Offset _faceInteriorPoint(List<Offset> face) {
  const offset = 1e-4;
  for (var i = 0; i < face.length; i++) {
    final a = face[i];
    final b = face[(i + 1) % face.length];
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final len2 = dx * dx + dy * dy;
    if (len2 < planarEpsilon * planarEpsilon) continue;
    final inv = offset / math.sqrt(len2);
    return Offset((a.dx + b.dx) / 2 + dy * inv, (a.dy + b.dy) / 2 - dx * inv);
  }
  return polygonCentroid(face);
}

List<List<Offset>> _splitExteriorOnly(
  List<Offset> polygon,
  List<(Offset, Offset)> cutSegments,
) {
  final clipped = <(Offset, Offset)>[];
  for (final seg in cutSegments) {
    clipped.addAll(_clipLineToSolid(seg.$1, seg.$2, polygon, const []));
  }
  if (clipped.isEmpty) return [polygon];

  final allSegments = <(Offset, Offset)>[];
  for (var i = 0; i < polygon.length; i++) {
    allSegments.add((polygon[i], polygon[(i + 1) % polygon.length]));
  }
  allSegments.addAll(clipped);

  final faces = PlanarGraph(splitAllAtIntersections(allSegments)).findFaces();
  if (faces.length <= 1) return [polygon];

  double maxArea = -1;
  var unboundedIdx = 0;
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

List<(List<Offset>, List<List<Offset>>)> _attachHoles(
  List<List<Offset>> faces,
  List<List<Offset>> holes,
) {
  if (faces.isEmpty) return const [];
  final assigned = List.generate(faces.length, (_) => <List<Offset>>[]);
  for (final hole in holes) {
    if (_holeIsOpenInAny(hole, faces)) continue;
    final hc = polygonCentroid(hole);
    int? best;
    var bestArea = double.infinity;
    for (var i = 0; i < faces.length; i++) {
      if (!isInsidePolygon(hc, faces[i])) continue;
      final area = polygonSignedArea(faces[i]).abs();
      if (area < bestArea) {
        bestArea = area;
        best = i;
      }
    }
    if (best != null) assigned[best].add(hole);
  }
  return [for (var i = 0; i < faces.length; i++) (faces[i], assigned[i])];
}

bool _holeIsOpenInAny(List<Offset> hole, List<List<Offset>> faces) {
  const merge = planarEpsilon * 100;
  for (final face in faces) {
    var hits = 0;
    for (final h in hole) {
      for (final f in face) {
        if ((h - f).distance < merge) {
          hits++;
          break;
        }
      }
    }
    if (hits >= 2) return true;
  }
  return false;
}

bool _isInSolid(
  Offset p,
  List<Offset> exterior,
  List<List<Offset>> holes,
) {
  if (!isInsidePolygon(p, exterior)) return false;
  for (final hole in holes) {
    if (isInsidePolygon(p, hole)) return false;
  }
  return true;
}

/// Clips the infinite line through (a,b) to the solid region of a possibly
/// holed polygon, returning the sub-segments that lie on paper.
List<(Offset, Offset)> _clipLineToSolid(
  Offset a,
  Offset b,
  List<Offset> exterior,
  List<List<Offset>> holes,
) {
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  if (dx * dx + dy * dy < planarEpsilon * planarEpsilon) return const [];

  final hits = <double>[];
  void addHits(List<Offset> ring) {
    for (var i = 0; i < ring.length; i++) {
      final t = _lineSegmentIntersectionT(
        a,
        b,
        ring[i],
        ring[(i + 1) % ring.length],
      );
      if (t != null) hits.add(t);
    }
  }

  addHits(exterior);
  for (final hole in holes) {
    addHits(hole);
  }
  if (hits.length < 2) return const [];
  hits.sort();

  final result = <(Offset, Offset)>[];
  for (var i = 0; i < hits.length - 1; i++) {
    final t0 = hits[i];
    final t1 = hits[i + 1];
    if ((t1 - t0) < planarEpsilon) continue;
    final mid = (t0 + t1) / 2;
    final midPt = Offset(a.dx + dx * mid, a.dy + dy * mid);
    if (_isInSolid(midPt, exterior, holes)) {
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
