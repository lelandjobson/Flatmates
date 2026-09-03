import 'package:vector_math/vector_math_64.dart';

/// One outward face that touches an outline edge.
class OutlineFace {
  const OutlineFace({
    required this.normal,
    required this.center,
  });

  final Vector3 normal;
  final Vector3 center;

  bool faces(Vector3 camera) => normal.dot(camera - center) > 1e-6;
}

/// World-space crease or silhouette candidate.
class OutlineEdge {
  const OutlineEdge({
    required this.a,
    required this.b,
    required this.faces,
  });

  final Vector3 a;
  final Vector3 b;
  final List<OutlineFace> faces;
}

/// A polygon plus its outward normal, used to build outer edges.
class OutlineQuad {
  const OutlineQuad({
    required this.points,
    required this.normal,
  });

  final List<Vector3> points;
  final Vector3 normal;
}

/// True when this edge is a silhouette or a crease on a front face.
bool outlineEdgeVisible(OutlineEdge edge, Vector3 camera) {
  if (edge.faces.isEmpty) return false;
  if (edge.faces.length == 1) return edge.faces.single.faces(camera);
  final a = edge.faces[0].faces(camera);
  final b = edge.faces[1].faces(camera);
  if (a != b) return true;
  if (!a) return false;
  return edge.faces[0].normal.dot(edge.faces[1].normal) < 0.999;
}

/// Unique outer edges: drop coplanar joins inside a larger face.
List<OutlineEdge> collectOuterEdges(Iterable<OutlineQuad> quads) {
  final adjacent = <_EdgeKey, List<OutlineFace>>{};
  for (final quad in quads) {
    if (quad.points.length < 3) continue;
    final face = OutlineFace(normal: quad.normal, center: _average(quad.points));
    for (var i = 0; i < quad.points.length; i++) {
      final a = quad.points[i];
      final b = quad.points[(i + 1) % quad.points.length];
      adjacent.putIfAbsent(_EdgeKey(a, b), () => []).add(face);
    }
  }

  final edges = <OutlineEdge>[];
  for (final entry in adjacent.entries) {
    final faces = entry.value;
    if (faces.length >= 2 &&
        faces[0].normal.dot(faces[1].normal) >= 0.999) {
      continue;
    }
    edges.add(
      OutlineEdge(
        a: entry.key.a,
        b: entry.key.b,
        faces: faces.length <= 2 ? faces : faces.sublist(0, 2),
      ),
    );
  }
  return edges;
}

Vector3 _average(List<Vector3> pts) {
  final mid = Vector3.zero();
  for (final p in pts) {
    mid.add(p);
  }
  mid.scale(1 / pts.length);
  return mid;
}

class _EdgeKey {
  factory _EdgeKey(Vector3 a, Vector3 b) {
    final aq = _quantize(a);
    final bq = _quantize(b);
    if (_less(aq, bq)) return _EdgeKey._(aq, bq, a, b);
    return _EdgeKey._(bq, aq, b, a);
  }

  _EdgeKey._(this._a, this._b, this.a, this.b);

  final (int, int, int) _a;
  final (int, int, int) _b;
  final Vector3 a;
  final Vector3 b;

  static (int, int, int) _quantize(Vector3 p) => (
        (p.x * 1000).round(),
        (p.y * 1000).round(),
        (p.z * 1000).round(),
      );

  static bool _less((int, int, int) a, (int, int, int) b) {
    if (a.$1 != b.$1) return a.$1 < b.$1;
    if (a.$2 != b.$2) return a.$2 < b.$2;
    return a.$3 < b.$3;
  }

  @override
  bool operator ==(Object other) =>
      other is _EdgeKey && other._a == _a && other._b == _b;

  @override
  int get hashCode => Object.hash(_a, _b);
}
