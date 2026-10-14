import 'dart:math' as math;
import 'dart:ui';

import 'line_puzzle_models.dart';

enum MoveKind { step, exit, blocked }

/// Distance to a dot, in cells, where the peg may leave its groove.
const double kLineJunction = 0.15;

/// How far the drag must run along a new axis before the peg takes that track.
const double kLineTurn = 0.12;

/// How far past a paper-edge dot the peg must slide before the tool use ends.
const double kLineExit = 0.45;

/// How many times [point] already appears on the tool path.
int lineVisits(LineSession session, LinePoint point) {
  var count = 0;
  for (final stroke in session.strokes) {
    for (final dot in stroke.points) {
      if (dot == point) count++;
    }
  }
  return count;
}

LineSession setTool(LineSession session, LineTool tool) {
  if (session.tool == tool) return session;
  if (!session.canSwitchTool) return session;
  return session.copyWith(tool: tool);
}

/// What a drag from the current head toward [to] is allowed to do.
MoveKind classifyMove(LineSession session, LinePoint to) {
  if (session.phase != LinePhase.drawing) return MoveKind.blocked;
  final head = session.head;
  if (head == null) return MoveKind.blocked;
  final dx = (to.x - head.x).abs();
  final dy = (to.y - head.y).abs();
  if (dx + dy != 1) return MoveKind.blocked;
  if (!session.puzzle.bounds.contains(to)) {
    return session.puzzle.isEdgeDot(head) ? MoveKind.exit : MoveKind.blocked;
  }
  if (!session.puzzle.hasDot(to)) return MoveKind.blocked;
  if (lineVisits(session, to) >= session.puzzle.budget(to)) {
    return MoveKind.blocked;
  }
  return MoveKind.step;
}

/// Tap a paper-edge dot to start a tool use.
LineSession beginStroke(LineSession session, LinePoint at) {
  if (session.phase != LinePhase.browse && session.phase != LinePhase.paused) {
    return session;
  }
  if (!session.puzzle.isEdgeDot(at)) return session;
  if (lineVisits(session, at) >= session.puzzle.budget(at)) return session;
  final stroke = LineStroke(tool: session.tool, points: [at]);
  final drawing = session.copyWith(
    strokes: [...session.strokes, stroke],
    phase: LinePhase.drawing,
    strokeBase: session,
  );
  return _arrive(drawing, from: null, to: at);
}

/// Step onto an orthogonal neighbor, or leave the paper.
LineSession step(LineSession session, LinePoint to) {
  final kind = classifyMove(session, to);
  if (kind == MoveKind.blocked) return session;
  if (kind == MoveKind.exit) return exitStroke(session);
  final head = session.head!;
  final strokes = [...session.strokes];
  strokes[strokes.length - 1] = strokes.last.extend(to);
  final moved = session.copyWith(strokes: strokes);
  return _arrive(moved, from: head, to: to);
}

/// Dragging outward off an edge dot pauses the puzzle.
LineSession exitStroke(LineSession session) {
  if (session.phase != LinePhase.drawing) return session;
  final head = session.head;
  if (head == null || !session.puzzle.isEdgeDot(head)) return session;
  if (_won(session)) {
    return session.copyWith(phase: LinePhase.solved, clearStrokeBase: true);
  }
  return session.copyWith(
    phase: LinePhase.paused,
    clearFailure: true,
    clearStrokeBase: true,
  );
}

/// One drag sample applied to the peg. The line fills [delta] and can reverse.
class PegMove {
  const PegMove(this.session, this.peg, this.slack);

  final LineSession session;
  final LinePeg peg;
  final Offset slack;
}

/// Slide the peg by [delta] in world cells. Perpendicular drag is ignored
/// while the peg is mid-groove. Near a dot, a sideways drag can turn.
/// Backtracking pops anchors, which undoes that part of the open stroke.
PegMove movePeg(LineSession session, LinePeg peg, Offset delta) {
  var slack = delta;
  var current = session;
  var cursor = peg;
  for (var i = 0; i < 32; i++) {
    if (current.phase != LinePhase.drawing) break;
    final next = _advancePeg(current, cursor, slack);
    final idle =
        identical(next.session, current) &&
        next.peg.toward == cursor.toward &&
        next.peg.anchor == cursor.anchor &&
        (next.peg.t - cursor.t).abs() < 1e-6 &&
        (next.slack - slack).distance < 1e-6;
    current = next.session;
    cursor = next.peg;
    slack = next.slack;
    if (idle || current.phase != LinePhase.drawing) break;
  }
  return PegMove(current, cursor, slack);
}

/// Drop the open groove. The tip springs back to the last anchored dot.
LinePeg releasePeg(LinePeg peg) {
  if (peg.atAnchor) return LinePeg(anchors: peg.anchors);
  return LinePeg(anchors: peg.anchors);
}

PegMove _advancePeg(LineSession session, LinePeg peg, Offset slack) {
  if (peg.toward == null) return _fromVertex(session, peg, slack);
  return _inGroove(session, peg, slack);
}

PegMove _fromVertex(LineSession session, LinePeg peg, Offset slack) {
  final ax = slack.dx.abs();
  final ay = slack.dy.abs();
  if (ax < kLineTurn && ay < kLineTurn) return PegMove(session, peg, slack);
  final alongX = ax >= ay;
  final signX = slack.dx < 0 ? -1 : 1;
  final signY = slack.dy < 0 ? -1 : 1;
  final sx = alongX ? signX : 0;
  final sy = alongX ? 0 : signY;
  final anchor = peg.anchor;
  final target = LinePoint(anchor.x + sx, anchor.y + sy);
  final component = alongX ? ax : ay;

  if (_isBacktrack(peg, target)) {
    final kept = replayStroke(
      session,
      peg.anchors.sublist(0, peg.anchors.length - 1),
    );
    if (kept.phase != LinePhase.drawing) {
      return PegMove(
        kept,
        LinePeg(anchors: _anchorsOf(kept, peg)),
        Offset.zero,
      );
    }
    return PegMove(
      kept,
      LinePeg(anchors: kept.strokes.last.points, toward: anchor, t: 1),
      slack,
    );
  }

  final kind = classifyMove(session, target);
  if (kind == MoveKind.blocked) {
    final rest = alongX ? Offset(0, slack.dy) : Offset(slack.dx, 0);
    return PegMove(session, peg, rest);
  }
  if (kind == MoveKind.exit) {
    if (component >= kLineExit) {
      return PegMove(
        exitStroke(session),
        LinePeg(anchors: peg.anchors),
        Offset.zero,
      );
    }
    final rest = alongX ? Offset(0, slack.dy) : Offset(slack.dx, 0);
    return PegMove(session, peg.copyWith(toward: target, t: component), rest);
  }

  // The threshold only picks the track. The whole drag still fills the line.
  final rest = alongX
      ? Offset(signX * component, slack.dy)
      : Offset(slack.dx, signY * component);
  return PegMove(session, peg.copyWith(toward: target, t: 0), rest);
}

PegMove _inGroove(LineSession session, LinePeg peg, Offset slack) {
  final anchor = peg.anchor;
  final toward = peg.toward!;
  final dirX = toward.x - anchor.x;
  final dirY = toward.y - anchor.y;
  final along = slack.dx * dirX + slack.dy * dirY;
  final perpX = -dirY;
  final perpY = dirX;
  final perp = slack.dx * perpX + slack.dy * perpY;
  final outside = !session.puzzle.bounds.contains(toward);

  if (outside) {
    final nextT = peg.t + along;
    if (nextT >= kLineExit && along > 0) {
      return PegMove(
        exitStroke(session),
        LinePeg(anchors: peg.anchors),
        Offset.zero,
      );
    }
    if (nextT <= 0) {
      final rest = slack - Offset(dirX * -peg.t, dirY * -peg.t);
      return PegMove(session, peg.copyWith(clearToward: true, t: 0), rest);
    }
    return PegMove(
      session,
      peg.copyWith(t: nextT.clamp(0.0, kLineExit)),
      Offset.zero,
    );
  }

  final nextT = peg.t + along;
  if (nextT >= 1) {
    final arrived = step(session, toward);
    if (arrived.phase != LinePhase.drawing) {
      return PegMove(
        arrived,
        LinePeg(anchors: _anchorsOf(arrived, peg)),
        Offset.zero,
      );
    }
    if (identical(arrived, session)) {
      return PegMove(
        session,
        peg.copyWith(t: math.max(peg.t, kLineJunction)),
        Offset.zero,
      );
    }
    final consumed = 1 - peg.t;
    final rest = slack - Offset(dirX * consumed, dirY * consumed);
    return PegMove(
      arrived,
      LinePeg(anchors: arrived.strokes.last.points),
      rest,
    );
  }
  if (nextT <= 0) {
    final rest = slack - Offset(dirX * -peg.t, dirY * -peg.t);
    return PegMove(session, peg.copyWith(clearToward: true, t: 0), rest);
  }

  final moved = peg.copyWith(t: nextT);
  final near = nextT <= kLineJunction || nextT >= 1 - kLineJunction;
  if (!near || perp.abs() < kLineTurn) {
    return PegMove(
      session,
      moved,
      near ? Offset(perpX * perp, perpY * perp) : Offset.zero,
    );
  }
  if (nextT >= 1 - kLineJunction) {
    final arrived = step(session, toward);
    if (identical(arrived, session) || arrived.phase != LinePhase.drawing) {
      if (arrived.phase != LinePhase.drawing && !identical(arrived, session)) {
        return PegMove(
          arrived,
          LinePeg(anchors: _anchorsOf(arrived, peg)),
          Offset.zero,
        );
      }
      return PegMove(session, moved, Offset.zero);
    }
    return PegMove(
      arrived,
      LinePeg(anchors: arrived.strokes.last.points),
      Offset(perpX * perp, perpY * perp),
    );
  }
  return PegMove(
    session,
    peg.copyWith(clearToward: true, t: 0),
    Offset(perpX * perp, perpY * perp),
  );
}

bool _isBacktrack(LinePeg peg, LinePoint target) {
  if (peg.anchors.length < 2) return false;
  return peg.anchors[peg.anchors.length - 2] == target;
}

/// Rebuild the open stroke as [anchors], undoing anything past that prefix.
LineSession replayStroke(LineSession session, List<LinePoint> anchors) {
  final base = session.strokeBase;
  if (base == null || anchors.isEmpty) return session;
  var next = beginStroke(base, anchors.first);
  for (var i = 1; i < anchors.length; i++) {
    if (next.phase != LinePhase.drawing) return next;
    final stepped = step(next, anchors[i]);
    if (identical(stepped, next)) return next;
    next = stepped;
  }
  return next;
}

List<LinePoint> _anchorsOf(LineSession session, LinePeg fallback) {
  if (session.strokes.isEmpty) return fallback.anchors;
  return session.strokes.last.points;
}

/// Flipper, then border color, then number order.
LineSession _arrive(
  LineSession session, {
  required LinePoint? from,
  required LinePoint to,
}) {
  final flip = session.puzzle.flipperColor(to);
  final color = flip ?? session.paperColor;
  var covered = session.covered;
  var solved = session.solvedBorders;
  if (from != null) {
    covered = {...session.covered, LineEdge(from, to)};
    final border = _closeBorders(session, covered, color);
    if (border.failure != null) {
      return session.copyWith(
        paperColor: color,
        covered: covered,
        phase: LinePhase.failed,
        failure: border.failure,
      );
    }
    solved = border.solved;
  }

  final next = session.copyWith(
    paperColor: color,
    covered: covered,
    solvedBorders: solved,
    clearFailure: true,
  );
  final entered = _enterRegions(next, from: from, to: to);
  if (entered.failure != null) return entered;
  if (_won(entered)) {
    return entered.copyWith(phase: LinePhase.solved, clearFailure: true);
  }
  return entered;
}

({Set<int> solved, LineFailure? failure}) _closeBorders(
  LineSession session,
  Set<LineEdge> covered,
  int? color,
) {
  final solved = Set<int>.of(session.solvedBorders);
  for (var i = 0; i < session.puzzle.regions.length; i++) {
    final region = session.puzzle.regions[i];
    if (!region.needsBorder || solved.contains(i)) continue;
    var complete = true;
    for (final edge in region.edges) {
      if (!covered.contains(edge)) {
        complete = false;
        break;
      }
    }
    if (!complete) continue;
    if (region.color != null && color != region.color) {
      return (
        solved: solved,
        failure: LineFailure(regionIndex: i, kind: LineFailureKind.color),
      );
    }
    solved.add(i);
  }
  return (solved: solved, failure: null);
}

LineSession _enterRegions(
  LineSession session, {
  required LinePoint? from,
  required LinePoint to,
}) {
  final touched = <int>[];
  for (var i = 0; i < session.puzzle.regions.length; i++) {
    if (session.visited.contains(i)) continue;
    if (_touches(session.puzzle.regions[i], from, to)) touched.add(i);
  }
  touched.sort((a, b) {
    final ao = session.puzzle.regions[a].order ?? 1 << 20;
    final bo = session.puzzle.regions[b].order ?? 1 << 20;
    return ao.compareTo(bo);
  });

  final visited = Set<int>.of(session.visited);
  var orderCount = session.nextOrder - 1;
  for (final index in touched) {
    final region = session.puzzle.regions[index];
    if (region.order != null) {
      if (region.order != orderCount + 1) {
        return session.copyWith(
          visited: visited,
          phase: LinePhase.failed,
          failure: LineFailure(regionIndex: index, kind: LineFailureKind.order),
        );
      }
      orderCount++;
    }
    visited.add(index);
  }
  if (touched.isEmpty) return session;
  return session.copyWith(visited: visited, clearFailure: true);
}

bool _touches(LineRegion region, LinePoint? from, LinePoint to) {
  if (lineContains(region.ring, to)) return true;
  if (from != null && lineContains(region.ring, from)) return true;
  if (from == null) return false;
  return region.edges.contains(LineEdge(from, to));
}

bool _won(LineSession session) {
  for (var i = 0; i < session.puzzle.regions.length; i++) {
    final region = session.puzzle.regions[i];
    if (region.needsBorder && !session.solvedBorders.contains(i)) return false;
    if (region.order != null && !session.visited.contains(i)) return false;
  }
  return true;
}
