import 'dart:math' as math;
import 'dart:ui';

import '../papercut/paper.dart';
import 'blueprint.dart';

/// What a blueprint edge asks of the paper.
enum CriterionKind {
  /// A penned edge. Met where a paper piece outline runs along it.
  cut,

  /// A penciled edge. Met where a fold or a score runs along it.
  fold,
}

/// One edge of a blueprint piece and the tool work it needs.
class EdgeCriterion {
  const EdgeCriterion({
    required this.ring,
    required this.edge,
    required this.a,
    required this.b,
    required this.kind,
  });

  /// Blueprint piece index in [GridStep.polygons].
  final int ring;

  /// Edge index within that ring.
  final int edge;
  final Offset a;
  final Offset b;
  final CriterionKind kind;

  double get length => (b - a).distance;
}

/// Every criterion on [step], ring by ring. An edge style picks the kind.
List<List<EdgeCriterion>> stepCriteria(GridStep step) {
  return [
    for (var ring = 0; ring < step.polygons.length; ring++)
      [
        for (var edge = 0; edge < step.edgeCountOf(ring); edge++)
          EdgeCriterion(
            ring: ring,
            edge: edge,
            a: step.polygons[ring][edge],
            b: step.polygons[ring][(edge + 1) % step.polygons[ring].length],
            kind: step.edgeStyleOf(ring)[edge] == EdgeStyle.penciled
                ? CriterionKind.fold
                : CriterionKind.cut,
          ),
      ],
  ];
}

/// A criterion and the parts of it the sheet already satisfies.
class CriterionProgress {
  const CriterionProgress(this.criterion, this.met);

  final EdgeCriterion criterion;

  /// Model-space spans along the edge, sorted and merged.
  final List<(Offset, Offset)> met;

  double get metLength {
    var total = 0.0;
    for (final span in met) {
      total += (span.$2 - span.$1).distance;
    }
    return total;
  }

  bool get done => metLength >= criterion.length - _eps;
}

/// Criteria progress for every blueprint piece on a level.
class BlueprintProgress {
  const BlueprintProgress(this.rings);

  /// Parallel to [GridStep.polygons].
  final List<List<CriterionProgress>> rings;

  /// A blueprint piece is complete when every edge criterion is met.
  bool complete(int ring) {
    if (ring < 0 || ring >= rings.length) return false;
    final edges = rings[ring];
    return edges.isNotEmpty && edges.every((edge) => edge.done);
  }

  CriterionProgress? edge(int ring, int edge) {
    if (ring < 0 || ring >= rings.length) return null;
    final edges = rings[ring];
    if (edge < 0 || edge >= edges.length) return null;
    return edges[edge];
  }
}

/// Measures [step]'s criteria against the cuts and folds on [sheet].
///
/// Everything is compared in model space, so a piece that stepped apart
/// still meets the edge it was cut along.
BlueprintProgress blueprintProgress(GridStep step, PapercutSheet sheet) {
  final cuts = <(Offset, Offset)>[
    for (final piece in sheet.pieces) ...[
      ..._ringSegments(piece.vertices),
      for (final hole in piece.holes) ..._ringSegments(hole),
    ],
  ];
  final folds = <(Offset, Offset)>[
    for (final joint in sheet.folds) (joint.a, joint.b),
    for (final score in sheet.scores) (score.a, score.b),
  ];
  return BlueprintProgress([
    for (final ring in stepCriteria(step))
      [
        for (final criterion in ring)
          CriterionProgress(
            criterion,
            coveredSpans(
              criterion.a,
              criterion.b,
              criterion.kind == CriterionKind.cut ? cuts : folds,
            ),
          ),
      ],
  ]);
}

/// Parts of [a]–[b] that lie on any collinear segment in [lines].
List<(Offset, Offset)> coveredSpans(
  Offset a,
  Offset b,
  Iterable<(Offset, Offset)> lines,
) {
  final delta = b - a;
  final length = delta.distance;
  if (length < _eps) return const [];
  final unit = delta / length;
  double along(Offset point) =>
      (point.dx - a.dx) * unit.dx + (point.dy - a.dy) * unit.dy;
  double off(Offset point) =>
      ((point.dx - a.dx) * unit.dy - (point.dy - a.dy) * unit.dx).abs();

  final intervals = <(double, double)>[];
  for (final line in lines) {
    if (off(line.$1) > _eps || off(line.$2) > _eps) continue;
    final s = along(line.$1);
    final t = along(line.$2);
    final lo = math.max(0.0, math.min(s, t));
    final hi = math.min(length, math.max(s, t));
    if (hi - lo > _eps) intervals.add((lo, hi));
  }
  if (intervals.isEmpty) return const [];
  intervals.sort((x, y) => x.$1.compareTo(y.$1));
  final merged = <(double, double)>[intervals.first];
  for (final next in intervals.skip(1)) {
    final last = merged.last;
    if (next.$1 <= last.$2 + _eps) {
      merged[merged.length - 1] = (last.$1, math.max(last.$2, next.$2));
    } else {
      merged.add(next);
    }
  }
  return [for (final span in merged) (a + unit * span.$1, a + unit * span.$2)];
}

Iterable<(Offset, Offset)> _ringSegments(List<Offset> ring) sync* {
  for (var i = 0; i < ring.length; i++) {
    yield (ring[i], ring[(i + 1) % ring.length]);
  }
}

const _eps = 1e-4;
