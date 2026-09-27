import 'dart:math' as math;
import 'dart:ui';

import '../geometry/polygon_union.dart';
import '../papercut/paper.dart';
import 'blueprint.dart';

/// [radians] is counterclockwise in paper space. A clockwise quarter turn is −π/2.
Offset rotateGridPointBy(Offset point, Offset origin, double radians) {
  final delta = point - origin;
  final c = math.cos(radians);
  final s = math.sin(radians);
  return origin + Offset(delta.dx * c - delta.dy * s, delta.dx * s + delta.dy * c);
}

Offset rotateGridPoint(Offset point, Offset origin, {required bool clockwise}) {
  return rotateGridPointBy(point, origin, clockwise ? -math.pi / 2 : math.pi / 2);
}

GridStep rotateStep(GridStep step, {required bool clockwise}) {
  return rotateStepBy(
    step,
    step.paper.center,
    clockwise ? -math.pi / 2 : math.pi / 2,
  );
}

GridStep rotateStepBy(GridStep step, Offset origin, double radians) {
  return step.copyWith(
    polygons: [
      for (final polygon in step.polygons)
        [
          for (final point in polygon) rotateGridPointBy(point, origin, radians),
        ],
    ],
  );
}

PapercutSheet rotateSheet(
  PapercutSheet sheet,
  Offset origin, {
  required bool clockwise,
}) {
  return rotateSheetBy(sheet, origin, clockwise ? -math.pi / 2 : math.pi / 2);
}

PapercutSheet rotateSheetBy(PapercutSheet sheet, Offset origin, double radians) {
  Offset turn(Offset point) => rotateGridPointBy(point, origin, radians);
  return PapercutSheet(
    pieces: [
      for (final piece in sheet.pieces)
        PapercutPiece(
          id: piece.id,
          color: piece.color,
          vertices: [for (final point in piece.vertices) turn(point)],
          holes: [
            for (final hole in piece.holes) [for (final point in hole) turn(point)],
          ],
          separation: rotateGridPointBy(piece.separation, Offset.zero, radians),
        ),
    ],
    cutStrokes: [
      for (final stroke in sheet.cutStrokes) [for (final point in stroke) turn(point)],
    ],
    creases: [
      for (final crease in sheet.creases)
        PapercutCrease(
          id: crease.id,
          a: turn(crease.a),
          b: turn(crease.b),
          groupId: crease.groupId,
          angleDegrees: crease.angleDegrees,
        ),
    ],
    nextPieceId: sheet.nextPieceId,
  );
}

/// Unit cells whose centers fall inside a circle of [radius] cells.
Set<(int, int)> circleCells(int cx, int cy, int radius) {
  final cells = <(int, int)>{};
  for (var y = cy - radius; y <= cy + radius; y++) {
    for (var x = cx - radius; x <= cx + radius; x++) {
      final dx = x - cx + 0.0;
      final dy = y - cy + 0.0;
      if (dx * dx + dy * dy <= radius * radius + 1e-6) cells.add((x, y));
    }
  }
  return cells;
}

Set<(int, int)> rectangleCells(int x0, int y0, int x1, int y1) {
  final cells = <(int, int)>{};
  final left = math.min(x0, x1);
  final right = math.max(x0, x1);
  final bottom = math.min(y0, y1);
  final top = math.max(y0, y1);
  for (var y = bottom; y <= top; y++) {
    for (var x = left; x <= right; x++) {
      cells.add((x, y));
    }
  }
  return cells;
}

/// Fuses painted cells into outer polygons. Holes are dropped.
List<List<Offset>> polygonsFromCells(Set<(int, int)> cells, double spacing) {
  if (cells.isEmpty || spacing <= 0) return const [];
  final squares = [
    for (final (x, y) in cells)
      [
        Offset(x * spacing, y * spacing),
        Offset((x + 1) * spacing, y * spacing),
        Offset((x + 1) * spacing, (y + 1) * spacing),
        Offset(x * spacing, (y + 1) * spacing),
      ],
  ];
  final loops = unionPolygons(squares);
  return [
    for (final loop in loops)
      if (polygonSignedArea(loop) > 0) loop,
  ];
}

List<List<Offset>> mergeSelected(List<List<Offset>> polygons) {
  if (polygons.length < 2) return polygons;
  final loops = unionPolygons(polygons);
  final outers = [
    for (final loop in loops)
      if (polygonSignedArea(loop) > 0) loop,
  ];
  return outers.isEmpty ? polygons : outers;
}
