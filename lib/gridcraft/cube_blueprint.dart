import 'dart:math' as math;
import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

import 'blueprint.dart';

/// Edge length of the folded cube, and of every square in the net.
const double kCubeFace = 6;

/// One closed face of the folded solid.
class CubeFace {
  const CubeFace({
    required this.stepIndex,
    required this.role,
    required this.corners,
  });

  /// Blueprint step this square belongs to.
  final int stepIndex;

  final CubeFaceRole role;

  /// Four corners of the quad, in ring order.
  final List<Vector3> corners;
}

enum CubeFaceRole { front, back, left, right, top, bottom }

/// Latin cross of a 6×6×6 cube. The hub at (6, 6)–(12, 12) is the front.
///
/// Each shared side is penciled on both squares. Every outer edge stays penned.
GridBlueprint cubeBlueprint() {
  List<Offset> square(double left, double bottom) {
    return [
      Offset(left, bottom),
      Offset(left + kCubeFace, bottom),
      Offset(left + kCubeFace, bottom + kCubeFace),
      Offset(left, bottom + kCubeFace),
    ];
  }

  List<EdgeStyle> edges({
    bool bottom = false,
    bool right = false,
    bool top = false,
    bool left = false,
  }) {
    EdgeStyle style(bool fold) => fold ? EdgeStyle.penciled : EdgeStyle.penned;
    return [style(bottom), style(right), style(top), style(left)];
  }

  return GridBlueprint(
    id: 'cube',
    name: 'Cube',
    steps: [
      GridStep(
        id: 'cube',
        label: 'Cube',
        gridSpacing: 1,
        paperMargin: 2,
        polygons: [
          square(6, 6),
          square(0, 6),
          square(12, 6),
          square(18, 6),
          square(6, 12),
          square(6, 0),
        ],
        edgeStyles: [
          edges(bottom: true, right: true, top: true, left: true),
          edges(right: true),
          edges(right: true, left: true),
          edges(left: true),
          edges(bottom: true),
          edges(top: true),
        ],
      ),
    ],
  );
}

/// Six quads of a cube folded from [cubeBlueprint]'s net.
///
/// The square with four penciled edges is the front. Its neighbors are left,
/// right, top, and bottom. The remaining square, past the left or right arm,
/// is the back. Any other blueprint returns null.
List<CubeFace>? foldedCube(GridBlueprint blueprint) {
  if (blueprint.steps.length != 1) return null;
  final step = blueprint.steps.single;
  if (step.polygons.length != CubeFaceRole.values.length) return null;

  final squares = <_NetSquare>[];
  for (var i = 0; i < step.polygons.length; i++) {
    if (!step.isRingClosed(i)) return null;
    final bounds = _faceBounds(step.polygons[i]);
    if (bounds == null) return null;
    squares.add(
      _NetSquare(
        bounds: bounds,
        ring: step.polygons[i],
        styles: step.edgeStyleOf(i),
      ),
    );
  }

  final hubs = squares.where((square) => square.penciledCount == 4).toList();
  if (hubs.length != 1) return null;
  final hub = hubs.single;

  final neighbors = <CubeFaceRole, _NetSquare>{};
  final attached = <_NetSquare>[];
  for (final square in squares) {
    if (identical(square, hub)) continue;
    if (!_sharesFold(hub, square)) continue;
    final role = _sideOf(hub, square);
    if (role == null || neighbors.containsKey(role)) return null;
    neighbors[role] = square;
    attached.add(square);
  }
  const arms = [
    CubeFaceRole.left,
    CubeFaceRole.right,
    CubeFaceRole.top,
    CubeFaceRole.bottom,
  ];
  if (arms.any((role) => !neighbors.containsKey(role))) return null;

  final leftover = [
    for (final square in squares)
      if (!identical(square, hub) && !attached.contains(square)) square,
  ];
  if (leftover.length != 1) return null;
  final back = leftover.single;
  final beside = neighbors[CubeFaceRole.left]!;
  final other = neighbors[CubeFaceRole.right]!;
  if (!_sharesFold(back, beside) && !_sharesFold(back, other)) return null;

  const half = kCubeFace / 2;
  Vector3 corner(double x, double y, double z) => Vector3(x, y, z);
  List<Vector3> quad(List<(double, double, double)> points) => [
    for (final point in points) corner(point.$1, point.$2, point.$3),
  ];

  return [
    CubeFace(
      stepIndex: 0,
      role: CubeFaceRole.front,
      corners: quad([
        (-half, -half, half),
        (half, -half, half),
        (half, half, half),
        (-half, half, half),
      ]),
    ),
    CubeFace(
      stepIndex: 0,
      role: CubeFaceRole.back,
      corners: quad([
        (half, -half, -half),
        (-half, -half, -half),
        (-half, half, -half),
        (half, half, -half),
      ]),
    ),
    CubeFace(
      stepIndex: 0,
      role: CubeFaceRole.left,
      corners: quad([
        (-half, -half, half),
        (-half, -half, -half),
        (-half, half, -half),
        (-half, half, half),
      ]),
    ),
    CubeFace(
      stepIndex: 0,
      role: CubeFaceRole.right,
      corners: quad([
        (half, -half, -half),
        (half, -half, half),
        (half, half, half),
        (half, half, -half),
      ]),
    ),
    CubeFace(
      stepIndex: 0,
      role: CubeFaceRole.top,
      corners: quad([
        (-half, half, half),
        (half, half, half),
        (half, half, -half),
        (-half, half, -half),
      ]),
    ),
    CubeFace(
      stepIndex: 0,
      role: CubeFaceRole.bottom,
      corners: quad([
        (-half, -half, -half),
        (half, -half, -half),
        (half, -half, half),
        (-half, -half, half),
      ]),
    ),
  ];
}

class _NetSquare {
  _NetSquare({required this.bounds, required this.ring, required this.styles});

  final Rect bounds;
  final List<Offset> ring;
  final List<EdgeStyle> styles;

  Offset get center => bounds.center;

  int get penciledCount =>
      styles.where((style) => style == EdgeStyle.penciled).length;
}

Rect? _faceBounds(List<Offset> ring) {
  if (ring.length != 4) return null;
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
  if ((maxX - minX - kCubeFace).abs() > 1e-6) return null;
  if ((maxY - minY - kCubeFace).abs() > 1e-6) return null;
  const corners = 4;
  var hits = 0;
  for (final point in ring) {
    final onX =
        (point.dx - minX).abs() < 1e-6 || (point.dx - maxX).abs() < 1e-6;
    final onY =
        (point.dy - minY).abs() < 1e-6 || (point.dy - maxY).abs() < 1e-6;
    if (onX && onY) hits++;
  }
  if (hits != corners) return null;
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

CubeFaceRole? _sideOf(_NetSquare hub, _NetSquare other) {
  final dx = other.center.dx - hub.center.dx;
  final dy = other.center.dy - hub.center.dy;
  if (dx.abs() < 1e-6 && dy.abs() < 1e-6) return null;
  if (dx.abs() > dy.abs()) {
    return dx < 0 ? CubeFaceRole.left : CubeFaceRole.right;
  }
  return dy < 0 ? CubeFaceRole.bottom : CubeFaceRole.top;
}

bool _sharesFold(_NetSquare a, _NetSquare b) {
  final left = _penciledSegments(a);
  final right = _penciledSegments(b);
  for (final ab in left) {
    for (final cd in right) {
      if (_segmentsOverlap(ab.$1, ab.$2, cd.$1, cd.$2)) return true;
    }
  }
  return false;
}

List<(Offset, Offset)> _penciledSegments(_NetSquare square) {
  final segments = <(Offset, Offset)>[];
  final count = math.min(square.ring.length, square.styles.length);
  for (var i = 0; i < count; i++) {
    if (square.styles[i] != EdgeStyle.penciled) continue;
    final next = (i + 1) % square.ring.length;
    segments.add((square.ring[i], square.ring[next]));
  }
  return segments;
}

bool _segmentsOverlap(Offset a, Offset b, Offset c, Offset d) {
  const eps = 1e-6;
  final abx = b.dx - a.dx;
  final aby = b.dy - a.dy;
  final cdx = d.dx - c.dx;
  final cdy = d.dy - c.dy;
  if (aby.abs() < eps && cdy.abs() < eps && (a.dy - c.dy).abs() < eps) {
    return _intervalsOverlap(a.dx, b.dx, c.dx, d.dx);
  }
  if (abx.abs() < eps && cdx.abs() < eps && (a.dx - c.dx).abs() < eps) {
    return _intervalsOverlap(a.dy, b.dy, c.dy, d.dy);
  }
  return false;
}

bool _intervalsOverlap(double a0, double a1, double b0, double b1) {
  final left = math.max(math.min(a0, a1), math.min(b0, b1));
  final right = math.min(math.max(a0, a1), math.max(b0, b1));
  return right - left > 1e-6;
}
