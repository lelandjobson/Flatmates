import 'dart:math' as math;
import 'dart:ui';

import 'geometry_2d.dart';

/// Epsilon for floating-point comparisons.
const double _epsilon = 1e-9;

// =============================================================================
// POINT-IN-POLYGON (Winding Number Algorithm)
// =============================================================================
// Translated from Boost.Geometry:
// geometry/include/boost/geometry/strategies/cartesian/point_in_poly_winding.hpp
//
// The winding number algorithm counts how many times the polygon winds around
// the point. A non-zero winding number means the point is inside.
// =============================================================================

/// Result of point-in-polygon test.
///
/// - `inside` (1): Point is strictly inside the polygon
/// - `boundary` (0): Point is on the polygon boundary
/// - `outside` (-1): Point is strictly outside the polygon
enum PointLocation {
  inside(1),
  boundary(0),
  outside(-1);

  const PointLocation(this.value);
  final int value;
}

/// Determines the location of a point relative to a polygon.
///
/// Uses the winding number algorithm which correctly handles:
/// - Concave polygons
/// - Polygons with holes
/// - Points on the boundary
///
/// Returns [PointLocation.inside], [PointLocation.boundary], or [PointLocation.outside].
PointLocation pointInPolygon(Offset point, Polygon2D polygon) {
  if (!polygon.isValid) return PointLocation.outside;

  // Check exterior ring
  final exteriorResult = _pointInRing(point, polygon.exterior);

  if (exteriorResult == PointLocation.outside) {
    return PointLocation.outside;
  }

  if (exteriorResult == PointLocation.boundary) {
    return PointLocation.boundary;
  }

  // Point is inside exterior ring - check holes
  for (final hole in polygon.holes) {
    final holeResult = _pointInRing(point, hole);

    if (holeResult == PointLocation.boundary) {
      // On hole boundary = on polygon boundary
      return PointLocation.boundary;
    }

    if (holeResult == PointLocation.inside) {
      // Inside a hole = outside the polygon
      return PointLocation.outside;
    }
  }

  return PointLocation.inside;
}

/// Convenience method: returns true if point is inside or on boundary.
bool isPointInPolygon(Offset point, Polygon2D polygon) {
  return pointInPolygon(point, polygon) != PointLocation.outside;
}

/// Convenience method: returns true if point is strictly inside (not on boundary).
bool isPointStrictlyInside(Offset point, Polygon2D polygon) {
  return pointInPolygon(point, polygon) == PointLocation.inside;
}

/// Winding number algorithm for a single ring.
PointLocation _pointInRing(Offset point, Ring2D ring) {
  if (!ring.isValid) return PointLocation.outside;

  int windingNumber = 0;
  final n = ring.length;

  for (int i = 0; i < n; i++) {
    final p1 = ring.points[i];
    final p2 = ring.points[(i + 1) % n];

    // Check if point is on this edge
    if (_isPointOnSegment(point, p1, p2)) {
      return PointLocation.boundary;
    }

    // Winding number calculation
    // Based on the crossing number variant that handles all cases
    if (p1.dy <= point.dy) {
      if (p2.dy > point.dy) {
        // Upward crossing
        final side = _crossProduct(p1, p2, point);
        if (side > _epsilon) {
          windingNumber++;
        }
      }
    } else {
      if (p2.dy <= point.dy) {
        // Downward crossing
        final side = _crossProduct(p1, p2, point);
        if (side < -_epsilon) {
          windingNumber--;
        }
      }
    }
  }

  return windingNumber != 0 ? PointLocation.inside : PointLocation.outside;
}

/// Computes the cross product (p2-p1) × (p-p1).
///
/// Returns:
/// - Positive if p is to the left of the line p1→p2
/// - Negative if p is to the right
/// - Zero if p is on the line
double _crossProduct(Offset p1, Offset p2, Offset p) {
  return (p2.dx - p1.dx) * (p.dy - p1.dy) - (p2.dy - p1.dy) * (p.dx - p1.dx);
}

/// Checks if a point lies on a line segment.
bool _isPointOnSegment(Offset p, Offset a, Offset b) {
  // Check if point is collinear with segment
  final cross = _crossProduct(a, b, p);
  if (cross.abs() > _epsilon) return false;

  // Check if point is within segment bounds
  final minX = math.min(a.dx, b.dx) - _epsilon;
  final maxX = math.max(a.dx, b.dx) + _epsilon;
  final minY = math.min(a.dy, b.dy) - _epsilon;
  final maxY = math.max(a.dy, b.dy) + _epsilon;

  return p.dx >= minX && p.dx <= maxX && p.dy >= minY && p.dy <= maxY;
}

// =============================================================================
// CENTROID (Bashein-Detmer Algorithm)
// =============================================================================
// Translated from Boost.Geometry:
// geometry/include/boost/geometry/strategies/cartesian/centroid_bashein_detmer.hpp
//
// Uses the signed area formula to compute the centroid, which works correctly
// for both convex and concave polygons.
// =============================================================================

/// Computes the centroid of a polygon.
///
/// Uses the Bashein-Detmer algorithm based on signed areas.
/// Correctly handles:
/// - Concave polygons
/// - Polygons with holes (holes subtract from the centroid calculation)
///
/// Returns null if the polygon has zero area or is invalid.
Offset? centroid(Polygon2D polygon) {
  if (!polygon.isValid) return null;

  // Accumulate signed area and weighted coordinates
  double sumA2 = 0;
  double sumX = 0;
  double sumY = 0;

  // Process exterior ring
  _accumulateCentroidContribution(polygon.exterior, (a2, x, y) {
    sumA2 += a2;
    sumX += x;
    sumY += y;
  });

  // Process holes (they subtract from the area)
  for (final hole in polygon.holes) {
    _accumulateCentroidContribution(hole, (a2, x, y) {
      sumA2 += a2;
      sumX += x;
      sumY += y;
    });
  }

  // Calculate centroid
  if (sumA2.abs() < _epsilon) return null;

  final a3 = 3 * sumA2;
  return Offset(sumX / a3, sumY / a3);
}

/// Computes the centroid of a simple ring (no holes).
Offset? ringCentroid(Ring2D ring) {
  if (!ring.isValid) return null;

  double sumA2 = 0;
  double sumX = 0;
  double sumY = 0;

  _accumulateCentroidContribution(ring, (a2, x, y) {
    sumA2 += a2;
    sumX += x;
    sumY += y;
  });

  if (sumA2.abs() < _epsilon) return null;

  final a3 = 3 * sumA2;
  return Offset(sumX / a3, sumY / a3);
}

/// Accumulates centroid contribution from a ring.
void _accumulateCentroidContribution(
  Ring2D ring,
  void Function(double a2, double x, double y) accumulate,
) {
  final n = ring.length;
  if (n < 3) return;

  for (int i = 0; i < n; i++) {
    final p1 = ring.points[i];
    final p2 = ring.points[(i + 1) % n];

    // Signed area contribution (determinant)
    final ai = p1.dx * p2.dy - p2.dx * p1.dy;

    accumulate(ai, ai * (p1.dx + p2.dx), ai * (p1.dy + p2.dy));
  }
}

// =============================================================================
// SEGMENT INTERSECTION (Cramer's Rule)
// =============================================================================
// Translated from Boost.Geometry:
// geometry/include/boost/geometry/strategies/cartesian/intersection.hpp
//
// Uses Cramer's rule to solve the line intersection equations.
// =============================================================================

/// Result of a segment intersection calculation.
class SegmentIntersection {
  const SegmentIntersection._({
    required this.type,
    this.point,
    this.segmentStart,
    this.segmentEnd,
  });

  /// No intersection.
  static const none = SegmentIntersection._(type: IntersectionType.none);

  /// Creates a point intersection result.
  factory SegmentIntersection.point(Offset p) {
    return SegmentIntersection._(type: IntersectionType.point, point: p);
  }

  /// Creates a collinear overlap result.
  factory SegmentIntersection.collinear(Offset start, Offset end) {
    return SegmentIntersection._(
      type: IntersectionType.collinear,
      segmentStart: start,
      segmentEnd: end,
    );
  }

  final IntersectionType type;
  final Offset? point;
  final Offset? segmentStart;
  final Offset? segmentEnd;

  bool get hasIntersection => type != IntersectionType.none;
  bool get isPoint => type == IntersectionType.point;
  bool get isCollinear => type == IntersectionType.collinear;
}

/// Type of segment intersection.
enum IntersectionType { none, point, collinear }

/// Computes the intersection of two line segments.
///
/// Segments are defined as (p1, p2) and (p3, p4).
///
/// Returns:
/// - [SegmentIntersection.none] if segments don't intersect
/// - [SegmentIntersection.point] if segments intersect at a single point
/// - [SegmentIntersection.collinear] if segments overlap (collinear case)
SegmentIntersection segmentIntersection(
  Offset p1,
  Offset p2,
  Offset p3,
  Offset p4,
) {
  final dxa = p2.dx - p1.dx;
  final dya = p2.dy - p1.dy;
  final dxb = p4.dx - p3.dx;
  final dyb = p4.dy - p3.dy;

  // Denominator of Cramer's rule
  final denom = dxa * dyb - dya * dxb;

  final wx = p1.dx - p3.dx;
  final wy = p1.dy - p3.dy;

  if (denom.abs() < _epsilon) {
    // Lines are parallel - check for collinearity
    final cross = dxa * wy - dya * wx;
    if (cross.abs() < _epsilon) {
      // Collinear - check for overlap
      return _collinearIntersection(p1, p2, p3, p4);
    }
    return SegmentIntersection.none;
  }

  // Calculate parameters using Cramer's rule
  final t = (dxb * wy - dyb * wx) / denom;
  final u = (dxa * wy - dya * wx) / denom;

  // Check if intersection is within both segments
  if (t >= -_epsilon &&
      t <= 1 + _epsilon &&
      u >= -_epsilon &&
      u <= 1 + _epsilon) {
    final x = p1.dx + t * dxa;
    final y = p1.dy + t * dya;
    return SegmentIntersection.point(Offset(x, y));
  }

  return SegmentIntersection.none;
}

/// Handles the collinear case for segment intersection.
SegmentIntersection _collinearIntersection(
  Offset p1,
  Offset p2,
  Offset p3,
  Offset p4,
) {
  // Project onto the axis with larger extent for numerical stability
  final useX = (p2.dx - p1.dx).abs() >= (p2.dy - p1.dy).abs();

  double proj(Offset p) => useX ? p.dx : p.dy;

  final a1 = proj(p1);
  final a2 = proj(p2);
  final b1 = proj(p3);
  final b2 = proj(p4);

  // Normalize so a1 <= a2 and b1 <= b2
  final minA = math.min(a1, a2);
  final maxA = math.max(a1, a2);
  final minB = math.min(b1, b2);
  final maxB = math.max(b1, b2);

  // Calculate overlap
  final overlapStart = math.max(minA, minB);
  final overlapEnd = math.min(maxA, maxB);

  if (overlapStart > overlapEnd + _epsilon) {
    return SegmentIntersection.none;
  }

  // Map back to 2D points
  Offset pointAt(double t) {
    if (useX) {
      final ratio = (maxA - minA).abs() < _epsilon ? 0.0 : (t - a1) / (a2 - a1);
      return Offset(t, p1.dy + ratio * (p2.dy - p1.dy));
    } else {
      final ratio = (maxA - minA).abs() < _epsilon ? 0.0 : (t - a1) / (a2 - a1);
      return Offset(p1.dx + ratio * (p2.dx - p1.dx), t);
    }
  }

  if ((overlapEnd - overlapStart).abs() < _epsilon) {
    // Single point overlap
    return SegmentIntersection.point(pointAt(overlapStart));
  }

  return SegmentIntersection.collinear(
    pointAt(overlapStart),
    pointAt(overlapEnd),
  );
}

/// Simple segment intersection that returns only the point (or null).
Offset? segmentIntersectionPoint(Offset p1, Offset p2, Offset p3, Offset p4) {
  final result = segmentIntersection(p1, p2, p3, p4);
  return result.point;
}

// =============================================================================
// LINE-POLYGON INTERSECTION
// =============================================================================

/// Finds all intersection points between a line segment and a polygon.
///
/// Returns a list of intersection points, sorted by distance from p1.
/// The list may contain duplicates at polygon vertices if the line
/// passes through a vertex.
List<Offset> linePolygonIntersectionPoints(
  Offset p1,
  Offset p2,
  Polygon2D polygon,
) {
  final intersections = <_ParameterizedIntersection>[];

  // Helper to calculate parameter along line
  double parameter(Offset p) {
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    if (dx.abs() >= dy.abs()) {
      return dx.abs() < _epsilon ? 0 : (p.dx - p1.dx) / dx;
    } else {
      return (p.dy - p1.dy) / dy;
    }
  }

  // Check exterior ring edges
  for (final edge in polygon.exterior.edges) {
    final result = segmentIntersection(p1, p2, edge.$1, edge.$2);
    if (result.isPoint && result.point != null) {
      intersections.add(
        _ParameterizedIntersection(
          point: result.point!,
          t: parameter(result.point!),
        ),
      );
    } else if (result.isCollinear) {
      if (result.segmentStart != null) {
        intersections.add(
          _ParameterizedIntersection(
            point: result.segmentStart!,
            t: parameter(result.segmentStart!),
          ),
        );
      }
      if (result.segmentEnd != null) {
        intersections.add(
          _ParameterizedIntersection(
            point: result.segmentEnd!,
            t: parameter(result.segmentEnd!),
          ),
        );
      }
    }
  }

  // Check hole edges
  for (final hole in polygon.holes) {
    for (final edge in hole.edges) {
      final result = segmentIntersection(p1, p2, edge.$1, edge.$2);
      if (result.isPoint && result.point != null) {
        intersections.add(
          _ParameterizedIntersection(
            point: result.point!,
            t: parameter(result.point!),
          ),
        );
      } else if (result.isCollinear) {
        if (result.segmentStart != null) {
          intersections.add(
            _ParameterizedIntersection(
              point: result.segmentStart!,
              t: parameter(result.segmentStart!),
            ),
          );
        }
        if (result.segmentEnd != null) {
          intersections.add(
            _ParameterizedIntersection(
              point: result.segmentEnd!,
              t: parameter(result.segmentEnd!),
            ),
          );
        }
      }
    }
  }

  // Sort by parameter and remove near-duplicates
  intersections.sort((a, b) => a.t.compareTo(b.t));

  final result = <Offset>[];
  for (final intersection in intersections) {
    if (result.isEmpty ||
        (result.last - intersection.point).distance > _epsilon * 100) {
      result.add(intersection.point);
    }
  }

  return result;
}

class _ParameterizedIntersection {
  const _ParameterizedIntersection({required this.point, required this.t});
  final Offset point;
  final double t;
}

// =============================================================================
// POLYGON-POLYGON INTERSECTION
// =============================================================================
// This is a simplified implementation using the Sutherland-Hodgman algorithm
// for convex clipping, with an extension for concave polygons.
// For full Boost.Geometry overlay functionality, a more complex implementation
// would be needed (using the sweep-line based overlay algorithm).
// =============================================================================

/// Computes the intersection of two polygons.
///
/// Returns a list of polygons representing the intersection region(s).
/// For simple cases (one convex polygon), returns a single polygon.
/// For complex cases, may return multiple polygons.
///
/// Note: This is a simplified implementation. For complex concave polygons
/// with holes, some edge cases may not be handled perfectly.
List<Polygon2D> polygonIntersection(Polygon2D a, Polygon2D b) {
  if (!a.isValid || !b.isValid) return [];

  // Quick rejection using bounding boxes
  final boundsA = Bounds2D.fromPolygon(a);
  final boundsB = Bounds2D.fromPolygon(b);
  if (!boundsA.intersects(boundsB)) return [];

  // For polygons without holes, use the Sutherland-Hodgman algorithm
  if (!a.hasHoles && !b.hasHoles) {
    final result = _sutherlandHodgman(a.exterior.points, b.exterior.points);
    if (result.isEmpty || result.length < 3) return [];
    return [Polygon2D.simple(result)];
  }

  // For polygons with holes, we need a more complex approach
  // This is a simplified version that handles basic cases
  return _intersectPolygonsWithHoles(a, b);
}

/// Sutherland-Hodgman polygon clipping algorithm.
///
/// Clips the subject polygon against each edge of the clip polygon.
List<Offset> _sutherlandHodgman(List<Offset> subject, List<Offset> clip) {
  if (subject.length < 3 || clip.length < 3) return [];

  var output = List<Offset>.from(subject);

  for (int i = 0; i < clip.length; i++) {
    if (output.isEmpty) break;

    final clipEdgeStart = clip[i];
    final clipEdgeEnd = clip[(i + 1) % clip.length];

    final input = output;
    output = [];

    for (int j = 0; j < input.length; j++) {
      final current = input[j];
      final previous = input[(j + input.length - 1) % input.length];

      final currentInside = _isLeftOfLine(current, clipEdgeStart, clipEdgeEnd);
      final previousInside = _isLeftOfLine(
        previous,
        clipEdgeStart,
        clipEdgeEnd,
      );

      if (currentInside) {
        if (!previousInside) {
          // Entering the clip region
          final intersection = _lineIntersection(
            previous,
            current,
            clipEdgeStart,
            clipEdgeEnd,
          );
          if (intersection != null) {
            output.add(intersection);
          }
        }
        output.add(current);
      } else if (previousInside) {
        // Leaving the clip region
        final intersection = _lineIntersection(
          previous,
          current,
          clipEdgeStart,
          clipEdgeEnd,
        );
        if (intersection != null) {
          output.add(intersection);
        }
      }
    }
  }

  return output;
}

/// Checks if a point is on the left side of a directed line.
bool _isLeftOfLine(Offset point, Offset lineStart, Offset lineEnd) {
  return _crossProduct(lineStart, lineEnd, point) >= -_epsilon;
}

/// Computes intersection of two infinite lines.
Offset? _lineIntersection(Offset p1, Offset p2, Offset p3, Offset p4) {
  final dxa = p2.dx - p1.dx;
  final dya = p2.dy - p1.dy;
  final dxb = p4.dx - p3.dx;
  final dyb = p4.dy - p3.dy;

  final denom = dxa * dyb - dya * dxb;
  if (denom.abs() < _epsilon) return null;

  final wx = p1.dx - p3.dx;
  final wy = p1.dy - p3.dy;

  final t = (dxb * wy - dyb * wx) / denom;
  return Offset(p1.dx + t * dxa, p1.dy + t * dya);
}

/// Handles polygon intersection when either polygon has holes.
List<Polygon2D> _intersectPolygonsWithHoles(Polygon2D a, Polygon2D b) {
  // First, intersect the exterior rings
  final exteriorIntersection = _sutherlandHodgman(
    a.exterior.points,
    b.exterior.points,
  );

  if (exteriorIntersection.isEmpty || exteriorIntersection.length < 3) {
    return [];
  }

  // Create initial result polygon
  var resultPoly = Polygon2D.simple(exteriorIntersection);

  // Subtract holes from polygon A
  for (final hole in a.holes) {
    final newResults = <Polygon2D>[];
    // For each current result, subtract the hole
    final subtracted = _subtractHole(resultPoly, hole);
    newResults.addAll(subtracted);
    if (newResults.isEmpty) return [];
    resultPoly = newResults.first;
  }

  // Subtract holes from polygon B
  for (final hole in b.holes) {
    final subtracted = _subtractHole(resultPoly, hole);
    if (subtracted.isEmpty) return [];
    resultPoly = subtracted.first;
  }

  return [resultPoly];
}

/// Subtracts a hole from a polygon.
///
/// This is a simplified implementation that handles common cases.
List<Polygon2D> _subtractHole(Polygon2D polygon, Ring2D hole) {
  // Check if hole intersects the polygon
  final holeBounds = Bounds2D.fromRing(hole);
  final polyBounds = Bounds2D.fromPolygon(polygon);

  if (!holeBounds.intersects(polyBounds)) {
    return [polygon];
  }

  // Check if any hole vertex is inside the polygon
  bool holeIntersectsPolygon = false;
  for (final point in hole.points) {
    if (pointInPolygon(point, polygon) != PointLocation.outside) {
      holeIntersectsPolygon = true;
      break;
    }
  }

  if (!holeIntersectsPolygon) {
    // Also check if any polygon vertex is inside the hole
    final holePoly = Polygon2D(hole);
    for (final point in polygon.exterior.points) {
      if (pointInPolygon(point, holePoly) != PointLocation.outside) {
        holeIntersectsPolygon = true;
        break;
      }
    }
  }

  if (!holeIntersectsPolygon) {
    return [polygon];
  }

  // Add the hole to the polygon
  return [
    Polygon2D(polygon.exterior, [...polygon.holes, hole]),
  ];
}

// =============================================================================
// UTILITY FUNCTIONS
// =============================================================================

/// Computes the signed area of a ring.
///
/// Returns a positive value for counter-clockwise rings,
/// negative for clockwise rings.
double signedArea(Ring2D ring) {
  if (!ring.isValid) return 0;

  double sum = 0;
  final n = ring.length;

  for (int i = 0; i < n; i++) {
    final p1 = ring.points[i];
    final p2 = ring.points[(i + 1) % n];
    sum += p1.dx * p2.dy - p2.dx * p1.dy;
  }

  return sum / 2;
}

/// Computes the unsigned area of a ring.
double ringArea(Ring2D ring) => signedArea(ring).abs();

/// Computes the area of a polygon (exterior minus holes).
double polygonArea(Polygon2D polygon) {
  if (!polygon.isValid) return 0;

  double area = signedArea(polygon.exterior).abs();

  for (final hole in polygon.holes) {
    area -= signedArea(hole).abs();
  }

  return math.max(0, area);
}

/// Returns true if the ring is oriented clockwise.
bool isClockwise(Ring2D ring) => signedArea(ring) < 0;

/// Returns true if the ring is oriented counter-clockwise.
bool isCounterClockwise(Ring2D ring) => signedArea(ring) > 0;

/// Creates a copy of the ring with reversed point order.
Ring2D reverseRing(Ring2D ring) {
  return Ring2D(ring.points.reversed.toList());
}

/// Normalizes a ring to counter-clockwise orientation.
Ring2D normalizeRingCCW(Ring2D ring) {
  return isClockwise(ring) ? reverseRing(ring) : ring;
}

/// Normalizes a ring to clockwise orientation.
Ring2D normalizeRingCW(Ring2D ring) {
  return isCounterClockwise(ring) ? reverseRing(ring) : ring;
}

/// Computes the perimeter of a ring.
double ringPerimeter(Ring2D ring) {
  if (ring.length < 2) return 0;

  double perimeter = 0;
  for (final edge in ring.edges) {
    perimeter += (edge.$2 - edge.$1).distance;
  }
  return perimeter;
}

/// Computes the perimeter of a polygon (all rings).
double polygonPerimeter(Polygon2D polygon) {
  double perimeter = ringPerimeter(polygon.exterior);
  for (final hole in polygon.holes) {
    perimeter += ringPerimeter(hole);
  }
  return perimeter;
}

/// Checks if a polygon is convex.
///
/// A polygon is convex if all vertices turn in the same direction.
bool isConvex(Polygon2D polygon) {
  if (polygon.hasHoles) return false;
  return isRingConvex(polygon.exterior);
}

/// Checks if a ring is convex.
bool isRingConvex(Ring2D ring) {
  if (ring.length < 3) return false;

  bool? isPositive;
  final n = ring.length;

  for (int i = 0; i < n; i++) {
    final p1 = ring.points[i];
    final p2 = ring.points[(i + 1) % n];
    final p3 = ring.points[(i + 2) % n];

    final cross = _crossProduct(p1, p2, p3);

    if (cross.abs() > _epsilon) {
      if (isPositive == null) {
        isPositive = cross > 0;
      } else if ((cross > 0) != isPositive) {
        return false;
      }
    }
  }

  return true;
}

/// Checks if a point is inside the bounding box of a polygon.
bool isPointInBounds(Offset point, Polygon2D polygon) {
  return Bounds2D.fromPolygon(polygon).contains(point);
}

/// Returns the distance from a point to the nearest polygon edge.
double distanceToPolygon(Offset point, Polygon2D polygon) {
  double minDist = double.infinity;

  for (final edge in polygon.exterior.edges) {
    final dist = _distanceToSegment(point, edge.$1, edge.$2);
    if (dist < minDist) minDist = dist;
  }

  for (final hole in polygon.holes) {
    for (final edge in hole.edges) {
      final dist = _distanceToSegment(point, edge.$1, edge.$2);
      if (dist < minDist) minDist = dist;
    }
  }

  return minDist;
}

/// Computes the distance from a point to a line segment.
double _distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final ap = p - a;

  final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
  if (lenSq < _epsilon) {
    // Degenerate segment
    return (p - a).distance;
  }

  // Project point onto line
  var t = (ap.dx * ab.dx + ap.dy * ab.dy) / lenSq;
  t = t.clamp(0.0, 1.0);

  final projection = Offset(a.dx + t * ab.dx, a.dy + t * ab.dy);
  return (p - projection).distance;
}

// =============================================================================
// POLYGON UNION
// =============================================================================
// Based on Boost.Geometry overlay concepts. Uses a simplified approach:
// - For non-overlapping polygons, return both
// - For overlapping polygons, compute merged boundary
// =============================================================================

/// Computes the union of two polygons.
///
/// Returns a list of polygons representing the combined region.
/// - If polygons don't overlap, returns both polygons
/// - If polygons overlap, returns merged polygon(s)
///
/// Note: This is a simplified implementation that works well for convex
/// polygons and simple concave cases.
List<Polygon2D> polygonUnion(Polygon2D a, Polygon2D b) {
  if (!a.isValid) return b.isValid ? [b] : [];
  if (!b.isValid) return [a];

  // Quick check: if bounding boxes don't intersect, return both
  final boundsA = Bounds2D.fromPolygon(a);
  final boundsB = Bounds2D.fromPolygon(b);
  if (!boundsA.intersects(boundsB)) {
    return [a, b];
  }

  // Check if one polygon is entirely inside the other
  final aInB = _isPolygonInsidePolygon(a, b);
  final bInA = _isPolygonInsidePolygon(b, a);

  if (aInB) return [b]; // a is inside b, return b
  if (bInA) return [a]; // b is inside a, return a

  // Check if polygons actually overlap by looking for edge intersections
  final hasIntersection = _polygonsHaveEdgeIntersection(a, b);

  if (!hasIntersection) {
    // No edge intersections - check if one contains the other or they're separate
    // We already checked containment above, so they must be separate
    return [a, b];
  }

  // Polygons overlap - compute union using Weiler-Atherton style approach
  return _computePolygonUnion(a, b);
}

/// Checks if polygon a is entirely inside polygon b.
bool _isPolygonInsidePolygon(Polygon2D a, Polygon2D b) {
  for (final point in a.exterior.points) {
    if (pointInPolygon(point, b) == PointLocation.outside) {
      return false;
    }
  }
  return true;
}

/// Checks if two polygons have any edge intersections.
bool _polygonsHaveEdgeIntersection(Polygon2D a, Polygon2D b) {
  for (final edgeA in a.exterior.edges) {
    for (final edgeB in b.exterior.edges) {
      final result = segmentIntersection(
        edgeA.$1,
        edgeA.$2,
        edgeB.$1,
        edgeB.$2,
      );
      if (result.hasIntersection) {
        return true;
      }
    }
  }
  return false;
}

/// Computes the union of two overlapping polygons.
List<Polygon2D> _computePolygonUnion(Polygon2D a, Polygon2D b) {
  // Collect all vertices and intersection points
  final allPoints = <Offset>[];

  // Add vertices from a that are outside b
  for (final point in a.exterior.points) {
    if (pointInPolygon(point, b) != PointLocation.inside) {
      allPoints.add(point);
    }
  }

  // Add vertices from b that are outside a
  for (final point in b.exterior.points) {
    if (pointInPolygon(point, a) != PointLocation.inside) {
      allPoints.add(point);
    }
  }

  // Add intersection points
  for (final edgeA in a.exterior.edges) {
    for (final edgeB in b.exterior.edges) {
      final result = segmentIntersection(
        edgeA.$1,
        edgeA.$2,
        edgeB.$1,
        edgeB.$2,
      );
      if (result.isPoint && result.point != null) {
        allPoints.add(result.point!);
      }
    }
  }

  if (allPoints.length < 3) {
    // Fallback: return both polygons
    return [a, b];
  }

  // Compute convex hull of all points as a simple approximation
  // For a proper union, we'd need to trace the boundary
  final hull = convexHull(allPoints);
  if (hull.length < 3) {
    return [a, b];
  }

  return [Polygon2D.simple(hull)];
}

// =============================================================================
// POLYGON DIFFERENCE
// =============================================================================
// Subtracts polygon B from polygon A.
// =============================================================================

/// Computes the difference of two polygons (A - B).
///
/// Returns a list of polygons representing A with B removed.
/// If B doesn't overlap A, returns A unchanged.
/// If B completely covers A, returns empty list.
List<Polygon2D> polygonDifference(Polygon2D a, Polygon2D b) {
  if (!a.isValid) return [];
  if (!b.isValid) return [a];

  // Quick check: if bounding boxes don't intersect, return a unchanged
  final boundsA = Bounds2D.fromPolygon(a);
  final boundsB = Bounds2D.fromPolygon(b);
  if (!boundsA.intersects(boundsB)) {
    return [a];
  }

  // Check if a is entirely inside b
  if (_isPolygonInsidePolygon(a, b)) {
    return []; // a is completely covered by b
  }

  // Check if b is entirely inside a
  if (_isPolygonInsidePolygon(b, a)) {
    // b creates a hole in a
    return [
      Polygon2D(a.exterior, [...a.holes, b.exterior]),
    ];
  }

  // Partial overlap - clip a against the inverse of b
  // Use Sutherland-Hodgman with inverted clip region
  final clipped = _clipPolygonDifference(a.exterior.points, b.exterior.points);

  if (clipped.isEmpty || clipped.length < 3) {
    return [];
  }

  return [Polygon2D.simple(clipped)];
}

/// Clips polygon A against the inverse of polygon B.
List<Offset> _clipPolygonDifference(List<Offset> subject, List<Offset> clip) {
  if (subject.length < 3 || clip.length < 3) return subject;

  // For difference, we keep points that are OUTSIDE the clip polygon
  // This is a simplified approach - proper difference is more complex

  final result = <Offset>[];

  // Add subject vertices that are outside clip
  for (final point in subject) {
    final poly = Polygon2D.simple(clip);
    if (pointInPolygon(point, poly) == PointLocation.outside) {
      result.add(point);
    }
  }

  // Add intersection points
  for (int i = 0; i < subject.length; i++) {
    final s1 = subject[i];
    final s2 = subject[(i + 1) % subject.length];

    for (int j = 0; j < clip.length; j++) {
      final c1 = clip[j];
      final c2 = clip[(j + 1) % clip.length];

      final intersection = segmentIntersection(s1, s2, c1, c2);
      if (intersection.isPoint && intersection.point != null) {
        result.add(intersection.point!);
      }
    }
  }

  if (result.length < 3) return subject;

  // Order points by angle from centroid to form a valid polygon
  return _orderPointsByAngle(result);
}

/// Orders points by angle from their centroid.
List<Offset> _orderPointsByAngle(List<Offset> points) {
  if (points.length < 3) return points;

  // Calculate centroid
  double cx = 0, cy = 0;
  for (final p in points) {
    cx += p.dx;
    cy += p.dy;
  }
  cx /= points.length;
  cy /= points.length;

  // Sort by angle
  final sorted = List<Offset>.from(points);
  sorted.sort((a, b) {
    final angleA = math.atan2(a.dy - cy, a.dx - cx);
    final angleB = math.atan2(b.dy - cy, b.dx - cx);
    return angleA.compareTo(angleB);
  });

  return sorted;
}

// =============================================================================
// CLOSEST POINT ALGORITHMS
// =============================================================================
// Based on Boost.Geometry closest_points algorithms.
// =============================================================================

/// Result of closest point calculation.
class ClosestPointResult {
  const ClosestPointResult({
    required this.point,
    required this.distance,
    required this.parameter,
    this.edgeIndex,
  });

  /// The closest point on the geometry.
  final Offset point;

  /// Distance from the query point to the closest point.
  final double distance;

  /// Parameter along the segment/edge (0 to 1).
  final double parameter;

  /// For rings/polygons, the index of the edge containing the closest point.
  final int? edgeIndex;
}

/// Finds the closest point on a segment to a given point.
///
/// Returns the closest point and the parameter t in [0, 1] along the segment.
ClosestPointResult closestPointOnSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final ap = p - a;

  final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
  if (lenSq < _epsilon) {
    // Degenerate segment
    return ClosestPointResult(
      point: a,
      distance: (p - a).distance,
      parameter: 0,
    );
  }

  // Project point onto line
  var t = (ap.dx * ab.dx + ap.dy * ab.dy) / lenSq;
  t = t.clamp(0.0, 1.0);

  final closest = Offset(a.dx + t * ab.dx, a.dy + t * ab.dy);
  return ClosestPointResult(
    point: closest,
    distance: (p - closest).distance,
    parameter: t,
  );
}

/// Finds the closest point on a ring to a given point.
///
/// Returns the closest point, the edge index, and the parameter along that edge.
ClosestPointResult closestPointOnRing(Offset p, Ring2D ring) {
  if (!ring.isValid) {
    return ClosestPointResult(
      point: p,
      distance: double.infinity,
      parameter: 0,
    );
  }

  Offset? bestPoint;
  double bestDistance = double.infinity;
  double bestParameter = 0;
  int bestEdgeIndex = 0;

  int edgeIndex = 0;
  for (final edge in ring.edges) {
    final result = closestPointOnSegment(p, edge.$1, edge.$2);
    if (result.distance < bestDistance) {
      bestDistance = result.distance;
      bestPoint = result.point;
      bestParameter = result.parameter;
      bestEdgeIndex = edgeIndex;
    }
    edgeIndex++;
  }

  return ClosestPointResult(
    point: bestPoint ?? ring.points.first,
    distance: bestDistance,
    parameter: bestParameter,
    edgeIndex: bestEdgeIndex,
  );
}

/// Finds the closest point on a polygon boundary to a given point.
///
/// Searches both exterior ring and all holes.
ClosestPointResult closestPointOnPolygon(Offset p, Polygon2D polygon) {
  if (!polygon.isValid) {
    return ClosestPointResult(
      point: p,
      distance: double.infinity,
      parameter: 0,
    );
  }

  // Check exterior ring
  var best = closestPointOnRing(p, polygon.exterior);

  // Check holes
  for (final hole in polygon.holes) {
    final result = closestPointOnRing(p, hole);
    if (result.distance < best.distance) {
      best = result;
    }
  }

  return best;
}

/// Finds the closest point on a polyline (open path) to a given point.
ClosestPointResult closestPointOnPolyline(Offset p, List<Offset> polyline) {
  if (polyline.isEmpty) {
    return ClosestPointResult(
      point: p,
      distance: double.infinity,
      parameter: 0,
    );
  }

  if (polyline.length == 1) {
    return ClosestPointResult(
      point: polyline.first,
      distance: (p - polyline.first).distance,
      parameter: 0,
    );
  }

  Offset? bestPoint;
  double bestDistance = double.infinity;
  double bestParameter = 0;
  int bestEdgeIndex = 0;

  for (int i = 0; i < polyline.length - 1; i++) {
    final result = closestPointOnSegment(p, polyline[i], polyline[i + 1]);
    if (result.distance < bestDistance) {
      bestDistance = result.distance;
      bestPoint = result.point;
      bestParameter = result.parameter;
      bestEdgeIndex = i;
    }
  }

  return ClosestPointResult(
    point: bestPoint ?? polyline.first,
    distance: bestDistance,
    parameter: bestParameter,
    edgeIndex: bestEdgeIndex,
  );
}

// =============================================================================
// CONVEX HULL (Graham Scan)
// =============================================================================
// Computes the convex hull of a set of points using Graham scan algorithm.
// =============================================================================

/// Computes the convex hull of a set of points.
///
/// Uses the Graham scan algorithm with O(n log n) complexity.
/// Returns the hull vertices in counter-clockwise order.
List<Offset> convexHull(List<Offset> points) {
  if (points.length < 3) return List.from(points);

  // Find the lowest point (and leftmost if tied)
  var lowest = points[0];
  for (final p in points) {
    if (p.dy < lowest.dy || (p.dy == lowest.dy && p.dx < lowest.dx)) {
      lowest = p;
    }
  }

  // Sort points by polar angle with respect to lowest point
  final sorted = List<Offset>.from(points);
  sorted.remove(lowest);
  sorted.sort((a, b) {
    final angleA = math.atan2(a.dy - lowest.dy, a.dx - lowest.dx);
    final angleB = math.atan2(b.dy - lowest.dy, b.dx - lowest.dx);
    if ((angleA - angleB).abs() < _epsilon) {
      // Same angle - closer point first
      final distA = (a - lowest).distance;
      final distB = (b - lowest).distance;
      return distA.compareTo(distB);
    }
    return angleA.compareTo(angleB);
  });

  // Build hull using stack
  final hull = <Offset>[lowest];

  for (final point in sorted) {
    // Remove points that make clockwise turns
    while (hull.length > 1) {
      final top = hull[hull.length - 1];
      final nextToTop = hull[hull.length - 2];
      final cross = _crossProduct(nextToTop, top, point);
      if (cross <= _epsilon) {
        hull.removeLast();
      } else {
        break;
      }
    }
    hull.add(point);
  }

  return hull;
}

// =============================================================================
// DELAUNAY TRIANGULATION (Bowyer-Watson)
// =============================================================================
// Computes a Delaunay triangulation of a set of 2D points using the
// incremental Bowyer-Watson algorithm.
// =============================================================================

/// Computes the Delaunay triangulation of a set of 2D points.
///
/// Returns triangle index triples referencing the input [points] list.
/// Duplicate points are handled via tolerance-based deduplication.
List<(int, int, int)> delaunayTriangulation(List<Offset> points) {
  if (points.length < 3) return [];

  // Deduplicate points with tolerance
  final uniquePoints = <Offset>[];
  final seen = <int, int>{}; // quantized key -> index in uniquePoints
  final indexMap = <int>[]; // original index -> deduped index

  for (final p in points) {
    final key = ((p.dx * 1000).round()) * 100000007 + (p.dy * 1000).round();
    if (seen.containsKey(key)) {
      indexMap.add(seen[key]!);
    } else {
      seen[key] = uniquePoints.length;
      indexMap.add(uniquePoints.length);
      uniquePoints.add(p);
    }
  }

  if (uniquePoints.length < 3) return [];

  // Compute bounding box and create super-triangle
  double minX = uniquePoints[0].dx;
  double maxX = uniquePoints[0].dx;
  double minY = uniquePoints[0].dy;
  double maxY = uniquePoints[0].dy;
  for (final p in uniquePoints) {
    if (p.dx < minX) minX = p.dx;
    if (p.dx > maxX) maxX = p.dx;
    if (p.dy < minY) minY = p.dy;
    if (p.dy > maxY) maxY = p.dy;
  }
  final dx = maxX - minX;
  final dy = maxY - minY;
  final dmax = math.max(dx, dy);
  final midX = (minX + maxX) / 2;
  final midY = (minY + maxY) / 2;

  // Super-triangle vertices (indices n, n+1, n+2)
  final n = uniquePoints.length;
  final st0 = Offset(midX - 20 * dmax, midY - dmax);
  final st1 = Offset(midX, midY + 20 * dmax);
  final st2 = Offset(midX + 20 * dmax, midY - dmax);

  final allPts = [...uniquePoints, st0, st1, st2];

  // Triangle storage: each triangle is (i, j, k) with circumcircle cache
  final triangles = <_DelaunayTri>[];
  triangles.add(_DelaunayTri(n, n + 1, n + 2, allPts));

  // Insert points one by one
  for (var i = 0; i < n; i++) {
    final p = allPts[i];
    final badTriangles = <int>[];

    for (var t = 0; t < triangles.length; t++) {
      if (triangles[t].circumcircleContains(p)) {
        badTriangles.add(t);
      }
    }

    // Find the boundary polygon of the bad triangles
    final polygon = <(int, int)>[];
    for (final t in badTriangles) {
      final tri = triangles[t];
      final edges = [(tri.a, tri.b), (tri.b, tri.c), (tri.c, tri.a)];
      for (final edge in edges) {
        var shared = false;
        for (final other in badTriangles) {
          if (other == t) continue;
          if (triangles[other].hasEdge(edge.$1, edge.$2)) {
            shared = true;
            break;
          }
        }
        if (!shared) polygon.add(edge);
      }
    }

    // Remove bad triangles (in reverse order to preserve indices)
    badTriangles.sort((a, b) => b.compareTo(a));
    for (final idx in badTriangles) {
      triangles.removeAt(idx);
    }

    // Re-triangulate the polygonal hole with the new point
    for (final edge in polygon) {
      triangles.add(_DelaunayTri(edge.$1, edge.$2, i, allPts));
    }
  }

  // Remove triangles that share vertices with the super-triangle
  final result = <(int, int, int)>[];
  for (final tri in triangles) {
    if (tri.a >= n || tri.b >= n || tri.c >= n) continue;
    result.add((tri.a, tri.b, tri.c));
  }

  return result;
}

class _DelaunayTri {
  final int a, b, c;
  final double cx, cy, radiusSq;

  factory _DelaunayTri(int a, int b, int c, List<Offset> points) {
    final pa = points[a];
    final pb = points[b];
    final pc = points[c];

    final ax = pa.dx, ay = pa.dy;
    final bx = pb.dx, by = pb.dy;
    final cxp = pc.dx, cyp = pc.dy;

    final d = 2 * (ax * (by - cyp) + bx * (cyp - ay) + cxp * (ay - by));
    double ccx, ccy;
    if (d.abs() < 1e-12) {
      // Degenerate: collinear points, use centroid as a fallback
      ccx = (ax + bx + cxp) / 3;
      ccy = (ay + by + cyp) / 3;
    } else {
      final aSq = ax * ax + ay * ay;
      final bSq = bx * bx + by * by;
      final cSq = cxp * cxp + cyp * cyp;
      ccx = (aSq * (by - cyp) + bSq * (cyp - ay) + cSq * (ay - by)) / d;
      ccy = (aSq * (cxp - bx) + bSq * (ax - cxp) + cSq * (bx - ax)) / d;
    }
    final rSq = (ax - ccx) * (ax - ccx) + (ay - ccy) * (ay - ccy);
    return _DelaunayTri._internal(a, b, c, ccx, ccy, rSq);
  }

  _DelaunayTri._internal(this.a, this.b, this.c, this.cx, this.cy, this.radiusSq);

  bool circumcircleContains(Offset p) {
    final dx = p.dx - cx;
    final dy = p.dy - cy;
    return dx * dx + dy * dy <= radiusSq + 1e-8;
  }

  bool hasEdge(int p, int q) {
    final verts = {a, b, c};
    return verts.contains(p) && verts.contains(q);
  }
}

// =============================================================================
// ALPHA HULL (Alpha Shape via Delaunay Triangulation)
// =============================================================================
// Computes a concave boundary around a set of 2D points by performing Delaunay
// triangulation and removing triangles with edges exceeding an alpha threshold.
// The alpha threshold is derived from the model's projected face edge lengths.
// =============================================================================

/// Computes the alpha hull (concave boundary) of a set of 2D points.
///
/// [points] — all projected 2D points (including back-face vertices).
/// [modelEdges] — edges from the model's projected faces, used to determine
/// the alpha threshold.
/// [alphaMultiplier] — multiplier applied to the longest model edge to get
/// the alpha threshold. Default is 1.1. Lower values produce tighter
/// boundaries; higher values approach the convex hull.
///
/// Returns the boundary polygon as an ordered list of points, or null if
/// the alpha hull cannot be computed.
List<Offset>? alphaHull(
  List<Offset> points,
  List<(Offset, Offset)> modelEdges, {
  double alphaMultiplier = 1.1,
}) {
  if (points.length < 3) return null;
  if (modelEdges.isEmpty) return null;

  // Compute alpha from the longest model edge * multiplier
  double maxEdgeLen = 0;
  for (final edge in modelEdges) {
    final d = (edge.$2 - edge.$1).distance;
    if (d > maxEdgeLen) maxEdgeLen = d;
  }
  if (maxEdgeLen < _epsilon) return null;
  final alpha = maxEdgeLen * alphaMultiplier;

  // Deduplicate points
  final uniquePoints = <Offset>[];
  final seenKeys = <int>{};
  for (final p in points) {
    final key = ((p.dx * 1000).round()) * 100000007 + (p.dy * 1000).round();
    if (!seenKeys.contains(key)) {
      seenKeys.add(key);
      uniquePoints.add(p);
    }
  }
  if (uniquePoints.length < 3) return null;

  // Delaunay triangulation
  final triangles = delaunayTriangulation(uniquePoints);
  if (triangles.isEmpty) return null;

  // Filter triangles: keep only those where ALL edges <= alpha
  final kept = <(int, int, int)>[];
  for (final tri in triangles) {
    final pa = uniquePoints[tri.$1];
    final pb = uniquePoints[tri.$2];
    final pc = uniquePoints[tri.$3];

    final ab = (pb - pa).distance;
    final bc = (pc - pb).distance;
    final ca = (pa - pc).distance;
    final longest = math.max(ab, math.max(bc, ca));

    if (longest <= alpha) {
      kept.add(tri);
    }
  }

  if (kept.isEmpty) return null;

  // Extract boundary edges (edges that appear in exactly one triangle)
  final edgeCount = <int, int>{};
  int edgeKey(int a, int b) {
    final lo = math.min(a, b);
    final hi = math.max(a, b);
    return lo * 1000000 + hi;
  }

  for (final tri in kept) {
    final edges = [
      edgeKey(tri.$1, tri.$2),
      edgeKey(tri.$2, tri.$3),
      edgeKey(tri.$3, tri.$1),
    ];
    for (final e in edges) {
      edgeCount[e] = (edgeCount[e] ?? 0) + 1;
    }
  }

  final boundaryEdges = <(int, int)>[];
  for (final entry in edgeCount.entries) {
    if (entry.value == 1) {
      final hi = entry.key % 1000000;
      final lo = entry.key ~/ 1000000;
      boundaryEdges.add((lo, hi));
    }
  }

  if (boundaryEdges.isEmpty) return null;

  // Order boundary edges into a closed polygon using adjacency walk
  final adjacency = <int, List<int>>{};
  for (final edge in boundaryEdges) {
    adjacency.putIfAbsent(edge.$1, () => []).add(edge.$2);
    adjacency.putIfAbsent(edge.$2, () => []).add(edge.$1);
  }

  // Start from the leftmost boundary point
  int startIdx = boundaryEdges.first.$1;
  Offset startPt = uniquePoints[startIdx];
  for (final entry in adjacency.entries) {
    final pt = uniquePoints[entry.key];
    if (pt.dx < startPt.dx || (pt.dx == startPt.dx && pt.dy < startPt.dy)) {
      startIdx = entry.key;
      startPt = pt;
    }
  }

  // Walk the boundary
  final ordered = <Offset>[uniquePoints[startIdx]];
  final visited = <int>{startIdx};
  var current = startIdx;

  // Choose first neighbor via rightmost turn (consistent winding)
  var incomingAngle = -math.pi / 2;
  var maxSteps = boundaryEdges.length + 2;

  while (maxSteps-- > 0) {
    final neighbors = adjacency[current];
    if (neighbors == null || neighbors.isEmpty) break;

    int? next;
    double bestTurn = double.negativeInfinity;
    final fromAngle = incomingAngle + math.pi;

    for (final n in neighbors) {
      if (visited.contains(n) && n != startIdx) continue;
      final np = uniquePoints[n];
      final cp = uniquePoints[current];
      final toAngle = math.atan2(np.dy - cp.dy, np.dx - cp.dx);
      var turn = fromAngle - toAngle;
      while (turn > math.pi) {
        turn -= 2 * math.pi;
      }
      while (turn < -math.pi) {
        turn += 2 * math.pi;
      }
      if (turn > bestTurn) {
        bestTurn = turn;
        next = n;
      }
    }

    if (next == null) break;
    if (next == startIdx) break; // closed loop

    final cp = uniquePoints[current];
    final np = uniquePoints[next];
    incomingAngle = math.atan2(np.dy - cp.dy, np.dx - cp.dx);
    visited.add(next);
    ordered.add(np);
    current = next;
  }

  if (ordered.length < 3) return null;

  // Verify we can close the loop (current should connect back to start)
  final finalNeighbors = adjacency[current];
  if (finalNeighbors == null || !finalNeighbors.contains(startIdx)) {
    // Could not form a closed loop — fallback
    if (ordered.length >= 3) return ordered;
    return null;
  }

  return ordered;
}

// =============================================================================
// DOUGLAS-PEUCKER SIMPLIFICATION
// =============================================================================
// Reduces the number of points in a polyline/ring while preserving shape.
// =============================================================================

/// Simplifies a ring using the Douglas-Peucker algorithm.
///
/// Reduces the number of points while maintaining the shape within
/// the given tolerance.
Ring2D simplifyRing(Ring2D ring, double tolerance) {
  if (ring.length <= 3) return ring;

  final simplified = _douglasPeucker(ring.points, tolerance);

  // Ensure ring remains valid
  if (simplified.length < 3) {
    return ring;
  }

  return Ring2D(simplified);
}

/// Simplifies a polygon using the Douglas-Peucker algorithm.
Polygon2D simplifyPolygon(Polygon2D polygon, double tolerance) {
  if (!polygon.isValid) return polygon;

  final simplifiedExterior = simplifyRing(polygon.exterior, tolerance);

  final simplifiedHoles = <Ring2D>[];
  for (final hole in polygon.holes) {
    final simplified = simplifyRing(hole, tolerance);
    if (simplified.isValid) {
      simplifiedHoles.add(simplified);
    }
  }

  return Polygon2D(simplifiedExterior, simplifiedHoles);
}

/// Simplifies a polyline using the Douglas-Peucker algorithm.
List<Offset> simplifyPolyline(List<Offset> polyline, double tolerance) {
  if (polyline.length <= 2) return polyline;
  return _douglasPeucker(polyline, tolerance);
}

/// Douglas-Peucker recursive implementation.
List<Offset> _douglasPeucker(List<Offset> points, double tolerance) {
  if (points.length <= 2) return List.from(points);

  // Find point with maximum distance from line between first and last
  final first = points.first;
  final last = points.last;

  double maxDist = 0;
  int maxIndex = 0;

  for (int i = 1; i < points.length - 1; i++) {
    final dist = _perpendicularDistance(points[i], first, last);
    if (dist > maxDist) {
      maxDist = dist;
      maxIndex = i;
    }
  }

  if (maxDist > tolerance) {
    // Recursively simplify
    final left = _douglasPeucker(points.sublist(0, maxIndex + 1), tolerance);
    final right = _douglasPeucker(points.sublist(maxIndex), tolerance);

    // Combine results (avoiding duplicate at maxIndex)
    return [...left.sublist(0, left.length - 1), ...right];
  } else {
    // All points are within tolerance, return endpoints only
    return [first, last];
  }
}

/// Computes perpendicular distance from a point to a line.
double _perpendicularDistance(Offset p, Offset lineStart, Offset lineEnd) {
  final dx = lineEnd.dx - lineStart.dx;
  final dy = lineEnd.dy - lineStart.dy;

  final lenSq = dx * dx + dy * dy;
  if (lenSq < _epsilon) {
    return (p - lineStart).distance;
  }

  // Calculate perpendicular distance using cross product
  final cross = (p.dx - lineStart.dx) * dy - (p.dy - lineStart.dy) * dx;
  return cross.abs() / math.sqrt(lenSq);
}

// =============================================================================
// SELF-INTERSECTION CHECK
// =============================================================================

/// Checks if a ring is simple (non-self-intersecting).
bool isSimpleRing(Ring2D ring) {
  if (!ring.isValid) return false;

  final n = ring.length;

  // Check each pair of non-adjacent edges
  for (int i = 0; i < n; i++) {
    final a1 = ring.points[i];
    final a2 = ring.points[(i + 1) % n];

    for (int j = i + 2; j < n; j++) {
      // Skip adjacent edges
      if (j == (i + n - 1) % n) continue;

      final b1 = ring.points[j];
      final b2 = ring.points[(j + 1) % n];

      final result = segmentIntersection(a1, a2, b1, b2);
      if (result.isPoint) {
        // Check if intersection is at a shared vertex (allowed)
        final p = result.point!;
        final isAtVertex =
            _isNearPoint(p, a1) ||
            _isNearPoint(p, a2) ||
            _isNearPoint(p, b1) ||
            _isNearPoint(p, b2);

        if (!isAtVertex) {
          return false; // True self-intersection
        }
      } else if (result.isCollinear) {
        return false; // Overlapping edges
      }
    }
  }

  return true;
}

/// Checks if a polygon is simple (no self-intersections).
bool isSimplePolygon(Polygon2D polygon) {
  if (!polygon.isValid) return false;

  // Check exterior ring
  if (!isSimpleRing(polygon.exterior)) return false;

  // Check each hole
  for (final hole in polygon.holes) {
    if (!isSimpleRing(hole)) return false;
  }

  // Check that holes don't intersect each other or the exterior
  // (simplified check - just verify holes are inside exterior)
  for (final hole in polygon.holes) {
    for (final point in hole.points) {
      if (_pointInRing(point, polygon.exterior) == PointLocation.outside) {
        return false;
      }
    }
  }

  return true;
}

/// Checks if two points are nearly equal.
bool _isNearPoint(Offset a, Offset b) {
  return (a - b).distance < _epsilon * 100;
}

// =============================================================================
// POLYGON BUFFER (OFFSET)
// =============================================================================
// Creates an offset polygon by moving all edges outward/inward.
// This is a simplified implementation for convex polygons.
// =============================================================================

/// Creates an offset polygon by moving edges by the given distance.
///
/// Positive distance expands the polygon, negative shrinks it.
/// Note: This is a simplified implementation that works best for convex polygons.
Polygon2D? bufferPolygon(Polygon2D polygon, double distance) {
  if (!polygon.isValid) return null;

  final bufferedExterior = _bufferRing(polygon.exterior, distance);
  if (bufferedExterior == null || bufferedExterior.length < 3) return null;

  final bufferedHoles = <Ring2D>[];
  for (final hole in polygon.holes) {
    // Holes are buffered in the opposite direction
    final buffered = _bufferRing(hole, -distance);
    if (buffered != null && buffered.length >= 3) {
      bufferedHoles.add(Ring2D(buffered));
    }
  }

  return Polygon2D(Ring2D(bufferedExterior), bufferedHoles);
}

/// Buffers a ring by offsetting each edge.
List<Offset>? _bufferRing(Ring2D ring, double distance) {
  if (!ring.isValid) return null;

  final n = ring.length;
  final result = <Offset>[];

  for (int i = 0; i < n; i++) {
    final p1 = ring.points[i];
    final p2 = ring.points[(i + 1) % n];

    // Calculate edge normal
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final len = math.sqrt(dx * dx + dy * dy);

    if (len < _epsilon) continue;

    // Normal pointing outward (assuming CCW winding)
    final nx = -dy / len;
    final ny = dx / len;

    // Offset both endpoints
    final offset1 = Offset(p1.dx + nx * distance, p1.dy + ny * distance);
    final offset2 = Offset(p2.dx + nx * distance, p2.dy + ny * distance);

    result.add(offset1);
    result.add(offset2);
  }

  if (result.length < 6) return null;

  // Intersect adjacent offset edges to find new vertices
  final vertices = <Offset>[];
  for (int i = 0; i < result.length; i += 2) {
    final a1 = result[i];
    final a2 = result[i + 1];
    final b1 = result[(i + 2) % result.length];
    final b2 = result[(i + 3) % result.length];

    final intersection = _lineIntersection(a1, a2, b1, b2);
    if (intersection != null) {
      vertices.add(intersection);
    } else {
      // Parallel edges - use midpoint
      vertices.add(Offset((a2.dx + b1.dx) / 2, (a2.dy + b1.dy) / 2));
    }
  }

  return vertices;
}

// =============================================================================
// OUTLINE TRACING FROM EDGES
// =============================================================================
// Traces a closed outline polygon from a list of unordered edges.
// Used for hit testing where we need a proper polygon boundary.
// =============================================================================

/// Traces a closed outline polygon from a list of unordered edges.
///
/// This algorithm:
/// 1. Builds an adjacency map from edges (point -> connected points), skipping
///    degenerate zero-length edges
/// 2. Starts from the leftmost point (guaranteed to be on outer boundary)
/// 3. Traverses using "rightmost turn" heuristic to stay on outer boundary
/// 4. Removes collinear points from the result
/// 5. Returns closed polygon points (without duplicating the start point)
///
/// The adjacency map uses `Set`-based neighbors, so duplicate edges (common
/// when all faces of a double-sided mesh are visible) are naturally handled
/// — they map to the same adjacency entries.
///
/// Returns null if edges don't form a valid closed loop or are empty.
List<Offset>? traceOutlineFromEdges(List<(Offset, Offset)> edges) {
  if (edges.isEmpty) return null;

  // Build adjacency map with tolerance-based point matching.
  // Degenerate (zero-length) edges are skipped.
  final adjacency = <_PointKey, Set<_PointKey>>{};
  final pointMap = <_PointKey, Offset>{}; // Map keys back to actual offsets

  for (final edge in edges) {
    final keyA = _PointKey(edge.$1);
    final keyB = _PointKey(edge.$2);

    // Skip zero-length (degenerate) edges
    if (keyA == keyB) continue;

    pointMap[keyA] = edge.$1;
    pointMap[keyB] = edge.$2;

    adjacency.putIfAbsent(keyA, () => <_PointKey>{}).add(keyB);
    adjacency.putIfAbsent(keyB, () => <_PointKey>{}).add(keyA);
  }

  if (adjacency.isEmpty) return null;

  // Find leftmost point (guaranteed to be on outer boundary)
  _PointKey startKey = adjacency.keys.first;
  Offset startPoint = pointMap[startKey]!;

  for (final key in adjacency.keys) {
    final point = pointMap[key]!;
    if (point.dx < startPoint.dx ||
        (point.dx == startPoint.dx && point.dy < startPoint.dy)) {
      startKey = key;
      startPoint = point;
    }
  }

  // Trace the outline using rightmost turn heuristic
  final outline = <Offset>[startPoint];
  var currentKey = startKey;
  // Start with direction pointing "up" (negative Y in screen coords)
  var incomingAngle = -math.pi / 2;

  // Take first step - choose the rightmost neighbor from start
  final firstNeighbors = adjacency[currentKey];
  if (firstNeighbors == null || firstNeighbors.isEmpty) return null;

  var nextKey = _findRightmostTurn(
    currentKey,
    firstNeighbors,
    incomingAngle,
    pointMap,
  );

  if (nextKey == null) return null;

  final currentPoint = pointMap[currentKey]!;
  final nextPoint = pointMap[nextKey]!;
  incomingAngle = math.atan2(
    nextPoint.dy - currentPoint.dy,
    nextPoint.dx - currentPoint.dx,
  );

  currentKey = nextKey;
  outline.add(pointMap[currentKey]!);

  // Continue tracing until we return to start
  var steps = 0;
  final maxSteps = edges.length * 2 + 10;

  while (currentKey != startKey && steps < maxSteps) {
    final neighbors = adjacency[currentKey];
    if (neighbors == null || neighbors.isEmpty) break;

    nextKey = _findRightmostTurn(
      currentKey,
      neighbors,
      incomingAngle,
      pointMap,
    );

    if (nextKey == null) break;

    final curr = pointMap[currentKey]!;
    final next = pointMap[nextKey]!;
    incomingAngle = math.atan2(next.dy - curr.dy, next.dx - curr.dx);

    currentKey = nextKey;

    // Don't add start point again - we're about to close the loop
    if (currentKey != startKey) {
      outline.add(pointMap[currentKey]!);
    }

    steps++;
  }

  // Validate we formed a closed loop
  if (currentKey != startKey || outline.length < 3) {
    return null;
  }

  // Remove collinear points from the outline.
  // Three consecutive collinear points mean the middle one is redundant.
  return _removeCollinearPoints(outline);
}

/// Removes collinear (redundant) points from a closed polygon.
///
/// A point is collinear if the cross product of the vectors formed by it
/// and its neighbors is approximately zero.
List<Offset> _removeCollinearPoints(List<Offset> points) {
  if (points.length <= 3) return points;

  final result = <Offset>[];
  final n = points.length;

  for (int i = 0; i < n; i++) {
    final prev = points[(i - 1 + n) % n];
    final curr = points[i];
    final next = points[(i + 1) % n];

    // Cross product of (curr - prev) x (next - curr)
    final cross =
        (curr.dx - prev.dx) * (next.dy - curr.dy) -
        (curr.dy - prev.dy) * (next.dx - curr.dx);

    // Keep the point only if it's not collinear (cross product is non-zero)
    if (cross.abs() > 1e-4) {
      result.add(curr);
    }
  }

  return result.length >= 3 ? result : points;
}

/// Finds the neighbor that represents the "rightmost turn" from the incoming direction.
/// This keeps us on the outer boundary of the shape.
_PointKey? _findRightmostTurn(
  _PointKey current,
  Set<_PointKey> neighbors,
  double incomingAngle,
  Map<_PointKey, Offset> pointMap,
) {
  if (neighbors.isEmpty) return null;

  final currentPoint = pointMap[current]!;
  // Reverse the incoming angle to get the direction we came from
  final fromAngle = incomingAngle + math.pi;

  _PointKey? bestNeighbor;
  double bestTurn = double.negativeInfinity;

  for (final neighbor in neighbors) {
    final neighborPoint = pointMap[neighbor]!;
    final toAngle = math.atan2(
      neighborPoint.dy - currentPoint.dy,
      neighborPoint.dx - currentPoint.dx,
    );

    // Calculate the turn angle (positive = right turn, negative = left turn)
    var turn = fromAngle - toAngle;

    // Normalize to [-pi, pi]
    while (turn > math.pi) {
      turn -= 2 * math.pi;
    }
    while (turn < -math.pi) {
      turn += 2 * math.pi;
    }

    // We want the most negative turn (rightmost = most clockwise)
    // But avoid going back the way we came (turn ≈ 0)
    if (turn.abs() > 0.001 && turn > bestTurn) {
      bestTurn = turn;
      bestNeighbor = neighbor;
    }
  }

  // If no valid turn found, just pick any neighbor that isn't going back
  if (bestNeighbor == null && neighbors.isNotEmpty) {
    for (final neighbor in neighbors) {
      final neighborPoint = pointMap[neighbor]!;
      final toAngle = math.atan2(
        neighborPoint.dy - currentPoint.dy,
        neighborPoint.dx - currentPoint.dx,
      );
      var turn = fromAngle - toAngle;
      while (turn > math.pi) {
        turn -= 2 * math.pi;
      }
      while (turn < -math.pi) {
        turn += 2 * math.pi;
      }
      if (turn.abs() > 0.001) {
        return neighbor;
      }
    }
  }

  return bestNeighbor;
}

/// Key for point matching with tolerance.
class _PointKey {
  final int _x;
  final int _y;

  _PointKey(Offset point)
    : _x = (point.dx * 1000).round(),
      _y = (point.dy * 1000).round();

  @override
  bool operator ==(Object other) =>
      other is _PointKey && other._x == _x && other._y == _y;

  @override
  int get hashCode => _x.hashCode ^ (_y.hashCode * 31);
}
