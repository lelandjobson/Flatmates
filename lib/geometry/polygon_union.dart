import 'dart:math' as math;
import 'dart:ui';

import 'geometry_algorithms.dart';

const double planarEpsilon = 1e-6;

// ---------------------------------------------------------------------------
// Shared planar-graph utilities (used by paper_splitting and polygon union)
// ---------------------------------------------------------------------------

double parameterOnSegment(Offset a, Offset b, Offset p) {
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  final len2 = dx * dx + dy * dy;
  if (len2 < planarEpsilon * planarEpsilon) return 0;
  return ((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / len2;
}

bool isInsidePolygon(Offset p, List<Offset> polygon) {
  var inside = false;
  for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final pi = polygon[i];
    final pj = polygon[j];
    if (((pi.dy > p.dy) != (pj.dy > p.dy)) &&
        (p.dx <
            (pj.dx - pi.dx) * (p.dy - pi.dy) / (pj.dy - pi.dy) + pi.dx)) {
      inside = !inside;
    }
  }
  return inside;
}

double polygonSignedArea(List<Offset> polygon) {
  var area = 0.0;
  for (var i = 0; i < polygon.length; i++) {
    final j = (i + 1) % polygon.length;
    area += polygon[i].dx * polygon[j].dy;
    area -= polygon[j].dx * polygon[i].dy;
  }
  return area / 2;
}

Offset polygonCentroid(List<Offset> polygon) {
  double cx = 0, cy = 0, area = 0;
  for (int i = 0; i < polygon.length; i++) {
    final j = (i + 1) % polygon.length;
    final cross =
        polygon[i].dx * polygon[j].dy - polygon[j].dx * polygon[i].dy;
    area += cross;
    cx += (polygon[i].dx + polygon[j].dx) * cross;
    cy += (polygon[i].dy + polygon[j].dy) * cross;
  }
  area /= 2;
  if (area.abs() < planarEpsilon) {
    return polygon.reduce((a, b) => a + b) / polygon.length.toDouble();
  }
  return Offset(cx / (6 * area), cy / (6 * area));
}

/// Splits all segments at their mutual intersection points, producing atomic
/// sub-segments where no two segments cross except at endpoints.
List<(Offset, Offset)> splitAllAtIntersections(
  List<(Offset, Offset)> segments,
) {
  final splits = List<List<double>>.generate(
    segments.length,
    (_) => [0.0, 1.0],
  );

  void addSplit(int idx, Offset p) {
    final t = parameterOnSegment(segments[idx].$1, segments[idx].$2, p);
    if (t > planarEpsilon && t < 1 - planarEpsilon) splits[idx].add(t);
  }

  for (var i = 0; i < segments.length; i++) {
    for (var j = i + 1; j < segments.length; j++) {
      final hit = segmentIntersection(
        segments[i].$1,
        segments[i].$2,
        segments[j].$1,
        segments[j].$2,
      );
      if (!hit.hasIntersection) continue;
      if (hit.isPoint && hit.point != null) {
        addSplit(i, hit.point!);
        addSplit(j, hit.point!);
      } else if (hit.isCollinear) {
        // T-junctions and overlapping roof/wall seams: split both
        // segments at the overlap interval so shared runs cancel.
        if (hit.segmentStart != null) {
          addSplit(i, hit.segmentStart!);
          addSplit(j, hit.segmentStart!);
        }
        if (hit.segmentEnd != null) {
          addSplit(i, hit.segmentEnd!);
          addSplit(j, hit.segmentEnd!);
        }
      }
    }
  }

  final result = <(Offset, Offset)>[];
  for (var i = 0; i < segments.length; i++) {
    final s = segments[i];
    final ts = splits[i]..sort();
    for (var k = 0; k < ts.length - 1; k++) {
      final t0 = ts[k];
      final t1 = ts[k + 1];
      if ((t1 - t0) < planarEpsilon) continue;
      result.add((
        Offset(
          s.$1.dx + (s.$2.dx - s.$1.dx) * t0,
          s.$1.dy + (s.$2.dy - s.$1.dy) * t0,
        ),
        Offset(
          s.$1.dx + (s.$2.dx - s.$1.dx) * t1,
          s.$1.dy + (s.$2.dy - s.$1.dy) * t1,
        ),
      ));
    }
  }
  return result;
}

// ---------------------------------------------------------------------------
// Planar graph + face detection
// ---------------------------------------------------------------------------

class PlanarGraph {
  PlanarGraph(List<(Offset, Offset)> segments) {
    for (final seg in segments) {
      final a = _addVertex(seg.$1);
      final b = _addVertex(seg.$2);
      if (a == b) continue;
      _addEdge(a, b);
    }
    _sortAdjacency();
  }

  final List<Offset> vertices = [];
  final List<List<int>> adjacency = [];

  int _addVertex(Offset p) {
    for (var i = 0; i < vertices.length; i++) {
      if ((p - vertices[i]).distance < planarEpsilon * 100) return i;
    }
    vertices.add(p);
    adjacency.add([]);
    return vertices.length - 1;
  }

  void _addEdge(int a, int b) {
    if (!adjacency[a].contains(b)) adjacency[a].add(b);
    if (!adjacency[b].contains(a)) adjacency[b].add(a);
  }

  void _sortAdjacency() {
    for (var v = 0; v < vertices.length; v++) {
      final center = vertices[v];
      adjacency[v].sort((a, b) {
        final angleA =
            math.atan2(vertices[a].dy - center.dy, vertices[a].dx - center.dx);
        final angleB =
            math.atan2(vertices[b].dy - center.dy, vertices[b].dx - center.dx);
        return angleA.compareTo(angleB);
      });
    }
  }

  /// Finds all faces of the planar graph using the rightmost-turn walk.
  /// Returns pairs of (face vertex list, list of directed edges in the face).
  List<(List<Offset>, List<(int, int)>)> findFacesWithEdges() {
    final used = <(int, int)>{};
    final faces = <(List<Offset>, List<(int, int)>)>[];

    for (var v = 0; v < vertices.length; v++) {
      for (final w in adjacency[v]) {
        if (used.contains((v, w))) continue;
        final result = _traceFaceWithEdges(v, w, used);
        if (result != null && result.$1.length >= 3) {
          faces.add(result);
        }
      }
    }
    return faces;
  }

  /// Simple face finder (vertex lists only) for backward compatibility.
  List<List<Offset>> findFaces() {
    return findFacesWithEdges().map((e) => e.$1).toList();
  }

  (List<Offset>, List<(int, int)>)? _traceFaceWithEdges(
    int startFrom,
    int startTo,
    Set<(int, int)> used,
  ) {
    final face = <Offset>[];
    final edges = <(int, int)>[];
    var prev = startFrom;
    var curr = startTo;
    const maxSteps = 10000;

    for (var step = 0; step < maxSteps; step++) {
      if (used.contains((prev, curr))) return null;
      used.add((prev, curr));
      face.add(vertices[curr]);
      edges.add((prev, curr));

      final next = _nextEdge(prev, curr);
      if (next == -1) return null;

      prev = curr;
      curr = next;

      if (prev == startFrom && curr == startTo) {
        return (face, edges);
      }
    }
    return null;
  }

  int _nextEdge(int prev, int curr) {
    final neighbors = adjacency[curr];
    if (neighbors.isEmpty) return -1;
    if (neighbors.length == 1) return neighbors[0];

    final inAngle = math.atan2(
      vertices[prev].dy - vertices[curr].dy,
      vertices[prev].dx - vertices[curr].dx,
    );

    int bestIdx = -1;
    double bestDelta = double.infinity;

    for (final n in neighbors) {
      if (n == prev && neighbors.length > 1) continue;
      final outAngle = math.atan2(
        vertices[n].dy - vertices[curr].dy,
        vertices[n].dx - vertices[curr].dx,
      );
      var delta = outAngle - inAngle;
      while (delta <= 0) {
        delta += 2 * math.pi;
      }
      if (delta < bestDelta) {
        bestDelta = delta;
        bestIdx = n;
      }
    }

    if (bestIdx == -1) return prev;
    return bestIdx;
  }
}

// ---------------------------------------------------------------------------
// Polygon union via planar subdivision
// ---------------------------------------------------------------------------

/// Computes the union of a set of polygons, returning boundary loops.
/// Outer boundaries are CCW, holes are CW.
///
/// Each input polygon is a closed vertex list (implicit closure from last to
/// first vertex). The result is a list of closed loops representing the
/// combined outer boundaries and any interior holes.
List<List<Offset>> unionPolygons(List<List<Offset>> polygons) {
  if (polygons.isEmpty) return [];
  if (polygons.length == 1) return [polygons.first];

  // 1. Collect all edges from all input polygons.
  final allSegments = <(Offset, Offset)>[];
  for (final poly in polygons) {
    for (var i = 0; i < poly.length; i++) {
      allSegments.add((poly[i], poly[(i + 1) % poly.length]));
    }
  }

  // 2. Split at all mutual intersections.
  final atomic = splitAllAtIntersections(allSegments);
  if (atomic.isEmpty) return polygons;

  // 3. Build planar graph and find faces with their directed edges.
  final graph = PlanarGraph(atomic);
  final facesWithEdges = graph.findFacesWithEdges();
  if (facesWithEdges.isEmpty) return polygons;

  // 4. Identify the unbounded face (largest absolute area).
  double maxArea = -1;
  int unboundedIdx = 0;
  for (var i = 0; i < facesWithEdges.length; i++) {
    final area = polygonSignedArea(facesWithEdges[i].$1).abs();
    if (area > maxArea) {
      maxArea = area;
      unboundedIdx = i;
    }
  }

  // 5. Classify each face: is its centroid inside any input polygon?
  //    The unbounded face is always "outside".
  final filled = List<bool>.filled(facesWithEdges.length, false);
  for (var i = 0; i < facesWithEdges.length; i++) {
    if (i == unboundedIdx) continue;
    final face = facesWithEdges[i].$1;
    if (face.length < 3) continue;
    final centroid = polygonCentroid(face);
    for (final poly in polygons) {
      if (isInsidePolygon(centroid, poly)) {
        filled[i] = true;
        break;
      }
    }
  }

  // 6. Build directed-edge-to-face-index map.
  final edgeToFace = <(int, int), int>{};
  for (var fi = 0; fi < facesWithEdges.length; fi++) {
    for (final edge in facesWithEdges[fi].$2) {
      edgeToFace[edge] = fi;
    }
  }

  // 7. Find boundary edges: undirected edges where one adjacent face is
  //    filled and the other is not (or unbounded/missing).
  final boundarySegments = <(Offset, Offset)>[];
  final seen = <(int, int)>{};

  for (final entry in edgeToFace.entries) {
    final (a, b) = entry.key;
    if (seen.contains((a, b))) continue;
    seen.add((a, b));
    seen.add((b, a));

    final faceAB = entry.value;
    final faceBA = edgeToFace[(b, a)];

    final abFilled = filled[faceAB];
    final baFilled = faceBA != null ? filled[faceBA] : false;

    if (abFilled != baFilled) {
      // Orient the boundary edge so the filled face is on the left.
      if (abFilled) {
        boundarySegments.add((graph.vertices[a], graph.vertices[b]));
      } else {
        boundarySegments.add((graph.vertices[b], graph.vertices[a]));
      }
    }
  }

  if (boundarySegments.isEmpty) return polygons;

  // 8. Trace boundary segments into closed loops.
  final loops = _traceBoundaryLoops(boundarySegments);

  return loops.isEmpty ? polygons : loops;
}

/// Traces directed boundary segments into closed loops by chaining end-to-start.
List<List<Offset>> _traceBoundaryLoops(List<(Offset, Offset)> segments) {
  if (segments.isEmpty) return [];

  // Build adjacency: for each start point, which segments depart from it?
  final adj = <_PointKey, List<int>>{};
  for (var i = 0; i < segments.length; i++) {
    final key = _PointKey(segments[i].$1);
    adj.putIfAbsent(key, () => []).add(i);
  }

  final used = List<bool>.filled(segments.length, false);
  final loops = <List<Offset>>[];

  for (var startIdx = 0; startIdx < segments.length; startIdx++) {
    if (used[startIdx]) continue;

    final loop = <Offset>[];
    var current = startIdx;

    while (true) {
      if (used[current]) break;
      used[current] = true;
      loop.add(segments[current].$1);

      final endKey = _PointKey(segments[current].$2);
      final candidates = adj[endKey];
      if (candidates == null) break;

      int? next;
      for (final c in candidates) {
        if (!used[c]) {
          next = c;
          break;
        }
      }
      if (next == null) break;
      current = next;
    }

    if (loop.length >= 3) {
      loops.add(loop);
    }
  }

  return loops;
}

class _PointKey {
  _PointKey(this.point);

  final Offset point;
  static const double _quantize = 1e-3;

  @override
  int get hashCode {
    final qx = (point.dx / _quantize).round();
    final qy = (point.dy / _quantize).round();
    return Object.hash(qx, qy);
  }

  @override
  bool operator ==(Object other) {
    if (other is! _PointKey) return false;
    return (point - other.point).distance < planarEpsilon * 100;
  }
}
