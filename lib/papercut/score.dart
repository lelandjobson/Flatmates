import 'dart:math' as math;
import 'dart:ui';

import '../geometry/geometry_algorithms.dart';
import 'models.dart';
import 'paper.dart';
import 'safe_zone.dart';

const double kPapercutToleranceMm = kPapercutLateralMm;
const double kPapercutLengthSlop = 0.10;
const double kPapercutKinkDegrees = 45;
const double _sampleMm = 1.5;

class PapercutScore {
  const PapercutScore.pass() : passed = true, reason = null;

  const PapercutScore.fail(this.reason) : passed = false;

  final bool passed;
  final String? reason;
}

/// Cut perimeters and fold guides. A fold passes when a crease lies in its zone.
PapercutScore scorePapercutStep(PapercutStep step, PapercutSheet sheet) {
  final geometry = step.geometry;
  if (geometry is! PapercutCurveGeometry) return const PapercutScore.pass();
  if (step.wantsCutPerimeters) {
    final closed = geometry.cutCurves.toList();
    final open = geometry.curves
        .where(
          (curve) => curve.role == PapercutCurveRole.cut && !curve.closed,
        )
        .toList();
    if (closed.isEmpty && open.isEmpty) {
      return const PapercutScore.fail('This step has no cut outlines');
    }
    for (final curve in closed) {
      final score = scoreCutPerimeter(curve.points, sheet.cutStrokes);
      if (!score.passed) return score;
    }
    for (final curve in open) {
      final score = scoreOpenCut(curve, sheet.cutStrokes);
      if (!score.passed) return score;
    }
  }
  for (final fold in geometry.foldCurves) {
    final score = scoreFoldGuide(fold, sheet.creases);
    if (!score.passed) return score;
  }
  return const PapercutScore.pass();
}

/// A target perimeter passes when the player cuts cover it, match its length,
/// and share its corners without kinking off the path.
PapercutScore scoreCutPerimeter(
  List<Offset> target,
  List<List<Offset>> playerCuts,
) {
  if (target.length < 3) {
    return const PapercutScore.fail('Outline is not a closed shape');
  }
  final loop = [...target, target.first];
  final targetLength = _polylineLength(loop);
  if (targetLength < 1) {
    return const PapercutScore.fail('Outline is not a closed shape');
  }

  final targetSamples = sampleOffsets(target, closed: true, spacing: _sampleMm);
  for (final sample in targetSamples) {
    if (!_inAnyCutZone(sample, playerCuts)) {
      return const PapercutScore.fail('The cut misses the outline');
    }
  }

  final matched = <List<Offset>>[];
  var matchedLength = 0.0;
  for (final stroke in playerCuts) {
    final near = _lengthNear(stroke, target);
    if (near >= 8) matched.add(stroke);
    matchedLength += near;
  }
  final lengthError = (matchedLength - targetLength).abs() / targetLength;
  if (lengthError > kPapercutLengthSlop) {
    return const PapercutScore.fail('The cut length is off the outline');
  }

  final playerKinks = _playerKinks(matched.isEmpty ? playerCuts : matched);
  for (final kink in _turningKinks(target, closed: true)) {
    if (_nearest(kink, playerKinks) > kPapercutToleranceMm) {
      return const PapercutScore.fail('A corner of the outline was missed');
    }
  }
  for (final kink in playerKinks) {
    if (!pointInSafeZone(
      kink,
      target,
      closed: true,
      capsuleFraction: kPapercutCutCapsuleFraction,
    )) {
      return const PapercutScore.fail('A cut kinks off the outline');
    }
  }
  return const PapercutScore.pass();
}

/// An open cut guide passes when cut strokes cover it inside the cut zone.
PapercutScore scoreOpenCut(PapercutCurve cut, List<List<Offset>> playerCuts) {
  return _scoreGuide(
    cut,
    playerCuts,
    miss: 'The cut misses the guide',
    length: 'The cut length is off the guide',
    capsuleFraction: kPapercutCutCapsuleFraction,
  );
}

/// A blueprint fold passes when crease samples cover it inside the fold zone.
PapercutScore scoreFoldGuide(PapercutCurve fold, List<PapercutCrease> creases) {
  final guide = fold.points;
  if (guide.length < 2) {
    return const PapercutScore.fail('The fold misses the guide');
  }
  final samples = sampleOffsets(guide, closed: fold.closed, spacing: _sampleMm);
  for (final sample in samples) {
    if (!_inAnyCreaseZone(sample, creases)) {
      return const PapercutScore.fail('The fold misses the guide');
    }
  }
  final guideLength = _polylineLength(
    fold.closed ? [...guide, guide.first] : guide,
  );
  if (guideLength < 1) {
    return const PapercutScore.fail('The fold misses the guide');
  }
  var matchedLength = 0.0;
  for (final crease in creases) {
    matchedLength += _lengthInFoldZone(
      [crease.a, crease.b],
      guide,
      fold.closed,
    );
  }
  final lengthError = (matchedLength - guideLength).abs() / guideLength;
  if (lengthError > kPapercutLengthSlop) {
    return const PapercutScore.fail('The fold length is off the guide');
  }
  return const PapercutScore.pass();
}

PapercutScore _scoreGuide(
  PapercutCurve guideCurve,
  List<List<Offset>> strokes, {
  required String miss,
  required String length,
  required double capsuleFraction,
}) {
  final guide = guideCurve.points;
  if (guide.length < 2) return PapercutScore.fail(miss);
  final samples = sampleOffsets(
    guide,
    closed: guideCurve.closed,
    spacing: _sampleMm,
  );
  for (final sample in samples) {
    var covered = false;
    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      if (pointInSafeZone(
        sample,
        stroke,
        closed: false,
        capsuleFraction: capsuleFraction,
      )) {
        covered = true;
        break;
      }
    }
    if (!covered) return PapercutScore.fail(miss);
  }
  final guideLength = _polylineLength(
    guideCurve.closed ? [...guide, guide.first] : guide,
  );
  if (guideLength < 1) return PapercutScore.fail(miss);
  var matchedLength = 0.0;
  for (final stroke in strokes) {
    matchedLength += _lengthInside(
      stroke,
      guide,
      closed: guideCurve.closed,
      capsuleFraction: capsuleFraction,
    );
  }
  final lengthError = (matchedLength - guideLength).abs() / guideLength;
  if (lengthError > kPapercutLengthSlop) return PapercutScore.fail(length);
  return const PapercutScore.pass();
}

List<Offset> sampleOffsets(
  List<Offset> points, {
  required bool closed,
  double spacing = _sampleMm,
}) {
  if (points.isEmpty) return const [];
  if (points.length == 1) return List<Offset>.from(points);
  final path = closed ? [...points, points.first] : points;
  final out = <Offset>[path.first];
  for (var i = 0; i < path.length - 1; i++) {
    final a = path[i];
    final b = path[i + 1];
    final dist = (b - a).distance;
    if (dist < 1e-6) continue;
    var traveled = spacing;
    while (traveled < dist - 0.05) {
      final t = traveled / dist;
      out.add(Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t));
      traveled += spacing;
    }
    if ((out.last - b).distance > 0.2) out.add(b);
  }
  return out;
}

/// Length of [points] in millimeters, matching the scorer.
double polylineLengthMm(List<Offset> points) => _polylineLength(points);

/// How much of [stroke] lies in the outline's cut zone, in millimeters.
double lengthNearOutline(List<Offset> stroke, List<Offset> target) =>
    _lengthNear(stroke, target);

double _polylineLength(List<Offset> points) {
  var length = 0.0;
  for (var i = 0; i < points.length - 1; i++) {
    length += (points[i + 1] - points[i]).distance;
  }
  return length;
}

bool _inAnyCutZone(Offset point, List<List<Offset>> cuts) {
  for (final stroke in cuts) {
    if (stroke.length < 2) continue;
    if (pointInSafeZone(
      point,
      stroke,
      closed: false,
      capsuleFraction: kPapercutCutCapsuleFraction,
    )) {
      return true;
    }
  }
  return false;
}

bool _inAnyCreaseZone(Offset point, List<PapercutCrease> creases) {
  for (final crease in creases) {
    if (pointInSafeZone(
      point,
      [crease.a, crease.b],
      closed: false,
      capsuleFraction: kPapercutFoldCapsuleFraction,
    )) {
      return true;
    }
  }
  return false;
}

bool _onCurve(
  Offset point,
  List<Offset> curve, {
  required bool closed,
  required double capsuleFraction,
}) {
  return pointInSafeZone(
    point,
    curve,
    closed: closed,
    capsuleFraction: capsuleFraction,
  );
}

double _lengthNear(List<Offset> stroke, List<Offset> target) {
  return _lengthInside(
    stroke,
    target,
    closed: true,
    capsuleFraction: kPapercutCutCapsuleFraction,
  );
}

double _lengthInFoldZone(
  List<Offset> crease,
  List<Offset> guide,
  bool guideClosed,
) {
  return _lengthInside(
    crease,
    guide,
    closed: guideClosed,
    capsuleFraction: kPapercutFoldCapsuleFraction,
  );
}

double _lengthInside(
  List<Offset> stroke,
  List<Offset> curve, {
  required bool closed,
  required double capsuleFraction,
}) {
  if (stroke.length < 2) return 0;
  final samples = sampleOffsets(stroke, closed: false, spacing: 1);
  if (samples.length < 2) return 0;
  var length = 0.0;
  for (var i = 0; i < samples.length - 1; i++) {
    final inside0 = _onCurve(
      samples[i],
      curve,
      closed: closed,
      capsuleFraction: capsuleFraction,
    );
    final inside1 = _onCurve(
      samples[i + 1],
      curve,
      closed: closed,
      capsuleFraction: capsuleFraction,
    );
    final span = (samples[i + 1] - samples[i]).distance;
    if (inside0 && inside1) {
      length += span;
    } else if (inside0 || inside1) {
      length += span * 0.5;
    }
  }
  return length;
}

List<Offset> _playerKinks(List<List<Offset>> strokes) {
  final kinks = <Offset>[];
  for (final stroke in strokes) {
    kinks.addAll(_turningKinks(stroke, closed: false));
  }
  kinks.addAll(_crossingKinks(strokes));
  kinks.addAll(_endpointKinks(strokes));
  return kinks;
}

List<Offset> _turningKinks(List<Offset> points, {required bool closed}) {
  if (points.length < 3 && !closed) return const [];
  if (points.length < 3) return const [];
  final kinks = <Offset>[];
  final count = closed ? points.length : points.length - 2;
  final start = closed ? 0 : 1;
  for (var n = 0; n < count; n++) {
    final i = start + n;
    final prev = points[(i - 1 + points.length) % points.length];
    final curr = points[i % points.length];
    final next = points[(i + 1) % points.length];
    if (_turnDegrees(prev, curr, next) >= kPapercutKinkDegrees) {
      kinks.add(curr);
    }
  }
  return kinks;
}

List<Offset> _crossingKinks(List<List<Offset>> strokes) {
  final segments = <(Offset, Offset)>[];
  for (final stroke in strokes) {
    for (var i = 0; i < stroke.length - 1; i++) {
      if ((stroke[i + 1] - stroke[i]).distance < 0.2) continue;
      segments.add((stroke[i], stroke[i + 1]));
    }
  }
  final kinks = <Offset>[];
  for (var i = 0; i < segments.length; i++) {
    for (var j = i + 1; j < segments.length; j++) {
      final hit = segmentIntersection(
        segments[i].$1,
        segments[i].$2,
        segments[j].$1,
        segments[j].$2,
      );
      if (!hit.isPoint || hit.point == null) continue;
      if (_lineAngleDegrees(
            segments[i].$2 - segments[i].$1,
            segments[j].$2 - segments[j].$1,
          ) <
          kPapercutKinkDegrees) {
        continue;
      }
      kinks.add(hit.point!);
    }
  }
  return kinks;
}

List<Offset> _endpointKinks(List<List<Offset>> strokes) {
  final ends = <(Offset point, Offset dir)>[];
  for (final stroke in strokes) {
    if (stroke.length < 2) continue;
    final firstDir = stroke[1] - stroke[0];
    final lastDir = stroke[stroke.length - 1] - stroke[stroke.length - 2];
    if (firstDir.distance > 0.2) ends.add((stroke.first, firstDir));
    if (lastDir.distance > 0.2) ends.add((stroke.last, lastDir));
  }
  final kinks = <Offset>[];
  for (var i = 0; i < ends.length; i++) {
    for (var j = i + 1; j < ends.length; j++) {
      if ((ends[i].$1 - ends[j].$1).distance > 1.5) continue;
      if (_lineAngleDegrees(ends[i].$2, ends[j].$2) < kPapercutKinkDegrees) {
        continue;
      }
      kinks.add(
        Offset(
          (ends[i].$1.dx + ends[j].$1.dx) / 2,
          (ends[i].$1.dy + ends[j].$1.dy) / 2,
        ),
      );
    }
  }
  return kinks;
}

double _turnDegrees(Offset prev, Offset curr, Offset next) {
  final incoming = curr - prev;
  final outgoing = next - curr;
  if (incoming.distance < 0.4 || outgoing.distance < 0.4) return 0;
  final dot =
      (incoming.dx * outgoing.dx + incoming.dy * outgoing.dy) /
      (incoming.distance * outgoing.distance);
  return math.acos(dot.clamp(-1.0, 1.0)) * 180 / math.pi;
}

/// Smallest angle between two undirected lines, in degrees. 0 is parallel.
double _lineAngleDegrees(Offset a, Offset b) {
  if (a.distance < 1e-6 || b.distance < 1e-6) return 0;
  final dot = (a.dx * b.dx + a.dy * b.dy) / (a.distance * b.distance);
  final acute = math.acos(dot.abs().clamp(0.0, 1.0));
  return acute * 180 / math.pi;
}

double _nearest(Offset point, List<Offset> others) {
  var best = double.infinity;
  for (final other in others) {
    final dist = (point - other).distance;
    if (dist < best) best = dist;
  }
  return best;
}
