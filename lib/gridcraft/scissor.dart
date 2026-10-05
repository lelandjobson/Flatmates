import 'dart:math' as math;
import 'dart:ui';

import '../geometry/geometry_algorithms.dart';
import '../geometry/polygon_union.dart';
import '../papercut/paper.dart';
import 'blueprint.dart';
import 'fold.dart';

const _eps = 1e-4;

/// A scissor parked on the grid. [path] grows until a piece splits off.
class ScissorMarch {
  const ScissorMarch({
    required this.path,
    required this.direction,
    this.locked = false,
  });

  final List<Offset> path;
  final Offset direction;
  final bool locked;

  Offset get position => path.last;

  /// Where the next click will cut to, or null when the ray leaves the sheet.
  ///
  /// [direction] overrides the parked direction. The view passes screen-up so
  /// a roll changes the glowing segment.
  Offset? previewEnd(
    GridStep step,
    PapercutSheet sheet, {
    Offset? direction,
    List<List<Offset>>? closed,
    bool Function(Offset a, Offset b)? skipCollinear,
  }) {
    return nextOutlineHit(
      from: position,
      direction: direction ?? this.direction,
      closed: closed ?? cutOutlines(step, sheet),
      open: [...openBlueprint(step), ...sheet.cutStrokes],
      skipCollinear: skipCollinear,
    );
  }
}

/// Blueprint outlines and paper-piece boundaries the blade must not cross.
///
/// Open blueprint polylines are not closed rings. They travel with the open
/// strokes in [openBlueprint].
List<List<Offset>> cutOutlines(GridStep step, PapercutSheet sheet) {
  return [
    for (var i = 0; i < step.polygons.length; i++)
      if (step.isRingClosed(i)) step.polygons[i],
    for (final piece in sheet.pieces) piece.vertices,
    for (final piece in sheet.pieces) ...piece.holes,
  ];
}

/// Blueprint polylines that stay open. The blade stops on them without
/// inventing an edge back to the first point.
List<List<Offset>> openBlueprint(GridStep step) {
  return [
    for (var i = 0; i < step.polygons.length; i++)
      if (!step.isRingClosed(i)) step.polygons[i],
  ];
}

/// True when an interior sample of the open segment sits inside a blueprint piece.
///
/// Endpoints may lie on the boundary. Travel that only touches the boundary
/// does not enter.
bool segmentEntersBlueprintInterior(
  Offset from,
  Offset to,
  List<List<Offset>> blueprintPieces,
) {
  return piercedBlueprintRing(from, to, blueprintPieces) != null;
}

/// Index of the closed blueprint piece whose area [from]–[to] crosses.
///
/// Stopping on the outline, or traveling along it, does not count. Open
/// polylines have no area.
int? piercedBlueprint(GridStep step, Offset from, Offset to) {
  for (var i = 0; i < step.polygons.length; i++) {
    if (!step.isRingClosed(i)) continue;
    if (piercedBlueprintRing(from, to, [step.polygons[i]]) != null) return i;
  }
  return null;
}

int? piercedBlueprintRing(
  Offset from,
  Offset to,
  List<List<Offset>> blueprintPieces,
) {
  for (var i = 1; i < 8; i++) {
    final point = Offset.lerp(from, to, i / 8)!;
    for (var ringIndex = 0; ringIndex < blueprintPieces.length; ringIndex++) {
      final ring = blueprintPieces[ringIndex];
      if (ring.length < 3) continue;
      if (!isInsidePolygon(point, ring)) continue;
      if (_onRingBoundary(point, ring)) continue;
      return ringIndex;
    }
  }
  return null;
}

bool _onRingBoundary(Offset point, List<Offset> ring) {
  for (var i = 0; i < ring.length; i++) {
    if (_distanceToSegment(point, ring[i], ring[(i + 1) % ring.length]) <=
        1e-3) {
      return true;
    }
  }
  return false;
}

/// First outline hit in front of [from].
///
/// A crossing edge stops the ray. A vertex past that edge is not a target.
/// Traveling along an edge reaches that edge's next vertex.
Offset? nextOutlineHit({
  required Offset from,
  required Offset direction,
  required List<List<Offset>> closed,
  List<List<Offset>> open = const [],
  bool Function(Offset a, Offset b)? skipCollinear,
}) {
  final length = direction.distance;
  if (length < 1e-8) return null;
  final ray = direction / length;
  Offset? best;
  var bestT = double.infinity;
  void consider(double t, Offset point) {
    if (t <= _eps || t >= bestT) return;
    bestT = t;
    best = point;
  }

  void walk(List<Offset> ring, {required bool close}) {
    if (ring.length < 2) return;
    final count = close ? ring.length : ring.length - 1;
    for (var i = 0; i < count; i++) {
      final a = ring[i];
      final b = ring[(i + 1) % ring.length];
      _raySegment(from, ray, a, b, (t, point) {
        if (skipCollinear != null && _collinearRay(from, ray, a, b)) {
          if (skipCollinear(a, b)) return;
        }
        consider(t, point);
      });
    }
  }

  for (final ring in closed) {
    walk(ring, close: true);
  }
  for (final stroke in open) {
    walk(stroke, close: false);
  }
  return best;
}

/// Screen side of a tap, measured from the crosshair. Up is toward the top.
enum ScreenSide { up, down, left, right }

/// Points of the cut still in progress.
///
/// [path] runs from the paper edge through every stroke the blade has
/// finished. [tip] is where the blade is now, and lengthens the last stroke
/// while it travels. The path ends when the blade leaves the paper: that
/// last stroke does not stop where another cut can go forward. The caller
/// passes an empty path once the blade has left.
List<Offset> activeCutPoints(List<Offset> path, {Offset? tip}) {
  if (path.isEmpty) return const [];
  final points = List<Offset>.of(path);
  if (tip != null && (tip - points.last).distance >= 1e-3) {
    points.add(tip);
  }
  if (points.length < 2) return const [];
  return points;
}

/// Screen point a direction tap is measured from.
///
/// Follow mode uses the reticle. With the camera fixed, the tap is measured
/// from the tool. That point starts where the blade was placed on the paper
/// and moves with the blade.
Offset directionTapOrigin({
  required bool cameraFollowsTool,
  required Offset reticle,
  Offset? toolOnScreen,
}) {
  if (cameraFollowsTool || toolOnScreen == null) return reticle;
  return toolOnScreen;
}

/// Larger component of [delta] from the aim point.
///
/// A tap can sit off both axes. The bigger one wins: horizontal when
/// `|dx| >= |dy|`, otherwise vertical. Screen Y grows downward. Both
/// components inside [deadZone] are the aim point itself.
ScreenSide? dominantScreenSide(Offset delta, {double deadZone = 0}) {
  final ax = delta.dx.abs();
  final ay = delta.dy.abs();
  if (math.max(ax, ay) < deadZone) return null;
  if (ax >= ay) {
    return delta.dx >= 0 ? ScreenSide.right : ScreenSide.left;
  }
  return delta.dy >= 0 ? ScreenSide.down : ScreenSide.up;
}

/// Side a swipe cuts toward. The sheet scrolls under the blade, so the
/// cut is opposite the finger. A downward finger cuts up. Movement inside
/// [deadZone] is not a side.
ScreenSide? swipeCutSide(Offset fingerDelta, {double deadZone = 0}) {
  return dominantScreenSide(-fingerDelta, deadZone: deadZone);
}

/// One straight cut the blade can still take.
class ForwardCut {
  const ForwardCut({required this.direction, required this.end});

  /// Unit direction of the cut.
  final Offset direction;

  /// First outline the cut reaches.
  final Offset end;
}

/// Cuts from [from] that are not an exact reverse of [forward].
///
/// Only the opposite of the arrival line is dropped. That blocks a U-turn
/// along the stroke the blade just traveled, and still leaves a turn onto
/// another edge, even when the turn points partly back. The diagonal of a Z
/// meets its bar at more than a right angle, and that turn has to stay.
/// A cardinal that leaves the sheet without hitting an outline is omitted.
List<ForwardCut> forwardCuts({
  required Offset from,
  required Offset forward,
  required List<Offset> directions,
  required List<List<Offset>> closed,
  List<List<Offset>> open = const [],
  List<List<Offset>> boundary = const [],
  bool Function(Offset a, Offset b)? skipCollinear,
}) {
  final length = forward.distance;
  if (length < 1e-8) return const [];
  final heading = forward / length;
  final cuts = <ForwardCut>[];
  for (final direction in directions) {
    final span = direction.distance;
    if (span < 1e-8) continue;
    final ray = direction / span;
    final aligned = ray.dx * heading.dx + ray.dy * heading.dy;
    // Exact reverse of the arrival. A wider turn is a different edge.
    if (aligned < -1 + 1e-3) continue;
    final end = nextOutlineHit(
      from: from,
      direction: ray,
      closed: closed,
      open: open,
      skipCollinear: skipCollinear,
    );
    if (end == null || cutRidesBoundary(from, end, boundary)) continue;
    cuts.add(ForwardCut(direction: ray, end: end));
  }
  return cuts;
}

/// True when [from] to [to] lies on a paper edge. That slide does not cut.
bool cutRidesBoundary(Offset from, Offset to, List<List<Offset>> rings) {
  if ((to - from).distance < 1e-8) return false;
  for (final ring in rings) {
    if (ring.length < 2) continue;
    for (var i = 0; i < ring.length; i++) {
      final a = ring[i];
      final b = ring[(i + 1) % ring.length];
      if (_distanceToSegment(from, a, b) <= 1e-3 &&
          _distanceToSegment(to, a, b) <= 1e-3) {
        return true;
      }
    }
  }
  return false;
}

/// The cut most aligned with [forward], or null when [cuts] is empty.
ForwardCut? mostForwardCut(List<ForwardCut> cuts, Offset forward) {
  final length = forward.distance;
  if (length < 1e-8 || cuts.isEmpty) return null;
  final heading = forward / length;
  ForwardCut? best;
  var bestDot = -2.0;
  for (final cut in cuts) {
    final dot = cut.direction.dx * heading.dx + cut.direction.dy * heading.dy;
    if (dot <= bestDot) continue;
    best = cut;
    bestDot = dot;
  }
  return best;
}

/// Unit directions of the linework through [at], and the opposite of each.
///
/// A right-angle corner has four: both edges, and both edges running the
/// other way. A point in the middle of one edge has only that edge's two
/// directions. [forwardCuts] still drops the way the blade arrived.
List<Offset> lineworkDirections({
  required Offset at,
  List<List<Offset>> closed = const [],
  List<List<Offset>> open = const [],
}) {
  final rays = <Offset>[];
  void add(Offset ray) {
    final length = ray.distance;
    if (length < 1e-8) return;
    final unit = ray / length;
    for (final existing in rays) {
      final dot = existing.dx * unit.dx + existing.dy * unit.dy;
      if (dot > 1 - 1e-4) return;
    }
    rays.add(unit);
  }

  void walk(List<Offset> stroke, {required bool close}) {
    if (stroke.length < 2) return;
    final count = close ? stroke.length : stroke.length - 1;
    for (var i = 0; i < count; i++) {
      final a = stroke[i];
      final b = stroke[(i + 1) % stroke.length];
      if (_distanceToSegment(at, a, b) > 1e-3) continue;
      final delta = b - a;
      add(delta);
      add(-delta);
    }
  }

  for (final stroke in closed) {
    walk(stroke, close: true);
  }
  for (final stroke in open) {
    walk(stroke, close: false);
  }
  return rays;
}

/// Forward, left, and right of [forward], in paper space.
///
/// These stay put when the camera rolls. A tap still picks among them by
/// which screen side it is closest to. A cut that has not started still uses
/// this grid rule. Once the blade is on a stroke, [lineworkDirections] decides.
List<Offset> paperTurnDirections(Offset forward) {
  final length = forward.distance;
  if (length < 1e-8) return const [];
  final heading = forward / length;
  return [
    heading,
    Offset(-heading.dy, heading.dx),
    Offset(heading.dy, -heading.dx),
  ];
}

/// The cut whose direction matches [direction], or null when none does.
ForwardCut? cutFacing(List<ForwardCut> cuts, Offset direction) {
  final length = direction.distance;
  if (length < 1e-8) return null;
  final ray = direction / length;
  for (final cut in cuts) {
    final dot = cut.direction.dx * ray.dx + cut.direction.dy * ray.dy;
    if (dot > 0.9) return cut;
  }
  return null;
}

/// Place the blade on a paper-edge grid point, facing into the sheet.
ScissorMarch? placeScissor(Offset point, Rect paper) {
  final direction = _inward(point, paper);
  if (direction == null) return null;
  return ScissorMarch(path: [point], direction: direction);
}

/// Place the blade on a gem. Boundary gems face into the sheet. An interior
/// gem faces the paper center, which is where a new cut is allowed to start.
ScissorMarch placeAtEntry(Offset point, Rect paper) {
  final inward = _inward(point, paper);
  if (inward != null) return ScissorMarch(path: [point], direction: inward);
  final toward = paper.center - point;
  final direction = toward.distance < 1e-6
      ? const Offset(0, 1)
      : toward / toward.distance;
  return ScissorMarch(path: [point], direction: direction);
}

/// Place the blade on [ring], facing into that piece.
ScissorMarch? placeOnRing(Offset point, List<Offset> ring) {
  final direction = inwardOnRing(point, ring);
  if (direction == null) return null;
  return ScissorMarch(path: [point], direction: direction);
}

/// Unit direction of the blueprint edge nearest [aim], pointing into the sheet.
///
/// Used when that edge is at least as close as the paper border, so a gem or
/// a diagonal stroke is followed at its own angle. The paper center is not a
/// heading: it leaves orthogonal and diagonal linework at a slant.
Offset? headingAlongLinework({
  required Offset aim,
  required Offset from,
  required GridStep step,
}) {
  final edge = _nearestBlueprintEdge(aim, step);
  if (edge == null) return null;
  if (edge.distance > _borderDistance(aim, step.paper) + 1e-6) return null;
  final length = edge.direction.distance;
  if (length < 1e-8) return null;
  return _senseIntoSheet(from, edge.direction / length, aim, step.paper);
}

class _BlueprintEdge {
  const _BlueprintEdge({required this.direction, required this.distance});

  final Offset direction;
  final double distance;
}

_BlueprintEdge? _nearestBlueprintEdge(Offset aim, GridStep step) {
  _BlueprintEdge? best;
  for (var i = 0; i < step.polygons.length; i++) {
    final ring = step.polygons[i];
    final count = step.edgeCountOf(i);
    for (var e = 0; e < count; e++) {
      final a = ring[e];
      final b = ring[(e + 1) % ring.length];
      final delta = b - a;
      if (delta.distance < 1e-8) continue;
      final distance = _distanceToSegment(aim, a, b);
      if (best != null && distance >= best.distance - 1e-9) continue;
      best = _BlueprintEdge(direction: delta, distance: distance);
    }
  }
  return best;
}

/// Distance from [point] to the boundary of [paper]. Inside, that is the
/// distance to the nearest side.
double _borderDistance(Offset point, Rect paper) {
  if (paper.width < 1e-8 || paper.height < 1e-8) return double.infinity;
  final dx = math.min(
    (point.dx - paper.left).abs(),
    (paper.right - point.dx).abs(),
  );
  final dy = math.min(
    (point.dy - paper.top).abs(),
    (paper.bottom - point.dy).abs(),
  );
  final inside =
      point.dx >= paper.left - 1e-6 &&
      point.dx <= paper.right + 1e-6 &&
      point.dy >= paper.top - 1e-6 &&
      point.dy <= paper.bottom + 1e-6;
  if (inside) return math.min(dx, dy);
  final clamped = Offset(
    point.dx.clamp(paper.left, paper.right),
    point.dy.clamp(paper.top, paper.bottom),
  );
  return (point - clamped).distance;
}

/// [unit] or its opposite, whichever steps into [paper] and aims more toward
/// [aim]. A point already on the blade uses the paper center as the tie break.
Offset? _senseIntoSheet(Offset from, Offset unit, Offset aim, Rect paper) {
  bool inside(Offset ray) {
    final step = from + ray * 0.05;
    return step.dx > paper.left + 1e-6 &&
        step.dx < paper.right - 1e-6 &&
        step.dy > paper.top + 1e-6 &&
        step.dy < paper.bottom - 1e-6;
  }

  final towardAim = aim - from;
  final toward = towardAim.distance > 0.2 ? towardAim : paper.center - from;
  Offset? best;
  var bestDot = -double.infinity;
  for (final ray in [unit, -unit]) {
    if (!inside(ray)) continue;
    final dot = ray.dx * toward.dx + ray.dy * toward.dy;
    if (dot <= bestDot) continue;
    best = ray;
    bestDot = dot;
  }
  return best;
}

/// Heading for a new cut at [from].
///
/// A point on a piece faces into that piece, perpendicular to the edge it
/// sits on. Aiming at the original paper center is only for a point that is
/// not on a ring: a fresh cut edge is inside that rectangle, and the center
/// often lies outside the piece, so that aim runs backward or into a corner.
Offset openingHeading(
  Offset from,
  Rect paper, {
  List<Offset>? ring,
  List<List<Offset>> holes = const [],
}) {
  if (ring != null) {
    final inward = inwardOnRing(from, ring);
    if (inward != null) return inward;
  }
  for (final hole in holes) {
    final inward = inwardOnRing(from, hole);
    if (inward != null) return inward;
  }
  return placeAtEntry(from, paper).direction;
}

/// The piece whose drawn edge is closest to [aim], and the model point on it.
class PieceEdgeTarget {
  const PieceEdgeTarget({required this.index, required this.model});

  final int index;
  final Offset model;
}

/// Closest unit-grid point on each piece's drawn outline.
///
/// Edges are measured where the piece is shown (`vertex + separation`), so a
/// piece sitting above another can win even when both share the same model
/// coordinates. The returned point is converted back to model space.
PieceEdgeTarget? closestPieceEdge({
  required Offset aim,
  required List<PapercutPiece> pieces,
  required double spacing,
}) {
  PieceEdgeTarget? best;
  var bestDistance = double.infinity;
  for (var i = 0; i < pieces.length; i++) {
    final piece = pieces[i];
    final rings = [
      [for (final vertex in piece.vertices) vertex + piece.separation],
      for (final hole in piece.holes)
        [for (final vertex in hole) vertex + piece.separation],
    ];
    final hit = closestGridEdgePoint(aim, rings, spacing);
    if (hit == null) continue;
    final distance = (hit - aim).distance;
    if (distance >= bestDistance) continue;
    best = PieceEdgeTarget(index: i, model: hit - piece.separation);
    bestDistance = distance;
  }
  return best;
}

/// Closest unit-grid point on any closed outline. There is no distance cutoff.
Offset? closestGridEdgePoint(
  Offset point,
  List<List<Offset>> rings,
  double spacing,
) {
  Offset? best;
  var bestDistance = double.infinity;
  for (final ring in rings) {
    for (final vertex in pieceEdgeGridPoints(ring, spacing)) {
      final distance = (vertex - point).distance;
      if (distance >= bestDistance) continue;
      best = vertex;
      bestDistance = distance;
    }
  }
  return best;
}

/// Closest point on any closed outline. There is no distance cutoff.
Offset? closestOutlinePoint(Offset point, List<List<Offset>> rings) {
  Offset? best;
  var bestDistance = double.infinity;
  for (final ring in rings) {
    if (ring.length < 2) continue;
    for (var i = 0; i < ring.length; i++) {
      final closest = _closestOnSegment(
        point,
        ring[i],
        ring[(i + 1) % ring.length],
      );
      final distance = (closest - point).distance;
      if (distance >= bestDistance) continue;
      best = closest;
      bestDistance = distance;
    }
  }
  return best;
}

Offset _closestOnSegment(Offset point, Offset a, Offset b) {
  final delta = b - a;
  final len2 = delta.dx * delta.dx + delta.dy * delta.dy;
  if (len2 < 1e-12) return a;
  final t =
      (((point.dx - a.dx) * delta.dx + (point.dy - a.dy) * delta.dy) / len2)
          .clamp(0.0, 1.0);
  return Offset(a.dx + delta.dx * t, a.dy + delta.dy * t);
}

/// Grid points along a piece outline.
List<Offset> pieceEdgeGridPoints(List<Offset> ring, double spacing) {
  if (spacing <= 0 || ring.length < 2) return const [];
  final points = <Offset>[];
  void add(Offset point) {
    if (points.any((other) => (other - point).distance < _eps)) return;
    points.add(point);
  }

  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    final delta = b - a;
    final length = delta.distance;
    if (length < _eps) continue;
    final steps = (length / spacing).round().clamp(1, 10000);
    for (var step = 0; step <= steps; step++) {
      final t = step / steps;
      add(Offset(a.dx + delta.dx * t, a.dy + delta.dy * t));
    }
  }
  return points;
}

/// Grid points that lie on the paper border.
List<Offset> paperEdgeGridPoints(Rect paper, double spacing) {
  if (spacing <= 0) return const [];
  final points = <Offset>[];
  void add(Offset point) {
    if (points.any((other) => (other - point).distance < _eps)) return;
    points.add(point);
  }

  for (var x = paper.left; x <= paper.right + _eps; x += spacing) {
    add(Offset(x, paper.top));
    add(Offset(x, paper.bottom));
  }
  for (var y = paper.top; y <= paper.bottom + _eps; y += spacing) {
    add(Offset(paper.left, y));
    add(Offset(paper.right, y));
  }
  return points;
}

/// Blueprint vertices, cut vertices, and the paper border.
List<Offset> datumsFor(GridStep step, PapercutSheet sheet) {
  return [
    ...step.vertices,
    for (final stroke in sheet.cutStrokes) ...stroke,
    for (final crease in sheet.creases) ...[crease.a, crease.b],
  ];
}

/// Nearest datum ahead of [from] along [direction], or the far paper edge.
Offset? nextDatum({
  required Offset from,
  required Offset direction,
  required Rect paper,
  required List<Offset> datums,
  List<Offset>? boundary,
}) {
  Offset? best;
  var bestDistance = double.infinity;
  void consider(Offset point) {
    final along = _along(from, direction, point);
    if (along == null || along <= _eps || along >= bestDistance) return;
    best = point;
    bestDistance = along;
  }

  for (final datum in datums) {
    consider(datum);
  }
  final exit = boundary == null
      ? _paperExit(from, direction, paper)
      : _ringExit(from, direction, boundary);
  if (exit != null) consider(exit);
  return best;
}

/// Lays out a split. Finished blueprint pieces stay on their outline and
/// the scrap steps away, so a completed piece is its own object.
/// A won level stays where it was cut so leftover bursts land on the paper.
PapercutSheet layoutAfterSplit(
  PapercutSheet before,
  PapercutSheet after,
  double spacing, {
  Set<String> finished = const {},
  bool winning = false,
}) {
  if (winning || spacing <= 0) return after;
  return spreadPieces(before, after, spacing, pinned: finished);
}

/// Pulls the pieces created by a split off each other by [spacing].
///
/// New pieces step apart from their shared centroid. Every piece then
/// relaxes under a size-weighted push so none of the drawn bounds occupy
/// the same space, and packs back toward that first step when it can.
/// Pieces in [pinned] keep the separation they already have. A completed
/// blueprint piece stays on its outline while the scrap steps away.
PapercutSheet spreadPieces(
  PapercutSheet before,
  PapercutSheet after,
  double spacing, {
  Set<String> pinned = const {},
}) {
  if (spacing <= 0 || after.pieces.length < 2) return after;
  final oldIds = {for (final piece in before.pieces) piece.id};
  final fresh = <int>[];
  for (var i = 0; i < after.pieces.length; i++) {
    if (!oldIds.contains(after.pieces[i].id)) fresh.add(i);
  }
  if (fresh.length < 2) return after;
  var weight = 0.0;
  var gx = 0.0;
  var gy = 0.0;
  for (final index in fresh) {
    final piece = after.pieces[index];
    final area = polygonSignedArea(piece.vertices).abs();
    final centroid = polygonCentroid(piece.vertices);
    weight += area;
    gx += centroid.dx * area;
    gy += centroid.dy * area;
  }
  if (weight < 1e-8) return after;
  final group = Offset(gx / weight, gy / weight);
  bool stays(int index) =>
      !fresh.contains(index) || pinned.contains(after.pieces[index].id);
  final home = <Offset>[
    for (var i = 0; i < after.pieces.length; i++)
      if (stays(i))
        after.pieces[i].separation
      else
        after.pieces[i].separation +
            _nudge(polygonCentroid(after.pieces[i].vertices) - group, spacing),
  ];
  final settled = relaxSeparations(
    bounds: [for (final piece in after.pieces) _pieceBounds(piece.vertices)],
    areas: [
      for (final piece in after.pieces)
        math.max(polygonSignedArea(piece.vertices).abs(), spacing * spacing),
    ],
    home: home,
    gap: spacing,
    pinned: [for (final piece in after.pieces) pinned.contains(piece.id)],
  );
  return after.copyWith(
    pieces: [
      for (var i = 0; i < after.pieces.length; i++)
        after.pieces[i].copyWith(separation: settled[i]),
    ],
  );
}

Rect _pieceBounds(List<Offset> ring) {
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
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

/// Pushes overlapping pieces apart, then packs them back toward [home].
///
/// The push is the overlap depth. A larger neighbor takes less of it, so a
/// small piece slides out of the way of a big one. [gap] is the air kept
/// between drawn bounds.
List<Offset> relaxSeparations({
  required List<Rect> bounds,
  required List<double> areas,
  required List<Offset> home,
  double gap = 0,
  List<bool> pinned = const [],
}) {
  final sep = [...home];
  bool fixed(int index) => index < pinned.length && pinned[index];
  Rect shown(int index) => bounds[index].shift(sep[index]).inflate(gap / 2);

  Offset? push(Rect a, Rect b) {
    if (!a.overlaps(b)) return null;
    final overlapX = math.min(a.right, b.right) - math.max(a.left, b.left);
    final overlapY = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
    if (overlapX <= 1e-6 || overlapY <= 1e-6) return null;
    if (overlapX < overlapY) {
      final sign = a.center.dx <= b.center.dx ? 1.0 : -1.0;
      return Offset(sign * overlapX, 0);
    }
    final sign = a.center.dy <= b.center.dy ? 1.0 : -1.0;
    return Offset(0, sign * overlapY);
  }

  for (var iter = 0; iter < 24; iter++) {
    final force = List<Offset>.filled(sep.length, Offset.zero);
    var any = false;
    for (var i = 0; i < sep.length; i++) {
      for (var j = i + 1; j < sep.length; j++) {
        final mtv = push(shown(i), shown(j));
        if (mtv == null || (fixed(i) && fixed(j))) continue;
        any = true;
        if (fixed(i)) {
          force[j] += mtv;
        } else if (fixed(j)) {
          force[i] -= mtv;
        } else {
          final total = areas[i] + areas[j];
          force[i] -= mtv * (areas[j] / total);
          force[j] += mtv * (areas[i] / total);
        }
      }
    }
    if (!any) break;
    for (var i = 0; i < sep.length; i++) {
      if (fixed(i)) continue;
      sep[i] += force[i];
    }
  }

  for (var step = 0; step < 8; step++) {
    for (var i = 0; i < sep.length; i++) {
      if (fixed(i)) continue;
      final trial = sep[i] + (home[i] - sep[i]) * 0.35;
      final previous = sep[i];
      sep[i] = trial;
      var blocked = false;
      for (var j = 0; j < sep.length; j++) {
        if (j == i) continue;
        if (shown(i).overlaps(shown(j))) {
          blocked = true;
          break;
        }
      }
      if (blocked) sep[i] = previous;
    }
  }
  return sep;
}

/// Portions of [stroke] that still read as a cut on [piece].
///
/// A mark stays in the interior and travels with that piece. Where the stroke
/// lies on an outline, the split has already made that edge, so the mark is
/// dropped. An approach that only crosses another piece's margin is not taken.
List<List<Offset>> cutMarksOnPiece(List<Offset> stroke, PapercutPiece piece) {
  if (stroke.length < 2) return const [];
  final marks = <List<Offset>>[];
  for (var i = 0; i < stroke.length - 1; i++) {
    for (final part in segmentOnPiece(stroke[i], stroke[i + 1], piece)) {
      final mid = Offset(
        (part.$1.dx + part.$2.dx) / 2,
        (part.$1.dy + part.$2.dy) / 2,
      );
      if (!_inPieceInterior(mid, piece)) continue;
      marks.add([part.$1, part.$2]);
    }
  }
  return marks;
}

bool _inPieceInterior(Offset point, PapercutPiece piece) {
  if (!isInsidePolygon(point, piece.vertices)) return false;
  if (_distanceToRing(point, piece.vertices) <= 1e-3) return false;
  for (final hole in piece.holes) {
    if (isInsidePolygon(point, hole)) return false;
  }
  return true;
}

Offset _nudge(Offset delta, double spacing) {
  // Two cells each way, so the shared cut opens into a four-cell gap.
  final step = spacing * 2;
  final x = delta.dx.abs() < 1e-3 ? 0.0 : step * delta.dx.sign;
  final y = delta.dy.abs() < 1e-3 ? 0.0 : step * delta.dy.sign;
  return Offset(x, y);
}

class ScissorCommit {
  const ScissorCommit({required this.sheet, required this.march});

  final PapercutSheet sheet;
  final ScissorMarch? march;
}

/// Cuts from the march start through the next datum on [base].
///
/// The march stays locked once the blade has entered paper, until the piece
/// count grows.
ScissorCommit? commitScissor({
  required ScissorMarch march,
  required GridStep step,
  required PapercutSheet base,
  Offset? direction,
  List<List<Offset>>? closed,
}) {
  final dir = direction ?? march.direction;
  final aimed = ScissorMarch(
    path: march.path,
    direction: dir,
    locked: march.locked,
  );
  final end = aimed.previewEnd(
    step,
    base,
    closed: closed,
    skipCollinear: (a, b) => penciledRidesPennedNeighbor(
      step.polygons,
      step.edgeStyles,
      a,
      b,
      closed: step.ringClosed,
    ),
  );
  if (end == null) return null;
  final path = [...march.path, end];
  final thick = step.attachment.thickCut;
  final owner = _strokeOwner(base, path);
  final shift = owner?.separation ?? Offset.zero;
  final display = [
    for (final point in path)
      displayPoint(point, base.folds, pieceId: owner?.id) + shift,
  ];
  final cut = cutThroughFolds(
    base,
    display,
    thickCut: thick,
    blueprintPieces: [
      for (var i = 0; i < step.polygons.length; i++)
        if (step.isRingClosed(i)) step.polygons[i],
    ],
  );
  if (cut == null) return null;
  final split =
      cut.pieces.length > base.pieces.length ||
      _holeCount(cut) > _holeCount(base);
  if (split) {
    return ScissorCommit(sheet: cut, march: null);
  }
  final entered = _entersPieces(march.position, end, base.pieces);
  return ScissorCommit(
    sheet: cut,
    march: ScissorMarch(
      path: path,
      direction: dir,
      locked: march.locked || entered,
    ),
  );
}

/// Cut or fold span on the vertical grid line through [contact].
(Offset, Offset)? verticalSpan({
  required Offset contact,
  required GridStep step,
  required PapercutSheet sheet,
}) {
  final x = contact.dx;
  final marks = <double>[step.paper.top, step.paper.bottom];
  for (final datum in datumsFor(step, sheet)) {
    if ((datum.dx - x).abs() > _eps) continue;
    marks.add(datum.dy);
  }
  marks.sort();
  double? below;
  double? above;
  for (final y in marks) {
    if (y < contact.dy - _eps) below = y;
    if (y > contact.dy + _eps) {
      above = y;
      break;
    }
  }
  if (below == null || above == null) return null;
  return (Offset(x, below), Offset(x, above));
}

Offset? _inward(Offset point, Rect paper) {
  final onLeft = (point.dx - paper.left).abs() < _eps;
  final onRight = (point.dx - paper.right).abs() < _eps;
  final onBottom = (point.dy - paper.top).abs() < _eps;
  final onTop = (point.dy - paper.bottom).abs() < _eps;
  if (!onLeft && !onRight && !onBottom && !onTop) return null;
  if (onBottom && !onLeft && !onRight) return const Offset(0, 1);
  if (onTop && !onLeft && !onRight) return const Offset(0, -1);
  if (onLeft && !onBottom && !onTop) return const Offset(1, 0);
  if (onRight && !onBottom && !onTop) return const Offset(-1, 0);
  if (onBottom) return const Offset(0, 1);
  if (onTop) return const Offset(0, -1);
  if (onLeft) return const Offset(1, 0);
  return const Offset(-1, 0);
}

int _holeCount(PapercutSheet sheet) {
  var count = 0;
  for (final piece in sheet.pieces) {
    count += piece.holes.length;
  }
  return count;
}

bool _collinearRay(Offset from, Offset ray, Offset a, Offset b) {
  final edge = b - a;
  final denom = ray.dx * edge.dy - ray.dy * edge.dx;
  if (denom.abs() > 1e-6) return false;
  final rel = a - from;
  final cross = rel.dx * ray.dy - rel.dy * ray.dx;
  return cross.abs() <= 1e-3;
}

void _raySegment(
  Offset from,
  Offset ray,
  Offset a,
  Offset b,
  void Function(double t, Offset point) consider,
) {
  final edge = b - a;
  final denom = ray.dx * edge.dy - ray.dy * edge.dx;
  final rel = a - from;
  if (denom.abs() < 1e-8) {
    final cross = rel.dx * ray.dy - rel.dy * ray.dx;
    if (cross.abs() > 1e-3) return;
    final ta = rel.dx * ray.dx + rel.dy * ray.dy;
    final tb = (b.dx - from.dx) * ray.dx + (b.dy - from.dy) * ray.dy;
    if (ta > _eps) consider(ta, a);
    if (tb > _eps) consider(tb, b);
    return;
  }
  final t = (rel.dx * edge.dy - rel.dy * edge.dx) / denom;
  final u = (rel.dx * ray.dy - rel.dy * ray.dx) / denom;
  if (t <= _eps || u < -1e-4 || u > 1 + 1e-4) return;
  consider(t, Offset(from.dx + ray.dx * t, from.dy + ray.dy * t));
}

double? _along(Offset from, Offset direction, Offset point) {
  final rel = point - from;
  final cross = rel.dx * direction.dy - rel.dy * direction.dx;
  if (cross.abs() > 1e-3) return null;
  return rel.dx * direction.dx + rel.dy * direction.dy;
}

Offset? _paperExit(Offset from, Offset direction, Rect paper) {
  var best = double.infinity;
  Offset? hit;
  void consider(double t, Offset point) {
    if (t <= _eps || t >= best) return;
    if (!_onRect(point, paper)) return;
    best = t;
    hit = point;
  }

  if (direction.dx.abs() > 0.5) {
    final x = direction.dx > 0 ? paper.right : paper.left;
    final t = (x - from.dx) / direction.dx;
    consider(t, Offset(x, from.dy));
  }
  if (direction.dy.abs() > 0.5) {
    final y = direction.dy > 0 ? paper.bottom : paper.top;
    final t = (y - from.dy) / direction.dy;
    consider(t, Offset(from.dx, y));
  }
  return hit;
}

bool _onRect(Offset point, Rect paper) {
  final insideX =
      point.dx >= paper.left - _eps && point.dx <= paper.right + _eps;
  final insideY =
      point.dy >= paper.top - _eps && point.dy <= paper.bottom + _eps;
  if (!insideX || !insideY) return false;
  final onEdge =
      (point.dx - paper.left).abs() < _eps ||
      (point.dx - paper.right).abs() < _eps ||
      (point.dy - paper.top).abs() < _eps ||
      (point.dy - paper.bottom).abs() < _eps;
  return onEdge;
}

/// Piece the blade is traveling through, so its separation can be drawn.
PapercutPiece? _strokeOwner(PapercutSheet sheet, List<Offset> path) {
  for (var i = 0; i < path.length - 1; i++) {
    final mid = Offset(
      (path[i].dx + path[i + 1].dx) / 2,
      (path[i].dy + path[i + 1].dy) / 2,
    );
    for (final piece in sheet.pieces) {
      if (!_ownsInterior(piece, mid)) continue;
      return piece;
    }
  }
  return null;
}

bool _ownsInterior(PapercutPiece piece, Offset point) {
  if (piece.vertices.length < 3 || !isInsidePolygon(point, piece.vertices)) {
    return false;
  }
  for (final hole in piece.holes) {
    if (hole.length >= 3 && isInsidePolygon(point, hole)) return false;
  }
  return true;
}

bool _entersPieces(Offset a, Offset b, List<PapercutPiece> pieces) {
  final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
  for (final piece in pieces) {
    if (isInsidePolygon(mid, piece.vertices)) return true;
  }
  return false;
}

/// Piece the blade will enter, or the piece whose outline contains [point].
PapercutPiece? pieceFacing(
  Offset point,
  Offset direction,
  List<PapercutPiece> pieces,
) {
  PapercutPiece? touching;
  final probe = point + direction * 0.05;
  for (final piece in pieces) {
    if (!ownsPoint(piece.vertices, point)) continue;
    touching ??= piece;
    if (isInsidePolygon(probe, piece.vertices)) return piece;
  }
  return touching;
}

bool ownsPoint(List<Offset> ring, Offset point) {
  if (isInsidePolygon(point, ring)) return true;
  return _distanceToRing(point, ring) <= 1e-3;
}

/// Display shift for a mark at [point].
///
/// A mark follows the piece that contains it. On a shared edge it follows the
/// inner piece: the sheet's hole gives that edge to the cut-out, and a tie
/// between solid pieces goes to the smaller one.
Offset markSeparation(Offset point, List<PapercutPiece> pieces) {
  PapercutPiece? best;
  var bestArea = double.infinity;
  for (final piece in pieces) {
    if (!_pieceOwnsMark(piece, point)) continue;
    final area = polygonSignedArea(piece.vertices).abs();
    if (area < bestArea) {
      best = piece;
      bestArea = area;
    }
  }
  return best?.separation ?? Offset.zero;
}

bool _pieceOwnsMark(PapercutPiece piece, Offset point) {
  if (!ownsPoint(piece.vertices, point)) return false;
  for (final hole in piece.holes) {
    if (isInsidePolygon(point, hole)) return false;
    if (_distanceToRing(point, hole) <= 1e-3) return false;
  }
  return true;
}

/// Portions of segment [a]–[b] that lie on [piece].
///
/// The level keeps the authored ring whole, so the blade, hits, and victory
/// still see one blueprint piece. Drawing clips that ring onto the paper:
/// a cut through an edge splits it, and each side travels with the piece
/// that holds it. A point in a hole belongs to the cut-out, not the sheet.
List<(Offset, Offset)> segmentOnPiece(Offset a, Offset b, PapercutPiece piece) {
  final delta = b - a;
  if (delta.distance < 1e-8 || piece.vertices.length < 3) return const [];
  final parameters = <double>[0, 1];
  void addRing(List<Offset> ring) {
    for (var i = 0; i < ring.length; i++) {
      final hit = segmentIntersection(
        a,
        b,
        ring[i],
        ring[(i + 1) % ring.length],
      );
      if (hit.isPoint && hit.point != null) {
        parameters.add(parameterOnSegment(a, b, hit.point!).clamp(0.0, 1.0));
      } else if (hit.isCollinear) {
        final start = hit.segmentStart;
        final end = hit.segmentEnd;
        if (start != null) {
          parameters.add(parameterOnSegment(a, b, start).clamp(0.0, 1.0));
        }
        if (end != null) {
          parameters.add(parameterOnSegment(a, b, end).clamp(0.0, 1.0));
        }
      }
    }
  }

  addRing(piece.vertices);
  for (final hole in piece.holes) {
    addRing(hole);
  }
  parameters.sort();

  Offset at(double t) => Offset(a.dx + delta.dx * t, a.dy + delta.dy * t);
  final kept = <(Offset, Offset)>[];
  for (var i = 0; i < parameters.length - 1; i++) {
    final t0 = parameters[i];
    final t1 = parameters[i + 1];
    if (t1 - t0 < 1e-5) continue;
    if (!_pieceOwnsMark(piece, at((t0 + t1) / 2))) continue;
    kept.add((at(t0), at(t1)));
  }
  return kept;
}

/// Parts of [polygon] that lie on [piece].
///
/// A cut that crosses the blueprint shows up as the shared edge between two
/// pieces, so each side is its own ring and can travel with that piece.
List<List<Offset>> polygonOnPiece(List<Offset> polygon, PapercutPiece piece) {
  if (polygon.length < 3 || piece.vertices.length < 3) return const [];
  final segments = <(Offset, Offset)>[];
  void addRing(List<Offset> ring) {
    for (var i = 0; i < ring.length; i++) {
      final next = ring[(i + 1) % ring.length];
      if ((ring[i] - next).distance < 1e-4) continue;
      segments.add((ring[i], next));
    }
  }

  addRing(polygon);
  addRing(piece.vertices);
  for (final hole in piece.holes) {
    addRing(hole);
  }
  final faces = PlanarGraph(splitAllAtIntersections(segments)).findFaces();
  final kept = <List<Offset>>[];
  for (final face in faces) {
    if (face.length < 3 || polygonSignedArea(face).abs() < 1e-3) continue;
    if (!_ringOnPiece(face, piece)) continue;
    final sample = _faceSample(face);
    if (sample == null || !isInsidePolygon(sample, face)) continue;
    if (!isInsidePolygon(sample, polygon)) continue;
    if (!_inPieceSolid(sample, piece)) continue;
    kept.add(face);
  }
  return kept;
}

Offset? _faceSample(List<Offset> face) {
  const offset = 0.02;
  for (var i = 0; i < face.length; i++) {
    final a = face[i];
    final b = face[(i + 1) % face.length];
    final delta = b - a;
    final len2 = delta.dx * delta.dx + delta.dy * delta.dy;
    if (len2 < 1e-8) continue;
    final inv = offset / math.sqrt(len2);
    final sample = Offset(
      (a.dx + b.dx) / 2 + delta.dy * inv,
      (a.dy + b.dy) / 2 - delta.dx * inv,
    );
    if (isInsidePolygon(sample, face)) return sample;
  }
  final centroid = polygonCentroid(face);
  if (isInsidePolygon(centroid, face)) return centroid;
  return null;
}

bool _ringOnPiece(List<Offset> ring, PapercutPiece piece) {
  for (final point in ring) {
    if (!ownsPoint(piece.vertices, point)) return false;
    for (final hole in piece.holes) {
      if (isInsidePolygon(point, hole) && _distanceToRing(point, hole) > 1e-3) {
        return false;
      }
    }
  }
  return true;
}

bool _inPieceSolid(Offset point, PapercutPiece piece) {
  if (!isInsidePolygon(point, piece.vertices)) return false;
  for (final hole in piece.holes) {
    if (isInsidePolygon(point, hole)) return false;
  }
  return true;
}

double _distanceToRing(Offset point, List<Offset> ring) {
  var best = double.infinity;
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    final delta = b - a;
    final len2 = delta.dx * delta.dx + delta.dy * delta.dy;
    if (len2 < 1e-12) {
      final distance = (point - a).distance;
      if (distance < best) best = distance;
      continue;
    }
    final t =
        (((point.dx - a.dx) * delta.dx + (point.dy - a.dy) * delta.dy) / len2)
            .clamp(0.0, 1.0);
    final closest = Offset(a.dx + delta.dx * t, a.dy + delta.dy * t);
    final distance = (point - closest).distance;
    if (distance < best) best = distance;
  }
  return best;
}

/// Axis direction into [ring] from a point on its boundary.
///
/// A corner belongs to two edges. The direction kept is the one that steps
/// into the piece and, when both do, the one aimed more toward the piece.
Offset? inwardOnRing(Offset point, List<Offset> ring) {
  if (ring.length < 3) return null;
  final area = polygonSignedArea(ring);
  if (area.abs() < 1e-8) return null;
  final candidates = <Offset>[];
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    if (_distanceToSegment(point, a, b) > 1e-3) continue;
    final along = _segmentT(point, a, b);
    if (along < -1e-3 || along > 1 + 1e-3) continue;
    final normal = axisPerpendicular(a, b, ring);
    if (normal == null) continue;
    if (candidates.any((other) => other == normal)) continue;
    candidates.add(normal);
  }
  if (candidates.isEmpty) return null;
  final into = [
    for (final candidate in candidates)
      if (_stepsInside(point, candidate, ring)) candidate,
  ];
  final usable = into.isNotEmpty ? into : candidates;
  if (usable.length == 1) return usable.first;
  final center = polygonCentroid(ring) - point;
  var best = usable.first;
  var bestDot = -double.infinity;
  for (final candidate in usable) {
    final dot = candidate.dx * center.dx + candidate.dy * center.dy;
    if (dot <= bestDot) continue;
    best = candidate;
    bestDot = dot;
  }
  return best;
}

bool _stepsInside(Offset point, Offset direction, List<Offset> ring) {
  return isInsidePolygon(point + direction * 0.05, ring);
}

double _distanceToSegment(Offset point, Offset a, Offset b) {
  final delta = b - a;
  final len2 = delta.dx * delta.dx + delta.dy * delta.dy;
  if (len2 < 1e-12) return (point - a).distance;
  final t =
      (((point.dx - a.dx) * delta.dx + (point.dy - a.dy) * delta.dy) / len2)
          .clamp(0.0, 1.0);
  final closest = Offset(a.dx + delta.dx * t, a.dy + delta.dy * t);
  return (point - closest).distance;
}

double _segmentT(Offset point, Offset a, Offset b) {
  final delta = b - a;
  final len2 = delta.dx * delta.dx + delta.dy * delta.dy;
  if (len2 < 1e-12) return 0;
  return ((point.dx - a.dx) * delta.dx + (point.dy - a.dy) * delta.dy) / len2;
}

Offset? _ringExit(Offset from, Offset direction, List<Offset> ring) {
  var best = double.infinity;
  Offset? hit;
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    final t = _rayOnSegment(from, direction, a, b);
    if (t == null || t >= best) continue;
    best = t;
    hit = Offset(from.dx + direction.dx * t, from.dy + direction.dy * t);
  }
  return hit;
}

double? _rayOnSegment(Offset from, Offset direction, Offset p, Offset q) {
  final dxb = q.dx - p.dx;
  final dyb = q.dy - p.dy;
  final denom = direction.dx * dyb - direction.dy * dxb;
  if (denom.abs() < 1e-9) return null;
  final wx = from.dx - p.dx;
  final wy = from.dy - p.dy;
  final t = (dxb * wy - dyb * wx) / denom;
  final u = (direction.dx * wy - direction.dy * wx) / denom;
  if (t <= _eps) return null;
  if (u < -1e-3 || u > 1 + 1e-3) return null;
  return t;
}
