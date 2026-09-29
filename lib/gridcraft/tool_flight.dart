import 'dart:math' as math;

import 'package:flutter/animation.dart';

/// Face-on is 0. Past this the flat glyph is too thin to read.
const double kMaxRoll = 80 * math.pi / 180;

/// Almost edge-on, still wide enough that the face does not vanish.
const double kArriveRoll = 78 * math.pi / 180;

/// Seated tilt so the tool reads as a blade, not a sticker.
const double kRestRoll = 18 * math.pi / 180;

/// Mid-move roll while sliding from one snap to another.
const double kDipRoll = 50 * math.pi / 180;

/// How far aim drift, measured across the cut, may tilt a seated tool.
const double kNudgeRoll = 10 * math.pi / 180;

/// Blades ready to cut.
const double kBladeOpen = 14 * math.pi / 180;

/// Blades shut at the end of a stroke.
const double kBladeClosed = 0.0;

const Duration kArriveDuration = Duration(milliseconds: 320);
const Duration kRelocateDuration = Duration(milliseconds: 220);
const Duration kLeaveDuration = Duration(milliseconds: 220);
const Duration kCutDuration = Duration(milliseconds: 180);

/// Where the tool should sit. [aim] is the crosshair; drift from [anchor]
/// rolls a seated tool and does not move it.
class ToolCue {
  const ToolCue({
    required this.anchor,
    required this.direction,
    required this.aim,
    required this.reach,
  });

  final Offset anchor;
  final Offset direction;
  final Offset aim;
  final double reach;

  bool sameAnchor(ToolCue other) => (anchor - other.anchor).distance < 1e-3;
}

enum ToolFlightPhase { absent, arrive, hold, relocate, cut, leave }

class ToolPose {
  const ToolPose({
    required this.tip,
    required this.direction,
    required this.roll,
    required this.open,
    required this.lateral,
    required this.visible,
    this.cutting = false,
  });

  static const hidden = ToolPose(
    tip: Offset.zero,
    direction: Offset(1, 0),
    roll: 0,
    open: 0,
    lateral: 0,
    visible: 0,
  );

  /// World position of the blade tip.
  final Offset tip;

  /// World unit direction the blades point.
  final Offset direction;

  /// Signed roll around the cut axis, in radians.
  final double roll;

  /// Blade half-angle, in radians.
  final double open;

  /// Pixels along [screenPerpendicular] of the cut. Zero when seated.
  final double lateral;

  final double visible;

  /// True while the view is running this pose along its cut.
  final bool cutting;
}

/// Screen-space side of a cut. [sign] is +1 along [screenPerpendicular].
class ScreenApproach {
  const ScreenApproach({required this.sign, required this.distance});

  final double sign;
  final double distance;
}

/// Unit screen vector perpendicular to [heading].
Offset screenPerpendicular(Offset heading) {
  final length = heading.distance;
  if (length < 1e-6) return const Offset(0, -1);
  return Offset(-heading.dy / length, heading.dx / length);
}

/// Signed pixels that slide a screen point off its anchor, perpendicular
/// to [heading].
Offset lateralOffset(Offset heading, double lateral) =>
    screenPerpendicular(heading) * lateral;

/// The perpendicular that leaves [viewport] sooner.
ScreenApproach approachFor({
  required Offset anchor,
  required Offset heading,
  required Size viewport,
  double margin = 140,
}) {
  final perp = screenPerpendicular(heading);
  final plus = _exitDistance(anchor, perp, viewport);
  final minus = _exitDistance(anchor, -perp, viewport);
  final sign = plus <= minus ? 1.0 : -1.0;
  final travel = sign > 0 ? plus : minus;
  return ScreenApproach(sign: sign, distance: travel + margin);
}

double holdRoll(ToolCue cue, double sign) {
  final side = Offset(-cue.direction.dy, cue.direction.dx);
  final delta = cue.aim - cue.anchor;
  final across = delta.dx * side.dx + delta.dy * side.dy;
  final reach = cue.reach.abs() < 1e-6 ? 1.0 : cue.reach.abs();
  final nudge = (across / reach).clamp(-1.0, 1.0) * kNudgeRoll;
  return (sign * kRestRoll + nudge).clamp(-kMaxRoll, kMaxRoll);
}

ToolPose sampleArrive({
  required double t,
  required ToolCue cue,
  required double distance,
  required double sign,
}) {
  final u = Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));
  return ToolPose(
    tip: cue.anchor,
    direction: cue.direction,
    roll: _lerp(sign * kArriveRoll, holdRoll(cue, sign), u),
    open: kBladeOpen,
    lateral: sign * distance * (1 - u),
    visible: 1,
  );
}

ToolPose sampleHold({required ToolCue cue, required double sign}) {
  return ToolPose(
    tip: cue.anchor,
    direction: cue.direction,
    roll: holdRoll(cue, sign),
    open: kBladeOpen,
    lateral: 0,
    visible: 1,
  );
}

ToolPose sampleRelocate({
  required double t,
  required ToolPose from,
  required ToolCue to,
  required double sign,
}) {
  final raw = t.clamp(0.0, 1.0);
  final u = Curves.easeOutCubic.transform(raw);
  final seated = _lerp(from.roll, holdRoll(to, sign), u);
  final roll = _lerp(seated, sign * kDipRoll, math.sin(math.pi * raw))
      .clamp(-kMaxRoll, kMaxRoll);
  return ToolPose(
    tip: Offset.lerp(from.tip, to.anchor, u)!,
    direction: _lerpDirection(from.direction, to.direction, u),
    roll: roll,
    open: kBladeOpen,
    lateral: from.lateral * (1 - u),
    visible: 1,
  );
}

ToolPose sampleLeave({
  required double t,
  required ToolPose from,
  required double distance,
  required double sign,
}) {
  final raw = t.clamp(0.0, 1.0);
  final u = Curves.easeIn.transform(raw);
  final done = raw >= 1;
  return ToolPose(
    tip: from.tip,
    direction: from.direction,
    roll: _lerp(from.roll, sign * kArriveRoll, u).clamp(-kMaxRoll, kMaxRoll),
    open: from.open,
    lateral: from.lateral + sign * distance * u,
    visible: done ? 0 : from.visible,
    cutting: from.cutting,
  );
}

ToolPose sampleCut({
  required double t,
  required Offset from,
  required Offset to,
  required Offset direction,
  required double fromRoll,
  required double fromLateral,
  required double fromOpen,
  required double sign,
  bool present = false,
}) {
  final u = Curves.easeInOut.transform(t.clamp(0.0, 1.0));
  return ToolPose(
    tip: Offset.lerp(from, to, u)!,
    direction: direction,
    roll: _lerp(fromRoll, sign * kRestRoll, u).clamp(-kMaxRoll, kMaxRoll),
    open: _lerp(fromOpen, kBladeClosed, u),
    lateral: fromLateral * (1 - u),
    visible: present ? (1 - u) : 0,
    cutting: true,
  );
}

/// Plays one maneuver at a time. The caller owns the clock and passes raw
/// controller time in [0, 1].
class ToolFlight {
  ToolFlightPhase phase = ToolFlightPhase.absent;
  ToolCue? target;

  /// Hover before a new cut shows the tool. A march already in progress hides it.
  bool presented = true;

  ToolPose _from = ToolPose.hidden;
  double _distance = 0;
  double _sign = 1;
  Offset _cutTo = Offset.zero;
  Offset _cutDirection = const Offset(1, 0);
  bool _cutPresent = false;

  /// Returns a duration when [t] should restart at 0.
  Duration? offer(
    ToolCue? next, {
    required double t,
    ScreenApproach? approach,
    bool follow = false,
  }) {
    if (phase == ToolFlightPhase.cut) return null;

    if (next == null) {
      if (phase == ToolFlightPhase.absent || phase == ToolFlightPhase.leave) {
        return null;
      }
      _startLeave(t, approach);
      return kLeaveDuration;
    }

    if (phase == ToolFlightPhase.absent) {
      _startArrive(next, approach);
      return kArriveDuration;
    }

    if (phase == ToolFlightPhase.leave) {
      _startRelocate(next, t, approach);
      return kRelocateDuration;
    }

    final current = target;
    if (current != null && (follow || current.sameAnchor(next))) {
      target = next;
      return null;
    }

    _startRelocate(next, t, approach);
    return kRelocateDuration;
  }

  void beginCut({
    required Offset from,
    required Offset to,
    required Offset direction,
    required double t,
    bool present = false,
  }) {
    final current = pose(t);
    _cutTo = to;
    _cutDirection = direction;
    _cutPresent = present;
    phase = ToolFlightPhase.cut;
    target = ToolCue(
      anchor: from,
      direction: direction,
      aim: from,
      reach: 1,
    );
    _from = ToolPose(
      tip: from,
      direction: direction,
      roll: current.roll,
      open: current.open,
      lateral: current.lateral,
      visible: 1,
    );
  }

  void reset() {
    phase = ToolFlightPhase.absent;
    target = null;
    presented = true;
    _cutPresent = false;
  }

  /// Fly the current pose offscreen. Returns the leave duration.
  Duration depart(double t, ScreenApproach? approach) {
    _startLeave(t, approach);
    return kLeaveDuration;
  }

  /// Arrive and relocate become a hold. Leave becomes absent.
  void land() {
    switch (phase) {
      case ToolFlightPhase.arrive:
      case ToolFlightPhase.relocate:
        phase = ToolFlightPhase.hold;
      case ToolFlightPhase.leave:
        phase = ToolFlightPhase.absent;
        target = null;
      case ToolFlightPhase.cut:
      case ToolFlightPhase.hold:
      case ToolFlightPhase.absent:
        break;
    }
  }

  void seat(ToolCue cue) {
    phase = ToolFlightPhase.hold;
    target = cue;
  }

  ToolPose pose(double t) {
    final raw = _sample(t);
    if (presented || (phase == ToolFlightPhase.cut && _cutPresent)) return raw;
    return ToolPose(
      tip: raw.tip,
      direction: raw.direction,
      roll: raw.roll,
      open: raw.open,
      lateral: raw.lateral,
      visible: 0,
      cutting: raw.cutting,
    );
  }

  ToolPose _sample(double t) {
    final cue = target;
    switch (phase) {
      case ToolFlightPhase.absent:
        return ToolPose.hidden;
      case ToolFlightPhase.hold:
        if (cue == null) return ToolPose.hidden;
        return sampleHold(cue: cue, sign: _sign);
      case ToolFlightPhase.arrive:
        if (cue == null) return ToolPose.hidden;
        return sampleArrive(
          t: t,
          cue: cue,
          distance: _distance,
          sign: _sign,
        );
      case ToolFlightPhase.relocate:
        if (cue == null) return ToolPose.hidden;
        return sampleRelocate(t: t, from: _from, to: cue, sign: _sign);
      case ToolFlightPhase.leave:
        return sampleLeave(
          t: t,
          from: _from,
          distance: _distance,
          sign: _sign,
        );
      case ToolFlightPhase.cut:
        return sampleCut(
          t: t,
          from: _from.tip,
          to: _cutTo,
          direction: _cutDirection,
          fromRoll: _from.roll,
          fromLateral: _from.lateral,
          fromOpen: _from.open,
          sign: _sign,
          present: _cutPresent,
        );
    }
  }

  void _startArrive(ToolCue next, ScreenApproach? approach) {
    phase = ToolFlightPhase.arrive;
    target = next;
    _apply(approach);
  }

  void _startRelocate(ToolCue next, double t, ScreenApproach? approach) {
    _from = pose(t);
    phase = ToolFlightPhase.relocate;
    target = next;
    if (approach != null) _sign = approach.sign;
  }

  void _startLeave(double t, ScreenApproach? approach) {
    _from = pose(t);
    phase = ToolFlightPhase.leave;
    _apply(approach);
  }

  void _apply(ScreenApproach? approach) {
    if (approach == null) {
      _distance = 800;
      return;
    }
    _sign = approach.sign;
    _distance = approach.distance;
  }
}

double _exitDistance(Offset origin, Offset dir, Size viewport) {
  var best = double.infinity;
  if (dir.dx > 1e-8) {
    best = math.min(best, (viewport.width - origin.dx) / dir.dx);
  } else if (dir.dx < -1e-8) {
    best = math.min(best, (0 - origin.dx) / dir.dx);
  }
  if (dir.dy > 1e-8) {
    best = math.min(best, (viewport.height - origin.dy) / dir.dy);
  } else if (dir.dy < -1e-8) {
    best = math.min(best, (0 - origin.dy) / dir.dy);
  }
  if (!best.isFinite || best < 0) return viewport.longestSide;
  return best;
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

Offset _lerpDirection(Offset a, Offset b, double t) {
  final mixed = Offset.lerp(a, b, t)!;
  final length = mixed.distance;
  if (length < 1e-6) return b;
  return mixed / length;
}
