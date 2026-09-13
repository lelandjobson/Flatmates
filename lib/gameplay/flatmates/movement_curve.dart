import 'dart:math' as math;
import 'dart:ui';

import '../../geometry/curves_2d.dart';
import '../paths/path_shape.dart';
import '../paths/path_store.dart';
import '../volumes/volume.dart';
import '../volumes/volume_store.dart';
import 'movement_profile.dart';

const double _eps = 1e-9;

/// Half the 4-subtile path corridor, in world units.
double movementPathHalfWidth(VolumeGrid grid) =>
    (kPathWidthSubtiles / 2) * grid.subtileSize;

/// Facing-right in XZ when [tangent] is (x, z): person facing along, Y-up.
Offset movementFacingRight(Offset tangent) {
  final len = tangent.distance;
  if (len < _eps) return const Offset(0, 1);
  final nx = tangent.dx / len;
  final nz = tangent.dy / len;
  return Offset(-nz, nx);
}

/// One stride / corner sample on the median, after offset and jank.
class MovementKnot {
  const MovementKnot({
    required this.median,
    required this.position,
    required this.tangent,
    required this.isCorner,
  });

  final Offset median;
  final Offset position;
  final Offset tangent;
  final bool isCorner;
}

/// Built walk curve: median → stride knots → right offset → jank → smooth.
class MovementCurve {
  MovementCurve({
    required this.tiles,
    required this.profile,
    required this.tileSize,
    required this.medianPoints,
    required this.knots,
    required this.points,
    required this.strideDistances,
    required this.distances,
    required this.tangents,
    required this.curvatures,
    required this.tileDistances,
  });

  final List<(int, int)> tiles;
  final MovementProfile profile;
  final double tileSize;
  final List<Offset> medianPoints;
  final List<MovementKnot> knots;
  final List<Offset> points;
  final List<double> strideDistances;
  final List<double> distances;
  final List<Offset> tangents;
  final List<double> curvatures;

  /// Arc-length station for each route tile, including the closing duplicate.
  final List<double> tileDistances;

  double get totalLength => distances.isEmpty ? 0 : distances.last;

  bool get isClosed =>
      tiles.length >= 3 && tiles.first == tiles.last && totalLength > _eps;

  Offset pointAtDistance(double distance) =>
      _lerpAxis(points, distances, distance, (p) => p);

  Offset tangentAtDistance(double distance) {
    final t = _lerpAxis(tangents, distances, distance, (p) => p);
    final len = t.distance;
    return len < _eps ? const Offset(1, 0) : t / len;
  }

  double curvatureAtDistance(double distance) =>
      _lerpScalar(curvatures, distances, distance);

  /// `1` on a straight, down to `1 - bendSlowdown` at a sharp 90° corner.
  double speedMultiplierAtDistance(double distance) {
    final kappa = curvatureAtDistance(distance);
    final ref = (math.pi / 2) / math.max(tileSize * 0.4, _eps);
    final u = (kappa / ref).clamp(0.0, 1.0);
    final s = u * u * (3 - 2 * u);
    return 1 - profile.bendSlowdown * s;
  }

  (int index, double frac) strideAtDistance(double distance) {
    if (strideDistances.length < 2) return (0, 0);
    final d = _wrap(distance);
    var i = 0;
    while (i < strideDistances.length - 2 && d > strideDistances[i + 1]) {
      i++;
    }
    final a = strideDistances[i];
    final b = strideDistances[i + 1];
    final span = b - a;
    final frac = span < _eps ? 1.0 : ((d - a) / span).clamp(0.0, 1.0);
    return (i, frac);
  }

  double hopHeightAtDistance(double distance, double bodySize) {
    if (profile.hopHeight <= _eps || bodySize <= _eps) return 0;
    final frac = strideAtDistance(distance).$2;
    return math.sin(math.pi * frac) * profile.hopHeight * bodySize;
  }

  (int, int) tileAtDistance(double distance) {
    if (tiles.isEmpty) return (0, 0);
    if (tiles.length == 1) return tiles.first;
    final t = totalLength < _eps
        ? 0.0
        : (_wrap(distance) / totalLength).clamp(0.0, 1.0);
    final max = tiles.length - 1;
    final i = (t * max).floor().clamp(0, max);
    return tiles[i];
  }

  double facingYawAtDistance(double distance) {
    final t = tangentAtDistance(distance);
    if (t.dx.abs() < _eps && t.dy.abs() < _eps) return 0;
    return math.atan2(t.dx, t.dy);
  }

  /// Next route-tile station strictly ahead of [distance].
  ///
  /// If [distance] is already on a station, returns the tile after it. On a
  /// closed loop with [loop], wraps to the tile after the start.
  double nextTileStopDistance(double distance, {required bool loop}) {
    if (tileDistances.length < 2 || totalLength < _eps) return totalLength;
    final d = isClosed ? _wrap(distance) : distance.clamp(0.0, totalLength);
    const gap = 1e-4;
    for (final station in tileDistances) {
      if (station > d + gap) return station;
    }
    if (loop && isClosed && tileDistances.length >= 2) {
      return tileDistances[1];
    }
    return tileDistances.last;
  }

  double _wrap(double distance) {
    if (totalLength < _eps) return 0;
    if (!isClosed) return distance.clamp(0.0, totalLength);
    var d = distance % totalLength;
    if (d < 0) d += totalLength;
    return d;
  }
}

/// Median tile centers → stride knots → offset → jank → smoothness → clamp.
MovementCurve buildMovementCurve({
  required List<(int, int)> tiles,
  required VolumeGrid grid,
  required MovementProfile profile,
  PathStore? paths,
  String seed = '',
}) {
  final clamped = profile.clamped();
  if (tiles.isEmpty) {
    return MovementCurve(
      tiles: const [],
      profile: clamped,
      tileSize: grid.tileSize,
      medianPoints: const [],
      knots: const [],
      points: const [],
      strideDistances: const [],
      distances: const [],
      tangents: const [],
      curvatures: const [],
      tileDistances: const [],
    );
  }

  final closed = tiles.length >= 3 && tiles.first == tiles.last;
  final unique = closed ? tiles.sublist(0, tiles.length - 1) : tiles;
  final median = [
    for (final tile in unique)
      Offset(
        grid.tileCenter(tile.$1, tile.$2).x,
        grid.tileCenter(tile.$1, tile.$2).z,
      ),
  ];
  if (median.length == 1) {
    final p = median.first;
    return MovementCurve(
      tiles: List<(int, int)>.from(tiles),
      profile: clamped,
      tileSize: grid.tileSize,
      medianPoints: median,
      knots: [
        MovementKnot(
          median: p,
          position: p,
          tangent: const Offset(1, 0),
          isCorner: false,
        ),
      ],
      points: [p],
      strideDistances: const [0],
      distances: const [0],
      tangents: const [Offset(1, 0)],
      curvatures: const [0],
      tileDistances: const [0],
    );
  }

  final cum = _medianCumulative(median, closed: closed);
  final knots = _sampleKnots(
    median: median,
    cum: cum,
    closed: closed,
    stride: clamped.movementTileRatio * grid.tileSize,
  );
  final halfW = movementPathHalfWidth(grid);
  final offsetKnots = <MovementKnot>[];
  for (var i = 0; i < knots.length; i++) {
    offsetKnots.add(
      _offsetKnot(
        knots[i],
        profile: clamped,
        halfWidth: halfW,
        seed: seed,
        index: i,
      ),
    );
  }

  var points = _smoothKnots(
    offsetKnots,
    smoothness: clamped.smoothness,
    tileSize: grid.tileSize,
    closed: closed,
  );
  final bounds = paths == null
      ? PathBounds.virtualCorridor(median, halfW, closed: closed)
      : PathBounds.fromPaths(grid, paths);
  points = [for (final p in points) bounds.clampPoint(p)];
  if (closed && points.length >= 2 && (points.last - points.first).distance > 1e-4) {
    points = [...points, points.first];
  }

  final distances = _cumulative(points);
  final tangents = _tangentsAtVertices(points);
  final curvatures = _curvaturesAtVertices(points);
  final poly = Polyline2D(points);
  final strideDistances = <double>[];
  for (final knot in offsetKnots) {
    final d = poly.isValid
        ? poly.closestParameter(knot.position) * poly.totalLength
        : 0.0;
    if (strideDistances.isEmpty || (d - strideDistances.last).abs() > 1e-4) {
      strideDistances.add(d);
    }
  }
  if (strideDistances.isEmpty) {
    strideDistances.add(0);
  }
  if (distances.isNotEmpty &&
      (strideDistances.last - distances.last).abs() > 1e-4) {
    strideDistances.add(distances.last);
  }

  return MovementCurve(
    tiles: List<(int, int)>.from(tiles),
    profile: clamped,
    tileSize: grid.tileSize,
    medianPoints: median,
    knots: offsetKnots,
    points: points,
    strideDistances: strideDistances,
    distances: distances,
    tangents: tangents,
    curvatures: curvatures,
    tileDistances: _tileStations(
      tiles: tiles,
      medianPoints: median,
      points: points,
      distances: distances,
      closed: closed,
    ),
  );
}

List<double> _tileStations({
  required List<(int, int)> tiles,
  required List<Offset> medianPoints,
  required List<Offset> points,
  required List<double> distances,
  required bool closed,
}) {
  if (tiles.isEmpty || points.isEmpty || distances.isEmpty) return const [];
  final stations = <double>[];
  var minD = 0.0;
  for (var i = 0; i < tiles.length; i++) {
    if (i == 0) {
      stations.add(0);
      continue;
    }
    if (i == tiles.length - 1) {
      stations.add(distances.last);
      break;
    }
    final target =
        i < medianPoints.length ? medianPoints[i] : medianPoints.first;
    final d = _nearestDistanceFrom(points, distances, target, minD);
    stations.add(d);
    minD = d;
  }
  return stations;
}

double _nearestDistanceFrom(
  List<Offset> points,
  List<double> distances,
  Offset target,
  double minDistance,
) {
  var bestD = minDistance;
  var best = double.infinity;
  var found = false;
  for (var i = 0; i < points.length; i++) {
    if (distances[i] + 1e-6 < minDistance) continue;
    final err = (points[i] - target).distanceSquared;
    if (err < best) {
      best = err;
      bestD = distances[i];
      found = true;
    }
  }
  return found ? bestD : minDistance;
}

class _RawKnot {
  const _RawKnot({
    required this.median,
    required this.tangent,
    required this.isCorner,
  });

  final Offset median;
  final Offset tangent;
  final bool isCorner;
}

List<double> _medianCumulative(List<Offset> median, {required bool closed}) {
  final cum = <double>[0];
  for (var i = 0; i < median.length - 1; i++) {
    cum.add(cum.last + (median[i + 1] - median[i]).distance);
  }
  if (closed) {
    cum.add(cum.last + (median.first - median.last).distance);
  }
  return cum;
}

bool _isCornerVertex(List<Offset> median, int i, {required bool closed}) {
  final n = median.length;
  if (n < 3) return false;
  if (!closed && (i <= 0 || i >= n - 1)) return false;
  final prev = median[(i - 1 + n) % n];
  final curr = median[i];
  final next = median[(i + 1) % n];
  return _turns(prev, curr, next);
}

bool _turns(Offset a, Offset b, Offset c) {
  final inn = b - a;
  final out = c - b;
  final inLen = inn.distance;
  final outLen = out.distance;
  if (inLen < _eps || outLen < _eps) return false;
  final dot = (inn.dx * out.dx + inn.dy * out.dy) / (inLen * outLen);
  return dot < 0.85;
}

Offset _unit(Offset v) {
  final len = v.distance;
  if (len < _eps) return const Offset(1, 0);
  return v / len;
}

Offset _medianPoint(List<Offset> median, List<double> cum, double d) {
  if (d <= 0) return median.first;
  if (d >= cum.last) {
    return median.length + 1 == cum.length ? median.first : median.last;
  }
  for (var i = 0; i < cum.length - 1; i++) {
    if (d <= cum[i + 1]) {
      final a = median[i % median.length];
      final b = i + 1 >= median.length ? median.first : median[i + 1];
      final span = cum[i + 1] - cum[i];
      final t = span < _eps ? 0.0 : (d - cum[i]) / span;
      return Offset.lerp(a, b, t)!;
    }
  }
  return median.last;
}

Offset _medianTangent(List<Offset> median, List<double> cum, double d) {
  if (d <= 0) {
    return _unit(median[1] - median[0]);
  }
  for (var i = 0; i < cum.length - 1; i++) {
    if (d <= cum[i + 1] + _eps) {
      final a = median[i % median.length];
      final b = i + 1 >= median.length ? median.first : median[i + 1];
      return _unit(b - a);
    }
  }
  return _unit(median.last - median[median.length - 2]);
}

Offset _vertexTangent(List<Offset> median, int i, {required bool closed}) {
  final n = median.length;
  if (!closed && i <= 0) return _unit(median[1] - median[0]);
  if (!closed && i >= n - 1) return _unit(median.last - median[n - 2]);
  final prev = median[(i - 1 + n) % n];
  final curr = median[i];
  final next = median[(i + 1) % n];
  final inn = _unit(curr - prev);
  final out = _unit(next - curr);
  final sum = inn + out;
  if (sum.distance < _eps) return inn;
  return _unit(sum);
}

List<_RawKnot> _sampleKnots({
  required List<Offset> median,
  required List<double> cum,
  required bool closed,
  required double stride,
}) {
  final n = median.length;
  final vertexDist = <double>[
    for (var i = 0; i < n; i++) cum[i],
  ];
  final loopLen = cum.last;
  final mandatory = <double>{0};
  if (!closed) mandatory.add(loopLen);
  for (var i = 0; i < n; i++) {
    if (_isCornerVertex(median, i, closed: closed)) {
      mandatory.add(vertexDist[i]);
    }
  }
  if (closed) mandatory.add(loopLen);

  final ordered = mandatory.toList()..sort();
  final knots = <_RawKnot>[];

  void addAt(double d, {required bool isCorner}) {
    if (knots.isNotEmpty &&
        (d - _distanceOf(knots.last.median, median, cum)).abs() < 1e-6) {
      return;
    }
    Offset tangent;
    var corner = isCorner;
    for (var i = 0; i < n; i++) {
      if ((vertexDist[i] - d).abs() < 1e-6) {
        tangent = _vertexTangent(median, i, closed: closed);
        corner = corner || _isCornerVertex(median, i, closed: closed);
        knots.add(
          _RawKnot(
            median: median[i],
            tangent: tangent,
            isCorner: corner && (closed || (i != 0 && i != n - 1)),
          ),
        );
        return;
      }
    }
    knots.add(
      _RawKnot(
        median: _medianPoint(median, cum, d),
        tangent: _medianTangent(median, cum, d),
        isCorner: false,
      ),
    );
  }

  for (var m = 0; m < ordered.length; m++) {
    final dist = ordered[m];
    if (m > 0 && stride > _eps) {
      final prev = ordered[m - 1];
      var d = prev + stride;
      while (d < dist - stride * 0.25) {
        addAt(d, isCorner: false);
        d += stride;
      }
    }
    final isEnd = !closed && (dist - loopLen).abs() < 1e-6;
    final isStart = dist.abs() < 1e-6;
    addAt(dist, isCorner: !isStart && !isEnd);
  }

  if (knots.length < 2) {
    knots
      ..clear()
      ..add(
        _RawKnot(
          median: median.first,
          tangent: _unit(median[1] - median[0]),
          isCorner: false,
        ),
      )
      ..add(
        _RawKnot(
          median: closed ? median.first : median.last,
          tangent: _medianTangent(median, cum, loopLen),
          isCorner: false,
        ),
      );
  }
  if (closed &&
      knots.length >= 2 &&
      (knots.last.median - knots.first.median).distance < 1e-4) {
    knots.removeLast();
  }
  return knots;
}

double _distanceOf(Offset p, List<Offset> median, List<double> cum) {
  var best = 0.0;
  var bestD = double.infinity;
  for (var i = 0; i < cum.length - 1; i++) {
    final a = median[i % median.length];
    final b = i + 1 >= median.length ? median.first : median[i + 1];
    final ab = b - a;
    final ap = p - a;
    final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    final t = lenSq < _eps
        ? 0.0
        : ((ap.dx * ab.dx + ap.dy * ab.dy) / lenSq).clamp(0.0, 1.0);
    final c = Offset.lerp(a, b, t)!;
    final d = (c - p).distanceSquared;
    if (d < bestD) {
      bestD = d;
      best = cum[i] + t * (cum[i + 1] - cum[i]);
    }
  }
  return best;
}

MovementKnot _offsetKnot(
  _RawKnot knot, {
  required MovementProfile profile,
  required double halfWidth,
  required String seed,
  required int index,
}) {
  final right = movementFacingRight(knot.tangent);
  var lateral = profile.offset * halfWidth;
  final remaining = math.max(0.0, halfWidth - lateral.abs());
  if (profile.jank > _eps) {
    final hash = Object.hash(seed, index, profile.id);
    final roll = (hash & 0xffff) / 0xffff;
    if (roll < profile.jank) {
      final sign = (hash & 0x10000) == 0 ? 1.0 : -1.0;
      final mag = ((hash >> 17) & 0xff) / 255.0;
      lateral += sign * mag * profile.jankIntensity * remaining;
    }
  }
  lateral = lateral.clamp(-halfWidth, halfWidth);
  return MovementKnot(
    median: knot.median,
    position: knot.median + right * lateral,
    tangent: knot.tangent,
    isCorner: knot.isCorner,
  );
}

List<Offset> _smoothKnots(
  List<MovementKnot> knots, {
  required double smoothness,
  required double tileSize,
  bool closed = false,
}) {
  if (knots.isEmpty) return const [];
  if (knots.length == 1) return [knots.first.position];
  final ring = closed && knots.length >= 3;
  if (smoothness <= _eps) {
    final poly = [for (final k in knots) k.position];
    if (ring && (poly.last - poly.first).distance > 1e-4) {
      poly.add(poly.first);
    }
    return poly;
  }

  final expanded = <Offset>[];
  for (var i = 0; i < knots.length; i++) {
    final k = knots[i];
    final endCap = !ring && (i == 0 || i == knots.length - 1);
    if (!k.isCorner || endCap) {
      expanded.add(k.position);
      continue;
    }
    final prev = knots[(i - 1 + knots.length) % knots.length].position;
    final next = knots[(i + 1) % knots.length].position;
    expanded.addAll(
      _fillet(prev, k.position, next, smoothness: smoothness, tileSize: tileSize),
    );
  }
  if (ring && expanded.isNotEmpty && (expanded.last - expanded.first).distance > 1e-4) {
    expanded.add(expanded.first);
  }

  if (expanded.length < 3) return expanded;
  return _catmullDensify(expanded, smoothness);
}

List<Offset> _fillet(
  Offset prev,
  Offset corner,
  Offset next, {
  required double smoothness,
  required double tileSize,
}) {
  final incoming = corner - prev;
  final outgoing = next - corner;
  final inLen = incoming.distance;
  final outLen = outgoing.distance;
  if (inLen < 1e-4 || outLen < 1e-4) return [corner];
  final u = incoming / inLen;
  final v = outgoing / outLen;
  final maxR = math.min(inLen, outLen) * 0.45;
  final r = smoothness * math.min(maxR, tileSize * 0.45);
  if (r < 1e-4) return [corner];

  final start = corner - u * r;
  final end = corner + v * r;
  final cross = u.dx * v.dy - u.dy * v.dx;
  if (cross.abs() < _eps) return [start, end];
  final sign = cross >= 0 ? 1.0 : -1.0;
  final perp = Offset(-u.dy, u.dx) * sign;
  final center = start + perp * r;
  final startAngle = math.atan2(start.dy - center.dy, start.dx - center.dx);
  final endAngle = math.atan2(end.dy - center.dy, end.dx - center.dx);
  var sweep = endAngle - startAngle;
  if (sign > 0 && sweep < 0) sweep += 2 * math.pi;
  if (sign < 0 && sweep > 0) sweep -= 2 * math.pi;
  final steps = math.max(4, (sweep.abs() / (math.pi / 10)).round());
  final out = <Offset>[start];
  for (var s = 1; s < steps; s++) {
    final t = s / steps;
    final ang = startAngle + sweep * t;
    out.add(
      Offset(center.dx + r * math.cos(ang), center.dy + r * math.sin(ang)),
    );
  }
  out.add(end);
  return out;
}

List<Offset> _catmullDensify(List<Offset> pts, double smoothness) {
  if (pts.length < 2) return List<Offset>.from(pts);
  final samples = (2 + (smoothness * 8).round()).clamp(2, 10);
  final out = <Offset>[pts.first];
  for (var i = 0; i < pts.length - 1; i++) {
    final p0 = pts[i == 0 ? 0 : i - 1];
    final p1 = pts[i];
    final p2 = pts[i + 1];
    final p3 = pts[i + 2 >= pts.length ? pts.length - 1 : i + 2];
    for (var s = 1; s <= samples; s++) {
      final t = s / samples;
      out.add(_catmullRom(p0, p1, p2, p3, t));
    }
  }
  return out;
}

Offset _catmullRom(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
  final t2 = t * t;
  final t3 = t2 * t;
  return Offset(
    0.5 *
        (2 * p1.dx +
            (-p0.dx + p2.dx) * t +
            (2 * p0.dx - 5 * p1.dx + 4 * p2.dx - p3.dx) * t2 +
            (-p0.dx + 3 * p1.dx - 3 * p2.dx + p3.dx) * t3),
    0.5 *
        (2 * p1.dy +
            (-p0.dy + p2.dy) * t +
            (2 * p0.dy - 5 * p1.dy + 4 * p2.dy - p3.dy) * t2 +
            (-p0.dy + 3 * p1.dy - 3 * p2.dy + p3.dy) * t3),
  );
}

List<double> _cumulative(List<Offset> points) {
  if (points.isEmpty) return const [];
  final out = <double>[0];
  for (var i = 0; i < points.length - 1; i++) {
    out.add(out.last + (points[i + 1] - points[i]).distance);
  }
  return out;
}

List<Offset> _tangentsAtVertices(List<Offset> points) {
  if (points.isEmpty) return const [];
  if (points.length == 1) return const [Offset(1, 0)];
  return [
    for (var i = 0; i < points.length; i++)
      i == points.length - 1
          ? _unit(points[i] - points[i - 1])
          : _unit(points[i + 1] - points[i]),
  ];
}

List<double> _curvaturesAtVertices(List<Offset> points) {
  if (points.length < 3) {
    return [for (var i = 0; i < points.length; i++) 0.0];
  }
  final out = <double>[0];
  for (var i = 1; i < points.length - 1; i++) {
    final inn = points[i] - points[i - 1];
    final outgoing = points[i + 1] - points[i];
    final inLen = inn.distance;
    final outLen = outgoing.distance;
    if (inLen < _eps || outLen < _eps) {
      out.add(0);
      continue;
    }
    final cross = inn.dx * outgoing.dy - inn.dy * outgoing.dx;
    final dot = inn.dx * outgoing.dx + inn.dy * outgoing.dy;
    final angle = math.atan2(cross.abs(), dot).abs();
    final avg = (inLen + outLen) * 0.5;
    out.add(avg < _eps ? 0.0 : angle / avg);
  }
  out.add(0);
  return out;
}

Offset _lerpAxis(
  List<Offset> values,
  List<double> distances,
  double distance,
  Offset Function(Offset) pick,
) {
  if (values.isEmpty) return Offset.zero;
  if (values.length == 1 || distances.length < 2) return pick(values.first);
  final end = distances.last;
  final d = end < _eps ? 0.0 : distance.clamp(0.0, end);
  for (var i = 0; i < distances.length - 1; i++) {
    if (d <= distances[i + 1]) {
      final span = distances[i + 1] - distances[i];
      final t = span < _eps ? 0.0 : (d - distances[i]) / span;
      return Offset.lerp(pick(values[i]), pick(values[i + 1]), t)!;
    }
  }
  return pick(values.last);
}

double _lerpScalar(List<double> values, List<double> distances, double distance) {
  if (values.isEmpty) return 0;
  if (values.length == 1 || distances.length < 2) return values.first;
  final end = distances.last;
  final d = end < _eps ? 0.0 : distance.clamp(0.0, end);
  for (var i = 0; i < distances.length - 1; i++) {
    if (d <= distances[i + 1]) {
      final span = distances[i + 1] - distances[i];
      final t = span < _eps ? 0.0 : (d - distances[i]) / span;
      return values[i] + (values[i + 1] - values[i]) * t;
    }
  }
  return values.last;
}

/// Axis-aligned walkable rects used to keep interpolated points on the path.
class PathBounds {
  PathBounds(this.rects);

  final List<Rect> rects;

  factory PathBounds.fromPaths(VolumeGrid grid, PathStore paths) {
    final volumes = VolumeStore(grid: grid);
    final byTile = pathFootprintsByTile(volumes: volumes, paths: paths);
    final s = grid.subtileSize;
    final rects = <Rect>[];
    for (final entry in byTile.entries) {
      final origin = grid.tileOrigin(entry.key.$1, entry.key.$2);
      for (final piece in entry.value) {
        final left = origin.x + piece.originXSubtiles * s;
        final top = origin.z + piece.originZSubtiles * s;
        rects.add(
          Rect.fromLTWH(
            left,
            top,
            piece.widthSubtiles * s,
            piece.depthSubtiles * s,
          ),
        );
      }
    }
    return PathBounds(rects);
  }

  factory PathBounds.virtualCorridor(
    List<Offset> median,
    double halfWidth, {
    bool closed = false,
  }) {
    if (median.length < 2) return PathBounds(const []);
    final rects = <Rect>[];
    void addSeg(Offset a, Offset b) {
      if ((a.dx - b.dx).abs() < 1e-6) {
        rects.add(
          Rect.fromLTRB(
            a.dx - halfWidth,
            math.min(a.dy, b.dy),
            a.dx + halfWidth,
            math.max(a.dy, b.dy),
          ),
        );
      } else if ((a.dy - b.dy).abs() < 1e-6) {
        rects.add(
          Rect.fromLTRB(
            math.min(a.dx, b.dx),
            a.dy - halfWidth,
            math.max(a.dx, b.dx),
            a.dy + halfWidth,
          ),
        );
      } else {
        final minX = math.min(a.dx, b.dx) - halfWidth;
        final maxX = math.max(a.dx, b.dx) + halfWidth;
        final minZ = math.min(a.dy, b.dy) - halfWidth;
        final maxZ = math.max(a.dy, b.dy) + halfWidth;
        rects.add(Rect.fromLTRB(minX, minZ, maxX, maxZ));
      }
    }

    for (var i = 0; i < median.length - 1; i++) {
      addSeg(median[i], median[i + 1]);
    }
    if (closed) addSeg(median.last, median.first);
    return PathBounds(rects);
  }

  bool contains(Offset p) {
    for (final r in rects) {
      if (_containsInclusive(r, p)) return true;
    }
    return false;
  }

  Offset clampPoint(Offset p) {
    if (rects.isEmpty || contains(p)) return p;
    Offset best = p;
    var bestD = double.infinity;
    for (final r in rects) {
      final c = Offset(p.dx.clamp(r.left, r.right), p.dy.clamp(r.top, r.bottom));
      final d = (c - p).distanceSquared;
      if (d < bestD) {
        bestD = d;
        best = c;
      }
    }
    return best;
  }

  static bool _containsInclusive(Rect r, Offset p) {
    return p.dx >= r.left - 1e-6 &&
        p.dx <= r.right + 1e-6 &&
        p.dy >= r.top - 1e-6 &&
        p.dy <= r.bottom + 1e-6;
  }
}
