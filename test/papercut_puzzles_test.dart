import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flatmates/crafting/crafting_material.dart';
import 'package:flatmates/papercut/craft_puzzle.dart';
import 'package:flatmates/papercut/craft_v1.dart';
import 'package:flatmates/papercut/fold_pose.dart';
import 'package:flatmates/geometry/polygon_union.dart';
import 'package:flatmates/main.dart';
import 'package:flatmates/papercut/camera.dart';
import 'package:flatmates/papercut/measure.dart';
import 'package:flatmates/papercut/models.dart';
import 'package:flatmates/papercut/painter.dart';
import 'package:flatmates/papercut/paper.dart';
import 'package:flatmates/papercut/cut_graph.dart';
import 'package:flatmates/papercut/safe_zone.dart';
import 'package:flatmates/papercut/samples.dart';
import 'package:flatmates/papercut/score.dart';
import 'package:flatmates/papercut/split.dart';
import 'package:flatmates/rendering/scene/camera.dart';
import 'package:flatmates/router/app_router.dart';
import 'package:flatmates/screens/dev_routes_screen.dart';
import 'package:flatmates/screens/papercut_puzzles_view.dart';
import 'package:flatmates/ui/fm_theme.dart';
import 'package:flatmates/ui/game/game_tool_carousel.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('dev menu', () {
    test('keeps every route and lists only papercut puzzles', () {
      final names = router.configuration.routes
          .whereType<GoRoute>()
          .map((route) => route.name)
          .toSet();
      expect(
        names,
        containsAll(['gameview', 'legacy_crafting', 'papercut_puzzles']),
      );
      expect(kDevMenuRouteNames, {'papercut_puzzles', 'craft_editor'});
    });
  });

  group('sheet scale', () {
    test('an 8 cell sheet is 200mm', () {
      expect(CraftingMaterial.paperSizeCells, 8);
      expect(kPapercutSheetMm, 200);
      final sheet = PapercutSheet.square(color: kPapercutPink);
      final vertices = sheet.pieces.single.vertices;
      expect(vertices[1].dx - vertices[0].dx, 200);
      expect(vertices[2].dy - vertices[1].dy, 200);
    });
  });

  group('camera', () {
    test('flat mode is a 2000mm perspective lens', () {
      final cam = PapercutCamera();
      expect(cam.camera.projection, ProjectionType.perspective);
      expect(cam.focalLengthMm, 2000);
      final expected = 2 * math.atan(24 / (2 * 2000)) * 180 / math.pi;
      expect(cam.fovDegrees, closeTo(expected, 1e-6));
      expect(cam.camera.fovDegrees, lessThan(1));
    });

    test('dolly keeps the framing while the lens shortens', () {
      final cam = PapercutCamera();
      final distance = cam.distance;
      cam.beginToggle();
      cam.setBlend(1);
      expect(cam.focalLengthMm, 50);
      expect(cam.camera.projection, ProjectionType.perspective);
      expect(cam.distance, closeTo(distance * 50 / 2000, 0.05));
      expect(cam.azimuth, closeTo(PapercutCamera.perspectiveAzimuth, 1e-6));
    });

    test('pan slides the look-at across the sheet', () {
      final cam = PapercutCamera();
      cam.ensureFramed(const Size(400, 800), sheetMm: kPapercutSheetMm);
      final before = cam.lookAt;
      cam.panByScreen(const Offset(40, 0), const Size(400, 800));
      expect(cam.lookAt.dx, isNot(closeTo(before.dx, 0.5)));
      expect(cam.camera.projection, ProjectionType.perspective);
    });

    test('positive roll lifts world +X toward the top of the screen', () {
      final cam = PapercutCamera();
      const viewport = Size(400, 800);
      cam.ensureFramed(viewport, sheetMm: kPapercutSheetMm);
      final origin = cam.camera.projectToScreen(Vector3.zero(), viewport)!;
      final before = cam.camera.projectToScreen(Vector3(80, 0, 0), viewport)!;
      expect(before.dx, greaterThan(origin.dx + 10));

      cam.setRoll(math.pi / 2);
      final after = cam.camera.projectToScreen(Vector3(80, 0, 0), viewport)!;
      expect(after.dy, lessThan(origin.dy - 10));
    });

    test('roll snaps to the nearest 5 degrees', () {
      double deg(double degrees) => degrees * math.pi / 180;
      expect(PapercutCamera.snapRoll(deg(7)), closeTo(deg(5), 1e-9));
      expect(PapercutCamera.snapRoll(deg(8)), closeTo(deg(10), 1e-9));
      expect(PapercutCamera.snapRoll(deg(-2)), closeTo(0, 1e-9));
      expect(PapercutCamera.snapRoll(deg(-3)), closeTo(deg(-5), 1e-9));
      expect(PapercutCamera.snapRoll(deg(362)), closeTo(deg(360), 1e-9));
    });

    test('a clockwise screen sweep rolls the sheet clockwise', () {
      final roll = PapercutCamera.rollAfterScreenSweep(
        baseRoll: 0.2,
        startAngle: 0,
        currentAngle: math.pi / 2,
      );
      expect(roll, closeTo(0.2 - math.pi / 2, 1e-9));
    });

    test('angle samples survive the branch cut', () {
      final next = PapercutCamera.advanceAngle(3, -3);
      expect(next, greaterThan(3));
      expect(next, closeTo(3 + PapercutCamera.signedAngleDelta(3, -3), 1e-9));
    });

    test('one finger uses the center ray and two fingers use their line', () {
      const center = Offset(200, 400);
      expect(
        PapercutCamera.rotationAngle(const [Offset(280, 400)], center),
        closeTo(0, 1e-9),
      );
      expect(
        PapercutCamera.rotationAngle(const [
          Offset(120, 400),
          Offset(280, 400),
        ], center),
        closeTo(0, 1e-9),
      );
      expect(
        PapercutCamera.rotationAngle(const [
          Offset(200, 320),
          Offset(200, 480),
        ], center),
        closeTo(math.pi / 2, 1e-9),
      );
    });
  });

  group('split', () {
    test('a cut across the sheet yields two pieces', () {
      final sheet = PapercutSheet.square(color: kPapercutPink);
      final cut = applyPapercutCut(sheet, const [
        Offset(-150, 0),
        Offset(150, 0),
      ]);
      expect(cut, isNotNull);
      expect(cut!.pieces, hasLength(2));
      expect(cut.cutStrokes, hasLength(1));
      final area = cut.pieces.fold<double>(
        0,
        (sum, piece) => sum + polygonSignedArea(piece.vertices).abs(),
      );
      expect(area, closeTo(200 * 200, 1));
    });

    test('a cut that misses the sheet is ignored', () {
      final sheet = PapercutSheet.square(color: kPapercutPink);
      expect(
        applyPapercutCut(sheet, const [Offset(-10, 250), Offset(10, 250)]),
        isNull,
      );
    });
  });

  group('score', () {
    const square = [
      Offset(-40, -40),
      Offset(40, -40),
      Offset(40, 40),
      Offset(-40, 40),
    ];

    test('cuts on the perimeter pass', () {
      final cuts = [
        [square[0], square[1]],
        [square[1], square[2]],
        [square[2], square[3]],
        [square[3], square[0]],
      ];
      expect(scoreCutPerimeter(square, cuts).passed, isTrue);
    });

    test(
      'scissor lines that run long still count when they lie on the edges',
      () {
        final cuts = [
          [const Offset(-100, -40), const Offset(100, -40)],
          [const Offset(40, -100), const Offset(40, 100)],
          [const Offset(100, 40), const Offset(-100, 40)],
          [const Offset(-40, 100), const Offset(-40, -100)],
        ];
        expect(scoreCutPerimeter(square, cuts).passed, isTrue);
      },
    );

    test('a slash across the shape fails', () {
      final score = scoreCutPerimeter(square, const [
        [Offset(-80, -80), Offset(80, 80)],
      ]);
      expect(score.passed, isFalse);
    });

    test('a kink off the outline fails', () {
      final cuts = [
        [
          square[0],
          const Offset(0, -40),
          const Offset(0, -55),
          const Offset(0, -40),
          square[1],
        ],
        [square[1], square[2]],
        [square[2], square[3]],
        [square[3], square[0]],
      ];
      final score = scoreCutPerimeter(square, cuts);
      expect(score.passed, isFalse);
      expect(score.reason, 'A cut kinks off the outline');
    });

    test('a version-1 craft becomes cut and fold guides', () {
      final craft = _craftMin();
      expect(craft.version, 1);
      expect(craft.craftingSteps, [1, 2]);
      expect(craft.faces.first.flatLoops.first.first.x, 0);
      expect(craft.faces[1].transform, isA<CraftV1Rotation>());
      final rotation = craft.faces[1].transform as CraftV1Rotation;
      expect(rotation.axisStart.x, 10);
      expect(rotation.axisEnd.y, 10);
      expect(rotation.angleRadians, closeTo(math.pi / 2, 1e-6));
      expect(craft.edges.map((edge) => edge.role), ['fold', 'cut']);

      final blueprint = papercutBlueprintFromCraft(craft);
      final step = blueprint.steps.first;
      final geometry = step.geometry as PapercutCurveGeometry;
      expect(step.label, 'Step 1');
      expect(geometry.nets, hasLength(1));
      final sheet = geometry.nets.single.outer;
      expect(sheet, hasLength(4));
      final sheetBounds = Rect.fromPoints(sheet.first, sheet[2]);
      expect(sheetBounds.left, lessThan(0));
      expect(sheetBounds.top, lessThan(0));
      expect(sheetBounds.right, greaterThan(20));
      expect(sheetBounds.bottom, greaterThan(10));
      final other = blueprint.steps[1].geometry as PapercutCurveGeometry;
      final otherSheet = other.nets.single.outer;
      expect(
        (sheet[1].dx - sheet[0].dx).abs(),
        closeTo((otherSheet[1].dx - otherSheet[0].dx).abs(), 1e-6),
      );
      expect(
        (sheet[2].dy - sheet[1].dy).abs(),
        closeTo((otherSheet[2].dy - otherSheet[1].dy).abs(), 1e-6),
      );
      final fold = geometry.foldCurves.single;
      final cut = geometry.curves.where(
        (curve) => curve.role == PapercutCurveRole.cut,
      );
      expect(fold.points, [const Offset(10, 0), const Offset(10, 10)]);
      expect(fold.foldAngleDegrees, closeTo(90, 1e-4));
      expect(
        cut.any(
          (curve) =>
              curve.points.contains(const Offset(20, 0)) &&
              curve.points.contains(const Offset(20, 10)),
        ),
        isTrue,
      );
      expect(
        cut.any(
          (curve) =>
              curve.points.contains(const Offset(0, 0)) &&
              curve.points.contains(const Offset(0, 10)),
        ),
        isTrue,
      );
      expect(cut.every((curve) => !curve.closed), isTrue);

      final missed = scorePapercutStep(
        step,
        PapercutSheet(pieces: const [], cutStrokes: const []),
      );
      expect(missed.passed, isFalse);
      final boundary = cut.firstWhere(
        (curve) =>
            curve.points.contains(const Offset(0, 0)) &&
            curve.points.contains(const Offset(0, 10)),
      );
      expect(
        scoreOpenCut(boundary, [boundary.points]).passed,
        isTrue,
      );

      final flat = applyFoldPose(craft, 1, 0);
      final folded = applyFoldPose(craft, 1, 1);
      expect(flat['s1_p0_i0_f1']!.isIdentity(), isTrue);
      expect(folded['s1_p0_i0_f1']!.isIdentity(), isFalse);
    });

    test('a card step also needs the spine crease', () {
      final card = papercutSampleBlueprint().steps[2];
      const outline = [
        Offset(-75, -48),
        Offset(75, -48),
        Offset(75, 48),
        Offset(-75, 48),
      ];
      final cuts = [
        [outline[0], outline[1]],
        [outline[1], outline[2]],
        [outline[2], outline[3]],
        [outline[3], outline[0]],
      ];
      final cutOnly = PapercutSheet(
        pieces: PapercutSheet.square(color: kPapercutGreen).pieces,
        cutStrokes: cuts,
      );
      expect(scorePapercutStep(card, cutOnly).passed, isFalse);
      final creased = PapercutSheet(
        pieces: cutOnly.pieces,
        cutStrokes: cuts,
        creases: const [
          PapercutCrease(
            id: 'spine',
            a: Offset(-100, 0),
            b: Offset(100, 0),
            groupId: 'card-spine',
            angleDegrees: 90,
          ),
        ],
      );
      expect(scorePapercutStep(card, creased).passed, isTrue);
    });

    test('the sample blueprint scores an empty sheet as unfinished', () {
      final blueprint = papercutSampleBlueprint();
      final squareStep = blueprint.steps.first;
      final sheet = PapercutSheet.square(color: kPapercutPink);
      expect(scorePapercutStep(squareStep, sheet).passed, isFalse);
      final wedge = blueprint.steps.last;
      expect(wedge.geometry, isA<PapercutMeshGeometry>());
      expect(scorePapercutStep(wedge, PapercutSheet.empty()).passed, isTrue);
    });
  });

  group('safe zones', () {
    const line = [Offset(0, 0), Offset(40, 0)];

    test('cut caps are tighter than fold caps', () {
      expect(
        pointInSafeZone(
          const Offset(40.5, 0),
          line,
          closed: false,
          capsuleFraction: kPapercutCutCapsuleFraction,
        ),
        isTrue,
      );
      expect(
        pointInSafeZone(
          const Offset(43, 0),
          line,
          closed: false,
          capsuleFraction: kPapercutCutCapsuleFraction,
        ),
        isFalse,
      );
      expect(
        pointInSafeZone(
          const Offset(43, 0),
          line,
          closed: false,
          capsuleFraction: kPapercutFoldCapsuleFraction,
        ),
        isTrue,
      );
    });

    test('parallel lines do not meet', () {
      expect(
        lineLineIntersection(
          const Offset(0, 0),
          const Offset(10, 0),
          const Offset(0, 2),
          const Offset(10, 2),
        ),
        isNull,
      );
    });

    test('a crossing uses the hit nearest the scissor tip', () {
      final sheet = PapercutSheet(
        pieces: PapercutSheet.square(color: kPapercutPink).pieces,
        cutStrokes: const [
          [Offset(-100, 0), Offset(100, 0)],
          [Offset(-100, -20), Offset(100, -20)],
        ],
      );
      final plan = planScissorCut(const [Offset(0, -80), Offset(0, 40)], sheet);
      expect(plan, isNotNull);
      expect(plan!.stroke.first, const Offset(0, 40));
      expect(plan.joint!.dx, closeTo(0, 0.05));
      expect(plan.joint!.dy, closeTo(0, 0.05));
      expect(sheet.cutStrokes.first.last, const Offset(100, 0));
    });

    test('a scissor can start by crossing an existing cut safe zone', () {
      final sheet = PapercutSheet(
        pieces: PapercutSheet.square(color: kPapercutPink).pieces,
        cutStrokes: const [
          [Offset(0, 0), Offset(100, 0)],
        ],
      );
      final plan = planScissorCut(const [Offset(5, 1), Offset(5, 4)], sheet);
      expect(plan, isNotNull);
      expect(plan!.stroke.first, const Offset(5, 4));
      expect(plan.joint!.dx, closeTo(5, 0.05));
      expect(plan.joint!.dy, closeTo(3, 0.15));
      expect(plan.stroke.last.dy, greaterThan(1));
    });

    test('a scissor tip extends to a cut inside the safe zone', () {
      final sheet = PapercutSheet(
        pieces: PapercutSheet.square(color: kPapercutPink).pieces,
        cutStrokes: const [
          [Offset(-20, 42), Offset(20, 42)],
        ],
      );
      final plan = planScissorCut(const [Offset(0, -40), Offset(0, 40)], sheet);
      expect(plan, isNotNull);
      expect(plan!.joint!.dx, closeTo(0, 0.05));
      expect(plan.joint!.dy, closeTo(42, 0.05));
    });

    test(
      'a new cut extends onto an existing one and the graph records the joint',
      () {
        final joined = connectNewCut(
          const [Offset(0, 10), Offset(0, 3)],
          const [
            [Offset(-10, 0), Offset(10, 0)],
          ],
        );
        expect(joined.first, const Offset(0, 10));
        expect(joined.last.dx, closeTo(0, 0.05));
        expect(joined.last.dy, closeTo(0, 0.05));
        final graph = buildCutGraph([
          const [Offset(-10, 0), Offset(10, 0)],
          joined,
        ]);
        expect(graph.joints, hasLength(1));
        expect(graph.joints.single.dx, closeTo(0, 0.05));
        expect(graph.joints.single.dy, closeTo(0, 0.05));
      },
    );

    test('measure labels the outline, the cut graph, and the gap', () {
      final step = papercutSampleBlueprint().steps.first;
      final empty = buildPapercutMeasure(
        step,
        PapercutSheet.square(color: kPapercutPink),
      );
      expect(empty.outlines.single.outlineMm, 320);
      expect(empty.outlines.single.countedMm, 0);
      expect(empty.blueprint.map((edge) => edge.millimeters), [80, 80, 80, 80]);
      expect(empty.issues.where((issue) => issue.gap), isNotEmpty);

      final sheet = PapercutSheet(
        pieces: PapercutSheet.square(color: kPapercutPink).pieces,
        cutStrokes: const [
          [Offset(-100, -40), Offset(100, -40)],
          [Offset(40, -100), Offset(40, 100)],
        ],
      );
      final measured = buildPapercutMeasure(step, sheet);
      expect(measured.graph.map((edge) => edge.millimeters).toList()..sort(), [
        60,
        60,
        140,
        140,
      ]);
      expect(measured.nearest, isNotEmpty);
      expect(measured.outlines.single.countedMm, greaterThan(0));

      final far = buildPapercutMeasure(
        step,
        PapercutSheet(
          pieces: PapercutSheet.square(color: kPapercutPink).pieces,
          cutStrokes: const [
            [Offset(-40, -50), Offset(40, -50)],
          ],
        ),
      );
      expect(
        far.issues.where((issue) => !issue.gap).single.millimeters,
        inInclusiveRange(9, 11),
      );
    });

    test('a scissor cut must reach the paper edge', () {
      final sheet = PapercutSheet.square(color: kPapercutPink);
      expect(
        scissorReachesPaperEdge(const [Offset(-150, 0), Offset(150, 0)], sheet),
        isTrue,
      );
      expect(
        scissorReachesPaperEdge(const [
          Offset(-20, -20),
          Offset(20, 20),
        ], sheet),
        isFalse,
      );
    });
  });

  testWidgets('dev menu opens the papercut puzzles view', (tester) async {
    router.go('/dev-routes');
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => FmThemeData(),
        child: const FlatmatesApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('gameview'), findsNothing);
    expect(find.textContaining('papercut_puzzles'), findsOneWidget);

    await tester.tap(find.textContaining('papercut_puzzles'));
    await tester.pumpAndSettle();

    expect(find.text('One square'), findsOneWidget);
    expect(find.byTooltip('Scissors'), findsOneWidget);
    expect(find.byTooltip('Exacto'), findsOneWidget);
    expect(find.byTooltip('Straight edge'), findsOneWidget);

    await tester.tap(find.byTooltip('Dev tools'));
    await tester.pumpAndSettle();
    expect(find.text('Blueprint'), findsOneWidget);
    expect(find.text('Cuts'), findsOneWidget);
    expect(find.text('Graph'), findsOneWidget);
    expect(find.text('Nearest'), findsOneWidget);
    expect(find.text('320 / 0'), findsOneWidget);

    router.go('/dev-routes');
  });

  testWidgets('a version-1 craft loads its step guides', (tester) async {
    final craft = _craftMin();
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => FmThemeData(),
        child: MaterialApp(home: PapercutPuzzlesView(crafts: [craft])),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('papercut-craft-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('craft_min').last);
    await tester.pumpAndSettle();

    expect(find.text('Step 1'), findsOneWidget);
    final geometry = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<PapercutPainter>()
        .single
        .step
        .geometry as PapercutCurveGeometry;
    expect(geometry.foldCurves, hasLength(1));
    expect(
      geometry.curves.where((curve) => curve.role == PapercutCurveRole.cut),
      hasLength(greaterThan(1)),
    );
  });

  testWidgets('rotate toggles off by itself and by a second tap', (
    tester,
  ) async {
    await _pumpPapercut(tester);
    expect(_rotateScale(tester), 1);

    await tester.tap(find.byKey(const Key('papercut-rotate')));
    await tester.pump();
    expect(_rotateScale(tester), kGameToolCarouselScale);

    await tester.tap(find.byKey(const Key('papercut-rotate')));
    await tester.pump();
    expect(_rotateScale(tester), 1);

    await tester.tap(find.byKey(const Key('papercut-rotate')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(_rotateScale(tester), 1);

    final camera = _papercutCamera(tester);
    final before = camera.lookAt;
    final center = tester.getCenter(find.byKey(const Key('papercut-canvas')));
    final pan = await tester.startGesture(center);
    await pan.moveBy(const Offset(70, 16));
    await pan.up();
    await tester.pump();
    expect(camera.lookAt.dx, isNot(closeTo(before.dx, 0.5)));
    expect(camera.roll, closeTo(0, 1e-6));
  });

  testWidgets('a one-finger drag rolls about the screen center and snaps', (
    tester,
  ) async {
    await _pumpPapercut(tester);
    final camera = _papercutCamera(tester);
    final lookAt = camera.lookAt;
    final halfHeight = camera.framedHalfHeightMm;
    await tester.tap(find.byKey(const Key('papercut-rotate')));
    await tester.pump();

    final center = tester.getCenter(find.byKey(const Key('papercut-canvas')));
    const radius = 140.0;
    final sweep = 7 * math.pi / 180;
    final drag = await tester.startGesture(center + const Offset(radius, 0));
    await drag.moveTo(
      center + Offset(radius * math.cos(sweep), radius * math.sin(sweep)),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(_rotateScale(tester), kGameToolCarouselScale);
    expect(camera.roll, closeTo(-sweep, 0.02));
    expect(camera.lookAt, lookAt);
    expect(camera.framedHalfHeightMm, halfHeight);

    await drag.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(camera.roll, closeTo(-5 * math.pi / 180, 0.01));
    expect(_rotateScale(tester), kGameToolCarouselScale);

    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(_rotateScale(tester), 1);
  });

  testWidgets('scroll and pinch zoom the blueprint', (tester) async {
    await _pumpPapercut(tester);
    final camera = _papercutCamera(tester);
    final before = camera.framedHalfHeightMm;
    final center = tester.getCenter(find.byKey(const Key('papercut-canvas')));
    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(0, -80)),
    );
    await tester.pump();
    expect(camera.framedHalfHeightMm, lessThan(before));

    final zoomed = camera.framedHalfHeightMm;
    final first = await tester.startGesture(center + const Offset(-40, 0));
    final second = await tester.startGesture(center + const Offset(40, 0));
    await first.moveTo(center + const Offset(-90, 0));
    await second.moveTo(center + const Offset(90, 0));
    await tester.pump();
    expect(camera.framedHalfHeightMm, lessThan(zoomed));
    await first.up();
    await second.up();
  });

  testWidgets('two-finger rotate does not zoom the blueprint', (tester) async {
    await _pumpPapercut(tester);
    final camera = _papercutCamera(tester);
    final halfHeight = camera.framedHalfHeightMm;
    await tester.tap(find.byKey(const Key('papercut-rotate')));
    await tester.pump();

    final center = tester.getCenter(find.byKey(const Key('papercut-canvas')));
    final first = await tester.startGesture(center + const Offset(-90, 0));
    final second = await tester.startGesture(center + const Offset(90, 0));
    await first.moveTo(center + const Offset(0, -25));
    await second.moveTo(center + const Offset(0, 25));
    await tester.pump();

    expect(camera.roll, closeTo(-math.pi / 2, 0.08));
    expect(camera.framedHalfHeightMm, halfHeight);

    await first.up();
    await second.up();
  });
}

CraftV1 _craftMin() {
  final json = jsonDecode(
    File('test/fixtures/craft_min/craft.json').readAsStringSync(),
  );
  return CraftV1.fromJson(json as Map<String, dynamic>);
}

Future<void> _pumpPapercut(WidgetTester tester) async {
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => FmThemeData(),
      child: const MaterialApp(home: PapercutPuzzlesView()),
    ),
  );
  await tester.pumpAndSettle();
}

PapercutCamera _papercutCamera(WidgetTester tester) {
  return tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((paint) => paint.painter)
      .whereType<PapercutPainter>()
      .single
      .camera;
}

double _rotateScale(WidgetTester tester) {
  return tester
      .widget<AnimatedScale>(
        find.descendant(
          of: find.byKey(const Key('papercut-rotate')),
          matching: find.byType(AnimatedScale),
        ),
      )
      .scale;
}
