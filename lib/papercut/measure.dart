import 'dart:ui';

import '../geometry/geometry_algorithms.dart';
import 'cut_graph.dart';
import 'models.dart';
import 'paper.dart';
import 'safe_zone.dart';
import 'score.dart';

/// One drawable run. [millimeters] is the integer length shown on the edge.
class PapercutMeasureEdge {
  const PapercutMeasureEdge({required this.points, required this.millimeters});

  final List<Offset> points;
  final int millimeters;
}

/// A coverage gap or a cut that has left the outline.
class PapercutMeasureIssue {
  const PapercutMeasureIssue({
    required this.span,
    required this.mark,
    required this.nearest,
    required this.millimeters,
    required this.gap,
  });

  final List<Offset> span;
  final Offset mark;
  final Offset nearest;

  /// Distance from the outline, rounded to a millimeter.
  final int millimeters;

  /// True when the outline has no cut nearby. False when a cut has left it.
  final bool gap;
}

/// Outline length against the length the scorer counts.
class PapercutOutlineMeasure {
  const PapercutOutlineMeasure({
    required this.outlineMm,
    required this.countedMm,
  });

  final int outlineMm;
  final int countedMm;

  bool get off =>
      outlineMm > 0 &&
      (countedMm - outlineMm).abs() / outlineMm > kPapercutLengthSlop;
}

class PapercutMeasure {
  const PapercutMeasure({
    this.blueprint = const [],
    this.graph = const [],
    this.nearest = const [],
    this.issues = const [],
    this.outlines = const [],
  });

  final List<PapercutMeasureEdge> blueprint;
  final List<PapercutMeasureEdge> graph;
  final List<PapercutMeasureEdge> nearest;
  final List<PapercutMeasureIssue> issues;
  final List<PapercutOutlineMeasure> outlines;
}

const PapercutMeasure _empty = PapercutMeasure();

/// Lengths and mismatches for the dev overlay. Uses the scorer's zone length.
PapercutMeasure buildPapercutMeasure(PapercutStep step, PapercutSheet sheet) {
  final geometry = step.geometry;
  if (geometry is! PapercutCurveGeometry) return _empty;

  final blueprint = <PapercutMeasureEdge>[];
  final nearest = <PapercutMeasureEdge>[];
  final issues = <PapercutMeasureIssue>[];
  final outlines = <PapercutOutlineMeasure>[];

  for (final curve in geometry.curves) {
    blueprint.addAll(_chainEdges(curve.points, closed: curve.closed));
  }

  for (final curve in geometry.cutCurves) {
    final loop = [...curve.points, curve.points.first];
    final outline = polylineLengthMm(loop);
    var counted = 0.0;
    List<Offset>? closest;
    var closestNear = -1.0;
    for (final stroke in sheet.cutStrokes) {
      if (stroke.length < 2) continue;
      final near = lengthNearOutline(stroke, curve.points);
      counted += near;
      if (near > closestNear) {
        closestNear = near;
        closest = stroke;
      }
    }
    outlines.add(
      PapercutOutlineMeasure(
        outlineMm: outline.round(),
        countedMm: counted.round(),
      ),
    );
    if (closest != null && closestNear >= 8) {
      nearest.addAll(_zoneSpans(closest, curve.points));
    }
    issues.addAll(_gapIssues(loop, sheet.cutStrokes));
  }

  for (final stroke in sheet.cutStrokes) {
    issues.addAll(_strayIssues(stroke, geometry.cutCurves));
  }

  return PapercutMeasure(
    blueprint: blueprint,
    graph: _graphEdges(sheet.cutStrokes),
    nearest: nearest,
    issues: issues,
    outlines: outlines,
  );
}

List<PapercutMeasureEdge> _graphEdges(List<List<Offset>> strokes) {
  final joints = buildCutGraph(strokes).joints;
  final edges = <PapercutMeasureEdge>[];
  for (final stroke in strokes) {
    if (stroke.length < 2) continue;
    final total = polylineLengthMm(stroke);
    final marks = <double>[0, total];
    for (final joint in joints) {
      final hit = closestPointOnPolyline(joint, stroke);
      if (hit.distance > 0.5 || hit.edgeIndex == null) continue;
      marks.add(_arcLength(stroke, hit.edgeIndex!, hit.parameter));
    }
    marks.sort();
    var previous = marks.first;
    for (final mark in marks.skip(1)) {
      if (mark - previous < 1) continue;
      final slice = _slice(stroke, previous, mark);
      if (slice.length >= 2) {
        edges.add(
          PapercutMeasureEdge(
            points: slice,
            millimeters: (mark - previous).round(),
          ),
        );
      }
      previous = mark;
    }
  }
  return edges;
}

List<PapercutMeasureEdge> _chainEdges(
  List<Offset> points, {
  required bool closed,
}) {
  if (points.length < 2) return const [];
  final path = closed ? [...points, points.first] : points;
  final edges = <PapercutMeasureEdge>[];
  final chain = <Offset>[path.first];
  var chainLength = 0.0;

  void flush() {
    if (chain.length < 2 || chainLength < 1) {
      chainLength = 0;
      if (chain.isEmpty) chain.add(path.first);
      return;
    }
    edges.add(
      PapercutMeasureEdge(
        points: List<Offset>.of(chain),
        millimeters: chainLength.round(),
      ),
    );
    final last = chain.last;
    chain
      ..clear()
      ..add(last);
    chainLength = 0;
  }

  for (var i = 0; i < path.length - 1; i++) {
    final a = path[i];
    final b = path[i + 1];
    final length = (b - a).distance;
    if (length < 1e-6) continue;
    if (length >= 12 && chainLength >= 1) flush();
    chain.add(b);
    chainLength += length;
    if (length >= 12) flush();
  }
  flush();
  return edges;
}

List<PapercutMeasureEdge> _zoneSpans(List<Offset> stroke, List<Offset> target) {
  final samples = sampleOffsets(stroke, closed: false, spacing: 1);
  final spans = <PapercutMeasureEdge>[];
  final current = <Offset>[];

  void flush() {
    if (current.length < 2) {
      current.clear();
      return;
    }
    final length = polylineLengthMm(current);
    if (length >= 4) {
      spans.add(
        PapercutMeasureEdge(
          points: List<Offset>.of(current),
          millimeters: length.round(),
        ),
      );
    }
    current.clear();
  }

  for (final sample in samples) {
    final inside = pointInSafeZone(
      sample,
      target,
      closed: true,
      capsuleFraction: kPapercutCutCapsuleFraction,
    );
    if (inside) {
      current.add(sample);
    } else {
      flush();
    }
  }
  flush();
  return spans;
}

List<PapercutMeasureIssue> _gapIssues(
  List<Offset> loop,
  List<List<Offset>> cuts,
) {
  final samples = sampleOffsets(loop, closed: false, spacing: 3);
  return _runs(
    samples,
    gap: true,
    distanceOf: (point) => _nearestCut(point, cuts),
    tooFar: (hit) => hit.distance > kPapercutToleranceMm,
  );
}

List<PapercutMeasureIssue> _strayIssues(
  List<Offset> stroke,
  Iterable<PapercutCurve> outlines,
) {
  if (outlines.isEmpty || stroke.length < 2) return const [];
  final samples = sampleOffsets(stroke, closed: false, spacing: 4);
  return _runs(
    samples,
    gap: false,
    distanceOf: (point) {
      var best = _Hit(point, double.infinity);
      for (final outline in outlines) {
        final loop = [...outline.points, outline.points.first];
        final hit = closestPointOnPolyline(point, loop);
        if (hit.distance < best.distance) best = _Hit(hit.point, hit.distance);
      }
      return best;
    },
    tooFar: (hit) => hit.distance > kPapercutToleranceMm,
  );
}

List<PapercutMeasureIssue> _runs(
  List<Offset> samples, {
  required bool gap,
  required _Hit Function(Offset point) distanceOf,
  required bool Function(_Hit hit) tooFar,
}) {
  final issues = <PapercutMeasureIssue>[];
  final span = <Offset>[];
  Offset? worst;
  Offset? nearest;
  var worstDistance = 0.0;

  void flush() {
    final worstPoint = worst;
    final nearestPoint = nearest;
    if (span.length < 2 || worstPoint == null || nearestPoint == null) {
      span.clear();
      worst = null;
      return;
    }
    if (polylineLengthMm(span) >= 4 && worstDistance >= 4) {
      issues.add(
        PapercutMeasureIssue(
          span: List<Offset>.of(span),
          mark: worstPoint,
          nearest: nearestPoint,
          millimeters: worstDistance.isFinite ? worstDistance.round() : -1,
          gap: gap,
        ),
      );
    }
    span.clear();
    worst = null;
    worstDistance = 0;
  }

  for (final sample in samples) {
    final hit = distanceOf(sample);
    if (!tooFar(hit)) {
      flush();
      continue;
    }
    span.add(sample);
    if (hit.distance >= worstDistance) {
      worstDistance = hit.distance;
      worst = sample;
      nearest = hit.point;
    }
  }
  flush();
  return issues;
}

_Hit _nearestCut(Offset point, List<List<Offset>> cuts) {
  var best = _Hit(point, double.infinity);
  for (final stroke in cuts) {
    if (stroke.length < 2) continue;
    final hit = closestPointOnPolyline(point, stroke);
    if (hit.distance < best.distance) best = _Hit(hit.point, hit.distance);
  }
  return best;
}

double _arcLength(List<Offset> points, int edgeIndex, double t) {
  var length = 0.0;
  for (var i = 0; i < edgeIndex && i < points.length - 1; i++) {
    length += (points[i + 1] - points[i]).distance;
  }
  if (edgeIndex < points.length - 1) {
    length += (points[edgeIndex + 1] - points[edgeIndex]).distance * t;
  }
  return length;
}

List<Offset> _slice(List<Offset> points, double start, double end) {
  final out = <Offset>[];
  var traveled = 0.0;
  for (var i = 0; i < points.length - 1; i++) {
    final a = points[i];
    final b = points[i + 1];
    final span = (b - a).distance;
    if (span < 1e-6) continue;
    final next = traveled + span;
    if (next < start) {
      traveled = next;
      continue;
    }
    if (out.isEmpty) out.add(_lerp(a, b, (start - traveled) / span));
    if (next >= end) {
      out.add(_lerp(a, b, (end - traveled) / span));
      break;
    }
    out.add(b);
    traveled = next;
  }
  return out;
}

Offset _lerp(Offset a, Offset b, double t) {
  final clamped = t.clamp(0.0, 1.0);
  return Offset(a.dx + (b.dx - a.dx) * clamped, a.dy + (b.dy - a.dy) * clamped);
}

class _Hit {
  const _Hit(this.point, this.distance);

  final Offset point;
  final double distance;
}
