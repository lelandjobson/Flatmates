import 'dart:io';
import 'dart:math' as math;

import 'package:flatmates/geometry/geometry_2d.dart';
import 'package:flatmates/geometry/geometry_algorithms.dart';
import 'package:flatmates/gridcraft/blueprint.dart';
import 'package:flatmates/gridcraft/level_io.dart';
import 'package:flatmates/gridcraft/painter.dart';
import 'package:flatmates/gridcraft/scissor.dart';
import 'package:flatmates/gridcraft/twin_ls.dart';
import 'package:flatmates/papercut/camera.dart';
import 'package:flatmates/papercut/models.dart';
import 'package:flatmates/papercut/paper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

void main() {
  test('two Ls sit on a sheet padded by 3', () {
    final step = twinLsBlueprint().steps.single;
    expect(step.gridSpacing, 1);
    expect(step.paperMargin, 3);
    final first = polygonBounds([step.polygons.first]);
    final second = polygonBounds([step.polygons[1]]);
    expect(first.width, 3);
    expect(first.height, 2);
    expect(second.width, 3);
    expect(second.height, 2);

    final content = polygonBounds(step.polygons);
    final paper = step.paper;
    expect(paper.left, content.left - 3);
    expect(paper.top, content.top - 3);
    expect(paper.right, content.right + 3);
    expect(paper.bottom, content.bottom + 3);
  });

  test('the scissor stops at the next datum and stays locked until a split', () {
    final step = twinLsBlueprint().steps.single;
    final base = _sheet(step);
    final start = Offset(1, step.paper.top);
    final march = placeScissor(start, step.paper);
    expect(march, isNotNull);
    expect(march!.direction, const Offset(0, 1));
    expect(placeOnRing(start, base.pieces.single.vertices)!.direction, const Offset(0, 1));

    final end = march.previewEnd(step, base);
    expect(end, isNotNull);
    expect(end!.dx, closeTo(1, 1e-6));
    expect(end.dy, closeTo(0, 1e-6));

    final first = commitScissor(march: march, step: step, base: base);
    expect(first, isNotNull);
    expect(first!.march, isNotNull);
    expect(first.march!.locked, isTrue);
    expect(first.sheet.pieces, hasLength(base.pieces.length));

    var current = first.march;
    ScissorCommit? last = first;
    var guard = 0;
    while (current != null && guard < 8) {
      last = commitScissor(march: current, step: step, base: base);
      expect(last, isNotNull);
      current = last!.march;
      guard++;
    }
    expect(last!.march, isNull);
    expect(last.sheet.pieces, hasLength(2));

    final spread = spreadPieces(base, last.sheet, step.gridSpacing);
    final shifts = [for (final piece in spread.pieces) piece.separation.dx];
    expect(shifts.toSet().length, greaterThan(1));
    expect(
      (shifts.reduce(math.max) - shifts.reduce(math.min)).abs(),
      greaterThanOrEqualTo(step.gridSpacing * 4 - 1e-6),
    );
  });

  testWidgets('a finished cut paints two separated pieces', (tester) async {
    final step = twinLsBlueprint().steps.single;
    final base = _sheet(step);
    var march = placeScissor(Offset(1, step.paper.top), step.paper);
    PapercutSheet sheet = base;
    ScissorMarch? current = march;
    var guard = 0;
    while (current != null && guard < 8) {
      final commit = commitScissor(march: current, step: step, base: base);
      expect(commit, isNotNull);
      sheet = commit!.march == null
          ? spreadPieces(base, commit.sheet, step.gridSpacing)
          : commit.sheet;
      current = commit.march;
      guard++;
    }
    expect(sheet.pieces, hasLength(2));
    final boxes = [
      for (final piece in sheet.pieces) _shownBounds(piece),
    ];
    expect(boxes[0].overlaps(boxes[1]), isFalse);

    for (final polygon in step.polygons) {
      for (final piece in sheet.pieces) {
        polygonIntersection(
          Polygon2D.simple(polygon),
          Polygon2D.simple(piece.vertices),
        );
      }
    }

    final camera = PapercutCamera();
    const viewport = Size(800, 600);
    camera.frameSheet(
      viewport,
      sheetMm: math.max(step.paper.width, step.paper.height),
      center: step.paper.center,
    );
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      errors.add(details);
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 600,
          child: CustomPaint(
            painter: GridPuzzlePainter(
              camera: camera,
              step: step,
              sheet: sheet,
              march: null,
              flash: 1,
              rulerX: null,
              showRuler: false,
              selected: const {},
              painted: const {},
              ghostCells: const {},
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(errors, isEmpty);
  });

  test('any aim starts on the closest paper edge', () {
    final step = twinLsBlueprint().steps.single;
    final paper = step.paper;
    final ring = [
      paper.topLeft,
      paper.topRight,
      paper.bottomRight,
      paper.bottomLeft,
    ];
    final outside = closestGridEdgePoint(Offset(paper.left - 6, 1.4), [ring], 1);
    expect(outside, isNotNull);
    expect(outside!.dx, closeTo(paper.left, 1e-6));
    expect(outside.dy, closeTo(1, 1e-6));

    final inside = closestGridEdgePoint(const Offset(3.2, 1), [ring], 1);
    expect(inside, isNotNull);
    expect(inside!.dx, closeTo(3, 1e-6));
    expect(inside.dy == paper.top || inside.dy == paper.bottom, isTrue);
  });

  test('unit dots sit on the puzzle grid and follow a pan', () {
    expect(unitGridStride(spacing: 1, pixelsPerUnit: 20), 1);
    expect(unitGridStride(spacing: 1, pixelsPerUnit: 3), 4);
    final points = unitGridPoints(const Rect.fromLTRB(-0.2, -0.2, 2.2, 1.1), 1);
    expect(points, contains(Offset.zero));
    expect(points, contains(const Offset(2, 1)));
    for (final point in points) {
      expect(point.dx, closeTo(point.dx.roundToDouble(), 1e-9));
      expect(point.dy, closeTo(point.dy.roundToDouble(), 1e-9));
    }

    final step = twinLsBlueprint().steps.single;
    final camera = PapercutCamera();
    const viewport = Size(800, 600);
    camera.frameSheet(
      viewport,
      sheetMm: math.max(step.paper.width, step.paper.height),
      center: step.paper.center,
    );
    final before = camera.camera.projectToScreen(Vector3(1, 1, 0), viewport);
    camera.panByScreen(const Offset(30, -20), viewport);
    final after = camera.camera.projectToScreen(Vector3(1, 1, 0), viewport);
    expect(before, isNotNull);
    expect(after, isNotNull);
    expect((after! - before!).distance, greaterThan(5));
  });

  test('quarter turns land on the next canonical angle', () {
    const quarter = math.pi / 2;
    double turn(double degrees, {required bool counterclockwise}) {
      return PapercutCamera.nextQuarterTurn(
        degrees * math.pi / 180,
        counterclockwise: counterclockwise,
      );
    }

    expect(turn(0, counterclockwise: true), closeTo(quarter, 1e-9));
    expect(turn(0, counterclockwise: false), closeTo(-quarter, 1e-9));
    expect(turn(90, counterclockwise: true), closeTo(math.pi, 1e-9));
    expect(turn(20, counterclockwise: true), closeTo(quarter, 1e-9));
    expect(turn(20, counterclockwise: false), closeTo(0, 1e-9));
    expect(turn(359, counterclockwise: true), closeTo(math.pi * 2, 1e-6));
    expect(turn(359, counterclockwise: false), closeTo(math.pi * 1.5, 1e-6));
  });

  test('the blade stops on the first outline edge and follows an edge to its vertex', () {
    final step = twinLsBlueprint().steps.single;
    final sheet = _sheet(step);
    final closed = cutOutlines(step, sheet);

    final across = nextOutlineHit(
      from: Offset(2, step.paper.top),
      direction: const Offset(0, 1),
      closed: closed,
    );
    expect(across, isNotNull);
    expect(across!.dx, closeTo(2, 1e-6));
    expect(across.dy, closeTo(0, 1e-6));

    final along = nextOutlineHit(
      from: const Offset(0, 0),
      direction: const Offset(1, 0),
      closed: closed,
    );
    expect(along, isNotNull);
    expect(along!.dx, closeTo(3, 1e-6));
    expect(along.dy, closeTo(0, 1e-6));
  });

  test('a saved level reloads spacing, margin, and polygons', () async {
    final directory = await Directory.systemTemp.createTemp('grid-levels');
    final store = LevelStore(directory: directory);
    final level = twinLsBlueprint();
    await store.save(level);
    final loaded = await store.loadAll();
    expect(loaded, hasLength(1));
    final step = loaded.single.steps.single;
    expect(step.gridSpacing, level.steps.single.gridSpacing);
    expect(step.paperMargin, level.steps.single.paperMargin);
    expect(step.polygons, level.steps.single.polygons);
  });
}

Rect _shownBounds(PapercutPiece piece) {
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = -double.infinity;
  var maxY = -double.infinity;
  for (final point in piece.vertices) {
    final shown = point + piece.separation;
    minX = math.min(minX, shown.dx);
    minY = math.min(minY, shown.dy);
    maxX = math.max(maxX, shown.dx);
    maxY = math.max(maxY, shown.dy);
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

PapercutSheet _sheet(GridStep step) {
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
