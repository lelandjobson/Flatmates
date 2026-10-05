import 'dart:math' as math;
import 'dart:ui';

import '../geometry/geometry_algorithms.dart';
import '../geometry/polygon_union.dart';
import '../papercut/models.dart';
import '../papercut/paper.dart';
import '../papercut/split.dart';
import 'blueprint.dart';
import 'dynamic_grid.dart';
import 'fold.dart';
import 'scissor.dart';

const double kDynamicSnapRadius = 0.65;
const double _eps = 1e-3;

/// Blank sheet for [step], the same rectangle the grid puzzle view cuts.
PapercutSheet dynamicPaperSheet(GridStep step) {
  final paper = step.paper;
  return PapercutSheet(
    pieces: [
      PapercutPiece(
        id: 'paper',
        color: kPapercutYellow,
        vertices: [
          paper.topLeft,
          paper.topRight,
          paper.bottomRight,
          paper.bottomLeft,
        ],
      ),
    ],
  );
}

/// What a finger stroke would do if it were released now.
class DynamicStrokeAssessment {
  const DynamicStrokeAssessment({
    required this.complete,
    required this.illegal,
    required this.crossedPieceIds,
    this.piercedIndex,
    this.fold,
  });

  /// The path has entered a paper piece and left it again.
  final bool complete;

  /// Some segment of the path cuts through a blueprint piece.
  final bool illegal;

  /// Blueprint piece the path cuts through, when [illegal].
  final int? piercedIndex;

  /// Paper pieces the path has entered and left.
  final List<String> crossedPieceIds;

  /// Straight crease across one crossed piece, when the folder can commit.
  final DynamicFoldSpan? fold;
}

/// Crease the folder would lay down, and a point on the smaller side.
class DynamicFoldSpan {
  const DynamicFoldSpan({
    required this.pieceId,
    required this.a,
    required this.b,
    required this.flap,
  });

  final String pieceId;
  final Offset a;
  final Offset b;
  final Offset flap;
}

/// Finger stroke stuck to a [DynamicGridGraph]. Nothing is committed here.
class DynamicStrokeSession {
  DynamicStrokeSession({required this.graph});

  DynamicGridGraph graph;
  final List<Offset> _points = [];
  bool _active = false;

  bool get active => _active;
  List<Offset> get points => List<Offset>.unmodifiable(_points);

  /// False when the snap misses the grid, or lands inside a paper piece.
  ///
  /// [rejectInsidePaper] is off for a tessellation stroke, which defines a
  /// translation and does not cut.
  bool begin(
    Offset finger,
    PapercutSheet sheet, {
    bool rejectInsidePaper = true,
  }) {
    final hit = graph.project(finger);
    if (hit == null || hit.distance > kDynamicSnapRadius) return false;
    if (rejectInsidePaper && pointStrictlyInsideSheet(hit.point, sheet)) {
      return false;
    }
    _points
      ..clear()
      ..add(hit.point);
    _active = true;
    return true;
  }

  void move(Offset finger) {
    if (!_active || _points.isEmpty) return;
    final next = followGrid(_points, finger, graph);
    _points
      ..clear()
      ..addAll(next);
  }

  void cancel() {
    _points.clear();
    _active = false;
  }
}

/// Slides [path] along [graph] toward [finger]. The finger can reverse.
List<Offset> followGrid(
  List<Offset> path,
  Offset finger,
  DynamicGridGraph graph,
) {
  final points = List<Offset>.of(path);
  if (points.isEmpty) return points;
  for (var guard = 0; guard < 24; guard++) {
    final head = points.last;
    final origin = points.length >= 2 ? points[points.length - 2] : null;
    final partial = origin != null && !_nearVertex(head, graph);
    if (!partial) {
      final exits = _exits(head, graph);
      _Step? best;
      for (final end in exits) {
        if (_blocked(points, end, origin)) continue;
        final proj = projectOntoSegment(finger, head, end);
        if ((proj - head).distance < _eps) continue;
        final score = (finger - proj).distance;
        final closer = score + _eps < (finger - head).distance;
        final arrived =
            (proj - end).distance <= _eps &&
            (finger - end).distance + _eps < (finger - head).distance;
        if (!closer && !arrived) continue;
        if (best == null || score < best.score) {
          best = _Step(proj, end, score);
        }
      }
      if (best == null) break;
      final back = origin != null && (best.end - origin).distance <= _eps;
      if (back && (best.proj - origin).distance <= _eps) {
        points.removeLast();
        continue;
      }
      if (back) {
        points[points.length - 1] = best.proj;
        break;
      }
      if ((best.proj - best.end).distance <= _eps) {
        points.add(best.end);
        continue;
      }
      points.add(best.proj);
      break;
    }

    final forward = _forwardEnd(origin, head, graph);
    if (forward == null) break;
    final backProj = projectOntoSegment(finger, head, origin);
    final fwdProj = projectOntoSegment(finger, head, forward);
    final goBack =
        (finger - backProj).distance + _eps < (finger - fwdProj).distance;
    if (goBack) {
      if ((backProj - origin).distance <= _eps) {
        points.removeLast();
        continue;
      }
      points[points.length - 1] = backProj;
      break;
    }
    if ((fwdProj - head).distance < _eps) break;
    if ((fwdProj - forward).distance <= _eps) {
      points[points.length - 1] = forward;
      continue;
    }
    points[points.length - 1] = fwdProj;
    break;
  }
  return points;
}

class _Step {
  const _Step(this.proj, this.end, this.score);
  final Offset proj;
  final Offset end;
  final double score;
}

bool _nearVertex(Offset point, DynamicGridGraph graph) {
  for (final vertex in graph.vertices) {
    if ((vertex - point).distance <= _eps) return true;
  }
  return false;
}

bool _blocked(List<Offset> points, Offset end, Offset? origin) {
  if (origin != null && (end - origin).distance <= _eps) return false;
  for (var i = 0; i < points.length - 1; i++) {
    if ((points[i] - end).distance <= _eps) return true;
  }
  return false;
}

List<Offset> _exits(Offset head, DynamicGridGraph graph) {
  final exits = <Offset>[];
  for (final link in graph.links) {
    final a = graph.vertices[link.$1];
    final b = graph.vertices[link.$2];
    if ((a - head).distance <= _eps) {
      exits.add(b);
    } else if ((b - head).distance <= _eps) {
      exits.add(a);
    } else if (_onSegment(head, a, b)) {
      exits.add(a);
      exits.add(b);
    }
  }
  return exits;
}

Offset? _forwardEnd(Offset origin, Offset head, DynamicGridGraph graph) {
  for (final link in graph.links) {
    final a = graph.vertices[link.$1];
    final b = graph.vertices[link.$2];
    final originOn =
        _onSegment(origin, a, b) ||
        (origin - a).distance <= _eps ||
        (origin - b).distance <= _eps;
    final headOn = _onSegment(head, a, b);
    if (!originOn || !headOn) continue;
    if ((a - origin).distance <= _eps) return b;
    if ((b - origin).distance <= _eps) return a;
    // Origin is mid-edge (the stroke start). The forward end is the endpoint
    // the head is moving toward.
    if ((head - a).distance < (head - b).distance) {
      if ((a - origin).distance > _eps) return a;
    } else if ((b - origin).distance > _eps) {
      return b;
    }
  }
  return null;
}

bool _onSegment(Offset point, Offset a, Offset b) {
  if ((point - a).distance <= _eps || (point - b).distance <= _eps) return true;
  final proj = projectOntoSegment(point, a, b);
  if ((proj - point).distance > _eps) return false;
  final t = parameterOn(a, b, point);
  return t >= -_eps && t <= 1 + _eps;
}

bool pointStrictlyInsideSheet(Offset point, PapercutSheet sheet) {
  for (final piece in sheet.pieces) {
    if (pointStrictlyInsidePiece(point, piece)) return true;
  }
  return false;
}

bool pointStrictlyInsidePiece(Offset point, PapercutPiece piece) {
  if (!_strictlyInsideRing(point, piece.vertices)) return false;
  for (final hole in piece.holes) {
    if (hole.length < 3) continue;
    if (_strictlyInsideRing(point, hole) ||
        _ringDistance(point, hole) <= _eps) {
      return false;
    }
  }
  return true;
}

bool _strictlyInsideRing(Offset point, List<Offset> ring) {
  if (ring.length < 3) return false;
  if (_ringDistance(point, ring) <= _eps) return false;
  return isInsidePolygon(point, ring);
}

double _ringDistance(Offset point, List<Offset> ring) {
  var best = double.infinity;
  for (var i = 0; i < ring.length; i++) {
    final on = projectOntoSegment(point, ring[i], ring[(i + 1) % ring.length]);
    best = math.min(best, (on - point).distance);
  }
  return best;
}

DynamicStrokeAssessment assessDynamicStroke(
  List<Offset> points,
  PapercutSheet sheet,
  GridStep step,
) {
  final pierced = _piercedIndex(points, step);
  final crossed = <String>[];
  DynamicFoldSpan? fold;
  for (final piece in sheet.pieces) {
    if (!_fullyCrossed(points, piece)) continue;
    crossed.add(piece.id);
    fold ??= _foldSpan(points, piece);
  }
  return DynamicStrokeAssessment(
    complete: crossed.isNotEmpty,
    illegal: pierced != null,
    piercedIndex: pierced,
    crossedPieceIds: crossed,
    fold: fold,
  );
}

int? _piercedIndex(List<Offset> points, GridStep step) {
  for (var i = 1; i < points.length; i++) {
    final hit = piercedBlueprint(step, points[i - 1], points[i]);
    if (hit != null) return hit;
  }
  return null;
}

bool _fullyCrossed(List<Offset> points, PapercutPiece piece) {
  if (points.length < 2) return false;
  if (pointStrictlyInsidePiece(points.last, piece)) return false;
  for (var i = 1; i < points.length; i++) {
    for (final t in const [0.25, 0.5, 0.75]) {
      final sample = Offset.lerp(points[i - 1], points[i], t)!;
      if (pointStrictlyInsidePiece(sample, piece)) return true;
    }
  }
  return false;
}

DynamicFoldSpan? _foldSpan(List<Offset> points, PapercutPiece piece) {
  final clips = <(Offset, Offset)>[];
  for (var i = 1; i < points.length; i++) {
    clips.addAll(_clipToRing(points[i - 1], points[i], piece.vertices));
  }
  if (clips.isEmpty) return null;
  final span = _oneStraightSpan(clips);
  if (span == null) return null;
  return DynamicFoldSpan(
    pieceId: piece.id,
    a: span.$1,
    b: span.$2,
    flap: _smallerFlap(piece.vertices, span.$1, span.$2),
  );
}

(Offset, Offset)? _oneStraightSpan(List<(Offset, Offset)> clips) {
  if (clips.length == 1) return clips.single;
  var a = clips.first.$1;
  var b = clips.first.$2;
  final dir = b - a;
  if (dir.distance < _eps) return null;
  for (final clip in clips.skip(1)) {
    if (_distanceToLine(clip.$1, a, b) > _eps) return null;
    if (_distanceToLine(clip.$2, a, b) > _eps) return null;
    if (parameterOn(a, b, clip.$1) < 0) a = clip.$1;
    if (parameterOn(a, b, clip.$2) < 0) a = clip.$2;
    if (parameterOn(a, b, clip.$1) > 1) b = clip.$1;
    if (parameterOn(a, b, clip.$2) > 1) b = clip.$2;
  }
  if ((a - b).distance < _eps) return null;
  return (a, b);
}

double _distanceToLine(Offset point, Offset a, Offset b) {
  final ab = b - a;
  final len = ab.distance;
  if (len < _eps) return (point - a).distance;
  final cross = ab.dx * (point.dy - a.dy) - ab.dy * (point.dx - a.dx);
  return cross.abs() / len;
}

List<(Offset, Offset)> _clipToRing(Offset a, Offset b, List<Offset> ring) {
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  if (dx * dx + dy * dy < _eps) return const [];
  final parameters = <double>[0, 1];
  for (var i = 0; i < ring.length; i++) {
    final hit = segmentIntersection(a, b, ring[i], ring[(i + 1) % ring.length]);
    if (!hit.isPoint || hit.point == null) continue;
    final t = parameterOn(a, b, hit.point!);
    if (t >= -_eps && t <= 1 + _eps) parameters.add(t.clamp(0.0, 1.0));
  }
  parameters.sort();
  final result = <(Offset, Offset)>[];
  for (var i = 0; i < parameters.length - 1; i++) {
    final t0 = parameters[i];
    final t1 = parameters[i + 1];
    if (t1 - t0 < 1e-5) continue;
    final mid = (t0 + t1) / 2;
    final probe = Offset(a.dx + dx * mid, a.dy + dy * mid);
    if (!_strictlyInsideRing(probe, ring) &&
        _ringDistance(probe, ring) > _eps) {
      continue;
    }
    if (!_ownsProbe(probe, ring)) continue;
    result.add((
      Offset(a.dx + dx * t0, a.dy + dy * t0),
      Offset(a.dx + dx * t1, a.dy + dy * t1),
    ));
  }
  return result;
}

bool _ownsProbe(Offset probe, List<Offset> ring) {
  if (_ringDistance(probe, ring) <= _eps) return true;
  return isInsidePolygon(probe, ring);
}

Offset _smallerFlap(List<Offset> ring, Offset a, Offset b) {
  final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
  final dir = b - a;
  final len = dir.distance;
  if (len < _eps) return mid;
  final normal = Offset(-dir.dy / len, dir.dx / len);
  final left = polygonSignedArea(_clipHalfPlane(ring, a, b, 1)).abs();
  final right = polygonSignedArea(_clipHalfPlane(ring, a, b, -1)).abs();
  final sign = left <= right ? 1.0 : -1.0;
  return mid + normal * sign * 0.25;
}

List<Offset> _clipHalfPlane(
  List<Offset> ring,
  Offset a,
  Offset b,
  double keepSign,
) {
  if (ring.length < 3) return const [];
  final out = <Offset>[];
  for (var i = 0; i < ring.length; i++) {
    final c = ring[i];
    final d = ring[(i + 1) % ring.length];
    final sc = sideOfLine(c, a, b);
    final sd = sideOfLine(d, a, b);
    final cIn = sc * keepSign >= -1e-7;
    final dIn = sd * keepSign >= -1e-7;
    if (cIn && dIn) {
      out.add(d);
    } else if (cIn && !dIn) {
      final hit = _lineSegmentHit(a, b, c, d);
      if (hit != null) out.add(hit);
    } else if (!cIn && dIn) {
      final hit = _lineSegmentHit(a, b, c, d);
      if (hit != null) out.add(hit);
      out.add(d);
    }
  }
  return out;
}

/// Intersection of the unbounded line through [a]–[b] with segment [c]–[d].
Offset? _lineSegmentHit(Offset a, Offset b, Offset c, Offset d) {
  final dxa = b.dx - a.dx;
  final dya = b.dy - a.dy;
  final dxb = d.dx - c.dx;
  final dyb = d.dy - c.dy;
  final denom = dxa * dyb - dya * dxb;
  if (denom.abs() < 1e-12) return null;
  final wx = a.dx - c.dx;
  final wy = a.dy - c.dy;
  final u = (dxa * wy - dya * wx) / denom;
  if (u < -1e-6 || u > 1 + 1e-6) return null;
  return Offset(c.dx + u * dxb, c.dy + u * dyb);
}

/// Splits [sheet] along [points] when the stroke has left the paper.
///
/// Returns null when the stroke is unfinished or cuts through a blueprint
/// piece. New pieces stay where they were: separation is left at zero.
PapercutSheet? commitDynamicCut({
  required PapercutSheet sheet,
  required List<Offset> points,
  required GridStep step,
}) {
  final assessment = assessDynamicStroke(points, sheet, step);
  if (!assessment.complete || assessment.illegal) return null;
  final next = applyPapercutCut(sheet, points);
  if (next == null) return null;
  return next;
}

/// Folds the smaller side across a straight through-stroke.
PapercutSheet? commitDynamicFold({
  required PapercutSheet sheet,
  required List<Offset> points,
  required GridStep step,
}) {
  final assessment = assessDynamicStroke(points, sheet, step);
  final span = assessment.fold;
  if (!assessment.complete || assessment.illegal || span == null) return null;
  return foldSheet(
    sheet: sheet,
    spanA: span.a,
    spanB: span.b,
    flapPoint: span.flap,
    facing: FoldFacing.toward,
    blueprintPieces: step.closedPolygons,
    pieceId: span.pieceId,
  );
}
