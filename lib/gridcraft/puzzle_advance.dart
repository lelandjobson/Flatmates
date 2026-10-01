import 'dart:math' as math;
import 'dart:ui';

import '../papercut/paper.dart';
import 'blueprint.dart';
import 'rules.dart';

/// World direction that points to the right of the screen.
///
/// Roll 0 keeps world +Y toward the top, so screen-right is world +X.
Offset screenRight(double roll) => Offset(math.cos(roll), -math.sin(roll));

/// Half of the visible width, in the same units as [framedHalfHeight].
double visibleHalfWidth({
  required double framedHalfHeight,
  required Size viewport,
}) {
  if (viewport.height < 2 || viewport.width < 2) return framedHalfHeight;
  return framedHalfHeight * (viewport.width / viewport.height);
}

/// Where to park the next puzzle so it starts offscreen, to the right of the
/// pieces that are already on the sheet.
///
/// The returned offset is added to the next puzzle's authored coordinates.
/// [occupied] are those piece positions, including separation. [right] is a
/// unit vector. [halfWidth] is the visible half-width along that vector.
Offset placeNextPuzzle({
  required Iterable<Offset> occupied,
  required Rect nextPaper,
  required Offset lookAt,
  required Offset right,
  required double halfWidth,
  required double padding,
}) {
  var occupiedMax = -double.infinity;
  for (final point in occupied) {
    occupiedMax = math.max(occupiedMax, _dot(point, right));
  }
  if (occupiedMax.isInfinite) occupiedMax = _dot(lookAt, right);
  final screenEdge = _dot(lookAt, right) + halfWidth;
  final anchor = math.max(occupiedMax, screenEdge);
  var nextMin = double.infinity;
  for (final corner in [
    nextPaper.topLeft,
    nextPaper.topRight,
    nextPaper.bottomRight,
    nextPaper.bottomLeft,
  ]) {
    nextMin = math.min(nextMin, _dot(corner, right));
  }
  return right * (anchor + padding - nextMin);
}

/// Paper positions as they are drawn, separation included.
Iterable<Offset> drawnPiecePoints(Iterable<PapercutPiece> pieces) sync* {
  for (final piece in pieces) {
    for (final point in piece.vertices) {
      yield point + piece.separation;
    }
  }
}

/// Authored level moved by [delta]. Edge styles and tool budgets stay put.
GridStep shiftStep(GridStep step, Offset delta) {
  if (delta == Offset.zero) return step;
  Offset move(Offset point) => point + delta;
  final rules = step.rules;
  return step.copyWith(
    polygons: [
      for (final ring in step.polygons) [for (final point in ring) move(point)],
    ],
    rules: rules.copyWith(
      forbidden: [for (final point in rules.forbidden) move(point)],
      colors: [
        for (final mark in rules.colors)
          ColorMark(move(mark.point), mark.color),
      ],
      numbers: [
        for (final mark in rules.numbers)
          OrderMark(move(mark.point), mark.number),
      ],
      arrows: [
        for (final edge in rules.arrows) GridEdge(move(edge.a), move(edge.b)),
      ],
      docks: [for (final point in rules.docks) move(point)],
      links: [
        for (final mark in rules.links) LinkMark(move(mark.point), mark.pair),
      ],
      seams: [
        for (final edge in rules.seams) GridEdge(move(edge.a), move(edge.b)),
      ],
    ),
    permutation: step.permutation.copyWith(
      noFold: [
        for (final zone in step.permutation.noFold)
          [for (final point in zone) move(point)],
      ],
    ),
  );
}

/// Sheet geometry moved by [delta]. Separation is a display nudge and stays.
PapercutSheet shiftSheet(PapercutSheet sheet, Offset delta) {
  if (delta == Offset.zero) return sheet;
  return sheet.copyWith(
    pieces: [
      for (final piece in sheet.pieces)
        PapercutPiece(
          id: piece.id,
          color: piece.color,
          backColor: piece.backColor,
          vertices: [for (final point in piece.vertices) point + delta],
          holes: [
            for (final hole in piece.holes)
              [for (final point in hole) point + delta],
          ],
          separation: piece.separation,
        ),
    ],
  );
}

double _dot(Offset point, Offset axis) =>
    point.dx * axis.dx + point.dy * axis.dy;
