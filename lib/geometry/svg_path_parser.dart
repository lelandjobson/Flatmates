import 'dart:math' as math;
import 'package:vector_math/vector_math_64.dart' hide Colors;

/// Parses an SVG `<path d="...">` string into a polygon outline suitable
/// for use as 3D geometry vertices.
///
/// Supports M, L, H, V, C, S, Q, T, A, Z (and lowercase relative variants).
/// Bezier curves are linearized via adaptive subdivision.
class SvgPathParser {
  SvgPathParser({this.curveTolerance = 1.0});

  /// Maximum deviation (in SVG units) before a bezier segment is subdivided.
  final double curveTolerance;

  /// Parse [pathData] and return a list of closed sub-path outlines.
  /// Each sub-path is a list of 2D points (x, y) in SVG coordinate space.
  List<List<_Point>> parseRaw(String pathData) {
    final tokens = _tokenize(pathData);
    final subPaths = <List<_Point>>[];
    var current = _Point(0, 0);
    var subPathStart = current;
    var lastControl = current;
    var currentPath = <_Point>[];
    String? lastCommand;

    int i = 0;

    void addPoint(_Point p) {
      if (currentPath.isEmpty || currentPath.last != p) {
        currentPath.add(p);
      }
    }

    void closePath() {
      if (currentPath.isNotEmpty) {
        addPoint(subPathStart);
        subPaths.add(currentPath);
        currentPath = <_Point>[];
      }
      current = subPathStart;
    }

    while (i < tokens.length) {
      final token = tokens[i];
      if (_isCommand(token)) {
        lastCommand = token;
        i++;
      } else if (lastCommand == null) {
        i++;
        continue;
      }

      final cmd = lastCommand;
      final rel = cmd == cmd.toLowerCase();
      final base = rel ? current : _Point(0, 0);

      switch (cmd.toUpperCase()) {
        case 'M':
          final x = _num(tokens, i++);
          final y = _num(tokens, i++);
          if (currentPath.isNotEmpty) {
            subPaths.add(currentPath);
            currentPath = <_Point>[];
          }
          current = _Point(base.x + x, base.y + y);
          subPathStart = current;
          addPoint(current);
          lastCommand = rel ? 'l' : 'L';
          break;

        case 'L':
          final x = _num(tokens, i++);
          final y = _num(tokens, i++);
          current = _Point(base.x + x, base.y + y);
          addPoint(current);
          break;

        case 'H':
          final x = _num(tokens, i++);
          current = _Point(rel ? current.x + x : x, current.y);
          addPoint(current);
          break;

        case 'V':
          final y = _num(tokens, i++);
          current = _Point(current.x, rel ? current.y + y : y);
          addPoint(current);
          break;

        case 'C':
          final x1 = base.x + _num(tokens, i++);
          final y1 = base.y + _num(tokens, i++);
          final x2 = base.x + _num(tokens, i++);
          final y2 = base.y + _num(tokens, i++);
          final x = base.x + _num(tokens, i++);
          final y = base.y + _num(tokens, i++);
          _subdivideCubic(
            current,
            _Point(x1, y1),
            _Point(x2, y2),
            _Point(x, y),
            addPoint,
          );
          lastControl = _Point(x2, y2);
          current = _Point(x, y);
          break;

        case 'S':
          final cx1 = 2 * current.x - lastControl.x;
          final cy1 = 2 * current.y - lastControl.y;
          final x2 = base.x + _num(tokens, i++);
          final y2 = base.y + _num(tokens, i++);
          final x = base.x + _num(tokens, i++);
          final y = base.y + _num(tokens, i++);
          _subdivideCubic(
            current,
            _Point(cx1, cy1),
            _Point(x2, y2),
            _Point(x, y),
            addPoint,
          );
          lastControl = _Point(x2, y2);
          current = _Point(x, y);
          break;

        case 'Q':
          final x1 = base.x + _num(tokens, i++);
          final y1 = base.y + _num(tokens, i++);
          final x = base.x + _num(tokens, i++);
          final y = base.y + _num(tokens, i++);
          _subdivideQuadratic(
            current,
            _Point(x1, y1),
            _Point(x, y),
            addPoint,
          );
          lastControl = _Point(x1, y1);
          current = _Point(x, y);
          break;

        case 'T':
          final cx = 2 * current.x - lastControl.x;
          final cy = 2 * current.y - lastControl.y;
          final x = base.x + _num(tokens, i++);
          final y = base.y + _num(tokens, i++);
          _subdivideQuadratic(
            current,
            _Point(cx, cy),
            _Point(x, y),
            addPoint,
          );
          lastControl = _Point(cx, cy);
          current = _Point(x, y);
          break;

        case 'A':
          final rx = _num(tokens, i++);
          final ry = _num(tokens, i++);
          final rotation = _num(tokens, i++);
          final largeArc = _num(tokens, i++).toInt();
          final sweep = _num(tokens, i++).toInt();
          final x = base.x + _num(tokens, i++);
          final y = base.y + _num(tokens, i++);
          _approximateArc(
            current,
            rx,
            ry,
            rotation,
            largeArc != 0,
            sweep != 0,
            _Point(x, y),
            addPoint,
          );
          current = _Point(x, y);
          break;

        case 'Z':
          closePath();
          break;

        default:
          i++;
      }
    }

    if (currentPath.isNotEmpty) {
      subPaths.add(currentPath);
    }

    return subPaths;
  }

  /// Parse the SVG path and return vertices as [Vector3] (x in SVG-X, y in
  /// SVG-Y, z = 0). The outline is scaled and centered so the bounding box
  /// fits within [targetSize] and the centroid is at the origin. SVG's Y-down
  /// is flipped to Y-up.
  List<Vector3> parse(String pathData, {double targetSize = 512.0}) {
    final subPaths = parseRaw(pathData);
    if (subPaths.isEmpty) return [];

    final all = subPaths.expand((p) => p).toList();
    if (all.isEmpty) return [];

    var minX = all[0].x, maxX = all[0].x;
    var minY = all[0].y, maxY = all[0].y;
    for (final p in all) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }

    final w = maxX - minX;
    final h = maxY - minY;
    if (w == 0 && h == 0) return [];

    final scale = targetSize / math.max(w, h);
    final cx = (minX + maxX) / 2;
    final cy = (minY + maxY) / 2;

    final longest = subPaths.reduce(
      (a, b) => a.length >= b.length ? a : b,
    );

    return longest.map((p) {
      final x = (p.x - cx) * scale;
      final y = -(p.y - cy) * scale; // flip Y
      return Vector3(x, y, 0);
    }).toList();
  }

  // ── Tokenizer ──

  static final _tokenPattern = RegExp(
    r'[MmLlHhVvCcSsQqTtAaZz]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?',
  );

  static List<String> _tokenize(String d) =>
      _tokenPattern.allMatches(d).map((m) => m.group(0)!).toList();

  static bool _isCommand(String t) => t.length == 1 && RegExp(r'[A-Za-z]').hasMatch(t);

  static double _num(List<String> tokens, int index) {
    if (index >= tokens.length) return 0;
    return double.tryParse(tokens[index]) ?? 0;
  }

  // ── Bezier Subdivision ──

  void _subdivideCubic(
    _Point p0,
    _Point p1,
    _Point p2,
    _Point p3,
    void Function(_Point) emit,
  ) {
    final flatness = _cubicFlatness(p0, p1, p2, p3);
    if (flatness <= curveTolerance) {
      emit(p3);
      return;
    }
    final mid01 = _mid(p0, p1);
    final mid12 = _mid(p1, p2);
    final mid23 = _mid(p2, p3);
    final mid012 = _mid(mid01, mid12);
    final mid123 = _mid(mid12, mid23);
    final mid0123 = _mid(mid012, mid123);
    _subdivideCubic(p0, mid01, mid012, mid0123, emit);
    _subdivideCubic(mid0123, mid123, mid23, p3, emit);
  }

  void _subdivideQuadratic(
    _Point p0,
    _Point p1,
    _Point p2,
    void Function(_Point) emit,
  ) {
    _subdivideCubic(
      p0,
      _Point(p0.x + 2 / 3 * (p1.x - p0.x), p0.y + 2 / 3 * (p1.y - p0.y)),
      _Point(p2.x + 2 / 3 * (p1.x - p2.x), p2.y + 2 / 3 * (p1.y - p2.y)),
      p2,
      emit,
    );
  }

  static double _cubicFlatness(_Point p0, _Point p1, _Point p2, _Point p3) {
    final ux = 3 * p1.x - 2 * p0.x - p3.x;
    final uy = 3 * p1.y - 2 * p0.y - p3.y;
    final vx = 3 * p2.x - 2 * p3.x - p0.x;
    final vy = 3 * p2.y - 2 * p3.y - p0.y;
    return math.max(ux * ux + uy * uy, vx * vx + vy * vy);
  }

  static _Point _mid(_Point a, _Point b) =>
      _Point((a.x + b.x) / 2, (a.y + b.y) / 2);

  // ── Arc Approximation ──

  void _approximateArc(
    _Point from,
    double rx,
    double ry,
    double xAxisRotationDeg,
    bool largeArc,
    bool sweep,
    _Point to,
    void Function(_Point) emit,
  ) {
    if (rx == 0 || ry == 0) {
      emit(to);
      return;
    }
    const steps = 16;
    for (int s = 1; s <= steps; s++) {
      final t = s / steps;
      emit(_Point(
        from.x + (to.x - from.x) * t,
        from.y + (to.y - from.y) * t,
      ));
    }
  }
}

class _Point {
  const _Point(this.x, this.y);
  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _Point && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

/// Triangulates a simple polygon using ear-clipping.
///
/// [vertices] should be a list of coplanar [Vector3] points forming a simple
/// polygon (no self-intersections). Returns a list of triangle faces, where
/// each face is a list of 3 vertex indices into [vertices].
List<List<int>> triangulatePolygon(List<Vector3> vertices) {
  if (vertices.length < 3) return [];
  if (vertices.length == 3) return [[0, 1, 2]];

  final n = vertices.length;
  final indices = List<int>.generate(n, (i) => i);
  final faces = <List<int>>[];

  final area = _signedArea2D(vertices, indices);
  if (area < 0) {
    indices.setAll(0, indices.reversed);
  }

  while (indices.length > 3) {
    bool earFound = false;
    for (int i = 0; i < indices.length; i++) {
      final prev = (i - 1 + indices.length) % indices.length;
      final next = (i + 1) % indices.length;
      final a = indices[prev];
      final b = indices[i];
      final c = indices[next];

      if (!_isConvex(vertices[a], vertices[b], vertices[c])) continue;

      bool containsPoint = false;
      for (int j = 0; j < indices.length; j++) {
        if (j == prev || j == i || j == next) continue;
        if (_pointInTriangle(
          vertices[indices[j]],
          vertices[a],
          vertices[b],
          vertices[c],
        )) {
          containsPoint = true;
          break;
        }
      }

      if (!containsPoint) {
        faces.add([a, b, c]);
        indices.removeAt(i);
        earFound = true;
        break;
      }
    }
    if (!earFound) break;
  }

  if (indices.length == 3) {
    faces.add([indices[0], indices[1], indices[2]]);
  }

  return faces;
}

double _signedArea2D(List<Vector3> verts, List<int> indices) {
  double area = 0;
  for (int i = 0; i < indices.length; i++) {
    final j = (i + 1) % indices.length;
    final vi = verts[indices[i]];
    final vj = verts[indices[j]];
    area += vi.x * vj.y - vj.x * vi.y;
  }
  return area;
}

bool _isConvex(Vector3 a, Vector3 b, Vector3 c) {
  return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x) > 0;
}

bool _pointInTriangle(Vector3 p, Vector3 a, Vector3 b, Vector3 c) {
  final d1 = _sign(p, a, b);
  final d2 = _sign(p, b, c);
  final d3 = _sign(p, c, a);
  final hasNeg = (d1 < 0) || (d2 < 0) || (d3 < 0);
  final hasPos = (d1 > 0) || (d2 > 0) || (d3 > 0);
  return !(hasNeg && hasPos);
}

double _sign(Vector3 p1, Vector3 p2, Vector3 p3) {
  return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y);
}
