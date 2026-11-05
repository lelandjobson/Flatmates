import 'dart:math' as math;
import 'dart:ui';

import '../geometry/polygon_union.dart'
    show polygonSignedArea, splitAllAtIntersections;

const geometryEpsilon = 1e-7;
const curveTolerance = 0.001;
double cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;
bool near(Offset a, Offset b) => (a - b).distance < geometryEpsilon;

/// Cramer's rule, following Boost.Geometry cartesian_segments. Collinear
/// contacts are classified separately, so shared boundaries aren't overlaps.
Offset? crossing(Offset a, Offset b, Offset c, Offset d) {
  final u = b - a, v = d - c;
  final denominator = cross(u, v);
  if (denominator.abs() < geometryEpsilon) return null;
  final t = cross(c - a, v) / denominator;
  final s = cross(c - a, u) / denominator;
  if (t < -geometryEpsilon ||
      t > 1 + geometryEpsilon ||
      s < -geometryEpsilon ||
      s > 1 + geometryEpsilon) {
    return null;
  }
  return a + u * t;
}

bool onSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  if (ab.distance < geometryEpsilon) return near(p, a);
  return cross(p - a, ab).abs() < geometryEpsilon * ab.distance &&
      (p - a).dx * ab.dx + (p - a).dy * ab.dy >= -geometryEpsilon &&
      (p - b).dx * ab.dx + (p - b).dy * ab.dy <= geometryEpsilon;
}

bool segmentsTouch(Offset a, Offset b, Offset c, Offset d) =>
    crossing(a, b, c, d) != null ||
    onSegment(a, c, d) ||
    onSegment(b, c, d) ||
    onSegment(c, a, b) ||
    onSegment(d, a, b);

bool simplePath(List<Offset> points, {required bool closed}) {
  final n = closed ? points.length : points.length - 1;
  if (n < 1) return false;
  for (var i = 0; i < n; i++) {
    final a = points[i], b = points[(i + 1) % points.length];
    if (near(a, b)) return false;
    for (var j = i + 1; j < n; j++) {
      final c = points[j], d = points[(j + 1) % points.length];
      if (j == i + 1 || (closed && i == 0 && j == n - 1)) {
        // Adjacent segments may meet, but cannot double back.
        final shared = j == i + 1 ? b : a;
        final p = j == i + 1 ? a : b;
        final q = j == i + 1 ? d : c;
        if (onSegment(p, shared, q) || onSegment(q, shared, p)) return false;
      } else if (segmentsTouch(a, b, c, d)) {
        return false;
      }
    }
  }
  return !closed || polygonSignedArea(points).abs() > geometryEpsilon;
}

bool inRing(Offset p, List<Offset> ring, {bool boundary = true}) {
  var inside = false;
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i], b = ring[(i + 1) % ring.length];
    if (onSegment(p, a, b)) return boundary;
    if ((a.dy > p.dy) != (b.dy > p.dy) &&
        p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}

List<Offset> simplifyRing(List<Offset> points) {
  final out = List<Offset>.of(points);
  var changed = true;
  while (changed && out.length > 3) {
    changed = false;
    for (var i = 0; i < out.length; i++) {
      if (onSegment(
        out[i],
        out[(i + out.length - 1) % out.length],
        out[(i + 1) % out.length],
      )) {
        out.removeAt(i);
        changed = true;
        break;
      }
    }
  }
  return out;
}

class Region {
  Region(List<Offset> outer, [List<List<Offset>> holes = const []])
    : outer = List.unmodifiable(outer),
      holes = List.unmodifiable(holes.map((h) => List<Offset>.unmodifiable(h)));
  final List<Offset> outer;
  final List<List<Offset>> holes;
  Iterable<List<Offset>> get rings => [outer, ...holes];
  double get area =>
      polygonSignedArea(outer).abs() -
      holes.fold(0.0, (sum, h) => sum + polygonSignedArea(h).abs());
  double get perimeter => rings.fold(
    0.0,
    (sum, ring) =>
        sum +
        List.generate(
          ring.length,
          (i) => (ring[i] - ring[(i + 1) % ring.length]).distance,
        ).fold(0.0, (a, b) => a + b),
  );
  Rect get bounds => Rect.fromLTRB(
    outer.map((p) => p.dx).reduce(math.min),
    outer.map((p) => p.dy).reduce(math.min),
    outer.map((p) => p.dx).reduce(math.max),
    outer.map((p) => p.dy).reduce(math.max),
  );
  bool contains(Offset p, {bool boundary = true}) =>
      inRing(p, outer, boundary: boundary) &&
      !holes.any((h) => inRing(p, h, boundary: !boundary));
  bool get valid =>
      simplePath(outer, closed: true) &&
      area > geometryEpsilon &&
      holes.every(
        (h) =>
            simplePath(h, closed: true) &&
            h.every((p) => inRing(p, outer, boundary: false)),
      ) &&
      !_ringsCross(rings.toList());
  bool containsRegion(Region other) =>
      measure([this, other], (p) => other.contains(p) && !contains(p)) <
      geometryEpsilon;
  bool overlaps(Region other) =>
      measure([this, other], (p) => contains(p) && other.contains(p)) >
      geometryEpsilon;
  List<List<Offset>> get triangles {
    final result = <List<Offset>>[];
    for (final quad in slabs([this], contains)) {
      for (var i = 1; i < quad.length - 1; i++) {
        final t = [quad[0], quad[i], quad[i + 1]];
        if (polygonSignedArea(t).abs() > geometryEpsilon) result.add(t);
      }
    }
    return result;
  }

  /// Intersect against a union of surface fragments, retaining disconnected
  /// pieces and holes through the same boundary reconstruction as subtraction.
  List<Region> clipTo(List<Region> surfaces) => _regionsFromCells(
    slabs([
      this,
      ...surfaces,
    ], (p) => contains(p) && surfaces.any((r) => r.contains(p))),
  );

  List<Region> subtract(Region cut) {
    final cells = slabs([this, cut], (p) => contains(p) && !cut.contains(p));
    return _regionsFromCells(cells);
  }

  /// Material union: retain every cell covered by either input and cancel
  /// shared internal boundaries, preserving holes and disconnected results.
  List<Region> union(Region other) => _regionsFromCells(
    slabs([this, other], (p) => contains(p) || other.contains(p)),
  );

  static List<Region> _regionsFromCells(List<List<Offset>> cells) {
    if (cells.isEmpty) return [];
    final loops = _cellBoundaries(cells).map(simplifyRing).toList();
    final outers = loops
        .where(
          (r) => !loops.any(
            (s) =>
                !identical(r, s) &&
                polygonSignedArea(s).abs() > polygonSignedArea(r).abs() &&
                inRing(r.first, s, boundary: false),
          ),
        )
        .toList();
    return [
      for (final o in outers)
        Region(
          o,
          loops
              .where(
                (r) => !identical(r, o) && inRing(r.first, o, boundary: false),
              )
              .toList(),
        ),
    ];
  }

  Map<String, dynamic> toJson() => {
    'outer': encodePoints(outer),
    'holes': holes.map(encodePoints).toList(),
  };
  factory Region.fromJson(Map<String, dynamic> json) => Region(
    decodePoints(json['outer']),
    (json['holes'] as List).map(decodePoints).toList(),
  );
}

/// Slab cells have disjoint interiors and CCW winding. Split seams at all
/// T-junctions, then cancel opposing half-edges. Unlike centroid-classified
/// polygon union this also preserves disconnected components of equal area.
List<List<Offset>> _cellBoundaries(List<List<Offset>> cells) {
  String key(Offset p) => '${(p.dx * 1e7).round()},${(p.dy * 1e7).round()}';
  final boundary = <(String, String), (Offset, Offset)>{};
  for (final e in splitAllAtIntersections(cells.expand(edges).toList())) {
    final a = key(e.$1), b = key(e.$2);
    if (a == b) continue;
    if (boundary.containsKey((b, a))) {
      boundary.remove((b, a));
    } else {
      boundary[(a, b)] = e;
    }
  }
  final result = <List<Offset>>[];
  while (boundary.isNotEmpty) {
    final first = boundary.entries.first;
    var current = first.key;
    final ring = <Offset>[];
    while (true) {
      final segment = boundary.remove(current);
      if (segment == null) throw StateError('Unclosed polygon boundary');
      ring.add(segment.$1);
      if (current.$2 == first.key.$1) break;
      final options = boundary.keys.where((k) => k.$1 == current.$2).toList();
      if (options.isEmpty) throw StateError('Unclosed polygon boundary');
      // At a point contact, follow the sharpest right turn to keep islands
      // separate rather than produce a self-touching ring.
      final incoming = segment.$2 - segment.$1;
      double angle((String, String) edge) {
        final e = boundary[edge]!;
        final d = e.$2 - e.$1;
        return math.atan2(
          cross(incoming, d),
          incoming.dx * d.dx + incoming.dy * d.dy,
        );
      }

      options.sort((a, b) => angle(a).compareTo(angle(b)));
      current = options.first;
    }
    if (ring.length >= 3) result.add(ring);
  }
  return result;
}

bool _ringsCross(List<List<Offset>> rings) {
  for (var i = 0; i < rings.length; i++) {
    for (var j = i + 1; j < rings.length; j++) {
      for (final a in edges(rings[i])) {
        for (final b in edges(rings[j])) {
          if (segmentsTouch(a.$1, a.$2, b.$1, b.$2)) return true;
        }
      }
      if (i > 0 &&
          (inRing(rings[i].first, rings[j]) ||
              inRing(rings[j].first, rings[i]))) {
        return true;
      }
    }
  }
  return false;
}

Iterable<(Offset, Offset)> edges(List<Offset> ring) sync* {
  for (var i = 0; i < ring.length; i++) {
    yield (ring[i], ring[(i + 1) % ring.length]);
  }
}

/// Vertical decomposition of a planar arrangement. Every vertex and crossing
/// defines a slab; membership is constant between its sorted boundary edges.
/// This handles concave regions and holes without bridging or triangle fans.
List<List<Offset>> slabs(List<Region> regions, bool Function(Offset) keep) {
  final segments = regions.expand((r) => r.rings).expand(edges).toList();
  final xs = segments.expand((e) => [e.$1.dx, e.$2.dx]).toList();
  for (var i = 0; i < segments.length; i++) {
    for (var j = i + 1; j < segments.length; j++) {
      final p = crossing(
        segments[i].$1,
        segments[i].$2,
        segments[j].$1,
        segments[j].$2,
      );
      if (p != null) xs.add(p.dx);
    }
  }
  xs.sort();
  final unique = <double>[];
  for (final x in xs) {
    if (unique.isEmpty || x - unique.last > geometryEpsilon) unique.add(x);
  }
  double yAt((Offset, Offset) e, double x) =>
      e.$1.dy + (e.$2.dy - e.$1.dy) * (x - e.$1.dx) / (e.$2.dx - e.$1.dx);
  final result = <List<Offset>>[];
  for (var i = 0; i + 1 < unique.length; i++) {
    final left = unique[i], right = unique[i + 1], mid = (left + right) / 2;
    final active =
        segments
            .where(
              (e) =>
                  math.min(e.$1.dx, e.$2.dx) < mid &&
                  math.max(e.$1.dx, e.$2.dx) > mid,
            )
            .toList()
          ..sort((a, b) => yAt(a, mid).compareTo(yAt(b, mid)));
    for (var j = 0; j + 1 < active.length; j++) {
      final bottom = active[j], top = active[j + 1];
      if (yAt(top, mid) - yAt(bottom, mid) < geometryEpsilon ||
          !keep(Offset(mid, (yAt(bottom, mid) + yAt(top, mid)) / 2))) {
        continue;
      }
      final quad = [
        Offset(left, yAt(bottom, left)),
        Offset(right, yAt(bottom, right)),
        Offset(right, yAt(top, right)),
        Offset(left, yAt(top, left)),
      ];
      final clean = <Offset>[];
      for (final p in quad) {
        if (clean.isEmpty || !near(clean.last, p)) clean.add(p);
      }
      if (clean.length > 2 && near(clean.first, clean.last)) clean.removeLast();
      if (clean.length >= 3) result.add(clean);
    }
  }
  return result;
}

double measure(List<Region> regions, bool Function(Offset) keep) => slabs(
  regions,
  keep,
).fold(0.0, (sum, p) => sum + polygonSignedArea(p).abs());
List<List<double>> encodePoints(List<Offset> points) =>
    points.map((p) => [p.dx, p.dy]).toList();
List<Offset> decodePoints(dynamic json) => (json as List)
    .map((p) => Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()))
    .toList();

List<Offset> flattenCurve(Offset a, Offset control, Offset b) {
  final out = <Offset>[a];
  void visit(Offset p, Offset c, Offset q, int level) {
    final mid = (p + q) / 2;
    if ((c - mid).distance <= curveTolerance || level >= 12) {
      out.add(q);
      return;
    }
    final pc = (p + c) / 2, cq = (c + q) / 2;
    final center = (pc + cq) / 2;
    visit(p, pc, center, level + 1);
    visit(center, cq, q, level + 1);
  }

  visit(a, control, b, 0);
  return out;
}

/// Trim an open screen path with a closed cutout, or split it where an open
/// blade path crosses. Each returned path is a retained connected panel run.
List<List<Offset>>? cutPolyline(
  List<Offset> path,
  List<Offset> blade,
  bool closed, {
  bool keepInside = false,
}) {
  if (path.length < 2 || blade.length < 2) return null;
  final result = <List<Offset>>[];
  var current = <Offset>[];
  var changed = false;
  void flush() {
    if (current.length > 1) result.add(current);
    current = [];
  }

  for (var i = 1; i < path.length; i++) {
    final a = path[i - 1], b = path[i], d = b - a;
    final ts = <double>[0, 1];
    for (var j = 1; j < blade.length; j++) {
      final p = crossing(a, b, blade[j - 1], blade[j]);
      if (p != null) {
        final t = ((p - a).dx * d.dx + (p - a).dy * d.dy) / d.distanceSquared;
        if (t > geometryEpsilon && t < 1 - geometryEpsilon) ts.add(t);
      }
    }
    ts.sort();
    final unique = <double>[];
    for (final t in ts) {
      if (unique.isEmpty || t - unique.last > geometryEpsilon) unique.add(t);
    }
    for (var j = 1; j < unique.length; j++) {
      final start = a + d * unique[j - 1], end = a + d * unique[j];
      if (closed && inRing((start + end) / 2, blade) != keepInside) {
        changed = true;
        flush();
        continue;
      }
      if (current.isEmpty) current.add(start);
      if (!near(current.last, start)) {
        flush();
        current.add(start);
      }
      current.add(end);
      if (!closed && j < unique.length - 1) {
        changed = true;
        flush();
      }
    }
    if (!closed &&
        i < path.length - 1 &&
        List.generate(
          blade.length - 1,
          (j) => onSegment(b, blade[j], blade[j + 1]),
        ).any((v) => v)) {
      changed = true;
      flush();
    }
  }
  flush();
  return changed ? result : null;
}
