import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import 'geometry.dart';

/// Tessellate a [Geometry] so that no triangle edge exceeds [maxEdgeLength].
///
/// The algorithm:
/// 1. Fan-triangulates any quads/n-gons into triangles.
/// 2. Iteratively bisects the longest edge of each triangle until all edges
///    are at or below [maxEdgeLength].
/// 3. Deduplicates shared midpoint vertices via an edge-to-vertex map.
///
/// Returns a new [Geometry] with the tessellated faces. The original geometry
/// is not modified.
///
/// If all edges are already within [maxEdgeLength], a shallow copy of the
/// original geometry is returned (faces are triangulated but no subdivision
/// is performed).
Geometry tessellateGeometry(Geometry geo, double maxEdgeLength) {
  if (geo.vertices.isEmpty || geo.faces.isEmpty || maxEdgeLength <= 0) {
    return geo;
  }

  final vertices = geo.vertices.map(Vector3.copy).toList();

  // Step 1: Fan-triangulate all faces.
  var triangles = <List<int>>[];
  for (final face in geo.faces) {
    if (face.length < 3) continue;
    triangles.addAll(_fanTriangulate(face));
  }

  // Step 2: Check if any subdivision is needed at all.
  final maxEdgeSq = maxEdgeLength * maxEdgeLength;
  if (!_anyEdgeExceeds(triangles, vertices, maxEdgeSq)) {
    return Geometry(
      id: geo.id,
      name: geo.name,
      vertices: vertices,
      faces: triangles,
      colorSeed: geo.colorSeed,
    );
  }

  // Step 3: Iterative longest-edge bisection.
  // Edge midpoint cache: canonical edge key -> midpoint vertex index.
  final midpointCache = <int, int>{};

  // Limit iterations to prevent runaway subdivision.
  const maxIterations = 20;
  for (var iteration = 0; iteration < maxIterations; iteration++) {
    var didSubdivide = false;
    final next = <List<int>>[];

    for (final tri in triangles) {
      final a = tri[0], b = tri[1], c = tri[2];
      final va = vertices[a], vb = vertices[b], vc = vertices[c];

      final abSq = _distSq(va, vb);
      final bcSq = _distSq(vb, vc);
      final caSq = _distSq(vc, va);

      // Find the longest edge.
      if (abSq <= maxEdgeSq && bcSq <= maxEdgeSq && caSq <= maxEdgeSq) {
        next.add(tri);
        continue;
      }

      didSubdivide = true;

      if (abSq >= bcSq && abSq >= caSq) {
        final m = _getOrCreateMidpoint(a, b, vertices, midpointCache);
        next.add([a, m, c]);
        next.add([m, b, c]);
      } else if (bcSq >= caSq) {
        final m = _getOrCreateMidpoint(b, c, vertices, midpointCache);
        next.add([a, b, m]);
        next.add([a, m, c]);
      } else {
        final m = _getOrCreateMidpoint(c, a, vertices, midpointCache);
        next.add([a, b, m]);
        next.add([m, b, c]);
      }
    }

    triangles = next;
    if (!didSubdivide) break;
  }

  return Geometry(
    id: geo.id,
    name: geo.name,
    vertices: vertices,
    faces: triangles,
    colorSeed: geo.colorSeed,
  );
}

/// Compute the world-space bounding box of a mesh's geometry, accounting for
/// the mesh's scale transform. Only scale is considered (not rotation), which
/// is a conservative approximation suitable for edge-length estimation.
GeometryBounds? worldSpaceBounds(Geometry geo, Vector3 scale) {
  final localBounds = geometryBounds(geo);
  if (localBounds == null) return null;
  return GeometryBounds(
    Vector3(
      localBounds.min.x * scale.x,
      localBounds.min.y * scale.y,
      localBounds.min.z * scale.z,
    ),
    Vector3(
      localBounds.max.x * scale.x,
      localBounds.max.y * scale.y,
      localBounds.max.z * scale.z,
    ),
  );
}

/// Compute the smallest AABB dimension (width, height, or depth) of a bounds.
/// Returns 0 for degenerate or null bounds.
double smallestDimension(GeometryBounds? bounds) {
  if (bounds == null) return 0;
  final s = bounds.size;
  final sx = s.x.abs(), sy = s.y.abs(), sz = s.z.abs();
  // Skip zero-size dimensions (flat objects).
  var smallest = double.infinity;
  if (sx > 1e-6) smallest = math.min(smallest, sx);
  if (sy > 1e-6) smallest = math.min(smallest, sy);
  if (sz > 1e-6) smallest = math.min(smallest, sz);
  return smallest.isFinite ? smallest : 0;
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Fan-triangulate a polygon face into triangles.
/// For a face [v0, v1, v2, v3, ...], produces triangles:
///   [v0, v1, v2], [v0, v2, v3], ...
List<List<int>> _fanTriangulate(List<int> face) {
  if (face.length == 3) return [face];
  final tris = <List<int>>[];
  for (var i = 1; i < face.length - 1; i++) {
    tris.add([face[0], face[i], face[i + 1]]);
  }
  return tris;
}

/// Squared distance between two Vector3s.
double _distSq(Vector3 a, Vector3 b) {
  final dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z;
  return dx * dx + dy * dy + dz * dz;
}

/// Whether any triangle edge in [triangles] exceeds [maxEdgeSq] (squared).
bool _anyEdgeExceeds(
  List<List<int>> triangles,
  List<Vector3> vertices,
  double maxEdgeSq,
) {
  for (final tri in triangles) {
    final va = vertices[tri[0]], vb = vertices[tri[1]], vc = vertices[tri[2]];
    if (_distSq(va, vb) > maxEdgeSq ||
        _distSq(vb, vc) > maxEdgeSq ||
        _distSq(vc, va) > maxEdgeSq) {
      return true;
    }
  }
  return false;
}

/// Get or create the midpoint vertex for the edge (i, j).
/// Uses a canonical key so (i,j) and (j,i) resolve to the same midpoint.
int _getOrCreateMidpoint(
  int i,
  int j,
  List<Vector3> vertices,
  Map<int, int> cache,
) {
  final key = _edgeKey(i, j);
  final existing = cache[key];
  if (existing != null) return existing;

  final mid = (vertices[i] + vertices[j]) * 0.5;
  final idx = vertices.length;
  vertices.add(mid);
  cache[key] = idx;
  return idx;
}

/// Canonical edge key from two vertex indices.
/// Uses Cantor pairing on the sorted pair for a unique int key.
int _edgeKey(int a, int b) {
  final lo = a < b ? a : b;
  final hi = a < b ? b : a;
  return (lo + hi) * (lo + hi + 1) ~/ 2 + hi;
}
