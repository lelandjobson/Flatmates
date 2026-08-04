import 'dart:math' as math;
import 'dart:ui';

import 'geometry_2d.dart';

/// Epsilon for floating-point comparisons.
const double _epsilon = 1e-9;

// =============================================================================
// CURVE INTERFACE
// =============================================================================

/// Abstract base class for 2D parametric curves.
///
/// All curves are parameterized by t in [0, 1] where:
/// - t = 0 corresponds to the start of the curve
/// - t = 1 corresponds to the end of the curve
abstract class Curve2D {
  /// Evaluates the curve at parameter t.
  ///
  /// [t] must be in range [0, 1].
  Offset pointAt(double t);

  /// Computes the tangent vector at parameter t.
  ///
  /// The tangent vector points in the direction of increasing t.
  /// The length of the tangent is proportional to the curve's speed at t.
  Offset tangentAt(double t);

  /// Computes the unit tangent vector at parameter t.
  Offset unitTangentAt(double t) {
    final tan = tangentAt(t);
    final len = tan.distance;
    if (len < _epsilon) return const Offset(1, 0);
    return tan / len;
  }

  /// Computes the normal vector at parameter t.
  ///
  /// The normal is perpendicular to the tangent, pointing to the left
  /// of the curve direction (90 degrees counter-clockwise from tangent).
  Offset normalAt(double t) {
    final tan = unitTangentAt(t);
    return Offset(-tan.dy, tan.dx);
  }

  /// Computes the approximate arc length of the curve.
  ///
  /// Uses numerical integration with the specified number of subdivisions.
  double length({int subdivisions = 100}) {
    double len = 0;
    Offset prev = pointAt(0);

    for (int i = 1; i <= subdivisions; i++) {
      final t = i / subdivisions;
      final curr = pointAt(t);
      len += (curr - prev).distance;
      prev = curr;
    }

    return len;
  }

  /// Converts the curve to a polyline with the specified number of segments.
  List<Offset> toPolyline(int segments) {
    if (segments < 1) segments = 1;

    final points = <Offset>[];
    for (int i = 0; i <= segments; i++) {
      points.add(pointAt(i / segments));
    }
    return points;
  }

  /// Returns the start point of the curve (t = 0).
  Offset get start => pointAt(0);

  /// Returns the end point of the curve (t = 1).
  Offset get end => pointAt(1);

  /// Computes the bounding box of the curve.
  Bounds2D get bounds {
    // Sample the curve to approximate bounds
    const samples = 20;
    final points = <Offset>[];
    for (int i = 0; i <= samples; i++) {
      points.add(pointAt(i / samples));
    }
    return Bounds2D.fromPoints(points);
  }
}

// =============================================================================
// LINEAR SEGMENT
// =============================================================================

/// A linear curve segment between two points.
class LineSegment2D extends Curve2D {
  LineSegment2D(this.p0, this.p1);

  /// Start point.
  final Offset p0;

  /// End point.
  final Offset p1;

  @override
  Offset pointAt(double t) {
    return Offset(p0.dx + t * (p1.dx - p0.dx), p0.dy + t * (p1.dy - p0.dy));
  }

  @override
  Offset tangentAt(double t) {
    return p1 - p0;
  }

  @override
  double length({int subdivisions = 100}) {
    return (p1 - p0).distance;
  }

  @override
  Bounds2D get bounds => Bounds2D.fromPoints([p0, p1]);
}

// =============================================================================
// QUADRATIC BEZIER CURVE
// =============================================================================

/// A quadratic Bezier curve defined by 3 control points.
///
/// The curve starts at p0, is influenced by control point p1,
/// and ends at p2.
///
/// Formula: B(t) = (1-t)²·P0 + 2(1-t)t·P1 + t²·P2
class QuadraticBezier2D extends Curve2D {
  QuadraticBezier2D(this.p0, this.p1, this.p2);

  /// Start point.
  final Offset p0;

  /// Control point.
  final Offset p1;

  /// End point.
  final Offset p2;

  @override
  Offset pointAt(double t) {
    final t1 = 1 - t;
    final t1Sq = t1 * t1;
    final tSq = t * t;

    return Offset(
      t1Sq * p0.dx + 2 * t1 * t * p1.dx + tSq * p2.dx,
      t1Sq * p0.dy + 2 * t1 * t * p1.dy + tSq * p2.dy,
    );
  }

  @override
  Offset tangentAt(double t) {
    // Derivative: B'(t) = 2(1-t)(P1-P0) + 2t(P2-P1)
    final t1 = 1 - t;

    return Offset(
      2 * t1 * (p1.dx - p0.dx) + 2 * t * (p2.dx - p1.dx),
      2 * t1 * (p1.dy - p0.dy) + 2 * t * (p2.dy - p1.dy),
    );
  }

  /// Splits the curve at parameter t into two curves.
  (QuadraticBezier2D, QuadraticBezier2D) splitAt(double t) {
    // De Casteljau's algorithm
    final q0 = _lerp(p0, p1, t);
    final q1 = _lerp(p1, p2, t);
    final r0 = _lerp(q0, q1, t);

    return (QuadraticBezier2D(p0, q0, r0), QuadraticBezier2D(r0, q1, p2));
  }

  @override
  Bounds2D get bounds {
    // For quadratic Bezier, extrema are at t where derivative = 0
    final extremaT = <double>[0, 1];

    // Solve for t where derivative = 0 for each axis
    // B'(t) = 2(1-t)(P1-P0) + 2t(P2-P1) = 0
    // Simplifies to: t = (P0 - P1) / (P0 - 2P1 + P2)

    final denomX = p0.dx - 2 * p1.dx + p2.dx;
    if (denomX.abs() > _epsilon) {
      final tX = (p0.dx - p1.dx) / denomX;
      if (tX > 0 && tX < 1) extremaT.add(tX);
    }

    final denomY = p0.dy - 2 * p1.dy + p2.dy;
    if (denomY.abs() > _epsilon) {
      final tY = (p0.dy - p1.dy) / denomY;
      if (tY > 0 && tY < 1) extremaT.add(tY);
    }

    final points = extremaT.map(pointAt).toList();
    return Bounds2D.fromPoints(points);
  }
}

// =============================================================================
// CUBIC BEZIER CURVE
// =============================================================================

/// A cubic Bezier curve defined by 4 control points.
///
/// The curve starts at p0, is influenced by control points p1 and p2,
/// and ends at p3.
///
/// Formula: B(t) = (1-t)³·P0 + 3(1-t)²t·P1 + 3(1-t)t²·P2 + t³·P3
class CubicBezier2D extends Curve2D {
  CubicBezier2D(this.p0, this.p1, this.p2, this.p3);

  /// Start point.
  final Offset p0;

  /// First control point.
  final Offset p1;

  /// Second control point.
  final Offset p2;

  /// End point.
  final Offset p3;

  @override
  Offset pointAt(double t) {
    final t1 = 1 - t;
    final t1Sq = t1 * t1;
    final t1Cu = t1Sq * t1;
    final tSq = t * t;
    final tCu = tSq * t;

    return Offset(
      t1Cu * p0.dx + 3 * t1Sq * t * p1.dx + 3 * t1 * tSq * p2.dx + tCu * p3.dx,
      t1Cu * p0.dy + 3 * t1Sq * t * p1.dy + 3 * t1 * tSq * p2.dy + tCu * p3.dy,
    );
  }

  @override
  Offset tangentAt(double t) {
    // Derivative: B'(t) = 3(1-t)²(P1-P0) + 6(1-t)t(P2-P1) + 3t²(P3-P2)
    final t1 = 1 - t;
    final t1Sq = t1 * t1;
    final tSq = t * t;

    return Offset(
      3 * t1Sq * (p1.dx - p0.dx) +
          6 * t1 * t * (p2.dx - p1.dx) +
          3 * tSq * (p3.dx - p2.dx),
      3 * t1Sq * (p1.dy - p0.dy) +
          6 * t1 * t * (p2.dy - p1.dy) +
          3 * tSq * (p3.dy - p2.dy),
    );
  }

  /// Computes the second derivative (acceleration) at parameter t.
  Offset secondDerivativeAt(double t) {
    // B''(t) = 6(1-t)(P2-2P1+P0) + 6t(P3-2P2+P1)
    final t1 = 1 - t;

    final ax = p2.dx - 2 * p1.dx + p0.dx;
    final ay = p2.dy - 2 * p1.dy + p0.dy;
    final bx = p3.dx - 2 * p2.dx + p1.dx;
    final by = p3.dy - 2 * p2.dy + p1.dy;

    return Offset(6 * t1 * ax + 6 * t * bx, 6 * t1 * ay + 6 * t * by);
  }

  /// Computes the curvature at parameter t.
  ///
  /// Curvature is the reciprocal of the radius of the osculating circle.
  double curvatureAt(double t) {
    final d1 = tangentAt(t);
    final d2 = secondDerivativeAt(t);

    // κ = |x'y'' - y'x''| / (x'² + y'²)^(3/2)
    final cross = d1.dx * d2.dy - d1.dy * d2.dx;
    final speedSq = d1.dx * d1.dx + d1.dy * d1.dy;
    final speedCubed = math.pow(speedSq, 1.5);

    if (speedCubed < _epsilon) return 0;
    return cross.abs() / speedCubed;
  }

  /// Splits the curve at parameter t into two curves.
  (CubicBezier2D, CubicBezier2D) splitAt(double t) {
    // De Casteljau's algorithm
    final q0 = _lerp(p0, p1, t);
    final q1 = _lerp(p1, p2, t);
    final q2 = _lerp(p2, p3, t);

    final r0 = _lerp(q0, q1, t);
    final r1 = _lerp(q1, q2, t);

    final s0 = _lerp(r0, r1, t);

    return (CubicBezier2D(p0, q0, r0, s0), CubicBezier2D(s0, r1, q2, p3));
  }

  @override
  Bounds2D get bounds {
    // For cubic Bezier, extrema are at t where derivative = 0
    final extremaT = <double>[0, 1];

    // Solve quadratic for each axis
    // B'(t) = at² + bt + c where:
    // a = -3P0 + 9P1 - 9P2 + 3P3
    // b = 6P0 - 12P1 + 6P2
    // c = -3P0 + 3P1

    void addRoots(double p0Val, double p1Val, double p2Val, double p3Val) {
      final a = -3 * p0Val + 9 * p1Val - 9 * p2Val + 3 * p3Val;
      final b = 6 * p0Val - 12 * p1Val + 6 * p2Val;
      final c = -3 * p0Val + 3 * p1Val;

      if (a.abs() < _epsilon) {
        // Linear case
        if (b.abs() > _epsilon) {
          final t = -c / b;
          if (t > 0 && t < 1) extremaT.add(t);
        }
      } else {
        // Quadratic case
        final discriminant = b * b - 4 * a * c;
        if (discriminant >= 0) {
          final sqrtD = math.sqrt(discriminant);
          final t1 = (-b + sqrtD) / (2 * a);
          final t2 = (-b - sqrtD) / (2 * a);
          if (t1 > 0 && t1 < 1) extremaT.add(t1);
          if (t2 > 0 && t2 < 1) extremaT.add(t2);
        }
      }
    }

    addRoots(p0.dx, p1.dx, p2.dx, p3.dx);
    addRoots(p0.dy, p1.dy, p2.dy, p3.dy);

    final points = extremaT.map(pointAt).toList();
    return Bounds2D.fromPoints(points);
  }
}

// =============================================================================
// POLYLINE AS CURVE
// =============================================================================

/// A piecewise linear curve defined by a series of points.
///
/// The curve parameter t maps linearly across the entire polyline:
/// - t = 0 is the first point
/// - t = 1 is the last point
/// - Intermediate values are interpolated along edges
class Polyline2D extends Curve2D {
  Polyline2D(this.points);

  /// Creates a polyline from a Ring2D (closed curve).
  factory Polyline2D.fromRing(Ring2D ring) {
    return Polyline2D([...ring.points, ring.points.first]);
  }

  /// The vertices of the polyline.
  final List<Offset> points;

  /// Number of points in the polyline.
  int get pointCount => points.length;

  /// Whether the polyline has at least 2 points.
  bool get isValid => pointCount >= 2;

  /// Total arc length of the polyline.
  late final double totalLength = _computeTotalLength();

  double _computeTotalLength() {
    if (points.length < 2) return 0;

    double len = 0;
    for (int i = 0; i < points.length - 1; i++) {
      len += (points[i + 1] - points[i]).distance;
    }
    return len;
  }

  /// Cumulative lengths at each vertex (for parameter mapping).
  late final List<double> _cumulativeLengths = _computeCumulativeLengths();

  List<double> _computeCumulativeLengths() {
    final lengths = <double>[0];
    for (int i = 0; i < points.length - 1; i++) {
      final segLen = (points[i + 1] - points[i]).distance;
      lengths.add(lengths.last + segLen);
    }
    return lengths;
  }

  @override
  Offset pointAt(double t) {
    if (!isValid) return points.isEmpty ? Offset.zero : points.first;
    if (t <= 0) return points.first;
    if (t >= 1) return points.last;

    // Map t to arc length
    final targetLen = t * totalLength;

    // Find the segment containing this length
    for (int i = 0; i < _cumulativeLengths.length - 1; i++) {
      if (targetLen <= _cumulativeLengths[i + 1]) {
        final segStart = _cumulativeLengths[i];
        final segEnd = _cumulativeLengths[i + 1];
        final segLen = segEnd - segStart;

        if (segLen < _epsilon) {
          return points[i];
        }

        final localT = (targetLen - segStart) / segLen;
        return _lerp(points[i], points[i + 1], localT);
      }
    }

    return points.last;
  }

  @override
  Offset tangentAt(double t) {
    if (!isValid) return const Offset(1, 0);
    if (t <= 0) {
      return points.length > 1 ? points[1] - points[0] : const Offset(1, 0);
    }
    if (t >= 1) {
      return points.length > 1
          ? points.last - points[points.length - 2]
          : const Offset(1, 0);
    }

    // Map t to arc length
    final targetLen = t * totalLength;

    // Find the segment containing this length
    for (int i = 0; i < _cumulativeLengths.length - 1; i++) {
      if (targetLen <= _cumulativeLengths[i + 1]) {
        return points[i + 1] - points[i];
      }
    }

    return points.last - points[points.length - 2];
  }

  @override
  double length({int subdivisions = 100}) => totalLength;

  @override
  List<Offset> toPolyline(int segments) {
    // Already a polyline, return points directly
    return List.from(points);
  }

  /// Finds the parameter t closest to a given point.
  double closestParameter(Offset point) {
    if (!isValid) return 0;

    double bestT = 0;
    double bestDistSq = double.infinity;

    for (int i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];

      // Project point onto segment
      final ab = b - a;
      final ap = point - a;
      final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;

      double localT;
      if (lenSq < _epsilon) {
        localT = 0;
      } else {
        localT = (ap.dx * ab.dx + ap.dy * ab.dy) / lenSq;
        localT = localT.clamp(0.0, 1.0);
      }

      final closest = _lerp(a, b, localT);
      final distSq =
          (point.dx - closest.dx) * (point.dx - closest.dx) +
          (point.dy - closest.dy) * (point.dy - closest.dy);

      if (distSq < bestDistSq) {
        bestDistSq = distSq;
        // Convert local t to global t
        final segStart = _cumulativeLengths[i];
        final segEnd = _cumulativeLengths[i + 1];
        final globalLen = segStart + localT * (segEnd - segStart);
        bestT = totalLength > _epsilon ? globalLen / totalLength : 0;
      }
    }

    return bestT;
  }

  /// Returns a sub-polyline from parameter t1 to t2.
  Polyline2D subCurve(double t1, double t2) {
    if (!isValid) return this;

    t1 = t1.clamp(0.0, 1.0);
    t2 = t2.clamp(0.0, 1.0);

    if (t1 > t2) {
      final temp = t1;
      t1 = t2;
      t2 = temp;
    }

    final result = <Offset>[pointAt(t1)];

    final len1 = t1 * totalLength;
    final len2 = t2 * totalLength;

    // Add intermediate vertices
    for (int i = 1; i < _cumulativeLengths.length - 1; i++) {
      if (_cumulativeLengths[i] > len1 && _cumulativeLengths[i] < len2) {
        result.add(points[i]);
      }
    }

    result.add(pointAt(t2));

    return Polyline2D(result);
  }

  @override
  Bounds2D get bounds => Bounds2D.fromPoints(points);
}

// =============================================================================
// CURVE PATH (COMPOSITE CURVE)
// =============================================================================

/// A path composed of multiple curve segments.
class CurvePath2D extends Curve2D {
  CurvePath2D(this.curves);

  /// The curve segments.
  final List<Curve2D> curves;

  /// Whether the path is valid (has at least one curve).
  bool get isValid => curves.isNotEmpty;

  /// Total length of all curves.
  late final double totalLength = _computeTotalLength();

  double _computeTotalLength() {
    double len = 0;
    for (final curve in curves) {
      len += curve.length();
    }
    return len;
  }

  /// Maps global parameter t to (curveIndex, localT).
  (int, double) _mapParameter(double t) {
    if (curves.isEmpty) return (0, 0.0);
    if (t <= 0) return (0, 0.0);
    if (t >= 1) return (curves.length - 1, 1.0);

    final targetLen = t * totalLength;
    double accumulated = 0;

    for (int i = 0; i < curves.length; i++) {
      final curveLen = curves[i].length();
      if (accumulated + curveLen >= targetLen) {
        final localLen = targetLen - accumulated;
        final double localT = curveLen > _epsilon ? localLen / curveLen : 0.0;
        return (i, localT);
      }
      accumulated += curveLen;
    }

    return (curves.length - 1, 1.0);
  }

  @override
  Offset pointAt(double t) {
    if (!isValid) return Offset.zero;
    final (index, localT) = _mapParameter(t);
    return curves[index].pointAt(localT);
  }

  @override
  Offset tangentAt(double t) {
    if (!isValid) return const Offset(1, 0);
    final (index, localT) = _mapParameter(t);
    return curves[index].tangentAt(localT);
  }

  @override
  double length({int subdivisions = 100}) => totalLength;

  @override
  Bounds2D get bounds {
    if (curves.isEmpty) return const Bounds2D(Offset.zero, Offset.zero);

    var result = curves.first.bounds;
    for (int i = 1; i < curves.length; i++) {
      result = result.union(curves[i].bounds);
    }
    return result;
  }

  /// Adds a curve to the path.
  CurvePath2D add(Curve2D curve) {
    return CurvePath2D([...curves, curve]);
  }
}

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

/// Linear interpolation between two points.
Offset _lerp(Offset a, Offset b, double t) {
  return Offset(a.dx + t * (b.dx - a.dx), a.dy + t * (b.dy - a.dy));
}

/// Finds the closest point on a curve to a given point.
///
/// Uses numerical sampling to find the approximate closest point.
(Offset point, double t) closestPointOnCurve(
  Offset point,
  Curve2D curve, {
  int samples = 100,
  int refinementIterations = 3,
}) {
  // Initial coarse sampling
  double bestT = 0;
  double bestDistSq = double.infinity;

  for (int i = 0; i <= samples; i++) {
    final t = i / samples;
    final p = curve.pointAt(t);
    final distSq =
        (point.dx - p.dx) * (point.dx - p.dx) +
        (point.dy - p.dy) * (point.dy - p.dy);

    if (distSq < bestDistSq) {
      bestDistSq = distSq;
      bestT = t;
    }
  }

  // Refinement using golden section search
  double a = math.max(0, bestT - 1 / samples);
  double b = math.min(1, bestT + 1 / samples);

  for (int iter = 0; iter < refinementIterations; iter++) {
    final range = b - a;
    const phi = 0.618033988749895;

    final t1 = b - phi * range;
    final t2 = a + phi * range;

    final p1 = curve.pointAt(t1);
    final p2 = curve.pointAt(t2);

    final d1 =
        (point.dx - p1.dx) * (point.dx - p1.dx) +
        (point.dy - p1.dy) * (point.dy - p1.dy);
    final d2 =
        (point.dx - p2.dx) * (point.dx - p2.dx) +
        (point.dy - p2.dy) * (point.dy - p2.dy);

    if (d1 < d2) {
      b = t2;
      if (d1 < bestDistSq) {
        bestDistSq = d1;
        bestT = t1;
      }
    } else {
      a = t1;
      if (d2 < bestDistSq) {
        bestDistSq = d2;
        bestT = t2;
      }
    }
  }

  return (curve.pointAt(bestT), bestT);
}

/// Computes the arc length of a curve segment from t1 to t2.
double arcLength(Curve2D curve, double t1, double t2, {int subdivisions = 50}) {
  if (t1 > t2) {
    final temp = t1;
    t1 = t2;
    t2 = temp;
  }

  double len = 0;
  Offset prev = curve.pointAt(t1);

  for (int i = 1; i <= subdivisions; i++) {
    final t = t1 + (t2 - t1) * i / subdivisions;
    final curr = curve.pointAt(t);
    len += (curr - prev).distance;
    prev = curr;
  }

  return len;
}

/// Finds the parameter t where the curve is at a given arc length from the start.
double parameterAtLength(
  Curve2D curve,
  double targetLength, {
  int subdivisions = 100,
}) {
  if (targetLength <= 0) return 0;

  double len = 0;
  Offset prev = curve.pointAt(0);

  for (int i = 1; i <= subdivisions; i++) {
    final t = i / subdivisions;
    final curr = curve.pointAt(t);
    final segLen = (curr - prev).distance;

    if (len + segLen >= targetLength) {
      // Interpolate within this segment
      final remaining = targetLength - len;
      final ratio = segLen > _epsilon ? remaining / segLen : 0;
      return (i - 1 + ratio) / subdivisions;
    }

    len += segLen;
    prev = curr;
  }

  return 1;
}
