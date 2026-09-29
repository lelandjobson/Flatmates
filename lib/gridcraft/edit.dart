import 'dart:math' as math;
import 'dart:ui';

import '../geometry/geometry_algorithms.dart';
import '../geometry/polygon_union.dart';
import '../papercut/paper.dart';
import 'blueprint.dart';
import 'rules.dart';

/// [radians] is counterclockwise in paper space. A clockwise quarter turn is −π/2.
Offset rotateGridPointBy(Offset point, Offset origin, double radians) {
  final delta = point - origin;
  final c = math.cos(radians);
  final s = math.sin(radians);
  return origin +
      Offset(delta.dx * c - delta.dy * s, delta.dx * s + delta.dy * c);
}

Offset rotateGridPoint(Offset point, Offset origin, {required bool clockwise}) {
  return rotateGridPointBy(
    point,
    origin,
    clockwise ? -math.pi / 2 : math.pi / 2,
  );
}

GridStep rotateStep(GridStep step, {required bool clockwise}) {
  return rotateStepBy(
    step,
    step.paper.center,
    clockwise ? -math.pi / 2 : math.pi / 2,
  );
}

GridStep rotateStepBy(GridStep step, Offset origin, double radians) {
  Offset turn(Offset point) => rotateGridPointBy(point, origin, radians);
  return step.copyWith(
    polygons: [
      for (final polygon in step.polygons)
        [
          for (final point in polygon) turn(point),
        ],
    ],
    rules: step.rules.turned(origin, (point, around) => turn(point)),
    permutation: step.permutation.turned(radians, turn),
  );
}

bool sameGridPoint(Offset a, Offset b) => (a - b).distance <= 1e-3;

/// Click result while a polyline is still open.
///
/// [closed] is set when the ring joins back to its first point.
/// [open] is set when a second click on the last point keeps the line open.
class DraftClick {
  const DraftClick({required this.draft, this.closed, this.open});

  final List<Offset> draft;
  final List<Offset>? closed;
  final List<Offset>? open;
}

/// Adds [point] to [draft], closes on the first vertex, or finishes an open line.
///
/// A second click on the last point commits the polyline without joining it
/// back to the start. Clicking the first point, once there are three vertices,
/// commits a closed ring. A segment that would cross the draft is refused.
DraftClick applyDraftClick(List<Offset> draft, Offset point) {
  if (draft.isNotEmpty && sameGridPoint(point, draft.last)) {
    if (draft.length >= 2) {
      return DraftClick(draft: const [], open: List<Offset>.from(draft));
    }
    return DraftClick(draft: draft);
  }
  final closing = draft.length >= 3 && sameGridPoint(point, draft.first);
  if (draftSegmentCrosses(draft, closing ? draft.first : point)) {
    return DraftClick(draft: draft);
  }
  if (closing) {
    return DraftClick(draft: const [], closed: List<Offset>.from(draft));
  }
  return DraftClick(draft: [...draft, point]);
}

/// True when the segment from the last draft vertex to [next] cuts an earlier edge.
bool draftSegmentCrosses(List<Offset> points, Offset next) {
  if (points.length < 3) return false;
  final tail = points.last;
  final closing = sameGridPoint(next, points.first);
  for (var i = 0; i < points.length - 1; i++) {
    if (i == points.length - 2) continue;
    final hit = segmentIntersectionPoint(tail, next, points[i], points[i + 1]);
    if (hit == null) continue;
    if (closing && sameGridPoint(hit, points.first)) continue;
    return true;
  }
  return false;
}

List<List<Offset>> translatePolygons(
  List<List<Offset>> polygons,
  Set<int> selected,
  Offset delta,
) {
  if (delta == Offset.zero || selected.isEmpty) return polygons;
  return [
    for (var i = 0; i < polygons.length; i++)
      if (selected.contains(i))
        [for (final point in polygons[i]) point + delta]
      else
        polygons[i],
  ];
}

/// Moves every picked rule widget by [delta]. Unpicked widgets stay put.
GridRules translateRules(GridRules rules, Set<RulePick> picked, Offset delta) {
  if (delta == Offset.zero || picked.isEmpty) return rules;
  bool take(RuleKind kind, int index) => picked.contains(RulePick(kind, index));
  Offset move(Offset point) => point + delta;
  return rules.copyWith(
    forbidden: [
      for (var i = 0; i < rules.forbidden.length; i++)
        take(RuleKind.forbidden, i)
            ? move(rules.forbidden[i])
            : rules.forbidden[i],
    ],
    colors: [
      for (var i = 0; i < rules.colors.length; i++)
        take(RuleKind.color, i)
            ? ColorMark(move(rules.colors[i].point), rules.colors[i].color)
            : rules.colors[i],
    ],
    numbers: [
      for (var i = 0; i < rules.numbers.length; i++)
        take(RuleKind.number, i)
            ? OrderMark(move(rules.numbers[i].point), rules.numbers[i].number)
            : rules.numbers[i],
    ],
    arrows: [
      for (var i = 0; i < rules.arrows.length; i++)
        take(RuleKind.arrow, i)
            ? GridEdge(move(rules.arrows[i].a), move(rules.arrows[i].b))
            : rules.arrows[i],
    ],
    docks: [
      for (var i = 0; i < rules.docks.length; i++)
        take(RuleKind.dock, i) ? move(rules.docks[i]) : rules.docks[i],
    ],
    links: [
      for (var i = 0; i < rules.links.length; i++)
        take(RuleKind.link, i)
            ? LinkMark(move(rules.links[i].point), rules.links[i].pair)
            : rules.links[i],
    ],
    seams: [
      for (var i = 0; i < rules.seams.length; i++)
        take(RuleKind.seam, i)
            ? GridEdge(move(rules.seams[i].a), move(rules.seams[i].b))
            : rules.seams[i],
    ],
  );
}

/// Left-to-right contains. Right-to-left also takes what the rectangle crosses.
enum MarqueePick { contain, cross }

class MarqueeHits {
  const MarqueeHits({required this.polygons, required this.marks});

  final Set<int> polygons;
  final Set<RulePick> marks;
}

/// [start] and [end] are screen points. Increasing x contains; decreasing x crosses.
MarqueePick marqueePick(Offset start, Offset end) {
  return end.dx + 1e-9 >= start.dx ? MarqueePick.contain : MarqueePick.cross;
}

bool pointInMarquee(Offset point, Rect rect, MarqueePick pick) {
  return _rectContains(rect, point);
}

bool edgeInMarquee(Offset a, Offset b, Rect rect, MarqueePick pick) {
  if (pick == MarqueePick.contain) {
    return _rectContains(rect, a) && _rectContains(rect, b);
  }
  return _segmentHitsRect(a, b, rect);
}

bool polygonInMarquee(
  List<Offset> polygon,
  Rect rect,
  MarqueePick pick, {
  bool closed = true,
}) {
  if (closed ? polygon.length < 3 : polygon.length < 2) return false;
  if (pick == MarqueePick.contain) {
    return polygon.every((point) => _rectContains(rect, point));
  }
  if (polygon.any((point) => _rectContains(rect, point))) return true;
  if (closed) {
    final corners = [
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
    ];
    for (final corner in corners) {
      if (isInsidePolygon(corner, polygon)) return true;
    }
  }
  final edges = closed ? polygon.length : polygon.length - 1;
  for (var i = 0; i < edges; i++) {
    final a = polygon[i];
    final b = polygon[(i + 1) % polygon.length];
    if (_segmentHitsRect(a, b, rect)) return true;
  }
  return false;
}

MarqueeHits marqueeHits(GridStep step, Rect rect, MarqueePick pick) {
  final polygons = <int>{};
  for (var i = 0; i < step.polygons.length; i++) {
    if (polygonInMarquee(
      step.polygons[i],
      rect,
      pick,
      closed: step.isRingClosed(i),
    )) {
      polygons.add(i);
    }
  }
  final marks = <RulePick>{};
  final rules = step.rules;
  void takePoint(RuleKind kind, int index, Offset point) {
    if (pointInMarquee(point, rect, pick)) marks.add(RulePick(kind, index));
  }

  void takeEdge(RuleKind kind, int index, GridEdge edge) {
    if (edgeInMarquee(edge.a, edge.b, rect, pick)) {
      marks.add(RulePick(kind, index));
    }
  }

  for (var i = 0; i < rules.forbidden.length; i++) {
    takePoint(RuleKind.forbidden, i, rules.forbidden[i]);
  }
  for (var i = 0; i < rules.colors.length; i++) {
    takePoint(RuleKind.color, i, rules.colors[i].point);
  }
  for (var i = 0; i < rules.numbers.length; i++) {
    takePoint(RuleKind.number, i, rules.numbers[i].point);
  }
  for (var i = 0; i < rules.docks.length; i++) {
    takePoint(RuleKind.dock, i, rules.docks[i]);
  }
  for (var i = 0; i < rules.links.length; i++) {
    takePoint(RuleKind.link, i, rules.links[i].point);
  }
  for (var i = 0; i < rules.arrows.length; i++) {
    takeEdge(RuleKind.arrow, i, rules.arrows[i]);
  }
  for (var i = 0; i < rules.seams.length; i++) {
    takeEdge(RuleKind.seam, i, rules.seams[i]);
  }
  return MarqueeHits(polygons: polygons, marks: marks);
}

bool _rectContains(Rect rect, Offset point) {
  return point.dx >= rect.left - 1e-6 &&
      point.dx <= rect.right + 1e-6 &&
      point.dy >= rect.top - 1e-6 &&
      point.dy <= rect.bottom + 1e-6;
}

bool _segmentHitsRect(Offset a, Offset b, Rect rect) {
  if (_rectContains(rect, a) || _rectContains(rect, b)) return true;
  final edges = [
    (rect.topLeft, rect.topRight),
    (rect.topRight, rect.bottomRight),
    (rect.bottomRight, rect.bottomLeft),
    (rect.bottomLeft, rect.topLeft),
  ];
  for (final (c, d) in edges) {
    if (segmentIntersectionPoint(a, b, c, d) != null) return true;
  }
  return false;
}

PapercutSheet rotateSheet(
  PapercutSheet sheet,
  Offset origin, {
  required bool clockwise,
}) {
  return rotateSheetBy(sheet, origin, clockwise ? -math.pi / 2 : math.pi / 2);
}

PapercutSheet rotateSheetBy(
  PapercutSheet sheet,
  Offset origin,
  double radians,
) {
  Offset turn(Offset point) => rotateGridPointBy(point, origin, radians);
  return PapercutSheet(
    pieces: [
      for (final piece in sheet.pieces)
        PapercutPiece(
          id: piece.id,
          color: piece.color,
          vertices: [for (final point in piece.vertices) turn(point)],
          holes: [
            for (final hole in piece.holes)
              [for (final point in hole) turn(point)],
          ],
          separation: rotateGridPointBy(piece.separation, Offset.zero, radians),
        ),
    ],
    cutStrokes: [
      for (final stroke in sheet.cutStrokes)
        [for (final point in stroke) turn(point)],
    ],
    creases: [
      for (final crease in sheet.creases)
        PapercutCrease(
          id: crease.id,
          a: turn(crease.a),
          b: turn(crease.b),
          groupId: crease.groupId,
          angleDegrees: crease.angleDegrees,
        ),
    ],
    folds: [
      for (final joint in sheet.folds)
        FoldJoint(
          a: turn(joint.a),
          b: turn(joint.b),
          side: joint.side,
          facing: joint.facing,
        ),
    ],
    scores: [
      for (final score in sheet.scores) ScoreLine(turn(score.a), turn(score.b)),
    ],
    marks: [
      for (final mark in sheet.marks)
        PaperMark(points: [for (final point in mark.points) turn(point)]),
    ],
    nextPieceId: sheet.nextPieceId,
  );
}

/// Unit cells whose centers fall inside a circle of [radius] cells.
Set<(int, int)> circleCells(int cx, int cy, int radius) {
  final cells = <(int, int)>{};
  for (var y = cy - radius; y <= cy + radius; y++) {
    for (var x = cx - radius; x <= cx + radius; x++) {
      final dx = x - cx + 0.0;
      final dy = y - cy + 0.0;
      if (dx * dx + dy * dy <= radius * radius + 1e-6) cells.add((x, y));
    }
  }
  return cells;
}

Set<(int, int)> rectangleCells(int x0, int y0, int x1, int y1) {
  final cells = <(int, int)>{};
  final left = math.min(x0, x1);
  final right = math.max(x0, x1);
  final bottom = math.min(y0, y1);
  final top = math.max(y0, y1);
  for (var y = bottom; y <= top; y++) {
    for (var x = left; x <= right; x++) {
      cells.add((x, y));
    }
  }
  return cells;
}

/// Fuses painted cells into outer polygons. Holes are dropped.
List<List<Offset>> polygonsFromCells(Set<(int, int)> cells, double spacing) {
  if (cells.isEmpty || spacing <= 0) return const [];
  final squares = [
    for (final (x, y) in cells)
      [
        Offset(x * spacing, y * spacing),
        Offset((x + 1) * spacing, y * spacing),
        Offset((x + 1) * spacing, (y + 1) * spacing),
        Offset(x * spacing, (y + 1) * spacing),
      ],
  ];
  final loops = unionPolygons(squares);
  return [
    for (final loop in loops)
      if (polygonSignedArea(loop) < 0)
        [for (final point in loop.reversed) point],
  ];
}

List<List<Offset>> mergeSelected(List<List<Offset>> polygons) {
  if (polygons.length < 2) return polygons;
  final loops = unionPolygons(polygons);
  final outers = [
    for (final loop in loops)
      if (polygonSignedArea(loop) < 0)
        [for (final point in loop.reversed) point],
  ];
  return outers.isEmpty ? polygons : outers;
}
