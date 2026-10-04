import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flatmates/geometry/geometry_2d.dart';
import 'package:flatmates/geometry/geometry_algorithms.dart';
import 'package:flatmates/geometry/polygon_union.dart';
import 'package:flatmates/gridcraft/blueprint.dart';
import 'package:flatmates/gridcraft/level_io.dart';
import 'package:flatmates/gridcraft/painter.dart';
import 'package:flatmates/gridcraft/rules.dart';
import 'package:flatmates/gridcraft/scissor.dart';
import 'package:flatmates/gridcraft/twin_ls.dart';
import 'package:flatmates/papercut/camera.dart';
import 'package:flatmates/papercut/models.dart';
import 'package:flatmates/papercut/paper.dart';
import 'package:flatmates/screens/grid_puzzle_view.dart';
import 'package:flatmates/ui/fm_theme.dart';
import 'package:flatmates/ui/game/view_crosshair.dart';
import 'package:flatmates/gridcraft/scissor_glyph.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

void main() {
  test('two Ls sit on a sheet padded by 2', () {
    final step = twinLsBlueprint().steps.single;
    expect(step.gridSpacing, 1);
    expect(step.paperMargin, 2);
    final first = polygonBounds([step.polygons.first]);
    final second = polygonBounds([step.polygons[1]]);
    expect(first.width, 3);
    expect(first.height, 2);
    expect(second.width, 3);
    expect(second.height, 2);

    final content = polygonBounds(step.polygons);
    final paper = step.paper;
    expect(paper.left, content.left - 2);
    expect(paper.top, content.top - 2);
    expect(paper.right, content.right + 2);
    expect(paper.bottom, content.bottom + 2);
  });

  test('a scissor segment cannot enter a blueprint piece interior', () {
    const ring = [Offset(0, 0), Offset(2, 0), Offset(2, 2), Offset(0, 2)];
    final step = GridStep(id: 'box', label: 'Box', polygons: [ring]);
    final sheet = PapercutSheet(
      pieces: [
        PapercutPiece(
          id: 'paper',
          color: const Color(0xFFFFF3B0),
          vertices: const [
            Offset(-2, -2),
            Offset(4, -2),
            Offset(4, 4),
            Offset(-2, 4),
          ],
        ),
      ],
    );
    final hit = nextOutlineHit(
      from: const Offset(-1, 1),
      direction: const Offset(1, 0),
      closed: cutOutlines(step, sheet),
    );
    expect(hit, isNotNull);
    expect(hit!.dx, closeTo(0, 1e-6));
    expect(
      segmentEntersBlueprintInterior(const Offset(-1, 1), hit, step.polygons),
      isFalse,
    );
    expect(
      segmentEntersBlueprintInterior(
        const Offset(-1, 1),
        const Offset(1, 1),
        step.polygons,
      ),
      isTrue,
    );
  });

  test('cutting through a blueprint piece is a failure of that piece', () {
    const ring = [Offset(0, 0), Offset(2, 0), Offset(2, 2), Offset(0, 2)];
    const other = [Offset(4, 0), Offset(6, 0), Offset(6, 2), Offset(4, 2)];
    final step = GridStep(
      id: 'box',
      label: 'Box',
      polygons: const [
        ring,
        other,
        [Offset(0, 3), Offset(2, 3)],
      ],
      ringClosed: const [true, true, false],
    );
    expect(
      piercedBlueprint(step, const Offset(-1, 1), const Offset(0, 1)),
      isNull,
    );
    expect(
      piercedBlueprint(step, const Offset(0, 0), const Offset(2, 0)),
      isNull,
    );
    expect(piercedBlueprint(step, const Offset(0, 1), const Offset(2, 1)), 0);
    expect(piercedBlueprint(step, const Offset(4, 1), const Offset(6, 1)), 1);
    expect(
      piercedBlueprint(step, const Offset(0, 3), const Offset(2, 3)),
      isNull,
    );
  });

  test(
    'the scissor stops at the next datum and stays locked until a split',
    () {
      final step = twinLsBlueprint().steps.single;
      final base = _sheet(step);
      final start = Offset(1, step.paper.top);
      final march = placeScissor(start, step.paper);
      expect(march, isNotNull);
      expect(march!.direction, const Offset(0, 1));
      expect(
        placeOnRing(start, base.pieces.single.vertices)!.direction,
        const Offset(0, 1),
      );

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
    },
  );

  test('a fresh cut edge faces straight into its piece', () {
    final step = twinLsBlueprint().steps.single;
    final base = _sheet(step);
    final vertical = _splitAcross(
      step,
      base,
      const Offset(-1, 0),
      vertical: true,
    );
    final horizontal = _splitAcross(
      step,
      base,
      const Offset(0, 3),
      vertical: false,
    );
    for (final sheet in [vertical, horizontal]) {
      expect(sheet.pieces, hasLength(2));
      for (final piece in sheet.pieces) {
        final edge = _freshEdge(piece.vertices, step.paper);
        expect(edge, isNotNull, reason: piece.vertices.toString());
        final from = edge!;
        final heading = openingHeading(from, step.paper, ring: piece.vertices);
        expect(heading.dx == 0 || heading.dy == 0, isTrue, reason: '$heading');
        expect(
          isInsidePolygon(from + heading * 0.2, piece.vertices),
          isTrue,
          reason: 'heading $heading from $from on ${piece.vertices}',
        );
        final centerAim = placeAtEntry(from, step.paper).direction;
        if (!_stepsInto(from, centerAim, piece.vertices)) {
          expect(heading, isNot(centerAim));
        }
        final end = nextOutlineHit(
          from: from,
          direction: heading,
          closed: [piece.vertices, ...step.closedPolygons],
          open: openBlueprint(step),
        );
        expect(end, isNotNull);
        final delta = end! - from;
        if (heading.dx.abs() > 0.5) {
          expect(delta.dy.abs(), lessThan(1e-6));
        } else {
          expect(delta.dx.abs(), lessThan(1e-6));
        }
        for (final vertex in piece.vertices) {
          expect(
            (end - vertex).distance,
            greaterThan(0.25),
            reason: 'cut from $from along $heading landed on corner $vertex',
          );
        }
      }
    }
  });

  test('an opening cut follows the untitled linework angle', () {
    GridStep load(String path) {
      return GridBlueprint.fromJson(
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>,
      ).steps.single;
    }

    bool axis(Offset heading) =>
        heading.dx.abs() < 1e-4 || heading.dy.abs() < 1e-4;
    bool parallel(Offset heading, Offset edge) {
      final cross = heading.dx * edge.dy - heading.dy * edge.dx;
      return cross.abs() < 1e-4;
    }

    final gems = load('levels/puzzles/triple-shape.json');
    for (final gem in gems.rules.colors) {
      final heading = headingAlongLinework(
        aim: gem.point,
        from: gem.point,
        step: gems,
      );
      expect(heading, isNotNull, reason: '${gem.point}');
      expect(axis(heading!), isTrue, reason: '$heading at ${gem.point}');
      final center = gems.paper.center - gem.point;
      final centerUnit = center / center.distance;
      expect(
        (heading - centerUnit).distance,
        greaterThan(0.2),
        reason: 'gem ${gem.point} still aims at the sheet center',
      );
    }

    final diagonal = load('levels/puzzles/puzzle-1790710681492.json');
    const onStroke = Offset(1, 0);
    final from = closestPieceEdge(
      aim: onStroke,
      pieces: [
        PapercutPiece(
          id: 'paper',
          color: const Color(0xFFFFF3B0),
          vertices: [
            diagonal.paper.topLeft,
            diagonal.paper.topRight,
            diagonal.paper.bottomRight,
            diagonal.paper.bottomLeft,
          ],
        ),
      ],
      spacing: diagonal.gridSpacing,
    );
    expect(from, isNotNull);
    final slant = headingAlongLinework(
      aim: onStroke,
      from: from!.model,
      step: diagonal,
    );
    expect(slant, isNotNull);
    expect(parallel(slant!, const Offset(1, 1)), isTrue, reason: '$slant');
    expect(
      headingAlongLinework(
        aim: diagonal.paper.topLeft,
        from: diagonal.paper.topLeft,
        step: diagonal,
      ),
      isNull,
    );
  });

  test(
    'a completed blueprint piece stays on the outline while the scrap moves',
    () {
      const color = Color(0xFFFFF3B0);
      final before = PapercutSheet(
        pieces: [
          PapercutPiece(
            id: 'sheet',
            color: color,
            vertices: const [
              Offset(0, 0),
              Offset(4, 0),
              Offset(4, 2),
              Offset(0, 2),
            ],
          ),
        ],
      );
      final after = PapercutSheet(
        pieces: [
          PapercutPiece(
            id: 'island',
            color: color,
            vertices: const [
              Offset(0, 0),
              Offset(2, 0),
              Offset(2, 2),
              Offset(0, 2),
            ],
          ),
          PapercutPiece(
            id: 'scrap',
            color: color,
            vertices: const [
              Offset(2, 0),
              Offset(4, 0),
              Offset(4, 2),
              Offset(2, 2),
            ],
          ),
        ],
      );
      final spread = layoutAfterSplit(before, after, 1, finished: {'island'});
      final stayed = layoutAfterSplit(
        before,
        after,
        1,
        finished: {'island'},
        winning: true,
      );
      expect(stayed.pieces[0].separation, Offset.zero);
      expect(stayed.pieces[1].separation, Offset.zero);
      expect(spread.pieces[0].id, 'island');
      expect(spread.pieces[0].separation, Offset.zero);
      expect(spread.pieces[1].separation, isNot(Offset.zero));
      expect(
        _shownBounds(spread.pieces[0]).overlaps(_shownBounds(spread.pieces[1])),
        isFalse,
      );
    },
  );

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
    final boxes = [for (final piece in sheet.pieces) _shownBounds(piece)];
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
    final outside = closestGridEdgePoint(Offset(paper.left - 6, 1.4), [
      ring,
    ], 1);
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

  test(
    'the blade stops on the first outline edge and follows an edge to its vertex',
    () {
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
    },
  );

  test('a diamond corner follows its edges instead of the grid', () {
    const diamond = [Offset(1, 0), Offset(0, 1), Offset(-1, 0), Offset(0, -1)];
    final corner = lineworkDirections(
      at: const Offset(1, 0),
      closed: const [diamond],
    );
    expect(corner, hasLength(4));
    final down = const Offset(-1, -1);
    final up = const Offset(-1, 1);
    expect(_hasRay(corner, down), isTrue);
    expect(_hasRay(corner, -down), isTrue);
    expect(_hasRay(corner, up), isTrue);
    expect(_hasRay(corner, -up), isTrue);
    expect(_hasRay(corner, const Offset(1, 0)), isFalse);
    expect(_hasRay(corner, const Offset(0, 1)), isFalse);

    final cuts = forwardCuts(
      from: const Offset(1, 0),
      forward: const Offset(1, -1),
      directions: corner,
      closed: const [diamond],
    );
    expect(_hasDirection(cuts, up / math.sqrt(2)), isFalse);
    final along = cutFacing(cuts, down);
    expect(along, isNotNull);
    expect(along!.end.dx, closeTo(0, 1e-6));
    expect(along.end.dy, closeTo(-1, 1e-6));

    final midway = lineworkDirections(
      at: const Offset(0.5, 0.5),
      closed: const [diamond],
      open: const [
        [Offset(0.5, 0), Offset(0.5, 0.5)],
      ],
    );
    expect(midway, hasLength(4));
    expect(_hasRay(midway, const Offset(0, 1)), isTrue);
    expect(_hasRay(midway, const Offset(0, -1)), isTrue);
    expect(_hasRay(midway, up), isTrue);
    expect(_hasRay(midway, down), isFalse);
  });

  test('the untitled Z diagonal can be entered from the bar that meets it', () {
    final step = GridBlueprint.fromJson(
      jsonDecode(
            File('levels/puzzles/puzzle-1790710681492.json').readAsStringSync(),
          )
          as Map<String, dynamic>,
    ).steps.single;
    final sheet = _sheet(step);
    final closed = cutOutlines(step, sheet);
    const corner = Offset(0, -1);
    final cuts = forwardCuts(
      from: corner,
      forward: const Offset(-1, 0),
      directions: lineworkDirections(at: corner, closed: closed),
      closed: closed,
      boundary: [sheet.pieces.single.vertices],
    );
    final into = cutFacing(cuts, const Offset(1, 1));
    expect(into, isNotNull, reason: '$cuts');
    expect(into!.end.dx, closeTo(3, 1e-6));
    expect(into.end.dy, closeTo(2, 1e-6));
    expect(_hasDirection(cuts, const Offset(1, 0)), isFalse);
  });

  test('paper turns stay on the cut and ignore a rolled camera', () {
    final turns = paperTurnDirections(const Offset(0, 1));
    expect(turns, hasLength(3));
    expect(turns.first, const Offset(0, 1));
    expect(turns[1], const Offset(-1, 0));
    expect(turns[2], const Offset(1, 0));

    final step = twinLsBlueprint().steps.single;
    final sheet = _sheet(step);
    final cuts = forwardCuts(
      from: const Offset(0, 0),
      forward: const Offset(0, 1),
      directions: turns,
      closed: cutOutlines(step, sheet),
    );
    final rolled = Offset(math.sin(0.4), math.cos(0.4));
    final chosen = mostForwardCut(cuts, rolled);
    expect(chosen, isNotNull);
    expect(chosen!.direction.dx.abs(), lessThan(1e-6));
    expect(chosen.direction.dy, closeTo(1, 1e-6));
  });

  test('forward cuts keep every screen cardinal except the reverse', () {
    final step = twinLsBlueprint().steps.single;
    final sheet = _sheet(step);
    final closed = cutOutlines(step, sheet);
    const cardinals = [
      Offset(0, 1),
      Offset(0, -1),
      Offset(1, 0),
      Offset(-1, 0),
    ];

    final paperEdge = [sheet.pieces.single.vertices];
    final arrived = forwardCuts(
      from: Offset(2, step.paper.top),
      forward: const Offset(0, 1),
      directions: cardinals,
      closed: closed,
      boundary: paperEdge,
    );
    expect(_hasDirection(arrived, const Offset(0, 1)), isTrue);
    expect(_hasDirection(arrived, const Offset(1, 0)), isFalse);
    expect(_hasDirection(arrived, const Offset(-1, 0)), isFalse);
    expect(_hasDirection(arrived, const Offset(0, -1)), isFalse);
    final ahead = cutFacing(arrived, const Offset(0, 1));
    expect(ahead, isNotNull);
    expect(ahead!.end.dx, closeTo(2, 1e-6));
    expect(ahead.end.dy, closeTo(0, 1e-6));

    final along = forwardCuts(
      from: const Offset(0, 0),
      forward: const Offset(0, 1),
      directions: cardinals,
      closed: closed,
    );
    final bottom = cutFacing(along, const Offset(1, 0));
    expect(bottom, isNotNull);
    expect(bottom!.end.dx, closeTo(3, 1e-6));
    expect(bottom.end.dy, closeTo(0, 1e-6));

    final leaving = forwardCuts(
      from: Offset(2, step.paper.top),
      forward: const Offset(1, 0),
      directions: cardinals,
      closed: closed,
      boundary: paperEdge,
    );
    expect(_hasDirection(leaving, const Offset(1, 0)), isFalse);
    expect(_hasDirection(leaving, const Offset(0, -1)), isFalse);
    expect(
      cutRidesBoundary(
        Offset(2, step.paper.top),
        Offset(step.paper.right, step.paper.top),
        paperEdge,
      ),
      isTrue,
    );
  });

  test('the closest drawn edge selects the piece above another sheet', () {
    final lower = PapercutPiece(
      id: 'lower',
      color: kPapercutYellow,
      vertices: const [Offset(0, 0), Offset(4, 0), Offset(4, 4), Offset(0, 4)],
      separation: const Offset(0, -6),
    );
    final upper = PapercutPiece(
      id: 'upper',
      color: kPapercutYellow,
      vertices: const [Offset(0, 0), Offset(4, 0), Offset(4, 4), Offset(0, 4)],
      separation: const Offset(0, 6),
    );
    final hit = closestPieceEdge(
      aim: const Offset(2, 8),
      pieces: [lower, upper],
      spacing: 1,
    );
    expect(hit, isNotNull);
    expect(hit!.index, 1);
    expect(hit.model.dx, closeTo(2, 1e-6));
    expect(hit.model.dy, inInclusiveRange(0, 4));
  });

  test('the larger crosshair offset picks the tap direction', () {
    const deadZone = 12.0;
    expect(
      dominantScreenSide(const Offset(-40, -10), deadZone: deadZone),
      ScreenSide.left,
    );
    expect(
      dominantScreenSide(const Offset(-10, -40), deadZone: deadZone),
      ScreenSide.up,
    );
    expect(
      dominantScreenSide(const Offset(8, 30), deadZone: deadZone),
      ScreenSide.down,
    );
    expect(
      dominantScreenSide(const Offset(36, 12), deadZone: deadZone),
      ScreenSide.right,
    );
    expect(dominantScreenSide(const Offset(5, -4), deadZone: deadZone), isNull);
  });

  test('a swipe cuts opposite the finger', () {
    const slop = 12.0;
    expect(swipeCutSide(const Offset(0, 40), deadZone: slop), ScreenSide.up);
    expect(swipeCutSide(const Offset(40, 8), deadZone: slop), ScreenSide.left);
    expect(swipeCutSide(const Offset(0, 8), deadZone: slop), isNull);
  });

  test('the active cut keeps every stroke until the blade leaves', () {
    expect(activeCutPoints(const [Offset(0, 0)]), isEmpty);
    expect(
      activeCutPoints(const [Offset(0, 0)], tip: const Offset(0, 1)),
      const [Offset(0, 0), Offset(0, 1)],
    );
    final traveled = activeCutPoints(const [
      Offset(0, 0),
      Offset(2, 0),
      Offset(2, 3),
    ], tip: const Offset(4, 3));
    expect(traveled, const [
      Offset(0, 0),
      Offset(2, 0),
      Offset(2, 3),
      Offset(4, 3),
    ]);
    expect(
      activeCutPoints(const [Offset(0, 0), Offset(2, 0), Offset(2, 3)]),
      const [Offset(0, 0), Offset(2, 0), Offset(2, 3)],
    );
    expect(activeCutPoints(const []), isEmpty);
  });

  test('a fixed camera measures the tap from the tool, not the reticle', () {
    const reticle = Offset(400, 300);
    const tool = Offset(120, 220);
    expect(
      directionTapOrigin(
        cameraFollowsTool: true,
        reticle: reticle,
        toolOnScreen: tool,
      ),
      reticle,
    );
    expect(
      directionTapOrigin(
        cameraFollowsTool: false,
        reticle: reticle,
        toolOnScreen: tool,
      ),
      tool,
    );
    expect(
      directionTapOrigin(cameraFollowsTool: false, reticle: reticle),
      reticle,
    );
    // Above the blade, not above the reticle.
    expect(
      dominantScreenSide(
        const Offset(130, 180) -
            directionTapOrigin(
              cameraFollowsTool: false,
              reticle: reticle,
              toolOnScreen: tool,
            ),
        deadZone: 28,
      ),
      ScreenSide.up,
    );
  });

  test('a leftward cut turns the sheet clockwise so that direction is up', () {
    expect(
      PapercutCamera.rollForScreenUp(const Offset(-1, 0)),
      closeTo(-math.pi / 2, 1e-9),
    );
    expect(
      PapercutCamera.rollForScreenUp(const Offset(1, 0)),
      closeTo(math.pi / 2, 1e-9),
    );
    expect(
      PapercutCamera.rollForScreenUp(const Offset(0, 1)),
      closeTo(0, 1e-9),
    );
    expect(
      PapercutCamera.rollForScreenUp(const Offset(-1, 0), near: math.pi * 2),
      closeTo(math.pi * 1.5, 1e-6),
    );
  });

  test('an approach cut stays off the liberated outline', () {
    final step = twinLsBlueprint().steps.single;
    final liberated = PapercutPiece(
      id: 'l',
      color: kPapercutYellow,
      vertices: step.polygons.first,
    );
    final paper = _sheet(step).pieces.single;
    const stroke = [Offset(1, -3), Offset(1, 0), Offset(3, 0)];

    bool covers(List<List<Offset>> marks, Offset point) {
      for (final mark in marks) {
        if (mark.length < 2) continue;
        final a = mark.first;
        final b = mark.last;
        final ab = b - a;
        final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
        if (len2 < 1e-8) continue;
        final t =
            ((point.dx - a.dx) * ab.dx + (point.dy - a.dy) * ab.dy) / len2;
        if (t < -1e-3 || t > 1 + 1e-3) continue;
        final closest = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
        if ((closest - point).distance < 1e-3) return true;
      }
      return false;
    }

    final onPiece = cutMarksOnPiece(stroke, liberated);
    expect(covers(onPiece, const Offset(1, -1.5)), isFalse);
    expect(covers(onPiece, const Offset(2, 0)), isFalse);

    final onPaper = cutMarksOnPiece(stroke, paper);
    expect(covers(onPaper, const Offset(1, -1.5)), isTrue);
  });

  test(
    'a separating cut drops off the new edges and interior marks travel',
    () {
      const yellow = Color(0xFFFFF3B0);
      final left = PapercutPiece(
        id: 'left',
        color: yellow,
        vertices: const [
          Offset(0, 0),
          Offset(2, 0),
          Offset(2, 4),
          Offset(0, 4),
        ],
      );
      final right = PapercutPiece(
        id: 'right',
        color: yellow,
        vertices: const [
          Offset(2, 0),
          Offset(4, 0),
          Offset(4, 4),
          Offset(2, 4),
        ],
        separation: const Offset(3, 0),
      );
      const seam = [Offset(2, 0), Offset(2, 4)];
      expect(cutMarksOnPiece(seam, left), isEmpty);
      expect(cutMarksOnPiece(seam, right), isEmpty);

      const slit = [Offset(3, 1), Offset(3, 3)];
      expect(cutMarksOnPiece(slit, left), isEmpty);
      final carried = [
        for (final mark in cutMarksOnPiece(slit, right))
          [for (final point in mark) point + right.separation],
      ];
      expect(carried, [
        [const Offset(6, 1), const Offset(6, 3)],
      ]);

      final sheet = PapercutPiece(
        id: 'sheet',
        color: yellow,
        vertices: const [
          Offset(-1, -1),
          Offset(5, -1),
          Offset(5, 5),
          Offset(-1, 5),
        ],
        holes: const [
          [Offset(2, 0), Offset(4, 0), Offset(4, 4), Offset(2, 4)],
        ],
      );
      expect(cutMarksOnPiece(seam, sheet), isEmpty);
      expect(cutMarksOnPiece(slit, sheet), isEmpty);

      const across = [Offset(1, 2), Offset(3, 2)];
      final onLeft = cutMarksOnPiece(across, left);
      final onRight = cutMarksOnPiece(across, right);
      expect(onLeft, hasLength(1));
      expect(onLeft.single.first.dx, closeTo(1, 1e-6));
      expect(onLeft.single.last.dx, closeTo(2, 1e-6));
      expect(onRight, hasLength(1));
      expect(onRight.single.first.dx, closeTo(2, 1e-6));
      expect(onRight.single.last.dx, closeTo(3, 1e-6));
    },
  );

  test('a smaller piece slides out of space a larger one occupies', () {
    final settled = relaxSeparations(
      bounds: const [Rect.fromLTWH(0, 0, 10, 10), Rect.fromLTWH(0, 0, 2, 2)],
      areas: const [100, 4],
      home: const [Offset.zero, Offset(1, 0)],
    );
    final big = const Rect.fromLTWH(0, 0, 10, 10).shift(settled[0]);
    final small = const Rect.fromLTWH(0, 0, 2, 2).shift(settled[1]);
    expect(big.overlaps(small), isFalse);
    expect(settled[1].distance, greaterThan(settled[0].distance));
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

  test('a cut through a blueprint divides it onto each piece', () {
    const yellow = Color(0xFFFFF3B0);
    const square = [Offset(0, 0), Offset(4, 0), Offset(4, 4), Offset(0, 4)];
    final left = PapercutPiece(
      id: 'left',
      color: yellow,
      vertices: const [Offset(0, 0), Offset(2, 0), Offset(2, 4), Offset(0, 4)],
    );
    final right = PapercutPiece(
      id: 'right',
      color: yellow,
      vertices: const [Offset(2, 0), Offset(4, 0), Offset(4, 4), Offset(2, 4)],
      separation: const Offset(3, 0),
    );
    final leftParts = polygonOnPiece(square, left);
    final rightParts = polygonOnPiece(square, right);
    expect(
      [
        for (final ring in leftParts) polygonBounds([ring]),
      ],
      [const Rect.fromLTRB(0, 0, 2, 4)],
      reason: leftParts.map((ring) => ring.toString()).join(' | '),
    );
    expect(
      [
        for (final ring in rightParts) polygonBounds([ring]),
      ],
      [const Rect.fromLTRB(2, 0, 4, 4)],
    );

    final sheet = PapercutPiece(
      id: 'sheet',
      color: yellow,
      vertices: const [
        Offset(-1, -1),
        Offset(5, -1),
        Offset(5, 5),
        Offset(-1, 5),
      ],
      holes: const [square],
    );
    final cutOut = PapercutPiece(
      id: 'cut-out',
      color: yellow,
      vertices: square,
      separation: const Offset(3, 0),
    );
    expect(polygonOnPiece(square, sheet), isEmpty);
    expect(
      polygonBounds(polygonOnPiece(square, cutOut)),
      const Rect.fromLTRB(0, 0, 4, 4),
    );
  });

  test('blueprint linework stays with the paper that holds it', () {
    const yellow = Color(0xFFFFF3B0);
    PapercutPiece box(String id, List<Offset> ring) {
      return PapercutPiece(id: id, color: yellow, vertices: ring);
    }

    final left = box('left', const [
      Offset(-1, -1),
      Offset(3.5, -1),
      Offset(3.5, 4),
      Offset(-1, 4),
    ]);
    final right = box('right', const [
      Offset(3.5, -1),
      Offset(9, -1),
      Offset(9, 4),
      Offset(3.5, 4),
    ]);
    const leftL = [
      Offset(0, 0),
      Offset(3, 0),
      Offset(3, 1),
      Offset(1, 1),
      Offset(1, 2),
      Offset(0, 2),
    ];
    const rightL = [
      Offset(4, 0),
      Offset(7, 0),
      Offset(7, 1),
      Offset(5, 1),
      Offset(5, 2),
      Offset(4, 2),
    ];
    for (var i = 0; i < leftL.length; i++) {
      final a = leftL[i];
      final b = leftL[(i + 1) % leftL.length];
      expect(segmentOnPiece(a, b, left), [(a, b)]);
      expect(segmentOnPiece(a, b, right), isEmpty);
    }
    for (var i = 0; i < rightL.length; i++) {
      final a = rightL[i];
      final b = rightL[(i + 1) % rightL.length];
      expect(segmentOnPiece(a, b, right), [(a, b)]);
      expect(segmentOnPiece(a, b, left), isEmpty);
    }

    final through = box('through', const [
      Offset(-1, -1),
      Offset(2, -1),
      Offset(2, 4),
      Offset(-1, 4),
    ]);
    final rest = box('rest', const [
      Offset(2, -1),
      Offset(9, -1),
      Offset(9, 4),
      Offset(2, 4),
    ]);
    final cut = segmentOnPiece(const Offset(0, 0), const Offset(3, 0), through);
    expect(cut, hasLength(1));
    expect(cut.single.$1, const Offset(0, 0));
    expect(cut.single.$2.dx, closeTo(2, 1e-6));
    expect(cut.single.$2.dy, closeTo(0, 1e-6));
    final other = segmentOnPiece(const Offset(0, 0), const Offset(3, 0), rest);
    expect(other, hasLength(1));
    expect(other.single.$1.dx, closeTo(2, 1e-6));
    expect(other.single.$2, const Offset(3, 0));

    final sheetPiece = PapercutPiece(
      id: 'sheet',
      color: yellow,
      vertices: const [
        Offset(-2, -2),
        Offset(6, -2),
        Offset(6, 6),
        Offset(-2, 6),
      ],
      holes: const [
        [Offset(0, 0), Offset(2, 0), Offset(2, 2), Offset(0, 2)],
      ],
    );
    final inner = box('inner', const [
      Offset(0, 0),
      Offset(2, 0),
      Offset(2, 2),
      Offset(0, 2),
    ]);
    const buried = [Offset(0.2, 1), Offset(1.8, 1)];
    expect(segmentOnPiece(buried[0], buried[1], sheetPiece), isEmpty);
    expect(segmentOnPiece(buried[0], buried[1], inner), [
      (buried[0], buried[1]),
    ]);
  });

  test('a mark on a cut-out follows the inner piece', () {
    const yellow = Color(0xFFFFF3B0);
    const hole = [Offset(0, 0), Offset(2, 0), Offset(2, 2), Offset(0, 2)];
    final sheet = PapercutPiece(
      id: 'sheet',
      color: yellow,
      vertices: const [
        Offset(-4, -4),
        Offset(8, -4),
        Offset(8, 8),
        Offset(-4, 8),
      ],
      holes: const [hole],
    );
    final inner = PapercutPiece(
      id: 'inner',
      color: yellow,
      vertices: hole,
      separation: const Offset(3, 1),
    );
    final pieces = [sheet, inner];
    expect(markSeparation(const Offset(1, 1), pieces), const Offset(3, 1));
    expect(markSeparation(const Offset(1, 0), pieces), const Offset(3, 1));
    expect(markSeparation(const Offset(5, 5), pieces), Offset.zero);
  });

  test('the play badge shows the open color and the next number', () {
    const rules = GridRules(
      colors: [ColorMark(Offset(1, 0), 0), ColorMark(Offset(2, 0), 0)],
      numbers: [OrderMark(Offset(1, 1), 1), OrderMark(Offset(2, 1), 2)],
      seams: [GridEdge(Offset.zero, Offset(1, 0))],
    );
    final open = ruleCue(
      rules,
      const CutProgress(openColor: 0, collectedColors: {0}),
    );
    expect(open.color, 0);
    expect(open.number, 1);
    expect(open.seamsLeft, 1);
    final done = ruleCue(
      rules,
      const CutProgress(nextNumber: 3, severedSeams: {0}),
    );
    expect(done.color, isNull);
    expect(done.number, isNull);
    expect(done.seamsLeft, isNull);
  });

  testWidgets('editor shapes and rule marks paint on the shared canvas', (
    tester,
  ) async {
    final step = GridStep(
      id: 'marks',
      label: 'Marks',
      polygons: const [
        [Offset(0, 0), Offset(2, 0), Offset(2, 2), Offset(0, 2)],
      ],
      rules: const GridRules(
        forbidden: [Offset(1, 1)],
        colors: [ColorMark(Offset(1, 0), 0)],
        numbers: [OrderMark(Offset(2, 1), 1)],
      ),
    );
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
              sheet: PapercutSheet.empty(),
              march: null,
              flash: 1,
              rulerX: null,
              showRuler: false,
              selected: const {0},
              fillShapes: true,
              draft: const [Offset(3, 0), Offset(4, 1)],
              blockedCuts: const [(Offset(0, 0), Offset(1, 0))],
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(errors, isEmpty);
  });

  testWidgets('grid puzzles opens the blueprint it was given', (tester) async {
    final directory = Directory.systemTemp.createTempSync('puzzle-play');
    addTearDown(() => directory.delete(recursive: true));
    const blueprint = GridBlueprint(
      id: 'route-extra',
      name: 'Route Extra',
      steps: [
        GridStep(
          id: 'step',
          label: 'Step',
          polygons: [
            [Offset.zero, Offset(2, 0), Offset(2, 2)],
          ],
          rules: GridRules(numbers: [OrderMark(Offset(1, 0), 1)]),
        ),
      ],
    );
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => FmThemeData(),
        child: MaterialApp(
          home: GridPuzzleView(
            initial: blueprint,
            store: LevelStore(directory: directory),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Route Extra'), findsOneWidget);
    expect(find.byKey(const Key('grid-rule-badge-number')), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('a scissor use fits the sheet and leaves the camera there', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('puzzle-fixed');
    addTearDown(() => directory.delete(recursive: true));
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => FmThemeData(),
        child: MaterialApp(
          home: GridPuzzleView(
            initial: twinLsBlueprint(),
            store: LevelStore(directory: directory),
          ),
        ),
      ),
    );
    await tester.pump();
    await _openCameraSettings(tester);
    await tester.tap(find.text('Follow tool'));
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.byType(ViewCrosshair), findsOneWidget);
    final seated = _glyphPainter(tester).pose.tip;

    final box = tester.renderObject<RenderBox>(
      find.byKey(const Key('grid-puzzle-canvas')),
    );
    final center = box.localToGlobal(box.size.center(Offset.zero));
    await tester.dragFrom(center, const Offset(180, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    final panned = _puzzlePainter(tester);
    final paper = panned.step.paper;
    expect((panned.camera.lookAt - paper.center).distance, greaterThan(1));
    final followed = _glyphPainter(tester).pose;
    expect(followed.visible, greaterThan(0));
    expect((followed.tip - seated).distance, greaterThan(0.4));

    await tester.tapAt(center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.byType(ViewCrosshair), findsNothing);
    final cutting = _puzzlePainter(tester);
    expect((cutting.camera.lookAt - paper.center).distance, lessThan(1));
    expect(cutting.camera.roll, closeTo(0, 1e-6));
    final glyph = _glyphPainter(tester);
    expect(glyph.pose.visible, greaterThan(0));
    final early = cutting.activeCut;
    expect(early.length, greaterThanOrEqualTo(2));
    expect(cutting.ghostCuts, isEmpty);
    final earlyLength = (early.last - early.first).distance;
    expect(earlyLength, greaterThan(0.05));

    await tester.pump(const Duration(milliseconds: 80));
    final later = _puzzlePainter(tester).activeCut;
    expect(later.length, early.length);
    expect(
      (later.last - later.first).distance,
      greaterThan(earlyLength + 0.05),
    );

    final fitted = cutting.camera.lookAt;
    await tester.dragFrom(center, const Offset(-90, 0));
    await tester.pump();
    expect(
      (_puzzlePainter(tester).camera.lookAt - fitted).distance,
      lessThan(1),
    );
  });

  testWidgets('a cut follows the blade without turning the sheet', (tester) async {
    final directory = Directory.systemTemp.createTempSync('puzzle-follow');
    addTearDown(() => directory.delete(recursive: true));
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => FmThemeData(),
        child: MaterialApp(
          home: GridPuzzleView(
            initial: twinLsBlueprint(),
            store: LevelStore(directory: directory),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    final box = tester.renderObject<RenderBox>(
      find.byKey(const Key('grid-puzzle-canvas')),
    );
    final center = box.size.center(Offset.zero);
    final camera = _puzzlePainter(tester).camera;
    final paper = _puzzlePainter(tester).step.paper;
    final here = camera.planePoint(center, box.size)!;
    final aside = camera.planePoint(center + const Offset(80, 0), box.size)!;
    final perPixel = (aside.dx - here.dx) / 80;
    final drag = (paper.left + 0.45 - here.dx) / perPixel;
    await tester.dragFrom(box.localToGlobal(center), Offset(-drag, 0));
    await tester.pump();
    final before = _puzzlePainter(tester).camera.lookAt;
    await tester.tapAt(box.localToGlobal(center));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final opening = _puzzlePainter(tester);
    final cut = opening.activeCut;
    expect(cut.length, greaterThanOrEqualTo(2));
    final edge = cut.first;
    final tip = cut.last;
    expect(
      (opening.camera.lookAt - edge).distance,
      greaterThan((tip - edge).distance),
    );
    expect(
      (opening.camera.lookAt - edge).distance,
      greaterThan((before - edge).distance),
    );

    await tester.pump(const Duration(milliseconds: 1000));

    final followed = _puzzlePainter(tester).camera;
    final blade = _glyphPainter(tester).pose.tip;
    expect((followed.lookAt - blade).distance, lessThan(2));
    expect(followed.roll, closeTo(0, 1e-6));
  });

  testWidgets('a cut rolls the sheet when rotate is on', (tester) async {
    final directory = Directory.systemTemp.createTempSync('puzzle-roll');
    addTearDown(() => directory.delete(recursive: true));
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => FmThemeData(),
        child: MaterialApp(
          home: GridPuzzleView(
            initial: twinLsBlueprint(),
            store: LevelStore(directory: directory),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    await _openCameraSettings(tester);
    await tester.tap(find.text('Rotate camera'));
    await tester.pump();

    final box = tester.renderObject<RenderBox>(
      find.byKey(const Key('grid-puzzle-canvas')),
    );
    final center = box.size.center(Offset.zero);
    final camera = _puzzlePainter(tester).camera;
    final paper = _puzzlePainter(tester).step.paper;
    final here = camera.planePoint(center, box.size)!;
    final aside = camera.planePoint(center + const Offset(80, 0), box.size)!;
    final perPixel = (aside.dx - here.dx) / 80;
    final drag = (paper.left - here.dx) / perPixel;
    await tester.dragFrom(box.localToGlobal(center), Offset(-drag, 0));
    await tester.pump();
    await tester.tapAt(box.localToGlobal(center));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));

    final followed = _puzzlePainter(tester).camera;
    final blade = _glyphPainter(tester).pose.tip;
    expect((followed.lookAt - blade).distance, lessThan(2));
    expect(followed.roll.abs(), greaterThan(0.4));
  });
}

Future<void> _openCameraSettings(WidgetTester tester) async {
  await tester.tap(find.text('devtools'));
  await tester.pump();
  await tester.tap(find.byKey(const Key('grid-dev-section')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text('Camera').last);
  await tester.pump();
}

GridPuzzlePainter _puzzlePainter(WidgetTester tester) {
  GridPuzzlePainter? found;
  for (final element in find.byType(CustomPaint).evaluate()) {
    final painter = (element.widget as CustomPaint).painter;
    if (painter is GridPuzzlePainter && painter.drawGrid) found = painter;
  }
  expect(found, isNotNull);
  return found!;
}

ScissorGlyphPainter _glyphPainter(WidgetTester tester) {
  ScissorGlyphPainter? found;
  for (final element in find.byType(CustomPaint).evaluate()) {
    final painter = (element.widget as CustomPaint).painter;
    if (painter is ScissorGlyphPainter) found = painter;
  }
  expect(found, isNotNull);
  return found!;
}

bool _hasDirection(List<ForwardCut> cuts, Offset direction) {
  return cuts.any((cut) => (cut.direction - direction).distance < 1e-6);
}

bool _hasRay(List<Offset> rays, Offset direction) {
  final length = direction.distance;
  if (length < 1e-8) return false;
  final unit = direction / length;
  return rays.any((ray) {
    final dot = ray.dx * unit.dx + ray.dy * unit.dy;
    return dot > 1 - 1e-4;
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

PapercutSheet _splitAcross(
  GridStep step,
  PapercutSheet base,
  Offset at, {
  required bool vertical,
}) {
  final start = vertical
      ? Offset(at.dx, step.paper.top)
      : Offset(step.paper.left, at.dy);
  var march = placeScissor(start, step.paper);
  expect(march, isNotNull);
  PapercutSheet? sheet;
  var guard = 0;
  while (march != null && guard < 8) {
    final commit = commitScissor(march: march, step: step, base: base);
    expect(commit, isNotNull);
    sheet = commit!.sheet;
    march = commit.march;
    guard++;
  }
  return sheet!;
}

/// Midpoint of the longest edge that is not on the original paper border.
Offset? _freshEdge(List<Offset> ring, Rect paper) {
  Offset? best;
  var bestLength = -1.0;
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    if (_onPaperBorder(mid, paper)) continue;
    final length = (b - a).distance;
    if (length <= bestLength) continue;
    best = mid;
    bestLength = length;
  }
  return best;
}

bool _onPaperBorder(Offset point, Rect paper) {
  final onVertical =
      (point.dx - paper.left).abs() < 1e-3 ||
      (point.dx - paper.right).abs() < 1e-3;
  final onHorizontal =
      (point.dy - paper.top).abs() < 1e-3 ||
      (point.dy - paper.bottom).abs() < 1e-3;
  return onVertical || onHorizontal;
}

bool _stepsInto(Offset point, Offset direction, List<Offset> ring) {
  return isInsidePolygon(point + direction * 0.2, ring);
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
