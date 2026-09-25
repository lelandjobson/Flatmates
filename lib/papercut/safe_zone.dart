import 'dart:math' as math;
import 'dart:ui';

import '../geometry/geometry_algorithms.dart';
import 'paper.dart';

/// Half-width of the band on each side of a curve, in millimeters.
const double kPapercutLateralMm = 3;

/// End cap as a fraction of [kPapercutLateralMm]. Cuts stay tight at the tips.
const double kPapercutCutCapsuleFraction = 0.25;

/// Folds may stop about one full band-width short of the guide.
const double kPapercutFoldCapsuleFraction = 1;

/// A point is in the zone when it sits in the lateral band, or in the round
/// cap past an open end. Closed curves have no caps.
bool pointInSafeZone(
  Offset point,
  List<Offset> curve, {
  required bool closed,
  double lateralMm = kPapercutLateralMm,
  double capsuleFraction = kPapercutCutCapsuleFraction,
}) {
  if (curve.length < 2 || lateralMm < 0) return false;
  final path = closed ? [...curve, curve.first] : curve;
  final hit = closestPointOnPolyline(point, path);
  if (closed) return hit.distance <= lateralMm + 1e-6;

  final edge = hit.edgeIndex ?? 0;
  final atStart = edge == 0 && hit.parameter <= 1e-4;
  final atEnd = edge >= path.length - 2 && hit.parameter >= 1 - 1e-4;
  if (!atStart && !atEnd) return hit.distance <= lateralMm + 1e-6;

  final endpoint = atStart ? path.first : path.last;
  final outward = atStart
      ? path.first - path[1]
      : path.last - path[path.length - 2];
  if (outward.distance < 1e-6) return hit.distance <= lateralMm + 1e-6;
  final dir = outward / outward.distance;
  final delta = point - endpoint;
  final overrun = delta.dx * dir.dx + delta.dy * dir.dy;
  if (overrun <= 0) return hit.distance <= lateralMm + 1e-6;
  return hit.distance <= lateralMm * capsuleFraction + 1e-6;
}

/// True when [curve]'s zone meets [ring], or the curve crosses the ring.
bool safeZoneTouchesRing(
  List<Offset> curve,
  List<Offset> ring, {
  required bool curveClosed,
  double lateralMm = kPapercutLateralMm,
  double capsuleFraction = kPapercutCutCapsuleFraction,
}) {
  if (curve.length < 2 || ring.length < 3) return false;
  if (_polylinesCross(curve, ring)) return true;
  for (final sample in _sampleRing(ring, 1)) {
    if (pointInSafeZone(
      sample,
      curve,
      closed: curveClosed,
      lateralMm: lateralMm,
      capsuleFraction: capsuleFraction,
    )) {
      return true;
    }
  }
  return false;
}

/// First point where [from] → [to] enters [curve]'s safe zone.
///
/// Null when the segment never crosses the boundary inward. Leaving the zone
/// is not a crossing; that side is toward the scissor tail.
ZoneCrossing? firstSafeZoneEntry(
  Offset from,
  Offset to,
  List<Offset> curve, {
  double capsuleFraction = kPapercutCutCapsuleFraction,
}) {
  if (curve.length < 2) return null;
  final length = (to - from).distance;
  if (length < 1e-6) return null;
  final steps = math.max(2, (length / 0.5).ceil());
  var previousInside = pointInSafeZone(
    from,
    curve,
    closed: false,
    capsuleFraction: capsuleFraction,
  );
  for (var i = 1; i <= steps; i++) {
    final t = i / steps;
    final point = Offset(
      from.dx + (to.dx - from.dx) * t,
      from.dy + (to.dy - from.dy) * t,
    );
    final inside = pointInSafeZone(
      point,
      curve,
      closed: false,
      capsuleFraction: capsuleFraction,
    );
    if (!previousInside && inside) {
      final refined = _refineEntry(
        from,
        to,
        curve,
        (i - 1) / steps,
        t,
        capsuleFraction,
      );
      return ZoneCrossing(t: refined, point: _lerp(from, to, refined));
    }
    previousInside = inside;
  }
  return null;
}

double _refineEntry(
  Offset from,
  Offset to,
  List<Offset> curve,
  double outsideT,
  double insideT,
  double capsuleFraction,
) {
  var lo = outsideT;
  var hi = insideT;
  for (var i = 0; i < 8; i++) {
    final mid = (lo + hi) / 2;
    final inside = pointInSafeZone(
      _lerp(from, to, mid),
      curve,
      closed: false,
      capsuleFraction: capsuleFraction,
    );
    if (inside) {
      hi = mid;
    } else {
      lo = mid;
    }
  }
  return hi;
}

Offset _lerp(Offset a, Offset b, double t) =>
    Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);

/// Where a segment crosses into a safe zone. [t] is 0 at the start.
class ZoneCrossing {
  const ZoneCrossing({required this.t, required this.point});

  final double t;
  final Offset point;
}

/// True when the scissor zone reaches a paper edge. An existing cut can also
/// start a scissor cut; that case is decided in the cut graph.
bool scissorReachesPaperEdge(List<Offset> segment, PapercutSheet sheet) {
  if (segment.length < 2) return false;
  for (final piece in sheet.pieces) {
    if (safeZoneTouchesRing(
      segment,
      piece.vertices,
      curveClosed: false,
      capsuleFraction: kPapercutCutCapsuleFraction,
    )) {
      return true;
    }
    for (final hole in piece.holes) {
      if (safeZoneTouchesRing(
        segment,
        hole,
        curveClosed: false,
        capsuleFraction: kPapercutCutCapsuleFraction,
      )) {
        return true;
      }
    }
  }
  return false;
}

/// Lateral rails, plus cap centers for an open curve.
class PapercutSafeZoneBand {
  const PapercutSafeZoneBand({
    required this.left,
    required this.right,
    required this.capRadius,
    this.start,
    this.end,
  });

  final List<Offset> left;
  final List<Offset> right;
  final double capRadius;
  final Offset? start;
  final Offset? end;

  bool get open => start != null && end != null;
}

PapercutSafeZoneBand safeZoneBand(
  List<Offset> points, {
  required bool closed,
  double lateralMm = kPapercutLateralMm,
  double capsuleFraction = kPapercutCutCapsuleFraction,
}) {
  if (points.length < 2) {
    return const PapercutSafeZoneBand(left: [], right: [], capRadius: 0);
  }
  return PapercutSafeZoneBand(
    left: _offsetRail(points, lateralMm, closed: closed),
    right: _offsetRail(points, -lateralMm, closed: closed),
    capRadius: closed ? 0 : lateralMm * capsuleFraction,
    start: closed ? null : points.first,
    end: closed ? null : points.last,
  );
}

List<Offset> _offsetRail(
  List<Offset> points,
  double distance, {
  required bool closed,
}) {
  final rail = <Offset>[];
  for (var i = 0; i < points.length; i++) {
    rail.add(_offsetVertex(points, i, distance, closed: closed));
  }
  return rail;
}

Offset _offsetVertex(
  List<Offset> points,
  int index,
  double distance, {
  required bool closed,
}) {
  final count = points.length;
  final curr = points[index];
  final hasPrev = closed || index > 0;
  final hasNext = closed || index < count - 1;
  final prev = points[(index - 1 + count) % count];
  final next = points[(index + 1) % count];
  if (!hasPrev) return curr + _unitLeftNormal(curr, next) * distance;
  if (!hasNext) return curr + _unitLeftNormal(prev, curr) * distance;

  final n0 = _unitLeftNormal(prev, curr);
  final n1 = _unitLeftNormal(curr, next);
  final sum = n0 + n1;
  if (sum.distance < 1e-6) return curr + n1 * distance;
  final unit = sum / sum.distance;
  final dot = unit.dx * n1.dx + unit.dy * n1.dy;
  final scale = (1 / math.max(dot.abs(), 0.25)).clamp(1.0, 4.0);
  final signed = dot < 0 ? -scale : scale;
  return curr + unit * (distance * signed);
}

Offset _unitLeftNormal(Offset a, Offset b) {
  final delta = b - a;
  final len = delta.distance;
  if (len < 1e-8) return Offset.zero;
  return Offset(-delta.dy / len, delta.dx / len);
}

bool _polylinesCross(List<Offset> curve, List<Offset> ring) {
  for (var i = 0; i < curve.length - 1; i++) {
    for (var j = 0; j < ring.length; j++) {
      final hit = segmentIntersection(
        curve[i],
        curve[i + 1],
        ring[j],
        ring[(j + 1) % ring.length],
      );
      if (hit.hasIntersection) return true;
    }
  }
  return false;
}

List<Offset> _sampleRing(List<Offset> ring, double spacing) {
  final out = <Offset>[ring.first];
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    final dist = (b - a).distance;
    if (dist < 1e-6) continue;
    var traveled = spacing;
    while (traveled < dist - 0.05) {
      final t = traveled / dist;
      out.add(Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t));
      traveled += spacing;
    }
    if ((out.last - b).distance > 0.2) out.add(b);
  }
  return out;
}
