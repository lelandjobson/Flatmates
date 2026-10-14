import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Orthogonal grid point. Y grows upward, matching the crafting sheet.
@immutable
class LinePoint {
  const LinePoint(this.x, this.y);

  final int x;
  final int y;

  Offset get offset => Offset(x.toDouble(), y.toDouble());

  @override
  bool operator ==(Object other) =>
      other is LinePoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x,$y)';
}

/// Undirected unit edge. Endpoints are stored in a stable order.
@immutable
class LineEdge {
  LineEdge(LinePoint a, LinePoint b) : a = _first(a, b), b = _second(a, b);

  final LinePoint a;
  final LinePoint b;

  static LinePoint _first(LinePoint a, LinePoint b) =>
      a.x < b.x || (a.x == b.x && a.y <= b.y) ? a : b;

  static LinePoint _second(LinePoint a, LinePoint b) =>
      identical(_first(a, b), a) ? b : a;

  @override
  bool operator ==(Object other) =>
      other is LineEdge && other.a == a && other.b == b;

  @override
  int get hashCode => Object.hash(a, b);

  @override
  String toString() => '$a—$b';
}

/// Inclusive integer rectangle of the paper, in grid units.
@immutable
class LineBounds {
  const LineBounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final int left;
  final int top;
  final int right;
  final int bottom;

  Rect get rect => Rect.fromLTRB(
    left.toDouble(),
    top.toDouble(),
    right.toDouble(),
    bottom.toDouble(),
  );

  bool contains(LinePoint point) =>
      point.x >= left &&
      point.x <= right &&
      point.y >= top &&
      point.y <= bottom;

  bool onRim(LinePoint point) =>
      contains(point) &&
      (point.x == left ||
          point.x == right ||
          point.y == top ||
          point.y == bottom);
}

/// One blueprint piece. [order] is a 1-based pass-through number.
/// [color] is a [kRulePalette] index the paper must be when the border closes.
/// [coverBorder] forces a full outline even when [color] is null.
@immutable
class LineRegion {
  LineRegion({
    required List<LinePoint> ring,
    this.order,
    this.color,
    this.coverBorder = false,
  }) : ring = List<LinePoint>.unmodifiable(ring),
       edges = List<LineEdge>.unmodifiable(_perimeter(ring));

  final List<LinePoint> ring;
  final int? order;
  final int? color;
  final bool coverBorder;
  final List<LineEdge> edges;

  bool get needsBorder => color != null || coverBorder;
}

/// Square chip on a dot. Crossing it tints the paper.
@immutable
class LineFlipper {
  const LineFlipper({required this.at, required this.color});

  final LinePoint at;
  final int color;
}

enum LineTool { cut, fold }

enum LinePhase { browse, drawing, paused, failed, solved }

enum LineFailureKind { order, color }

@immutable
class LineFailure {
  const LineFailure({required this.regionIndex, required this.kind});

  final int regionIndex;
  final LineFailureKind kind;
}

/// One tool use: a polyline that starts on the paper edge.
@immutable
class LineStroke {
  const LineStroke({required this.tool, required this.points});

  final LineTool tool;
  final List<LinePoint> points;

  LineStroke extend(LinePoint point) =>
      LineStroke(tool: tool, points: [...points, point]);
}

/// Blocky line puzzle on the crafting lattice.
class LinePuzzle {
  LinePuzzle({
    required this.id,
    required this.title,
    required this.blurb,
    required List<LineRegion> regions,
    List<LineFlipper> flippers = const [],
    Set<LinePoint> missing = const {},
    Set<LinePoint> doubles = const {},
    this.paperMargin = 2,
  }) : regions = List<LineRegion>.unmodifiable(regions),
       flippers = List<LineFlipper>.unmodifiable(flippers),
       missing = Set<LinePoint>.unmodifiable(missing),
       doubles = Set<LinePoint>.unmodifiable(doubles),
       bounds = _paperBounds(regions, paperMargin),
       _flipperAt = {for (final flip in flippers) flip.at: flip.color} {
    assert(regions.isNotEmpty, '$id needs a region');
    assert(() {
      for (final region in regions) {
        _assertBlocky(region.ring);
        for (final edge in region.edges) {
          assert(
            !missing.contains(edge.a) && !missing.contains(edge.b),
            '$id omits a border dot',
          );
        }
      }
      for (final dot in doubles) {
        assert(hasDot(dot), '$id double $dot is not a dot');
      }
      for (final flip in flippers) {
        assert(hasDot(flip.at), '$id flipper ${flip.at} is not a dot');
      }
      return true;
    }());
  }

  final String id;
  final String title;
  final String blurb;
  final int paperMargin;
  final List<LineRegion> regions;
  final List<LineFlipper> flippers;
  final Set<LinePoint> missing;
  final Set<LinePoint> doubles;
  final LineBounds bounds;
  final Map<LinePoint, int> _flipperAt;

  int? flipperColor(LinePoint point) => _flipperAt[point];

  bool hasDot(LinePoint point) =>
      bounds.contains(point) && !missing.contains(point);

  bool isEdgeDot(LinePoint point) => hasDot(point) && bounds.onRim(point);

  int budget(LinePoint point) => doubles.contains(point) ? 2 : 1;
}

/// Live play. Rules return a new session instead of mutating this one.
@immutable
class LineSession {
  const LineSession({
    required this.puzzle,
    required this.strokes,
    required this.tool,
    required this.phase,
    required this.paperColor,
    required this.visited,
    required this.solvedBorders,
    required this.covered,
    this.failure,
    this.strokeBase,
  });

  factory LineSession.start(LinePuzzle puzzle) {
    return LineSession(
      puzzle: puzzle,
      strokes: const [],
      tool: LineTool.cut,
      phase: LinePhase.browse,
      paperColor: null,
      visited: const {},
      solvedBorders: const {},
      covered: const {},
    );
  }

  final LinePuzzle puzzle;
  final List<LineStroke> strokes;
  final LineTool tool;
  final LinePhase phase;
  final int? paperColor;
  final Set<int> visited;
  final Set<int> solvedBorders;
  final Set<LineEdge> covered;
  final LineFailure? failure;

  /// Session from before the open stroke. Replaying it undoes that stroke.
  final LineSession? strokeBase;

  bool get canSwitchTool =>
      phase == LinePhase.browse || phase == LinePhase.paused;

  LinePoint? get head {
    if (phase != LinePhase.drawing || strokes.isEmpty) return null;
    final points = strokes.last.points;
    if (points.isEmpty) return null;
    return points.last;
  }

  /// Next 1-based number that may be entered.
  int get nextOrder {
    var seen = 0;
    for (final index in visited) {
      if (puzzle.regions[index].order != null) seen++;
    }
    return seen + 1;
  }

  LineSession copyWith({
    List<LineStroke>? strokes,
    LineTool? tool,
    LinePhase? phase,
    int? paperColor,
    bool clearColor = false,
    Set<int>? visited,
    Set<int>? solvedBorders,
    Set<LineEdge>? covered,
    LineFailure? failure,
    bool clearFailure = false,
    LineSession? strokeBase,
    bool clearStrokeBase = false,
  }) {
    return LineSession(
      puzzle: puzzle,
      strokes: strokes ?? this.strokes,
      tool: tool ?? this.tool,
      phase: phase ?? this.phase,
      paperColor: clearColor ? null : (paperColor ?? this.paperColor),
      visited: visited ?? this.visited,
      solvedBorders: solvedBorders ?? this.solvedBorders,
      covered: covered ?? this.covered,
      failure: clearFailure ? null : (failure ?? this.failure),
      strokeBase: clearStrokeBase ? null : (strokeBase ?? this.strokeBase),
    );
  }
}

/// Where the tool tip sits. [anchors] are dots the tip has fully reached.
/// [toward] is the next dot on the open groove, and [t] is 0 at the last
/// anchor and 1 at [toward].
@immutable
class LinePeg {
  const LinePeg({required this.anchors, this.toward, this.t = 0});

  final List<LinePoint> anchors;
  final LinePoint? toward;
  final double t;

  LinePoint get anchor => anchors.last;

  Offset get tip {
    final from = anchor.offset;
    final next = toward;
    if (next == null || t <= 0) return from;
    return Offset.lerp(from, next.offset, t.clamp(0.0, 1.0))!;
  }

  bool get atAnchor => toward == null || t <= 0.001;

  LinePeg copyWith({
    List<LinePoint>? anchors,
    LinePoint? toward,
    bool clearToward = false,
    double? t,
  }) {
    return LinePeg(
      anchors: anchors ?? this.anchors,
      toward: clearToward ? null : (toward ?? this.toward),
      t: t ?? this.t,
    );
  }
}

/// Axis-aligned rectangle ring, counterclockwise from the bottom-left.
List<LinePoint> lineRect(int left, int bottom, int right, int top) {
  return [
    LinePoint(left, bottom),
    LinePoint(right, bottom),
    LinePoint(right, top),
    LinePoint(left, top),
  ];
}

bool lineContains(List<LinePoint> ring, LinePoint point) {
  return _contains(ring, point.x.toDouble(), point.y.toDouble());
}

/// A point inside the piece, used to seat the number and color widgets.
Offset lineRegionAnchor(List<LinePoint> ring) {
  var minX = ring.first.x;
  var maxX = minX;
  var minY = ring.first.y;
  var maxY = minY;
  for (final point in ring) {
    if (point.x < minX) minX = point.x;
    if (point.x > maxX) maxX = point.x;
    if (point.y < minY) minY = point.y;
    if (point.y > maxY) maxY = point.y;
  }
  var sx = 0.0;
  var sy = 0.0;
  var count = 0;
  for (var x = minX; x < maxX; x++) {
    for (var y = minY; y < maxY; y++) {
      final cx = x + 0.5;
      final cy = y + 0.5;
      if (_onBoundary(ring, cx, cy)) continue;
      if (!_contains(ring, cx, cy)) continue;
      sx += cx;
      sy += cy;
      count++;
    }
  }
  if (count == 0) {
    for (final point in ring) {
      sx += point.x;
      sy += point.y;
    }
    return Offset(sx / ring.length, sy / ring.length);
  }
  return Offset(sx / count, sy / count);
}

List<LineEdge> _perimeter(List<LinePoint> ring) {
  final edges = <LineEdge>[];
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    final steps = math.max((b.x - a.x).abs(), (b.y - a.y).abs());
    if (steps == 0) continue;
    final dx = (b.x - a.x) ~/ steps;
    final dy = (b.y - a.y) ~/ steps;
    var x = a.x;
    var y = a.y;
    for (var s = 0; s < steps; s++) {
      final next = LinePoint(x + dx, y + dy);
      edges.add(LineEdge(LinePoint(x, y), next));
      x = next.x;
      y = next.y;
    }
  }
  return edges;
}

void _assertBlocky(List<LinePoint> ring) {
  assert(ring.length >= 4, 'ring needs four corners');
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    final dx = (a.x - b.x).abs();
    final dy = (a.y - b.y).abs();
    assert(dx == 0 || dy == 0, 'edge $a—$b leaves the grid');
    assert(dx + dy > 0, 'zero-length edge');
  }
}

LineBounds _paperBounds(List<LineRegion> regions, int margin) {
  var minX = regions.first.ring.first.x;
  var maxX = minX;
  var minY = regions.first.ring.first.y;
  var maxY = minY;
  for (final region in regions) {
    for (final point in region.ring) {
      if (point.x < minX) minX = point.x;
      if (point.x > maxX) maxX = point.x;
      if (point.y < minY) minY = point.y;
      if (point.y > maxY) maxY = point.y;
    }
  }
  return LineBounds(
    left: minX - margin,
    top: minY - margin,
    right: maxX + margin,
    bottom: maxY + margin,
  );
}

bool _contains(List<LinePoint> ring, double x, double y) {
  if (_onBoundary(ring, x, y)) return true;
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final yi = ring[i].y.toDouble();
    final yj = ring[j].y.toDouble();
    final xi = ring[i].x.toDouble();
    final xj = ring[j].x.toDouble();
    final crosses = (yi > y) != (yj > y);
    if (!crosses) continue;
    final at = (xj - xi) * (y - yi) / (yj - yi) + xi;
    if (x < at) inside = !inside;
  }
  return inside;
}

bool _onBoundary(List<LinePoint> ring, double x, double y) {
  const eps = 1e-9;
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    if (a.y == b.y && (y - a.y).abs() < eps) {
      final minX = math.min(a.x, b.x).toDouble();
      final maxX = math.max(a.x, b.x).toDouble();
      if (x >= minX - eps && x <= maxX + eps) return true;
    } else if (a.x == b.x && (x - a.x).abs() < eps) {
      final minY = math.min(a.y, b.y).toDouble();
      final maxY = math.max(a.y, b.y).toDouble();
      if (y >= minY - eps && y <= maxY + eps) return true;
    }
  }
  return false;
}
