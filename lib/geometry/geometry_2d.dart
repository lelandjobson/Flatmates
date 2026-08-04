import 'dart:ui';

/// A closed ring of 2D points representing a polygon boundary.
///
/// The ring is implicitly closed - the last point connects back to the first.
/// Points are stored as Flutter [Offset] objects for compatibility with
/// rendering code.
class Ring2D {
  /// Creates a ring from a list of points.
  ///
  /// The ring should have at least 3 points to form a valid polygon boundary.
  /// The ring is implicitly closed (last point connects to first).
  const Ring2D(this.points);

  /// Creates a ring from a list of (x, y) coordinate pairs.
  factory Ring2D.fromCoordinates(List<(double, double)> coords) {
    return Ring2D(coords.map((c) => Offset(c.$1, c.$2)).toList());
  }

  /// The vertices of the ring.
  final List<Offset> points;

  /// Returns true if the ring has enough points to form a valid polygon.
  bool get isValid => points.length >= 3;

  /// Returns the number of points in the ring.
  int get length => points.length;

  /// Returns true if the ring has no points.
  bool get isEmpty => points.isEmpty;

  /// Returns the point at the given index, with wrapping for closed ring access.
  Offset operator [](int index) => points[index % points.length];

  /// Returns an iterable of edges as (start, end) point pairs.
  Iterable<(Offset, Offset)> get edges sync* {
    if (points.length < 2) return;
    for (int i = 0; i < points.length; i++) {
      yield (points[i], points[(i + 1) % points.length]);
    }
  }

  @override
  String toString() => 'Ring2D(${points.length} points)';
}

/// A 2D polygon with an exterior boundary and optional interior holes.
///
/// The exterior ring defines the outer boundary of the polygon.
/// Holes are interior rings that represent areas excluded from the polygon.
///
/// This class follows the conventions from Boost.Geometry:
/// - Exterior ring is typically counter-clockwise (positive area)
/// - Interior rings (holes) are typically clockwise (negative area)
/// - All rings are implicitly closed
class Polygon2D {
  /// Creates a polygon with an exterior ring and optional holes.
  const Polygon2D(this.exterior, [this.holes = const []]);

  /// Creates a simple polygon without holes from a list of points.
  factory Polygon2D.simple(List<Offset> points) {
    return Polygon2D(Ring2D(points));
  }

  /// Creates a simple polygon from coordinate pairs.
  factory Polygon2D.fromCoordinates(List<(double, double)> coords) {
    return Polygon2D(Ring2D.fromCoordinates(coords));
  }

  /// The exterior boundary ring.
  final Ring2D exterior;

  /// Interior rings representing holes in the polygon.
  final List<Ring2D> holes;

  /// Returns true if the polygon has a valid exterior ring.
  bool get isValid => exterior.isValid;

  /// Returns true if the polygon has any holes.
  bool get hasHoles => holes.isNotEmpty;

  /// Returns the total number of rings (exterior + holes).
  int get ringCount => 1 + holes.length;

  @override
  String toString() {
    if (holes.isEmpty) {
      return 'Polygon2D(${exterior.length} points)';
    }
    return 'Polygon2D(${exterior.length} points, ${holes.length} holes)';
  }
}

/// Axis-aligned bounding box for 2D geometry.
class Bounds2D {
  /// Creates bounds from min and max corners.
  const Bounds2D(this.min, this.max);

  /// Creates bounds that contain all the given points.
  factory Bounds2D.fromPoints(Iterable<Offset> points) {
    final iter = points.iterator;
    if (!iter.moveNext()) {
      return const Bounds2D(Offset.zero, Offset.zero);
    }

    var minX = iter.current.dx;
    var minY = iter.current.dy;
    var maxX = minX;
    var maxY = minY;

    while (iter.moveNext()) {
      final p = iter.current;
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }

    return Bounds2D(Offset(minX, minY), Offset(maxX, maxY));
  }

  /// Creates bounds from a ring.
  factory Bounds2D.fromRing(Ring2D ring) => Bounds2D.fromPoints(ring.points);

  /// Creates bounds from a polygon (exterior ring only).
  factory Bounds2D.fromPolygon(Polygon2D polygon) =>
      Bounds2D.fromRing(polygon.exterior);

  /// The minimum corner (bottom-left in standard coordinates).
  final Offset min;

  /// The maximum corner (top-right in standard coordinates).
  final Offset max;

  /// The width of the bounds.
  double get width => max.dx - min.dx;

  /// The height of the bounds.
  double get height => max.dy - min.dy;

  /// The center point of the bounds.
  Offset get center => Offset((min.dx + max.dx) / 2, (min.dy + max.dy) / 2);

  /// The size of the bounds as an Offset (width, height).
  Offset get size => Offset(width, height);

  /// Returns true if this bounds contains the given point.
  bool contains(Offset point) {
    return point.dx >= min.dx &&
        point.dx <= max.dx &&
        point.dy >= min.dy &&
        point.dy <= max.dy;
  }

  /// Returns true if this bounds intersects with another bounds.
  bool intersects(Bounds2D other) {
    return min.dx <= other.max.dx &&
        max.dx >= other.min.dx &&
        min.dy <= other.max.dy &&
        max.dy >= other.min.dy;
  }

  /// Returns the intersection of this bounds with another, or null if they don't intersect.
  Bounds2D? intersection(Bounds2D other) {
    if (!intersects(other)) return null;

    return Bounds2D(
      Offset(
        min.dx > other.min.dx ? min.dx : other.min.dx,
        min.dy > other.min.dy ? min.dy : other.min.dy,
      ),
      Offset(
        max.dx < other.max.dx ? max.dx : other.max.dx,
        max.dy < other.max.dy ? max.dy : other.max.dy,
      ),
    );
  }

  /// Returns the union of this bounds with another.
  Bounds2D union(Bounds2D other) {
    return Bounds2D(
      Offset(
        min.dx < other.min.dx ? min.dx : other.min.dx,
        min.dy < other.min.dy ? min.dy : other.min.dy,
      ),
      Offset(
        max.dx > other.max.dx ? max.dx : other.max.dx,
        max.dy > other.max.dy ? max.dy : other.max.dy,
      ),
    );
  }

  @override
  String toString() => 'Bounds2D($min, $max)';
}
