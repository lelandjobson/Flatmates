import 'dart:math' as math;
import 'dart:ui';

import '../geometry/geometry_algorithms.dart';

/// Widest the dynamic grid may appear: this many world units across the screen.
const double kDynamicMaxCellsAcross = 12;

/// Side of a tangram square, legs of a tangram triangle, diameter of a circle.
const double kTangramModule = 2;

/// Okabe–Ito colors, in order. Neighboring tangram pieces stay distinct.
const List<Color> kTangramPalette = [
  Color(0xFFE69F00),
  Color(0xFF56B4E9),
  Color(0xFF009E73),
  Color(0xFFF0E442),
  Color(0xFF0072B2),
  Color(0xFFD55E00),
  Color(0xFFCC79A7),
];

const double _eps = 1e-6;
const double _weld = 1e-4;

/// How finely an arc is sampled once its crossings are known.
const double _arcStep = math.pi / 12;

enum TangramKind { square, triangle, circle }

/// One shape the player places. Its boundary is what the dynamic grid repeats.
///
/// [anchor] is the bottom-left of the 2×2 footprint for a square or triangle,
/// and the center of a circle. [turns] is quarter-turns counter-clockwise
/// around that footprint's center. A circle ignores [turns].
class TangramPiece {
  const TangramPiece({
    required this.id,
    required this.kind,
    required this.anchor,
    required this.colorIndex,
    this.turns = 0,
  });

  final String id;
  final TangramKind kind;
  final Offset anchor;
  final int colorIndex;
  final int turns;

  Color get color => kTangramPalette[colorIndex % kTangramPalette.length];

  TangramPiece copyWith({Offset? anchor, int? turns, int? colorIndex}) {
    return TangramPiece(
      id: id,
      kind: kind,
      anchor: anchor ?? this.anchor,
      colorIndex: colorIndex ?? this.colorIndex,
      turns: turns ?? this.turns,
    );
  }
}

/// Translations that override the bounding-box period.
///
/// [horizontal] replaces the width axis, [vertical] replaces the height axis.
/// Either may be null, which keeps that side of the bounding box. A rotation
/// is added later and is not stored yet.
class DynamicTessellation {
  const DynamicTessellation({this.horizontal, this.vertical});

  final Offset? horizontal;
  final Offset? vertical;

  static const bbox = DynamicTessellation();

  bool get isBbox => horizontal == null && vertical == null;

  /// Applies one drawn stroke. The longer component picks the axis.
  DynamicTessellation withDrawn(Offset delta) {
    if (delta.distance < _eps) return this;
    if (delta.dx.abs() >= delta.dy.abs()) {
      return DynamicTessellation(horizontal: delta, vertical: vertical);
    }
    return DynamicTessellation(horizontal: horizontal, vertical: delta);
  }
}

/// How the tangram repeats. [u] steps across, [v] steps up.
class TangramLattice {
  const TangramLattice({
    required this.bounds,
    required this.u,
    required this.v,
  });

  final Rect bounds;
  final Offset u;
  final Offset v;

  double get _det => u.dx * v.dy - u.dy * v.dx;

  bool get valid =>
      bounds.width > _eps &&
      bounds.height > _eps &&
      u.distance > _eps &&
      v.distance > _eps &&
      _det.abs() > _eps;

  Offset shift(int i, int j) =>
      Offset(u.dx * i + v.dx * j, u.dy * i + v.dy * j);

  /// Cells whose box meets [region], including the source at (0, 0).
  List<(int, int)> cellsCovering(Rect region) {
    if (!valid) return const [];
    final det = _det;
    var iMin = 1 << 30;
    var iMax = -iMin;
    var jMin = iMin;
    var jMax = -iMin;
    final margin =
        math.max(u.distance, v.distance) +
        math.max(bounds.width, bounds.height);
    final pad = region.inflate(margin);
    final targets = [
      pad.topLeft,
      pad.topRight,
      pad.bottomRight,
      pad.bottomLeft,
    ];
    final sources = [bounds.topLeft, bounds.bottomRight];
    for (final target in targets) {
      for (final source in sources) {
        final d = target - source;
        final i = ((d.dx * v.dy - d.dy * v.dx) / det).floor();
        final j = ((u.dx * d.dy - u.dy * d.dx) / det).floor();
        iMin = math.min(iMin, i);
        iMax = math.max(iMax, i);
        jMin = math.min(jMin, j);
        jMax = math.max(jMax, j);
      }
    }
    iMin -= 1;
    iMax += 1;
    jMin -= 1;
    jMax += 1;
    const cap = 80;
    if (iMax - iMin > cap) {
      final mid = (iMin + iMax) ~/ 2;
      iMin = mid - cap ~/ 2;
      iMax = mid + cap ~/ 2;
    }
    if (jMax - jMin > cap) {
      final mid = (jMin + jMax) ~/ 2;
      jMin = mid - cap ~/ 2;
      jMax = mid + cap ~/ 2;
    }
    final cells = <(int, int)>[];
    for (var i = iMin; i <= iMax; i++) {
      for (var j = jMin; j <= jMax; j++) {
        final box = bounds.shift(shift(i, j));
        if (box.inflate(0.05).overlaps(region.inflate(0.05))) {
          cells.add((i, j));
        }
      }
    }
    return cells;
  }
}

/// Bounding box of every tangram piece. Null when [pieces] is empty.
Rect? tangramBounds(Iterable<TangramPiece> pieces) {
  Rect? bounds;
  for (final piece in pieces) {
    final box = tangramPieceBounds(piece);
    bounds = bounds == null ? box : bounds.expandToInclude(box);
  }
  return bounds;
}

Rect tangramPieceBounds(TangramPiece piece) {
  if (piece.kind == TangramKind.circle) {
    return Rect.fromCircle(center: piece.anchor, radius: kTangramModule / 2);
  }
  final ring = tangramRing(piece);
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = -double.infinity;
  var maxY = -double.infinity;
  for (final point in ring) {
    minX = math.min(minX, point.dx);
    minY = math.min(minY, point.dy);
    maxX = math.max(maxX, point.dx);
    maxY = math.max(maxY, point.dy);
  }
  if (minX == double.infinity) return Rect.zero;
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

/// Period of [pieces]. Empty tangram has no lattice.
///
/// The default vectors are the bounding-box width and height. [tessellation]
/// replaces an axis when that stroke has been drawn. Parallel strokes fall
/// back to the bounding box so the grid does not collapse.
TangramLattice? tangramLattice(
  List<TangramPiece> pieces, {
  DynamicTessellation tessellation = DynamicTessellation.bbox,
}) {
  final bounds = tangramBounds(pieces);
  if (bounds == null || bounds.width < _eps || bounds.height < _eps) {
    return null;
  }
  var u = tessellation.horizontal ?? Offset(bounds.width, 0);
  var v = tessellation.vertical ?? Offset(0, bounds.height);
  if (u.distance < _eps) u = Offset(bounds.width, 0);
  if (v.distance < _eps) v = Offset(0, bounds.height);
  final lattice = TangramLattice(bounds: bounds, u: u, v: v);
  if (!lattice.valid) {
    return TangramLattice(
      bounds: bounds,
      u: Offset(bounds.width, 0),
      v: Offset(0, bounds.height),
    );
  }
  return lattice;
}

/// Filled ring for a square or triangle, in the same coordinates as [anchor].
///
/// A circle has no ring; its boundary is the circumference.
List<Offset> tangramRing(TangramPiece piece) {
  final origin = piece.anchor;
  final center = origin + const Offset(kTangramModule / 2, kTangramModule / 2);
  List<Offset> ring;
  switch (piece.kind) {
    case TangramKind.square:
      ring = [
        origin,
        origin + const Offset(kTangramModule, 0),
        origin + const Offset(kTangramModule, kTangramModule),
        origin + const Offset(0, kTangramModule),
      ];
    case TangramKind.triangle:
      ring = [
        origin,
        origin + const Offset(kTangramModule, 0),
        origin + const Offset(0, kTangramModule),
      ];
    case TangramKind.circle:
      return const [];
  }
  if (piece.kind == TangramKind.square || piece.turns % 4 == 0) return ring;
  return [for (final point in ring) _turnAround(point, center, piece.turns)];
}

Offset _turnAround(Offset point, Offset center, int turns) {
  var rel = point - center;
  for (var i = 0; i < turns % 4; i++) {
    rel = Offset(-rel.dy, rel.dx);
  }
  return center + rel;
}

/// Closest point on the dynamic grid to a finger, and how far it was.
class GridProjection {
  const GridProjection({
    required this.point,
    required this.distance,
    required this.link,
  });

  final Offset point;
  final double distance;
  final int link;
}

/// Walkable paths of one dynamic grid: vertices plus the links between them.
class DynamicGridGraph {
  const DynamicGridGraph({required this.vertices, required this.links});

  final List<Offset> vertices;

  /// Pairs of indexes into [vertices].
  final List<(int, int)> links;

  bool hasSegment(Offset a, Offset b, {double epsilon = 1e-3}) {
    for (final link in links) {
      final p = vertices[link.$1];
      final q = vertices[link.$2];
      final forward =
          (p - a).distance <= epsilon && (q - b).distance <= epsilon;
      final back = (p - b).distance <= epsilon && (q - a).distance <= epsilon;
      if (forward || back) return true;
    }
    return false;
  }

  bool containsPoint(Offset point, {double epsilon = 0.05}) {
    for (final vertex in vertices) {
      if ((vertex - point).distance <= epsilon) return true;
    }
    final hit = project(point);
    return hit != null && hit.distance <= epsilon;
  }

  GridProjection? project(Offset point) {
    GridProjection? best;
    for (var i = 0; i < links.length; i++) {
      final a = vertices[links[i].$1];
      final b = vertices[links[i].$2];
      final on = projectOntoSegment(point, a, b);
      final distance = (on - point).distance;
      if (best == null || distance < best.distance) {
        best = GridProjection(point: on, distance: distance, link: i);
      }
    }
    return best;
  }
}

/// Dynamic grid covering [cover]. No pieces means no paths.
///
/// The tangram boundary is copied by [tessellation], or by its bounding box
/// when that is still the period.
DynamicGridGraph buildDynamicGrid({
  List<TangramPiece> pieces = const [],
  DynamicTessellation tessellation = DynamicTessellation.bbox,
  Rect? cover,
}) {
  final lattice = tangramLattice(pieces, tessellation: tessellation);
  if (lattice == null) {
    return const DynamicGridGraph(vertices: [], links: []);
  }
  final region = cover ?? lattice.bounds;
  final curves = [for (final piece in pieces) ..._pieceCurves(piece)];
  final segs = <_Seg>[];
  final arcs = <_Arc>[];
  for (final cell in lattice.cellsCovering(region)) {
    final shift = lattice.shift(cell.$1, cell.$2);
    for (final curve in curves) {
      if (curve is _Seg) {
        segs.add(_Seg(curve.a + shift, curve.b + shift));
      } else if (curve is _Arc) {
        arcs.add(
          _Arc(curve.center + shift, curve.radius, curve.start, curve.sweep),
        );
      }
    }
  }
  return _weldCurves(_split(segs, arcs));
}

class _Seg {
  const _Seg(this.a, this.b);
  final Offset a;
  final Offset b;
}

class _Arc {
  const _Arc(this.center, this.radius, this.start, this.sweep);
  final Offset center;
  final double radius;
  final double start;
  final double sweep;
}

List<Object> _pieceCurves(TangramPiece piece) {
  if (piece.kind == TangramKind.circle) {
    return [_Arc(piece.anchor, kTangramModule / 2, 0, math.pi * 2)];
  }
  final ring = tangramRing(piece);
  return [
    for (var i = 0; i < ring.length; i++)
      _Seg(ring[i], ring[(i + 1) % ring.length]),
  ];
}

(List<_Seg>, List<_Arc>) _split(List<_Seg> segs, List<_Arc> arcs) {
  final splits = <List<double>>[
    for (final _ in segs) <double>[0, 1],
  ];
  final arcSplits = <List<double>>[
    for (final arc in arcs) <double>[arc.start, arc.start + arc.sweep],
  ];

  final segBuckets = _buckets(segs.length, (index) {
    final seg = segs[index];
    return Rect.fromPoints(seg.a, seg.b);
  });
  _eachPair(segBuckets, (i, j) {
    final hit = segmentIntersection(segs[i].a, segs[i].b, segs[j].a, segs[j].b);
    if (hit.isPoint && hit.point != null) {
      _addParam(splits[i], segs[i], hit.point!);
      _addParam(splits[j], segs[j], hit.point!);
    } else if (hit.isCollinear) {
      if (hit.segmentStart != null) {
        _addParam(splits[i], segs[i], hit.segmentStart!);
        _addParam(splits[j], segs[j], hit.segmentStart!);
      }
      if (hit.segmentEnd != null) {
        _addParam(splits[i], segs[i], hit.segmentEnd!);
        _addParam(splits[j], segs[j], hit.segmentEnd!);
      }
    }
  });

  for (var k = 0; k < arcs.length; k++) {
    final arc = arcs[k];
    final box = Rect.fromCircle(center: arc.center, radius: arc.radius);
    for (final i in _bucketHits(segBuckets, box)) {
      for (final point in circleSegmentHits(
        arc.center,
        arc.radius,
        segs[i].a,
        segs[i].b,
      )) {
        final onArc = _angleInto(arc, _angle(arc.center, point));
        if (onArc == null) continue;
        _addParam(splits[i], segs[i], point);
        arcSplits[k].add(onArc);
      }
    }
  }

  final arcBuckets = _buckets(arcs.length, (index) {
    final arc = arcs[index];
    return Rect.fromCircle(center: arc.center, radius: arc.radius);
  });
  _eachPair(arcBuckets, (i, j) {
    for (final point in circleCircleHits(
      arcs[i].center,
      arcs[i].radius,
      arcs[j].center,
      arcs[j].radius,
    )) {
      final onI = _angleInto(arcs[i], _angle(arcs[i].center, point));
      final onJ = _angleInto(arcs[j], _angle(arcs[j].center, point));
      if (onI == null || onJ == null) continue;
      arcSplits[i].add(onI);
      arcSplits[j].add(onJ);
    }
  });

  final out = <_Seg>[];
  for (var i = 0; i < segs.length; i++) {
    final ts = _uniqueSorted(splits[i]);
    for (var t = 0; t < ts.length - 1; t++) {
      if (ts[t + 1] - ts[t] < 1e-5) continue;
      out.add(_Seg(_at(segs[i], ts[t]), _at(segs[i], ts[t + 1])));
    }
  }
  final outArcs = <_Arc>[];
  for (var i = 0; i < arcs.length; i++) {
    final angles = _uniqueSorted(arcSplits[i]);
    for (var a = 0; a < angles.length - 1; a++) {
      final sweep = angles[a + 1] - angles[a];
      if (sweep < 1e-5) continue;
      outArcs.add(_Arc(arcs[i].center, arcs[i].radius, angles[a], sweep));
    }
  }
  for (final arc in outArcs) {
    final samples = sampleArc(arc.center, arc.radius, arc.start, arc.sweep);
    for (var i = 0; i < samples.length - 1; i++) {
      out.add(_Seg(samples[i], samples[i + 1]));
    }
  }
  return (out, const []);
}

const double _bucket = 2;

Map<int, List<int>> _buckets(int count, Rect Function(int index) boxOf) {
  final buckets = <int, List<int>>{};
  for (var i = 0; i < count; i++) {
    final box = boxOf(i);
    final x0 = (box.left / _bucket).floor();
    final x1 = (box.right / _bucket).floor();
    final y0 = (box.top / _bucket).floor();
    final y1 = (box.bottom / _bucket).floor();
    for (var x = x0; x <= x1; x++) {
      for (var y = y0; y <= y1; y++) {
        (buckets[_bucketKey(x, y)] ??= <int>[]).add(i);
      }
    }
  }
  return buckets;
}

int _bucketKey(int x, int y) => (x + 4096) * 8192 + (y + 4096);

void _eachPair(Map<int, List<int>> buckets, void Function(int i, int j) visit) {
  final seen = <int>{};
  for (final ids in buckets.values) {
    for (var a = 0; a < ids.length; a++) {
      for (var b = a + 1; b < ids.length; b++) {
        final i = math.min(ids[a], ids[b]);
        final j = math.max(ids[a], ids[b]);
        if (!seen.add(i * 1000003 + j)) continue;
        visit(i, j);
      }
    }
  }
}

List<int> _bucketHits(Map<int, List<int>> buckets, Rect box) {
  final hits = <int>{};
  final x0 = (box.left / _bucket).floor();
  final x1 = (box.right / _bucket).floor();
  final y0 = (box.top / _bucket).floor();
  final y1 = (box.bottom / _bucket).floor();
  for (var x = x0; x <= x1; x++) {
    for (var y = y0; y <= y1; y++) {
      final ids = buckets[_bucketKey(x, y)];
      if (ids != null) hits.addAll(ids);
    }
  }
  return hits.toList();
}

void _addParam(List<double> splits, _Seg seg, Offset point) {
  final t = parameterOn(seg.a, seg.b, point);
  if (t < -1e-4 || t > 1 + 1e-4) return;
  splits.add(t.clamp(0.0, 1.0));
}

List<double> _uniqueSorted(List<double> values) {
  final sorted = List<double>.of(values)..sort();
  final out = <double>[];
  for (final value in sorted) {
    if (out.isEmpty || (value - out.last).abs() > 1e-5) out.add(value);
  }
  return out;
}

Offset _at(_Seg seg, double t) {
  return Offset(
    seg.a.dx + (seg.b.dx - seg.a.dx) * t,
    seg.a.dy + (seg.b.dy - seg.a.dy) * t,
  );
}

DynamicGridGraph _weldCurves((List<_Seg>, List<_Arc>) curves) {
  final vertices = <Offset>[];
  final index = <String, int>{};
  final links = <(int, int)>[];
  final seen = <String>{};

  int idOf(Offset point) {
    final key = '${(point.dx / _weld).round()},${(point.dy / _weld).round()}';
    return index.putIfAbsent(key, () {
      vertices.add(point);
      return vertices.length - 1;
    });
  }

  for (final seg in curves.$1) {
    if ((seg.a - seg.b).distance < _weld) continue;
    final a = idOf(seg.a);
    final b = idOf(seg.b);
    if (a == b) continue;
    final lo = math.min(a, b);
    final hi = math.max(a, b);
    final key = '$lo:$hi';
    if (!seen.add(key)) continue;
    links.add((a, b));
  }
  return DynamicGridGraph(vertices: vertices, links: links);
}

double _angle(Offset center, Offset point) {
  return math.atan2(point.dy - center.dy, point.dx - center.dx);
}

double? _angleInto(_Arc arc, double angle) {
  var sweep = angle - arc.start;
  final tau = math.pi * 2;
  while (sweep < -1e-6) {
    sweep += tau;
  }
  while (sweep >= tau) {
    sweep -= tau;
  }
  if (arc.sweep >= tau - 1e-4) return arc.start + sweep;
  if (sweep <= arc.sweep + 1e-4) return arc.start + sweep.clamp(0.0, arc.sweep);
  return null;
}

Offset _onCircle(Offset center, double radius, double angle) {
  return Offset(
    center.dx + radius * math.cos(angle),
    center.dy + radius * math.sin(angle),
  );
}

/// Samples [start] → [start] + [sweep], keeping both ends.
List<Offset> sampleArc(
  Offset center,
  double radius,
  double start,
  double sweep,
) {
  final steps = math.max(1, (sweep.abs() / _arcStep).ceil());
  return [
    for (var i = 0; i <= steps; i++)
      _onCircle(center, radius, start + sweep * i / steps),
  ];
}

/// Circle-segment hits. [t] along the segment stays in [0, 1].
List<Offset> circleSegmentHits(
  Offset center,
  double radius,
  Offset a,
  Offset b,
) {
  final d = b - a;
  final f = a - center;
  final aCoef = d.dx * d.dx + d.dy * d.dy;
  if (aCoef < _eps) return const [];
  final bCoef = 2 * (f.dx * d.dx + f.dy * d.dy);
  final cCoef = f.dx * f.dx + f.dy * f.dy - radius * radius;
  final disc = bCoef * bCoef - 4 * aCoef * cCoef;
  if (disc < -1e-8) return const [];
  final root = disc <= 0 ? 0.0 : math.sqrt(disc);
  final hits = <Offset>[];
  for (final sign in const [-1.0, 1.0]) {
    if (disc <= 0 && sign > 0) break;
    final t = (-bCoef + sign * root) / (2 * aCoef);
    if (t < -1e-5 || t > 1 + 1e-5) continue;
    final clamped = t.clamp(0.0, 1.0);
    hits.add(Offset(a.dx + d.dx * clamped, a.dy + d.dy * clamped));
  }
  return hits;
}

/// Up to two intersections of two circles.
List<Offset> circleCircleHits(Offset c0, double r0, Offset c1, double r1) {
  final d = c1 - c0;
  final dist = d.distance;
  if (dist < _eps) return const [];
  if (dist > r0 + r1 + 1e-6) return const [];
  if (dist < (r0 - r1).abs() - 1e-6) return const [];
  final a = (r0 * r0 - r1 * r1 + dist * dist) / (2 * dist);
  final h2 = r0 * r0 - a * a;
  final h = h2 <= 0 ? 0.0 : math.sqrt(h2);
  final base = Offset(c0.dx + d.dx * a / dist, c0.dy + d.dy * a / dist);
  final perp = Offset(-d.dy / dist, d.dx / dist);
  if (h < 1e-6) return [base];
  return [base + perp * h, base - perp * h];
}

double parameterOn(Offset a, Offset b, Offset point) {
  final d = b - a;
  final len2 = d.dx * d.dx + d.dy * d.dy;
  if (len2 < _eps) return 0;
  return ((point.dx - a.dx) * d.dx + (point.dy - a.dy) * d.dy) / len2;
}

Offset projectOntoSegment(Offset point, Offset a, Offset b) {
  final t = parameterOn(a, b, point).clamp(0.0, 1.0);
  return Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
}

/// True when [point] lies in [piece] or in one of its lattice copies.
bool hitsTangram(TangramPiece piece, Offset point, TangramLattice lattice) {
  if (!lattice.valid) return _hitsLocal(piece, point);
  final delta = point - piece.anchor;
  final det = lattice._det;
  final iEst = (delta.dx * lattice.v.dy - delta.dy * lattice.v.dx) / det;
  final jEst = (lattice.u.dx * delta.dy - lattice.u.dy * delta.dx) / det;
  final span = math.max(lattice.u.distance, lattice.v.distance);
  final reach = span < _eps ? 1 : (kTangramModule / span).ceil() + 1;
  final i0 = iEst.round();
  final j0 = jEst.round();
  for (var i = i0 - reach; i <= i0 + reach; i++) {
    for (var j = j0 - reach; j <= j0 + reach; j++) {
      if (_hitsLocal(piece, point - lattice.shift(i, j))) return true;
    }
  }
  return false;
}

bool _hitsLocal(TangramPiece piece, Offset point) {
  if (piece.kind == TangramKind.circle) {
    return (point - piece.anchor).distance <= kTangramModule / 2 + 1e-3;
  }
  final ring = tangramRing(piece);
  if (_ringDistance(point, ring) <= 1e-3) return true;
  return _insideRing(point, ring);
}

bool _insideRing(Offset point, List<Offset> ring) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final pi = ring[i];
    final pj = ring[j];
    final crosses = (pi.dy > point.dy) != (pj.dy > point.dy);
    if (!crosses) continue;
    final x = (pj.dx - pi.dx) * (point.dy - pi.dy) / (pj.dy - pi.dy) + pi.dx;
    if (point.dx < x) inside = !inside;
  }
  return inside;
}

double _ringDistance(Offset point, List<Offset> ring) {
  var best = double.infinity;
  for (var i = 0; i < ring.length; i++) {
    final on = projectOntoSegment(point, ring[i], ring[(i + 1) % ring.length]);
    best = math.min(best, (on - point).distance);
  }
  return best;
}
