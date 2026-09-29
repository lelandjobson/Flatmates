import 'dart:math' as math;
import 'dart:ui';

import 'models.dart';

/// A paper piece: one region of the sheet after zero or more cuts.
///
/// Coordinates are millimeters in craft papercut, and grid units in a level.
/// This is not a blueprint piece.
class PapercutPiece {
  const PapercutPiece({
    required this.id,
    required this.color,
    required this.vertices,
    this.holes = const [],
    this.separation = Offset.zero,
  });

  final String id;
  final Color color;
  final List<Offset> vertices;
  final List<List<Offset>> holes;

  /// Display nudge so a finished cut pulls this piece off its neighbors.
  /// Cut geometry stays in grid space; only drawing uses this.
  final Offset separation;

  PapercutPiece copyWith({Offset? separation}) {
    return PapercutPiece(
      id: id,
      color: color,
      vertices: vertices,
      holes: holes,
      separation: separation ?? this.separation,
    );
  }

  PapercutPiece clone() {
    return PapercutPiece(
      id: id,
      color: color,
      vertices: List<Offset>.from(vertices),
      holes: [for (final hole in holes) List<Offset>.from(hole)],
      separation: separation,
    );
  }
}

/// A straight-edge crease. It is drawn, not folded into a mesh.
class PapercutCrease {
  const PapercutCrease({
    required this.id,
    required this.a,
    required this.b,
    required this.groupId,
    required this.angleDegrees,
  });

  final String id;
  final Offset a;
  final Offset b;
  final String groupId;
  final double angleDegrees;
}

/// Which way a folded flap faces the camera.
enum FoldFacing { toward, away, unfolded }

/// A joint between a flap and the paper it folded from.
///
/// Piece vertices stay in unfolded coordinates. [side] is the sign of the
/// cross product that marks the flap. Display reflects the flap while
/// [facing] is not [FoldFacing.unfolded].
class FoldJoint {
  const FoldJoint({
    required this.a,
    required this.b,
    required this.side,
    required this.facing,
  });

  final Offset a;
  final Offset b;
  final double side;
  final FoldFacing facing;

  FoldJoint copyWith({FoldFacing? facing}) {
    return FoldJoint(a: a, b: b, side: side, facing: facing ?? this.facing);
  }
}

/// The mark left when a fold is opened. Dark grey at 15% opacity.
class ScoreLine {
  const ScoreLine(this.a, this.b);

  final Offset a;
  final Offset b;
}

/// A pen or pencil stroke stored on the paper face that was showing.
class PaperMark {
  const PaperMark({required this.points});

  /// Unfolded paper coordinates.
  final List<Offset> points;
}

class PapercutSheet {
  const PapercutSheet({
    required this.pieces,
    this.cutStrokes = const [],
    this.creases = const [],
    this.folds = const [],
    this.scores = const [],
    this.marks = const [],
    this.nextPieceId = 1,
  });

  factory PapercutSheet.square({required Color color}) {
    final half = kPapercutSheetMm / 2;
    return PapercutSheet(
      pieces: [
        PapercutPiece(
          id: 'sheet-0',
          color: color,
          vertices: [
            Offset(-half, -half),
            Offset(half, -half),
            Offset(half, half),
            Offset(-half, half),
          ],
        ),
      ],
    );
  }

  factory PapercutSheet.empty() => const PapercutSheet(pieces: []);

  final List<PapercutPiece> pieces;
  final List<List<Offset>> cutStrokes;
  final List<PapercutCrease> creases;
  final List<FoldJoint> folds;
  final List<ScoreLine> scores;
  final List<PaperMark> marks;
  final int nextPieceId;

  PapercutSheet copyWith({
    List<PapercutPiece>? pieces,
    List<List<Offset>>? cutStrokes,
    List<PapercutCrease>? creases,
    List<FoldJoint>? folds,
    List<ScoreLine>? scores,
    List<PaperMark>? marks,
    int? nextPieceId,
  }) {
    return PapercutSheet(
      pieces: pieces ?? this.pieces,
      cutStrokes: cutStrokes ?? this.cutStrokes,
      creases: creases ?? this.creases,
      folds: folds ?? this.folds,
      scores: scores ?? this.scores,
      marks: marks ?? this.marks,
      nextPieceId: nextPieceId ?? this.nextPieceId,
    );
  }

  PapercutSheet clone() {
    return PapercutSheet(
      pieces: [for (final piece in pieces) piece.clone()],
      cutStrokes: [for (final stroke in cutStrokes) List<Offset>.from(stroke)],
      creases: List<PapercutCrease>.from(creases),
      folds: List<FoldJoint>.from(folds),
      scores: List<ScoreLine>.from(scores),
      marks: [
        for (final mark in marks)
          PaperMark(points: List<Offset>.from(mark.points)),
      ],
      nextPieceId: nextPieceId,
    );
  }
}

/// Moving-average smooth, used on exacto strokes before they are unprojected.
List<Offset> smoothOffsets(List<Offset> raw, {int window = 4}) {
  if (raw.length < 3 || window <= 0) return List<Offset>.from(raw);
  final smoothed = <Offset>[];
  for (var i = 0; i < raw.length; i++) {
    var sum = Offset.zero;
    var count = 0;
    final start = math.max(0, i - window);
    final end = math.min(raw.length - 1, i + window);
    for (var j = start; j <= end; j++) {
      sum += raw[j];
      count++;
    }
    smoothed.add(sum / count.toDouble());
  }
  return smoothed;
}

List<Offset> resampleOffsets(List<Offset> points, double spacing) {
  if (points.length < 2 || spacing <= 0) return List<Offset>.from(points);
  final out = <Offset>[points.first];
  var anchor = points.first;
  var remain = spacing;
  for (var i = 1; i < points.length; i++) {
    var from = anchor;
    final end = points[i];
    var dist = (end - from).distance;
    while (dist + 1e-6 >= remain && dist > 1e-6) {
      final t = remain / dist;
      final point = Offset(
        from.dx + (end.dx - from.dx) * t,
        from.dy + (end.dy - from.dy) * t,
      );
      out.add(point);
      from = point;
      dist = (end - from).distance;
      remain = spacing;
    }
    remain -= dist;
    anchor = end;
  }
  if ((out.last - points.last).distance > spacing * 0.25) {
    out.add(points.last);
  }
  return out;
}
