import 'dart:ui';

import '../geometry/geometry_2d.dart';
import '../geometry/geometry_algorithms.dart';
import '../geometry/polygon_union.dart';
import '../papercut/paper.dart';

/// Half a grid unit. A press farther than this from every piece misses.
const double kPiecePickTolerance = 0.5;

const int _kLeafCapacity = 4;

/// Axis-aligned quadtree of piece bounds in drawn space.
///
/// A query returns the pieces whose bounds meet the search rectangle. The
/// caller distance-tests that set, not the whole sheet.
class PieceQuadtree {
  PieceQuadtree(this.bounds, {this.minSize = 1}) : _root = _nodeFor(bounds) {
    for (var i = 0; i < bounds.length; i++) {
      if (bounds[i].isEmpty) continue;
      _insert(_root, i);
    }
  }

  final List<Rect> bounds;
  final double minSize;
  final _Node _root;

  List<int> query(Rect region) {
    final out = <int>[];
    _query(_root, region, out);
    return out;
  }

  void _insert(_Node node, int id) {
    final rect = bounds[id];
    final children = node.children;
    if (children != null) {
      final child = _soleChild(children, rect);
      if (child != null) {
        _insert(child, id);
        return;
      }
    }
    node.items.add(id);
    if (children == null &&
        node.items.length > _kLeafCapacity &&
        node.bounds.width > minSize &&
        node.bounds.height > minSize) {
      _split(node);
    }
  }

  void _split(_Node node) {
    final children = _quarters(node.bounds);
    node.children = children;
    final staying = <int>[];
    for (final id in node.items) {
      final child = _soleChild(children, bounds[id]);
      if (child == null) {
        staying.add(id);
      } else {
        _insert(child, id);
      }
    }
    node.items
      ..clear()
      ..addAll(staying);
  }

  void _query(_Node node, Rect region, List<int> out) {
    if (!_meets(node.bounds, region)) return;
    for (final id in node.items) {
      if (_meets(bounds[id], region)) out.add(id);
    }
    final children = node.children;
    if (children == null) return;
    for (final child in children) {
      _query(child, region, out);
    }
  }

  static _Node? _soleChild(List<_Node> children, Rect rect) {
    _Node? found;
    for (final child in children) {
      if (!_contains(child.bounds, rect)) continue;
      if (found != null) return null;
      found = child;
    }
    return found;
  }

  static bool _meets(Rect a, Rect b) {
    return a.left <= b.right &&
        b.left <= a.right &&
        a.top <= b.bottom &&
        b.top <= a.bottom;
  }

  static bool _contains(Rect outer, Rect inner) {
    return inner.left >= outer.left &&
        inner.right <= outer.right &&
        inner.top >= outer.top &&
        inner.bottom <= outer.bottom;
  }

  static List<_Node> _quarters(Rect bounds) {
    final midX = (bounds.left + bounds.right) / 2;
    final midY = (bounds.top + bounds.bottom) / 2;
    return [
      _Node(Rect.fromLTRB(bounds.left, bounds.top, midX, midY)),
      _Node(Rect.fromLTRB(midX, bounds.top, bounds.right, midY)),
      _Node(Rect.fromLTRB(bounds.left, midY, midX, bounds.bottom)),
      _Node(Rect.fromLTRB(midX, midY, bounds.right, bounds.bottom)),
    ];
  }

  static _Node _nodeFor(List<Rect> bounds) {
    Rect? union;
    for (final rect in bounds) {
      if (rect.isEmpty) continue;
      union = union == null ? rect : union.expandToInclude(rect);
    }
    return _Node(union ?? Rect.zero);
  }
}

class _Node {
  _Node(this.bounds);

  final Rect bounds;
  final List<int> items = [];
  List<_Node>? children;
}

/// Drawn bounds of [piece], including its separation nudge.
Rect drawnPieceBounds(PapercutPiece piece) {
  if (piece.vertices.isEmpty) return Rect.zero;
  final shift = piece.separation;
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = -double.infinity;
  var maxY = -double.infinity;
  for (final vertex in piece.vertices) {
    final x = vertex.dx + shift.dx;
    final y = vertex.dy + shift.dy;
    if (x < minX) minX = x;
    if (y < minY) minY = y;
    if (x > maxX) maxX = x;
    if (y > maxY) maxY = y;
  }
  if (maxX - minX < 1e-9 && maxY - minY < 1e-9) return Rect.zero;
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

/// Index of the closest piece within [kPiecePickTolerance] grid units of
/// [point]. Distance is zero on the paper and the boundary distance otherwise.
/// The quadtree supplies the candidates.
int? closestPieceIndex({
  required Offset point,
  required List<PapercutPiece> pieces,
  required double unit,
}) {
  if (pieces.isEmpty || unit <= 0) return null;
  final reach = kPiecePickTolerance * unit;
  final bounds = [for (final piece in pieces) drawnPieceBounds(piece)];
  final tree = PieceQuadtree(bounds, minSize: unit);
  final region = Rect.fromCircle(center: point, radius: reach);
  var best = double.infinity;
  var bestIndex = -1;
  for (final index in tree.query(region)) {
    final distance = _paperDistance(point - pieces[index].separation, pieces[index]);
    if (distance > reach) continue;
    if (distance < best - 1e-9 || (distance <= best + 1e-9 && index > bestIndex)) {
      best = distance;
      bestIndex = index;
    }
  }
  return bestIndex < 0 ? null : bestIndex;
}

double _paperDistance(Offset local, PapercutPiece piece) {
  if (piece.vertices.length < 3) return double.infinity;
  var onPaper = isInsidePolygon(local, piece.vertices);
  if (onPaper) {
    for (final hole in piece.holes) {
      if (hole.length >= 3 && isInsidePolygon(local, hole)) {
        onPaper = false;
        break;
      }
    }
  }
  if (onPaper) return 0;
  return distanceToPolygon(
    local,
    Polygon2D(
      Ring2D(piece.vertices),
      [for (final hole in piece.holes) if (hole.length >= 3) Ring2D(hole)],
    ),
  );
}
