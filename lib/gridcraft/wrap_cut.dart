import 'dart:math' as math;
import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

import '../geometry/polygon_union.dart';
import '../papercut/paper.dart';
import '../papercut/split.dart';
import 'blueprint.dart';
import 'folded_model.dart';
import 'placement.dart';
import 'scissor.dart';

const double _eps = 1e-6;

/// Distance along a stroke, in paper units, that decides which side of a
/// line the blade is on.
const double _probe = 1e-3;

double _cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;

double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

// ---------------------------------------------------------------------------
// Snapping
// ---------------------------------------------------------------------------

/// Nearest-point lookup over pattern lines and paper edges.
class SegmentQuadtree {
  SegmentQuadtree(this.segments) {
    final box = pointBounds([
      for (final (a, b) in segments) ...[a, b],
    ]);
    _root = _SegmentNode(box.inflate(1), 0);
    for (var i = 0; i < segments.length; i++) {
      _insert(_root, i, _box(segments[i]));
    }
  }

  static const int _capacity = 8;
  static const int _maxDepth = 8;

  final List<(Offset, Offset)> segments;
  late final _SegmentNode _root;

  /// Segment indexes whose bounds come within [reach] of [point].
  Set<int> near(Offset point, double reach) {
    final query = Rect.fromCircle(center: point, radius: reach);
    final found = <int>{};
    void visit(_SegmentNode node) {
      if (!_touches(node.bounds, query)) return;
      final children = node.children;
      if (children == null) {
        for (final index in node.items) {
          if (_touches(_box(segments[index]), query)) found.add(index);
        }
        return;
      }
      for (final child in children) {
        visit(child);
      }
    }

    visit(_root);
    return found;
  }

  /// The pattern vertex nearest [point] within [tolerance], else the nearest
  /// point on a line within it. Vertices are segment ends and crossings.
  Offset? snap(Offset point, double tolerance) {
    final candidates = near(point, tolerance).toList();
    Offset? vertex;
    var vertexDistance = tolerance;
    void considerVertex(Offset at) {
      final distance = (at - point).distance;
      if (distance > vertexDistance) return;
      vertexDistance = distance;
      vertex = at;
    }

    for (final index in candidates) {
      final (a, b) = segments[index];
      considerVertex(a);
      considerVertex(b);
    }
    for (var i = 0; i < candidates.length; i++) {
      for (var j = i + 1; j < candidates.length; j++) {
        final hit = _segmentCrossing(
          segments[candidates[i]],
          segments[candidates[j]],
        );
        if (hit != null) considerVertex(hit);
      }
    }
    if (vertex != null) return vertex;
    Offset? best;
    var bestDistance = tolerance;
    for (final index in candidates) {
      final (a, b) = segments[index];
      final at = _closestOnSegment(point, a, b);
      final distance = (at - point).distance;
      if (distance > bestDistance) continue;
      bestDistance = distance;
      best = at;
    }
    return best;
  }

  void _insert(_SegmentNode node, int index, Rect box) {
    final children = node.children;
    if (children != null) {
      for (final child in children) {
        if (_touches(child.bounds, box)) _insert(child, index, box);
      }
      return;
    }
    node.items.add(index);
    if (node.items.length <= _capacity || node.depth >= _maxDepth) return;
    final b = node.bounds;
    final c = b.center;
    node.children = [
      _SegmentNode(Rect.fromLTRB(b.left, b.top, c.dx, c.dy), node.depth + 1),
      _SegmentNode(Rect.fromLTRB(c.dx, b.top, b.right, c.dy), node.depth + 1),
      _SegmentNode(Rect.fromLTRB(b.left, c.dy, c.dx, b.bottom), node.depth + 1),
      _SegmentNode(
        Rect.fromLTRB(c.dx, c.dy, b.right, b.bottom),
        node.depth + 1,
      ),
    ];
    final items = [...node.items];
    node.items.clear();
    for (final item in items) {
      _insert(node, item, _box(segments[item]));
    }
  }

  static Rect _box((Offset, Offset) segment) =>
      Rect.fromPoints(segment.$1, segment.$2);

  static bool _touches(Rect a, Rect b) =>
      a.left <= b.right &&
      b.left <= a.right &&
      a.top <= b.bottom &&
      b.top <= a.bottom;
}

class _SegmentNode {
  _SegmentNode(this.bounds, this.depth);

  final Rect bounds;
  final int depth;
  final List<int> items = [];
  List<_SegmentNode>? children;
}

/// Pattern lines and the edges of [piece], ready for snapping.
SegmentQuadtree patternQuadtree(
  List<(Offset, Offset)> lines,
  PapercutPiece piece,
) {
  return SegmentQuadtree([
    ...lines,
    for (final ring in [piece.vertices, ...piece.holes])
      for (var i = 0; i < ring.length; i++)
        (ring[i], ring[(i + 1) % ring.length]),
  ]);
}

/// Where a tap at [point] puts the blade: the nearest pattern vertex, pattern
/// line, or paper edge within [tolerance] that lies on the paper.
Offset? snapToPattern(
  SegmentQuadtree tree,
  PapercutPiece piece,
  Offset point,
  double tolerance,
) {
  final at = tree.snap(point, tolerance);
  if (at == null || !ownsPoint(piece.vertices, at)) return null;
  for (final hole in piece.holes) {
    if (hole.length >= 3 &&
        isInsidePolygon(at, hole) &&
        _ringDistance(at, hole) > 1e-6) {
      return null;
    }
  }
  return at;
}

// ---------------------------------------------------------------------------
// Model adjacency
// ---------------------------------------------------------------------------

/// The face across one outline edge, and that edge's index on it.
class FaceNeighbor {
  const FaceNeighbor(this.face, this.edge);

  final int face;
  final int edge;
}

/// For every face and outline edge, the face that shares that edge in 3D,
/// matched by world endpoints. Unlike [FoldedModel.hinges], this includes
/// edges that were cut apart in the net.
List<List<FaceNeighbor?>> faceAdjacency(
  FoldedModel model, {
  double tolerance = 1e-4,
}) {
  final rings = [for (final face in model.faces) face.worldRing()];
  bool same(Vector3 a, Vector3 b) => (a - b).length < tolerance;
  return [
    for (var i = 0; i < rings.length; i++)
      [
        for (var e = 0; e < rings[i].length; e++)
          () {
            final a = rings[i][e];
            final b = rings[i][(e + 1) % rings[i].length];
            for (var j = 0; j < rings.length; j++) {
              if (j == i) continue;
              final ring = rings[j];
              for (var f = 0; f < ring.length; f++) {
                final p = ring[f];
                final q = ring[(f + 1) % ring.length];
                if ((same(a, q) && same(b, p)) || (same(a, p) && same(b, q))) {
                  return FaceNeighbor(j, f);
                }
              }
            }
            return null;
          }(),
      ],
  ];
}

// ---------------------------------------------------------------------------
// Convex constraints
// ---------------------------------------------------------------------------

/// Points p with (p − [point])·[normal] ≥ 0. [normal] is a unit vector.
class HalfPlane {
  const HalfPlane(this.point, this.normal);

  final Offset point;
  final Offset normal;

  double side(Offset p) => _dot(p - point, normal);

  bool holds(Offset p, [double tolerance = _eps]) => side(p) >= -tolerance;

  HalfPlane get flipped => HalfPlane(point, -normal);

  /// True when [a]–[b] lies on this half-plane's line.
  bool onLine(Offset a, Offset b) =>
      side(a).abs() < 1e-6 && side(b).abs() < 1e-6;
}

/// Inward half-planes of a counter-clockwise convex [ring].
List<HalfPlane> convexSides(List<Offset> ring) {
  final sides = <HalfPlane>[];
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final edge = ring[(i + 1) % ring.length] - a;
    final length = edge.distance;
    if (length < 1e-12) continue;
    sides.add(HalfPlane(a, Offset(-edge.dy, edge.dx) / length));
  }
  return sides;
}

/// Sutherland–Hodgman: [ring] inside every half-plane of [sides]. A concave
/// ring stays correct in area; the clip window is convex.
List<Offset> clipByHalfPlanes(List<Offset> ring, Iterable<HalfPlane> sides) {
  var output = ring;
  for (final side in sides) {
    if (output.length < 3) return const [];
    final input = output;
    output = <Offset>[];
    for (var i = 0; i < input.length; i++) {
      final current = input[i];
      final previous = input[(i + input.length - 1) % input.length];
      final dc = side.side(current);
      final dp = side.side(previous);
      final inCurrent = dc >= -1e-9;
      final inPrevious = dp >= -1e-9;
      if (inCurrent) {
        if (!inPrevious) output.add(_lerpAt(previous, current, dp, dc));
        output.add(current);
      } else if (inPrevious) {
        output.add(_lerpAt(previous, current, dp, dc));
      }
    }
  }
  return output.length < 3 ? const [] : output;
}

Offset _lerpAt(Offset a, Offset b, double da, double db) {
  final t = da / (da - db);
  return Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
}

double _ringArea(List<Offset> ring) =>
    ring.length < 3 ? 0 : polygonSignedArea(ring).abs();

/// Area of [piece] inside the convex window [sides].
double _areaWithin(PapercutPiece piece, List<HalfPlane> sides) {
  var area = _ringArea(clipByHalfPlanes(piece.vertices, sides));
  for (final hole in piece.holes) {
    area -= _ringArea(clipByHalfPlanes(hole, sides));
  }
  return math.max(0, area);
}

List<Offset> _counterClockwise(List<Offset> ring) =>
    polygonSignedArea(ring) < 0 ? ring.reversed.toList() : ring;

// ---------------------------------------------------------------------------
// Flaps and folds
// ---------------------------------------------------------------------------

/// Part of the sheet on one model face: the sheet piece inside a convex set
/// of half-planes, one per fold line so far.
class WrapFlap {
  const WrapFlap({
    required this.face,
    required this.sides,
    required this.facePaper,
    this.parent,
    this.fold,
  });

  final int face;
  final List<HalfPlane> sides;

  /// [face]'s outline in paper coordinates, counter-clockwise.
  final List<Offset> facePaper;

  /// Flap this one folded off, and the fold that did it. Null on the anchor.
  final int? parent;
  final int? fold;

  bool holds(Offset point, [double tolerance = _eps]) =>
      sides.every((side) => side.holds(point, tolerance));

  WrapFlap withSide(HalfPlane side) => WrapFlap(
    face: face,
    sides: [...sides, side],
    facePaper: facePaper,
    parent: parent,
    fold: fold,
  );
}

/// A fold across model edge [a]→[b], in paper coordinates. [near] keeps its
/// place; [far] turns by [angle] about the line, in [near]'s paper frame.
class WrapFold {
  const WrapFold({
    required this.a,
    required this.b,
    required this.near,
    required this.far,
    required this.angle,
    required this.extent,
    this.crossings = const [],
  });

  final Offset a;
  final Offset b;
  final int near;
  final int far;
  final double angle;

  /// [near]'s half-planes before the fold: the fold runs where they all hold.
  final List<HalfPlane> extent;

  /// Parameters along [a]→[b] where the cut meets the fold line.
  final List<double> crossings;

  Offset at(double t) => a + (b - a) * t;

  /// The far side's turn at [scale] of the full fold.
  Matrix4 turn(double scale) {
    final d = b - a;
    final length = d.distance;
    if (length < 1e-12) return Matrix4.identity();
    final axis = Vector3(d.dx / length, d.dy / length, 0);
    final pivot = Vector3(a.dx, a.dy, 0);
    return Matrix4.translation(pivot)
      ..rotate(axis, angle * scale)
      ..translateByVector3(-pivot);
  }

  WrapFold withExtent(HalfPlane side) => WrapFold(
    a: a,
    b: b,
    near: near,
    far: far,
    angle: angle,
    extent: [...extent, side],
    crossings: crossings,
  );

  WrapFold withCrossings(Iterable<double> more) {
    final next = [...crossings];
    for (final t in more) {
      if (next.every((known) => (known - t).abs() > 1e-7)) next.add(t);
    }
    next.sort();
    return WrapFold(
      a: a,
      b: b,
      near: near,
      far: far,
      angle: angle,
      extent: extent,
      crossings: next,
    );
  }
}

/// A fold the blade set off during a stroke, at [at] along the stroke.
class WrapFoldEvent {
  const WrapFoldEvent({required this.fold, required this.at});

  final int fold;
  final double at;
}

/// Where along a model edge [WrapCut.foldEdges] looks for paper to fold.
const List<double> _kEdgeProbes = [
  0.5,
  0.25,
  0.75,
  0.125,
  0.375,
  0.625,
  0.875,
  0.02,
  0.98,
];

/// Edge [edge] of flap [flap]'s face, [a]→[b] in paper coordinates, that
/// the paper can fold over. [at] is on the paper there, and [outward] points
/// off the face.
class WrapEdge {
  const WrapEdge({
    required this.flap,
    required this.edge,
    required this.a,
    required this.b,
    required this.at,
    required this.outward,
  });

  final int flap;
  final int edge;
  final Offset a;
  final Offset b;
  final Offset at;
  final Offset outward;
}

/// The level coordinates a placement lays the piece's coordinates into.
Matrix4 placementMatrix(PiecePlacement placement) {
  const cosines = [1.0, 0.0, -1.0, 0.0];
  const sines = [0.0, 1.0, 0.0, -1.0];
  final turns = placement.quarterTurns % 4;
  final c = cosines[turns];
  final s = sines[turns];
  return Matrix4(
    c,
    s,
    0,
    0, //
    -s,
    c,
    0,
    0, //
    0,
    0,
    1,
    0, //
    placement.offset.dx,
    placement.offset.dy,
    0,
    1,
  );
}

// ---------------------------------------------------------------------------
// The cut session
// ---------------------------------------------------------------------------

/// One stroke of a [WrapCut]: from [from] to [to] in paper coordinates, with
/// the folds it set off.
class WrapStroke {
  const WrapStroke({
    required this.cut,
    required this.from,
    required this.to,
    required this.legs,
    this.folds = const [],
  });

  final WrapCut cut;
  final Offset from;
  final Offset to;
  final List<WrapFoldEvent> folds;

  /// The flaps of [cut] the blade runs on, each from its fraction of the way
  /// along. Never empty.
  final List<(double, int)> legs;

  /// The flap the blade is on [t] of the way along.
  int flapAt(double t) {
    var flap = legs.first.$2;
    for (final (from, on) in legs) {
      if (from > t + 1e-9) break;
      flap = on;
    }
    return flap;
  }
}

/// A cut through pattern paper laid on a model face. Strokes run in the
/// piece's own coordinates. Whenever the blade leaves its flap's face across
/// a model edge, the paper past that edge's line folds onto the next face.
class WrapCut {
  const WrapCut._({
    required this.model,
    required this.adjacency,
    required this.piece,
    required this.placement,
    required this.lines,
    required this.flaps,
    required this.folds,
    required this.path,
    required this.idSeed,
    required this.autoFold,
    this.direction,
    this.bladeOn,
    this.previous,
    this.result,
  });

  /// [piece] laid by [placement] on its face, before any stroke.
  factory WrapCut.start({
    required FoldedModel model,
    required PapercutPiece piece,
    required PiecePlacement placement,
    required List<(Offset, Offset)> lines,
    List<List<FaceNeighbor?>>? adjacency,
    int idSeed = 1,
    bool autoFold = false,
  }) {
    final anchor = model.faces[placement.face].toWorld.multiplied(
      placementMatrix(placement),
    );
    return WrapCut._(
      model: model,
      adjacency: adjacency ?? faceAdjacency(model),
      piece: piece,
      placement: placement,
      lines: lines,
      flaps: [
        WrapFlap(
          face: placement.face,
          sides: const [],
          facePaper: _facePaper(model, placement.face, anchor),
        ),
      ],
      folds: const [],
      path: const [],
      idSeed: idSeed,
      autoFold: autoFold,
    );
  }

  final FoldedModel model;
  final List<List<FaceNeighbor?>> adjacency;
  final PapercutPiece piece;
  final PiecePlacement placement;
  final List<(Offset, Offset)> lines;
  final List<WrapFlap> flaps;
  final List<WrapFold> folds;
  final List<Offset> path;
  final int idSeed;

  /// A stroke folds the paper wherever the blade leaves its face. Otherwise
  /// the paper folds only by [foldedAlong].
  final bool autoFold;

  /// The last stroke's direction.
  final Offset? direction;

  /// The flap the last stroke left the blade on. Null before any stroke.
  final int? bladeOn;

  /// This cut one stroke earlier.
  final WrapCut? previous;

  /// The paper once the path has split it. Null while the cut goes on.
  final PapercutSheet? result;

  bool get finished => result != null;

  Offset? get blade => path.isEmpty ? null : path.last;

  /// Paper coordinates to the world on the anchor face.
  Matrix4 get anchor => model.faces[placement.face].toWorld.multiplied(
    placementMatrix(placement),
  );

  /// +1 when paper +z points out of the model, else −1.
  double get outwardSide {
    final up = anchor.getRotation().transformed(Vector3(0, 0, 1));
    return up.dot(model.outwardNormal(placement.face)) >= 0 ? 1 : -1;
  }

  /// [flap]'s paper to the world, each fold turned by [scale] of the way.
  Matrix4 flapToWorld(int flap, {double Function(int fold)? scale}) =>
      _flapMatrix(anchor, flaps, folds, flap, scale);

  /// Unit normal of [flap] pointing out of the model.
  Vector3 flapNormal(int flap, {double Function(int fold)? scale}) =>
      flapToWorld(
        flap,
        scale: scale,
      ).getRotation().transformed(Vector3(0, 0, outwardSide)).normalized();

  /// The convex part of the plane [flap] covers, around the piece.
  List<Offset> flapWindow(int flap) {
    final box = pointBounds(piece.vertices).inflate(1);
    return clipByHalfPlanes([
      box.topLeft,
      box.topRight,
      box.bottomRight,
      box.bottomLeft,
    ], flaps[flap].sides);
  }

  /// Flaps holding the paper just past [point] toward [toward]. A point on
  /// a fold line, heading along it, is on both sides.
  List<int> flapsAt(Offset point, [Offset? toward]) {
    final probe = toward == null || toward.distance < 1e-12
        ? point
        : point + toward / toward.distance * _probe;
    return [
      for (var i = 0; i < flaps.length; i++)
        if (flaps[i].holds(probe)) i,
    ];
  }

  /// The flap the blade is shown on: the first holding the paper past it
  /// toward [toward] on its face, else the first holding [point] itself on
  /// its face. A blade resting on a torn fold line stays on the paper it
  /// came along, not the paper across the tear.
  int bladeFlap(Offset point, [Offset? toward]) {
    final holders = flapsAt(point, toward);
    for (final i in holders) {
      if (ownsPoint(flaps[i].facePaper, point)) return i;
    }
    for (var i = 0; i < flaps.length; i++) {
      if (flaps[i].holds(point) && ownsPoint(flaps[i].facePaper, point)) {
        return i;
      }
    }
    return holders.isEmpty ? 0 : holders.first;
  }

  /// The blade set down at [point], before any stroke.
  WrapCut placedAt(Offset point) => _copy(path: [point], clearDirection: true);

  /// Straight strokes from the blade along the pattern and the path so far,
  /// each ending at a vertex of those edges. The paper's own edge is not a
  /// way to go: a slide along it reaches the far side of the sheet. Along
  /// the path the blade travels, cutting nothing; see [travels]. A stroke
  /// stops at a tear it would cross onto paper lying elsewhere on the model.
  List<ForwardCut> options() {
    final at = blade;
    if (at == null || finished) return const [];
    final closed = [piece.vertices, ...piece.holes];
    final open = [
      for (final (a, b) in lines) [a, b],
      if (path.length > 1) path,
    ];
    final directions = lineworkDirections(at: at, open: open);
    final cuts = <ForwardCut>[];
    for (final ray in directions) {
      var end = nextOutlineHit(
        from: at,
        direction: ray,
        closed: closed,
        open: open,
      );
      if (end == null) continue;
      if (_tearAlong(at, end) case final tear?) {
        end = Offset.lerp(at, end, tear)!;
      }
      if ((end - at).distance < 1e-6) continue;
      if (!_onPaper(Offset.lerp(at, end, 0.5)!)) continue;
      if (!_lineVertex(end, open)) continue;
      cuts.add(ForwardCut(direction: ray, end: end));
    }
    return cuts;
  }

  /// The flap the blade ends on after [cut], one of [options], with the
  /// paper as it lies now.
  int flapAfter(ForwardCut cut) =>
      _walk(blade!, cut.end, flaps, folds).legs.last.$2;

  /// True when [point] is a vertex of one of [strokes].
  bool _lineVertex(Offset point, List<List<Offset>> strokes) {
    for (final stroke in strokes) {
      for (final vertex in stroke) {
        if ((vertex - point).distance < 1e-4) return true;
      }
    }
    return false;
  }

  /// True when the path's [segment] only carries the blade along the paper
  /// edge or the path before it.
  bool travels(int segment) => _travels(path, segment);

  /// True when [cut] would only carry the blade, as [travels].
  bool travelsAlong(ForwardCut cut) =>
      _travels([...path, cut.end], path.length - 1);

  bool _travels(List<Offset> path, int segment) {
    final from = path[segment];
    final to = path[segment + 1];
    if (cutRidesBoundary(from, to, [piece.vertices, ...piece.holes])) {
      return true;
    }
    for (var i = 0; i < segment; i++) {
      if (_rides(from, to, path[i], path[i + 1])) return true;
    }
    return false;
  }

  /// The runs of [path] that cut, between the stretches the blade travels.
  List<List<Offset>> _cutRuns(List<Offset> path) {
    final runs = <List<Offset>>[];
    var run = <Offset>[];
    for (var i = 0; i < path.length - 1; i++) {
      if (_travels(path, i)) {
        if (run.length > 1) runs.add(run);
        run = [];
        continue;
      }
      if (run.isEmpty) run.add(path[i]);
      run.add(path[i + 1]);
    }
    if (run.length > 1) runs.add(run);
    return runs;
  }

  /// Cuts along [cut]. With [autoFold], folds the paper wherever the blade
  /// leaves its face.
  WrapStroke stroke(ForwardCut cut) {
    final from = blade!;
    final to = cut.end;
    final nextFlaps = [...flaps];
    final nextFolds = [...folds];
    final events = <WrapFoldEvent>[];
    if (autoFold) _foldAlong(from, to, nextFlaps, nextFolds, events);
    final legs = _walk(from, to, nextFlaps, nextFolds).legs;
    final nextPath = [...path, to];
    final cuts = [
      for (var i = 0; i < nextPath.length - 1; i++) !_travels(nextPath, i),
    ];
    for (var k = 0; k < nextFolds.length; k++) {
      final fold = nextFolds[k];
      final hits = <double>[
        if (cuts.last) ..._lineCrossings(fold, from, to),
        if (k >= folds.length)
          for (var i = 0; i < path.length - 1; i++)
            if (cuts[i]) ..._lineCrossings(fold, path[i], path[i + 1]),
      ];
      if (hits.isNotEmpty) nextFolds[k] = fold.withCrossings(hits);
    }
    final runs = _cutRuns(nextPath);
    final sheet = runs.isEmpty
        ? null
        : applyPapercutCuts(
            PapercutSheet(pieces: [piece], nextPieceId: idSeed),
            runs,
            recordStroke: false,
          );
    final split =
        sheet != null &&
        (sheet.pieces.length > 1 || _holeCount(sheet) > piece.holes.length);
    return WrapStroke(
      cut: _copy(
        flaps: nextFlaps,
        folds: nextFolds,
        path: nextPath,
        direction: cut.direction,
        bladeOn: legs.last.$2,
        result: split ? sheet : null,
      ),
      from: from,
      to: to,
      legs: legs,
      folds: events,
    );
  }

  /// The fraction of [from]→[to] where the blade, folding the paper as it
  /// goes with [autoFold], would first cross a tear onto paper lying
  /// elsewhere on the model. Null when it never does.
  double? _tearAlong(Offset from, Offset to) {
    var reach = 1.0;
    for (var guard = 0; guard < 4; guard++) {
      final end = Offset.lerp(from, to, reach)!;
      final trialFlaps = [...flaps];
      final trialFolds = [...folds];
      if (autoFold) _foldAlong(from, end, trialFlaps, trialFolds, []);
      final tear = _walk(from, end, trialFlaps, trialFolds).tear;
      if (tear == null) return reach < 1 ? reach : null;
      reach *= tear;
      if (reach < 1e-9) return 0;
    }
    return reach;
  }

  /// The flaps the blade runs on along [from]→[to] over [flaps], from
  /// [bladeOn], and where it would first cross a tear onto paper lying
  /// elsewhere on the model. The blade keeps to its flap while that holds
  /// the paper ahead, and otherwise moves onto paper meeting it in the world.
  ({List<(double, int)> legs, double? tear}) _walk(
    Offset from,
    Offset to,
    List<WrapFlap> flaps,
    List<WrapFold> folds,
  ) {
    final delta = to - from;
    final breaks = <double>[0, 1];
    for (final flap in flaps) {
      for (final side in flap.sides) {
        final rate = _dot(delta, side.normal);
        if (rate.abs() < 1e-12) continue;
        final s = -side.side(from) / rate;
        if (s > 1e-9 && s < 1 - 1e-9) breaks.add(s);
      }
    }
    breaks.sort();
    Vector3 world(int flap, Offset point) => _flapMatrix(
      anchor,
      flaps,
      folds,
      flap,
      null,
    ).transformed3(Vector3(point.dx, point.dy, 0));
    final legs = <(double, int)>[];
    var on = bladeOn;
    for (var k = 0; k < breaks.length - 1; k++) {
      final s = breaks[k];
      if (breaks[k + 1] - s < 1e-9) continue;
      final middle = from + delta * ((s + breaks[k + 1]) / 2);
      final holders = [
        for (var i = 0; i < flaps.length; i++)
          if (flaps[i].holds(middle)) i,
      ];
      if (holders.isEmpty) continue;
      if (on != null && holders.contains(on)) {
        if (legs.isEmpty) legs.add((s, on));
        continue;
      }
      final ranked = [
        ...holders.where((i) => ownsPoint(flaps[i].facePaper, middle)),
        ...holders.where((i) => !ownsPoint(flaps[i].facePaper, middle)),
      ];
      int? next;
      if (on == null) {
        next = ranked.first;
      } else {
        final at = from + delta * s;
        final here = world(on, at);
        for (final i in ranked) {
          if ((world(i, at) - here).length < 1e-4) {
            next = i;
            break;
          }
        }
      }
      if (next == null) {
        return (legs: legs.isEmpty ? [(0.0, on!)] : legs, tear: s);
      }
      legs.add((s, next));
      on = next;
    }
    if (legs.isEmpty) legs.add((0, on ?? 0));
    return (legs: legs, tear: null);
  }

  /// The model edges the paper can fold over as it lies now: each edge of a
  /// flap's face with a neighbor across it, paper on the flap at the edge,
  /// and paper past it that is not folded there yet.
  List<WrapEdge> foldEdges() {
    if (finished) return const [];
    final edges = <WrapEdge>[];
    for (var f = 0; f < flaps.length; f++) {
      final flap = flaps[f];
      final ring = flap.facePaper;
      if (ring.length < 3) continue;
      final middle = polygonCentroid(ring);
      for (var e = 0; e < ring.length; e++) {
        if (adjacency[flap.face][e] == null) continue;
        final a = ring[e];
        final b = ring[(e + 1) % ring.length];
        final length = (b - a).distance;
        if (length < 1e-9) continue;
        var outward = Offset(b.dy - a.dy, a.dx - b.dx) / length;
        if (_dot(middle - a, outward) > 0) outward = -outward;
        for (final t in _kEdgeProbes) {
          final at = Offset.lerp(a, b, t)!;
          if (!flap.holds(at) || !_onPaper(at)) continue;
          if (!_fold(f, e, at, outward, [...flaps], [...folds])) continue;
          edges.add(
            WrapEdge(flap: f, edge: e, a: a, b: b, at: at, outward: outward),
          );
          break;
        }
      }
    }
    return edges;
  }

  /// The paper folded over [edge], one of [foldEdges], as a stroke crossing
  /// it would fold it with [autoFold]. Null when it no longer folds there.
  WrapCut? foldedAlong(WrapEdge edge) =>
      finished ? null : _foldedAlong(edge, piece);

  /// As [foldedAlong], folding only where [paper] lies past [edge].
  WrapCut? _foldedAlong(WrapEdge edge, PapercutPiece paper) {
    final nextFlaps = [...flaps];
    final nextFolds = [...folds];
    if (!_fold(
      edge.flap,
      edge.edge,
      edge.at,
      edge.outward,
      nextFlaps,
      nextFolds,
      paper: paper,
    )) {
      return null;
    }
    final k = nextFolds.length - 1;
    final hits = [
      for (var i = 0; i < path.length - 1; i++)
        if (!travels(i)) ..._lineCrossings(nextFolds[k], path[i], path[i + 1]),
    ];
    if (hits.isNotEmpty) nextFolds[k] = nextFolds[k].withCrossings(hits);
    final at = blade;
    var on = bladeOn;
    if (at != null && on != null && !nextFlaps[on].holds(at)) {
      final holders = [
        for (var i = 0; i < nextFlaps.length; i++)
          if (nextFlaps[i].holds(at)) i,
      ];
      if (holders.isNotEmpty) {
        on = holders.firstWhere(
          (i) => ownsPoint(nextFlaps[i].facePaper, at),
          orElse: () => holders.first,
        );
      }
    }
    return _copy(
      flaps: nextFlaps,
      folds: nextFolds,
      bladeOn: on,
      result: result,
    );
  }

  /// This cut with [kept] folded round the model: from the anchor's flap,
  /// breadth first, each flap folds over every edge of its face that [kept]
  /// crosses, as a stroke crossing it would fold it with [autoFold].
  WrapCut _foldedOut(PapercutPiece kept) {
    var cut = this;
    final order = [0];
    final seen = {0};
    for (var head = 0; head < order.length && head < 64; head++) {
      final f = order[head];
      for (var e = 0; e < cut.flaps[f].facePaper.length; e++) {
        final edge = cut._crossing(f, e, kept);
        if (edge == null) continue;
        cut = cut._foldedAlong(edge, kept) ?? cut;
      }
      for (var i = 0; i < cut.flaps.length; i++) {
        if (cut.flaps[i].parent == f && seen.add(i)) order.add(i);
      }
    }
    return cut;
  }

  /// Edge [edge] of [flap]'s face where [kept] runs across it on that
  /// flap, with a neighbor across it. Null when [kept] does not cross it.
  WrapEdge? _crossing(int flap, int edge, PapercutPiece kept) {
    final holder = flaps[flap];
    final ring = holder.facePaper;
    if (ring.length < 3 || adjacency[holder.face][edge] == null) return null;
    final a = ring[edge];
    final b = ring[(edge + 1) % ring.length];
    final line = b - a;
    final len2 = _dot(line, line);
    if (len2 < 1e-12) return null;
    var outward = Offset(line.dy, -line.dx) / math.sqrt(len2);
    if (_dot(polygonCentroid(ring) - a, outward) > 0) outward = -outward;
    final breaks = <double>[0, 1];
    for (final loop in [kept.vertices, ...kept.holes]) {
      for (var i = 0; i < loop.length; i++) {
        final hit = _segmentCrossing(
          (a, b),
          (loop[i], loop[(i + 1) % loop.length]),
        );
        if (hit != null) breaks.add(_dot(hit - a, line) / len2);
      }
    }
    breaks.sort();
    for (var i = 0; i < breaks.length - 1; i++) {
      if (breaks[i + 1] - breaks[i] < 1e-9) continue;
      final at = Offset.lerp(a, b, (breaks[i] + breaks[i + 1]) / 2)!;
      if (!holder.holds(at) || !_strictlyIn(at, kept)) continue;
      return WrapEdge(
        flap: flap,
        edge: edge,
        a: a,
        b: b,
        at: at,
        outward: outward,
      );
    }
    return null;
  }

  /// Splits the finished cut into what stays wrapped, what springs back, and
  /// scrap. See [WrapFinish]. Without [autoFold], each piece is first folded
  /// round the model by [_foldedOut], and the one covering the most face
  /// area is kept.
  WrapFinish finish(WrapProgress progress) {
    final pieces = result?.pieces ?? [piece];
    var kept = -1;
    var keptCover = 1e-6;
    var keptCut = this;
    var relief = [for (final _ in folds) const <(double, double)>[]];
    for (var i = 0; i < pieces.length; i++) {
      final out = autoFold ? this : _foldedOut(pieces[i]);
      final stretches = relieveFolds(out.folds, piece, pieces[i]);
      final keep = [for (final stretch in stretches) stretch.isNotEmpty];
      var cover = 0.0;
      for (var f = 0; f < out.flaps.length; f++) {
        final window = out._coverWindow(f, keep);
        if (window == null) continue;
        cover += _areaWithin(pieces[i], window.sides);
      }
      if (cover > keptCover) {
        keptCover = cover;
        kept = i;
        keptCut = out;
        relief = stretches;
      }
    }
    return keptCut._finishKeeping(
      progress,
      pieces,
      kept,
      relief,
      foldsBefore: folds.length,
    );
  }

  WrapFinish _finishKeeping(
    WrapProgress progress,
    List<PapercutPiece> pieces,
    int kept,
    List<List<(double, double)>> relief, {
    required int foldsBefore,
  }) {
    final patches = <PaperPatch>[];
    final overhang = <List<Offset>>[];
    if (kept >= 0) {
      final keptPiece = pieces[kept];
      final keep = [for (final stretch in relief) stretch.isNotEmpty];
      for (var f = 0; f < flaps.length; f++) {
        final window = _coverWindow(f, keep);
        if (window == null) {
          final ring = clipByHalfPlanes(keptPiece.vertices, flaps[f].sides);
          if (_ringArea(ring) > 1e-6) overhang.add(ring);
          continue;
        }
        final patch = _patch(keptPiece, window);
        if (patch != null) patches.add(patch);
        final faceSides = convexSides(window.facePaper);
        for (var e = 0; e < faceSides.length; e++) {
          final slab = clipByHalfPlanes(keptPiece.vertices, [
            ...flaps[f].sides,
            ...faceSides.take(e),
            faceSides[e].flipped,
          ]);
          if (_ringArea(slab) > 1e-6) overhang.add(slab);
        }
      }
    }

    final others = [
      for (var i = 0; i < pieces.length; i++)
        if (i != kept) pieces[i],
    ]..sort((a, b) => _pieceArea(b).compareTo(_pieceArea(a)));
    final leftover = others.isEmpty ? null : others.first;
    var nextId = (result?.nextPieceId ?? idSeed) + 1;
    final scraps = <PapercutPiece>[
      ...others.skip(1),
      for (final ring in _scrapRings(overhang))
        PapercutPiece(
          id: '${piece.id}-scrap-${nextId++}',
          color: piece.color,
          backColor: piece.backColor,
          vertices: ring.$1,
          holes: ring.$2,
        ),
    ];
    final next = progress.adding(model, patches);
    return WrapFinish(
      cut: this,
      kept: kept < 0 ? null : pieces[kept],
      leftover: leftover,
      scraps: scraps,
      patches: patches,
      relief: relief,
      progress: next,
      points: next.pointsOver(model, progress),
      nextId: nextId,
      foldedOut: {for (var k = foldsBefore; k < folds.length; k++) k},
    );
  }

  /// [flap]'s face window where it sits once folds not in [keep] are let go:
  /// the flap's half-planes and that face's outline, in paper coordinates.
  ({int face, Matrix4 toWorld, List<Offset> facePaper, List<HalfPlane> sides})?
  _coverWindow(int flap, List<bool> keep) {
    var face = flaps[flap].face;
    var index = flap;
    final turns = <Matrix4>[];
    var settled = false;
    while (true) {
      final current = flaps[index];
      final fold = current.fold;
      final parent = current.parent;
      if (fold == null || parent == null) break;
      if (keep[fold]) {
        if (!settled) face = current.face;
        settled = true;
        turns.add(folds[fold].turn(1));
      } else if (!settled) {
        face = flaps[parent].face;
      }
      index = parent;
    }
    var toWorld = anchor;
    for (final turn in turns.reversed) {
      toWorld = toWorld.multiplied(turn);
    }
    final facePaper = _facePaperOrNull(model, face, toWorld);
    if (facePaper == null) return null;
    return (
      face: face,
      toWorld: toWorld,
      facePaper: facePaper,
      sides: [...flaps[flap].sides, ...convexSides(facePaper)],
    );
  }

  PaperPatch? _patch(
    PapercutPiece kept,
    ({int face, Matrix4 toWorld, List<Offset> facePaper, List<HalfPlane> sides})
    window,
  ) {
    final ring = clipByHalfPlanes(kept.vertices, window.sides);
    if (_ringArea(ring) < 1e-6) return null;
    final toFace = Matrix4.inverted(
      model.faces[window.face].toWorld,
    ).multiplied(window.toWorld);
    Offset map(Offset point) {
      final at = toFace.transformed3(Vector3(point.dx, point.dy, 0));
      return Offset(at.x, at.y);
    }

    final holes = [
      for (final hole in kept.holes)
        if (clipByHalfPlanes(hole, window.sides) case final clipped
            when _ringArea(clipped) > 1e-6)
          [for (final point in clipped) map(point)],
    ];
    final box = pointBounds(ring);
    return PaperPatch(
      face: window.face,
      ring: [for (final point in ring) map(point)],
      holes: holes,
      lines: [
        for (final (a, b) in lines)
          if (_touchesRect(a, b, box)) (map(a), map(b)),
      ],
      color: kept.color,
    );
  }

  bool _onPaper(Offset point) => _onPiece(piece, point);

  /// Walks [from]→[to], folding each flap the blade leaves through a model
  /// edge. Flaps on both sides of a fold line the blade rides fold together.
  void _foldAlong(
    Offset from,
    Offset to,
    List<WrapFlap> flaps,
    List<WrapFold> folds,
    List<WrapFoldEvent> events,
  ) {
    final delta = to - from;
    final length = delta.distance;
    if (length < 1e-9) return;
    final unit = delta / length;
    var s0 = 0.0;
    final spent = <int>{};
    for (var guard = 0; guard < 24; guard++) {
      final at = from + delta * s0;
      final probe = at + unit * _probe;
      final behind = at - unit * _probe;
      final exits = <(int, double, List<int>)>[];
      var first = double.infinity;
      for (var i = 0; i < flaps.length; i++) {
        if (spent.contains(i)) continue;
        // A blade on the edge of the flap it came along may leave it right
        // here, across a tear.
        final came = s0 < 1e-9 ? i == bladeOn : flaps[i].holds(behind);
        if (!flaps[i].holds(probe) && !(came && flaps[i].holds(at))) continue;
        final exit = _exit(flaps[i].facePaper, from, to, s0);
        if (exit == null) continue;
        exits.add((i, exit.$1, exit.$2));
        first = math.min(first, exit.$1);
      }
      if (exits.isEmpty) return;
      var folded = false;
      for (final (flap, s, edges) in exits) {
        if (s > first + 1e-7) continue;
        for (final edge in edges) {
          if (_fold(flap, edge, from + delta * s, unit, flaps, folds)) {
            events.add(WrapFoldEvent(fold: folds.length - 1, at: s));
            folded = true;
            break;
          }
        }
        if (!folded) spent.add(flap);
      }
      if (first > s0 + 1e-9) {
        s0 = first;
        if (folded) spent.clear();
      }
    }
  }

  /// Splits [flaps][flap] along its face's [edge] when the paper past it can
  /// fold onto the neighboring face. False when the edge has no neighbor,
  /// is already folded at [at], or has no [paper], the whole piece unless
  /// given, past it.
  ///
  /// A fold line runs on past its own model edge, splitting the paper there
  /// as a tear. Where the blade reaches this edge along such a tear, past a
  /// model vertex, the paper beyond folds onto the neighbor with this flap,
  /// and leaves the flaps across the tear, unless one of them already lays
  /// it on the model. See [_tear].
  bool _fold(
    int flap,
    int edge,
    Offset at,
    Offset unit,
    List<WrapFlap> flaps,
    List<WrapFold> folds, {
    PapercutPiece? paper,
  }) {
    final current = flaps[flap];
    final neighbor = adjacency[current.face][edge];
    if (neighbor == null) return false;
    final ring = current.facePaper;
    final a = ring[edge];
    final b = ring[(edge + 1) % ring.length];
    final torn = [
      for (final side in current.sides)
        if (side.onLine(a, b)) side,
    ];
    final along = [
      for (final fold in folds)
        if (_collinear(fold, a, b)) fold,
    ];
    if (torn.isNotEmpty && along.any((fold) => _foldsAt(fold, at))) {
      return false;
    }
    final kept = [
      for (final side in current.sides)
        if (!torn.contains(side)) side,
    ];
    final beyond = at + unit * _probe;
    if (!kept.every((side) => side.holds(beyond)) ||
        !_onPiece(paper ?? piece, beyond)) {
      return false;
    }
    if (torn.isNotEmpty) {
      for (var f = 0; f < flaps.length; f++) {
        if (f != flap &&
            flaps[f].holds(beyond) &&
            ownsPoint(flaps[f].facePaper, beyond)) {
          return false;
        }
      }
    }
    final line = convexSides([a, b, b + Offset(-(b - a).dy, (b - a).dx)]).first;

    final near = _flapMatrix(anchor, flaps, folds, flap, null);
    final aw = near.transformed3(Vector3(a.dx, a.dy, 0));
    final bw = near.transformed3(Vector3(b.dx, b.dy, 0));
    final axis = (bw - aw).normalized();
    final from = model.outwardNormal(current.face);
    final onto = model.outwardNormal(neighbor.face);
    var angle = math.atan2(axis.dot(from.cross(onto)), from.dot(onto));
    if (near.getRotation().determinant() < 0) angle = -angle;

    final index = folds.length;
    final fold = WrapFold(
      a: a,
      b: b,
      near: flap,
      far: flaps.length,
      angle: angle,
      extent: kept,
    );
    final farMatrix = near.multiplied(fold.turn(1));
    final farPaper = _facePaper(model, neighbor.face, farMatrix);
    final farSides = [
      for (final side in kept) ?_ownSide(side, a, b, farPaper),
      line.flipped,
    ];
    if (torn.isNotEmpty) _tear(flaps, folds, flap, farSides, kept, along, at);
    folds.add(fold);
    if (torn.isEmpty) flaps[flap] = current.withSide(line);
    flaps.add(
      WrapFlap(
        face: neighbor.face,
        sides: farSides,
        facePaper: farPaper,
        parent: flap,
        fold: index,
      ),
    );
    return true;
  }

  /// [side], when it leaves all of [facePaper] to the far flap. A side that
  /// would clip the face gives way to the face's own edge from hinge end [a]
  /// or [b] when it runs through that end, and is let go otherwise. Fold
  /// lines of other edges only follow the face's edges where corners are
  /// square.
  static HalfPlane? _ownSide(
    HalfPlane side,
    Offset a,
    Offset b,
    List<Offset> facePaper,
  ) {
    if (facePaper.every((point) => side.holds(point, 1e-6))) return side;
    for (final end in [a, b]) {
      if (side.side(end).abs() > 1e-6) continue;
      for (final own in convexSides(facePaper)) {
        if (own.side(end).abs() < 1e-6 && !own.onLine(a, b)) return own;
      }
    }
    return null;
  }

  /// Moves a tear so the paper in [region], folding off [flap] across the
  /// torn line, leaves every other flap. Each flap holding some of it is cut
  /// back along a side of [region] through the model vertex the tear runs
  /// from, keeping what it can, and so is every fold it is the near side of.
  void _tear(
    List<WrapFlap> flaps,
    List<WrapFold> folds,
    int flap,
    List<HalfPlane> region,
    List<HalfPlane> kept,
    List<WrapFold> along,
    Offset at,
  ) {
    Offset? vertex;
    for (final fold in along) {
      for (final end in [fold.a, fold.b]) {
        if (vertex == null || (end - at).distance < (vertex - at).distance) {
          vertex = end;
        }
      }
    }
    final through = [
      for (final side in kept)
        if (vertex != null && side.side(vertex).abs() < 1e-6) side,
    ];
    final cuts = through.isEmpty ? kept : through;
    if (cuts.isEmpty) return;
    final box = pointBounds(piece.vertices).inflate(1);
    final window = [box.topLeft, box.topRight, box.bottomRight, box.bottomLeft];
    for (var f = 0; f < flaps.length; f++) {
      if (f == flap) continue;
      final sides = flaps[f].sides;
      if (_ringArea(clipByHalfPlanes(window, [...sides, ...region])) < 1e-6) {
        continue;
      }
      HalfPlane? best;
      var bestArea = -1.0;
      for (final side in cuts) {
        final area = _ringArea(
          clipByHalfPlanes(window, [...sides, side.flipped]),
        );
        if (area > bestArea) {
          bestArea = area;
          best = side.flipped;
        }
      }
      if (best == null) continue;
      flaps[f] = flaps[f].withSide(best);
      for (var k = 0; k < folds.length; k++) {
        if (folds[k].near == f) folds[k] = folds[k].withExtent(best);
      }
    }
  }

  WrapCut _copy({
    List<WrapFlap>? flaps,
    List<WrapFold>? folds,
    List<Offset>? path,
    Offset? direction,
    int? bladeOn,
    bool clearDirection = false,
    PapercutSheet? result,
  }) {
    return WrapCut._(
      model: model,
      adjacency: adjacency,
      piece: piece,
      placement: placement,
      lines: lines,
      flaps: flaps ?? this.flaps,
      folds: folds ?? this.folds,
      path: path ?? this.path,
      idSeed: idSeed,
      autoFold: autoFold,
      direction: clearDirection ? null : (direction ?? this.direction),
      bladeOn: clearDirection ? null : (bladeOn ?? this.bladeOn),
      previous: this,
      result: result,
    );
  }
}

Matrix4 _flapMatrix(
  Matrix4 anchor,
  List<WrapFlap> flaps,
  List<WrapFold> folds,
  int flap,
  double Function(int fold)? scale,
) {
  final turns = <Matrix4>[];
  var index = flap;
  while (true) {
    final current = flaps[index];
    final fold = current.fold;
    final parent = current.parent;
    if (fold == null || parent == null) break;
    turns.add(folds[fold].turn(scale?.call(fold) ?? 1));
    index = parent;
  }
  var matrix = anchor;
  for (final turn in turns.reversed) {
    matrix = matrix.multiplied(turn);
  }
  return matrix;
}

/// [face]'s outline carried into the paper coordinates [toWorld] maps out of.
List<Offset> _facePaper(FoldedModel model, int face, Matrix4 toWorld) {
  final back = Matrix4.inverted(toWorld);
  return _counterClockwise([
    for (final point in model.faces[face].worldRing())
      () {
        final local = back.transformed3(point);
        return Offset(local.x, local.y);
      }(),
  ]);
}

/// As [_facePaper], or null when the face does not lie in the paper's plane.
List<Offset>? _facePaperOrNull(FoldedModel model, int face, Matrix4 toWorld) {
  final back = Matrix4.inverted(toWorld);
  final ring = <Offset>[];
  for (final point in model.faces[face].worldRing()) {
    final local = back.transformed3(point);
    if (local.z.abs() > 1e-3) return null;
    ring.add(Offset(local.x, local.y));
  }
  return _counterClockwise(ring);
}

/// True when [a]–[b] lies on [fold]'s line.
bool _collinear(WrapFold fold, Offset a, Offset b) {
  final line = fold.b - fold.a;
  final length = line.distance;
  if (length < 1e-12) return false;
  return (_cross(line, a - fold.a) / length).abs() < 1e-6 &&
      (_cross(line, b - fold.a) / length).abs() < 1e-6;
}

/// True when [at] lies on [fold]'s own model edge, not on the line past it.
bool _foldsAt(WrapFold fold, Offset at) {
  final line = fold.b - fold.a;
  final len2 = _dot(line, line);
  if (len2 < 1e-12) return false;
  final t = _dot(at - fold.a, line) / len2;
  return t >= -1e-6 && t <= 1 + 1e-6;
}

/// First parameter in [s0, 1) where [from]→[to] leaves the convex [ring],
/// with the edges it leaves through, the best match for the stroke's heading
/// first. Null when it stays inside, misses, or only grazes a corner.
(double, List<int>)? _exit(
  List<Offset> ring,
  Offset from,
  Offset to,
  double s0,
) {
  final delta = to - from;
  final length = delta.distance;
  if (length < 1e-12 || ring.length < 3) return null;
  var sIn = s0;
  var sOut = 1.0;
  var out = <int>[];
  final aligned = <int, double>{};
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final edge = ring[(i + 1) % ring.length] - a;
    final span = edge.distance;
    if (span < 1e-12) continue;
    final inward = Offset(-edge.dy, edge.dx) / span;
    final start = _dot(from - a, inward);
    final rate = _dot(delta, inward);
    if (rate.abs() < 1e-9 * length) {
      if (start + rate * s0 < -1e-6) return null;
      continue;
    }
    final s = -start / rate;
    if (rate < 0) {
      aligned[i] = -rate / length;
      if (s < sOut - 1e-7) {
        sOut = s;
        out = [i];
      } else if ((s - sOut).abs() <= 1e-7) {
        out.add(i);
      }
    } else {
      sIn = math.max(sIn, s);
    }
  }
  if (out.isEmpty || sOut < s0 - 1e-7 || sOut >= 1 - 1e-7) return null;
  if (sIn > sOut + 1e-7) return null;
  if (sOut - sIn < 1e-7 && sIn > s0 + 1e-7) return null;
  out.sort((x, y) => aligned[y]!.compareTo(aligned[x]!));
  return (math.max(sOut, s0), out);
}

/// Parameters along [fold]'s line where [from]–[to] meets it: one where it
/// crosses, both ends where it runs along the line. Cramer's rule, as in
/// Boost.Geometry's `cartesian_segments`.
List<double> _lineCrossings(WrapFold fold, Offset from, Offset to) {
  final line = fold.b - fold.a;
  final delta = to - from;
  final lineLength = line.distance;
  final length = delta.distance;
  if (lineLength < 1e-12 || length < 1e-12) return const [];
  final w = fold.a - from;
  final denom = _cross(delta, line);
  if (denom.abs() > 1e-12 * lineLength * length) {
    final s = _cross(w, line) / denom;
    if (s < -1e-9 || s > 1 + 1e-9) return const [];
    return [_cross(w, delta) / denom];
  }
  if (_cross(w, delta).abs() / length > 1e-7) return const [];
  final len2 = lineLength * lineLength;
  return [_dot(from - fold.a, line) / len2, _dot(to - fold.a, line) / len2];
}

// ---------------------------------------------------------------------------
// Fold relief
// ---------------------------------------------------------------------------

/// The stretches of each fold that stay folded once the cut is done, as
/// parameter intervals along [WrapFold.a]→[WrapFold.b].
///
/// The cut's crossings and the paper's edges break each fold line into
/// stretches. A stretch between two of them that runs inside [kept] keeps
/// its fold, so a strip or peninsula curls around the model. Every other
/// stretch is discarded, and the paper there springs back flat.
List<List<(double, double)>> relieveFolds(
  List<WrapFold> folds,
  PapercutPiece sheet,
  PapercutPiece? kept,
) {
  final rings = [sheet.vertices, ...sheet.holes];
  final box = pointBounds(sheet.vertices);
  return [
    for (final fold in folds)
      () {
        final line = fold.b - fold.a;
        final len2 = _dot(line, line);
        if (len2 < 1e-12 || kept == null) return const <(double, double)>[];
        var lo = double.infinity;
        var hi = -double.infinity;
        for (final corner in [
          box.topLeft,
          box.topRight,
          box.bottomLeft,
          box.bottomRight,
        ]) {
          final t = _dot(corner - fold.a, line) / len2;
          lo = math.min(lo, t);
          hi = math.max(hi, t);
        }
        for (final side in fold.extent) {
          final start = side.side(fold.a);
          final rate = _dot(line, side.normal);
          if (rate.abs() < 1e-12) {
            if (start < -1e-6) return const <(double, double)>[];
            continue;
          }
          final t = -start / rate;
          if (rate > 0) {
            lo = math.max(lo, t);
          } else {
            hi = math.min(hi, t);
          }
        }
        if (hi - lo < 1e-9) return const <(double, double)>[];
        final breaks = <double>[lo, hi];
        for (final ring in rings) {
          for (var i = 0; i < ring.length; i++) {
            final probe = WrapFold(
              a: fold.a,
              b: fold.b,
              near: 0,
              far: 0,
              angle: 0,
              extent: const [],
            );
            for (final t in _lineCrossings(
              probe,
              ring[i],
              ring[(i + 1) % ring.length],
            )) {
              if (t > lo && t < hi) breaks.add(t);
            }
          }
        }
        for (final t in fold.crossings) {
          if (t > lo && t < hi) breaks.add(t);
        }
        breaks.sort();
        final stretches = <(double, double)>[];
        for (var i = 0; i < breaks.length - 1; i++) {
          final t0 = breaks[i];
          final t1 = breaks[i + 1];
          if (t1 - t0 < 1e-9) continue;
          final middle = fold.at((t0 + t1) / 2);
          if (!_strictlyIn(middle, kept)) continue;
          if (stretches.isNotEmpty && (stretches.last.$2 - t0).abs() < 1e-9) {
            stretches.last = (stretches.last.$1, t1);
          } else {
            stretches.add((t0, t1));
          }
        }
        return stretches;
      }(),
  ];
}

bool _strictlyIn(Offset point, PapercutPiece piece) {
  if (!isInsidePolygon(point, piece.vertices)) return false;
  if (_ringDistance(point, piece.vertices) < 1e-6) return false;
  for (final hole in piece.holes) {
    if (hole.length < 3) continue;
    if (isInsidePolygon(point, hole)) return false;
    if (_ringDistance(point, hole) < 1e-6) return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Alignment
// ---------------------------------------------------------------------------

/// [flap]'s face as a pattern cell, in paper coordinates: its outline when
/// every edge of the face runs along the pattern or the paper's edge and the
/// paper covers the face. Null otherwise.
List<Offset>? alignedCell(WrapCut cut, int flap) {
  final holder = cut.flaps[flap];
  final ring = holder.facePaper;
  if (ring.length < 3) return null;
  final piece = cut.piece;
  final guides = [
    ...cut.lines,
    for (final edges in [piece.vertices, ...piece.holes])
      for (var i = 0; i < edges.length; i++)
        (edges[i], edges[(i + 1) % edges.length]),
  ];
  for (var i = 0; i < ring.length; i++) {
    if (!_alongGuides(ring[i], ring[(i + 1) % ring.length], guides)) {
      return null;
    }
  }
  final middle = polygonCentroid(ring);
  final probes = [
    middle,
    for (var i = 0; i < ring.length; i++) ...[
      ring[i],
      Offset.lerp(ring[i], ring[(i + 1) % ring.length], 0.5)!,
    ],
  ];
  for (final point in probes) {
    final inset = point + (middle - point) * 1e-3;
    if (!holder.holds(inset) || !_strictlyIn(inset, piece)) return null;
  }
  return ring;
}

/// Where a cut can start on [flap]'s face: each vertex of the face that
/// lies on the paper, in paper coordinates.
List<Offset> faceEdgeStarts(WrapCut cut, [int flap = 0]) {
  final holder = cut.flaps[flap];
  final starts = <Offset>[];
  for (final point in holder.facePaper) {
    if (!holder.holds(point) || !_onPiece(cut.piece, point)) continue;
    if (starts.any((known) => (known - point).distance < 1e-6)) continue;
    starts.add(point);
  }
  return starts;
}

/// [p]→[q] is covered end to end by [guides] lying along it.
bool _alongGuides(Offset p, Offset q, List<(Offset, Offset)> guides) {
  final length = (q - p).distance;
  if (length < 1e-9) return true;
  final unit = (q - p) / length;
  final spans = <(double, double)>[];
  for (final (a, b) in guides) {
    if (_cross(a - p, unit).abs() > 1e-4) continue;
    if (_cross(b - p, unit).abs() > 1e-4) continue;
    final s = _dot(a - p, unit) / length;
    final t = _dot(b - p, unit) / length;
    final lo = math.min(s, t);
    final hi = math.max(s, t);
    if (hi < -1e-6 || lo > 1 + 1e-6) continue;
    spans.add((lo, hi));
  }
  spans.sort((x, y) => x.$1.compareTo(y.$1));
  var reach = 0.0;
  for (final (lo, hi) in spans) {
    if (lo > reach + 1e-6) return false;
    reach = math.max(reach, hi);
    if (reach >= 1 - 1e-6) return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Coverage
// ---------------------------------------------------------------------------

/// Wrapped pattern paper on one model face, in that face's level
/// coordinates. [lines] are the pattern lines it carries, before clipping.
class PaperPatch {
  const PaperPatch({
    required this.face,
    required this.ring,
    this.holes = const [],
    this.lines = const [],
    required this.color,
  });

  final int face;
  final List<Offset> ring;
  final List<List<Offset>> holes;
  final List<(Offset, Offset)> lines;
  final Color color;
}

/// Patches wrapped so far and how much of each face they cover.
class WrapProgress {
  const WrapProgress({this.patches = const [], this.covered = const {}});

  final List<PaperPatch> patches;

  /// Face index to covered area.
  final Map<int, double> covered;

  /// Fraction of [face] covered, 0–1.
  double fraction(FoldedModel model, int face) {
    final area = _ringArea(model.faces[face].outline);
    if (area < 1e-9) return 1;
    return ((covered[face] ?? 0) / area).clamp(0.0, 1.0);
  }

  /// Every face covered.
  bool complete(FoldedModel model) {
    for (var i = 0; i < model.faces.length; i++) {
      if (fraction(model, i) < 1 - 1e-3) return false;
    }
    return true;
  }

  WrapProgress adding(FoldedModel model, List<PaperPatch> more) {
    if (more.isEmpty) return this;
    final patches = [...this.patches, ...more];
    final covered = Map<int, double>.of(this.covered);
    for (final face in {for (final patch in more) patch.face}) {
      final rings = [
        for (final patch in patches)
          if (patch.face == face) _counterClockwise(patch.ring),
      ];
      final union = unionPolygons(rings);
      var area = 0.0;
      for (final loop in union) {
        area += polygonSignedArea(loop);
      }
      covered[face] = math.min(
        area.abs(),
        _ringArea(model.faces[face].outline),
      );
    }
    return WrapProgress(patches: patches, covered: covered);
  }

  /// 100 per face of new coverage over [before], rounded.
  int pointsOver(FoldedModel model, WrapProgress before) {
    var total = 0.0;
    for (var i = 0; i < model.faces.length; i++) {
      total += fraction(model, i) - before.fraction(model, i);
    }
    return (total * 100).round();
  }
}

/// 0–1: how far the [index]th of folds swinging one after another has
/// swung, [elapsed] into the run. Each takes [each] and starts [overlap]
/// (0–1) of [each] before the one before it ends.
double staggeredSwing(
  int index,
  Duration elapsed,
  Duration each,
  double overlap,
) {
  final step = each.inMicroseconds * (1 - overlap.clamp(0.0, 1.0));
  final t = (elapsed.inMicroseconds - index * step) / each.inMicroseconds;
  return t.clamp(0.0, 1.0);
}

/// How long [count] folds take to swing by [staggeredSwing].
Duration staggeredLength(int count, Duration each, double overlap) {
  if (count <= 0) return Duration.zero;
  final step = each.inMicroseconds * (1 - overlap.clamp(0.0, 1.0));
  return each + Duration(microseconds: ((count - 1) * step).round());
}

/// A finished [cut]: the [kept] piece wrapped as [patches], the [leftover]
/// sheet that springs back flat into the hand, and [scraps] for the
/// inventory, overhang included. [relief] holds the fold stretches that
/// stayed folded in [kept]; every other fold springs back.
class WrapFinish {
  const WrapFinish({
    required this.cut,
    required this.kept,
    required this.leftover,
    required this.scraps,
    required this.patches,
    required this.relief,
    required this.progress,
    required this.points,
    required this.nextId,
    this.foldedOut = const {},
  });

  /// The cut as finished, with [foldedOut] folds made as it finished.
  final WrapCut cut;
  final PapercutPiece? kept;
  final PapercutPiece? leftover;
  final List<PapercutPiece> scraps;
  final List<PaperPatch> patches;
  final List<List<(double, double)>> relief;
  final WrapProgress progress;
  final int points;

  /// First piece id the caller can still hand out.
  final int nextId;

  /// Folds of [cut] made as it finished, folding [kept] round the model.
  final Set<int> foldedOut;

  /// Folds that stay folded in [kept].
  Set<int> get keptFolds => {
    for (var k = 0; k < relief.length; k++)
      if (relief[k].isNotEmpty) k,
  };
}

/// Overhang slabs merged into outlines, each with the holes inside it.
List<(List<Offset>, List<List<Offset>>)> _scrapRings(List<List<Offset>> slabs) {
  if (slabs.isEmpty) return const [];
  final loops = [
    for (final loop in unionPolygons([
      for (final slab in slabs) _counterClockwise(slab),
    ]))
      if (_ringArea(loop) > 1e-3) loop,
  ];
  if (loops.isEmpty) return const [];
  final largest = loops.reduce((a, b) => _ringArea(a) >= _ringArea(b) ? a : b);
  final outerSign = polygonSignedArea(largest).sign;
  final outer = [
    for (final loop in loops)
      if (polygonSignedArea(loop).sign == outerSign) _counterClockwise(loop),
  ];
  final holes = [
    for (final loop in loops)
      if (polygonSignedArea(loop).sign != outerSign) loop,
  ];
  return [
    for (final ring in outer)
      (
        ring,
        [
          for (final hole in holes)
            if (isInsidePolygon(polygonCentroid(hole), ring)) hole,
        ],
      ),
  ];
}

double _pieceArea(PapercutPiece piece) {
  var area = _ringArea(piece.vertices);
  for (final hole in piece.holes) {
    area -= _ringArea(hole);
  }
  return area;
}

int _holeCount(PapercutSheet sheet) {
  var count = 0;
  for (final piece in sheet.pieces) {
    count += piece.holes.length;
  }
  return count;
}

bool _touchesRect(Offset a, Offset b, Rect box) {
  final inflated = box.inflate(1e-6);
  if (inflated.contains(a) || inflated.contains(b)) return true;
  final lineBox = Rect.fromPoints(a, b);
  return lineBox.left <= inflated.right &&
      inflated.left <= lineBox.right &&
      lineBox.top <= inflated.bottom &&
      inflated.top <= lineBox.bottom;
}

Offset? _segmentCrossing((Offset, Offset) p, (Offset, Offset) q) {
  final d1 = p.$2 - p.$1;
  final d2 = q.$2 - q.$1;
  final denom = _cross(d1, d2);
  if (denom.abs() < 1e-12) return null;
  final w = q.$1 - p.$1;
  final s = _cross(w, d2) / denom;
  final t = _cross(w, d1) / denom;
  if (s < -1e-9 || s > 1 + 1e-9 || t < -1e-9 || t > 1 + 1e-9) return null;
  return p.$1 + d1 * s;
}

Offset _closestOnSegment(Offset point, Offset a, Offset b) {
  final ab = b - a;
  final len2 = _dot(ab, ab);
  if (len2 < 1e-18) return a;
  final t = (_dot(point - a, ab) / len2).clamp(0.0, 1.0);
  return a + ab * t;
}

double _segmentDistance(Offset point, Offset a, Offset b) =>
    (_closestOnSegment(point, a, b) - point).distance;

/// On [piece] or its edge, holes' edges included.
bool _onPiece(PapercutPiece piece, Offset point) {
  final onEdge = _ringDistance(point, piece.vertices) < 1e-6;
  if (!onEdge && !isInsidePolygon(point, piece.vertices)) return false;
  for (final hole in piece.holes) {
    if (hole.length < 3 || _ringDistance(point, hole) < 1e-6) continue;
    if (isInsidePolygon(point, hole)) return false;
  }
  return true;
}

/// [from]–[to] runs along [a]–[b], one inside the other.
bool _rides(Offset from, Offset to, Offset a, Offset b) =>
    (_segmentDistance(from, a, b) < 1e-6 &&
        _segmentDistance(to, a, b) < 1e-6) ||
    (_segmentDistance(a, from, to) < 1e-6 &&
        _segmentDistance(b, from, to) < 1e-6);

double _ringDistance(Offset point, List<Offset> ring) {
  var best = double.infinity;
  for (var i = 0; i < ring.length; i++) {
    best = math.min(
      best,
      _segmentDistance(point, ring[i], ring[(i + 1) % ring.length]),
    );
  }
  return best;
}
