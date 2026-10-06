import 'package:flatmates/gridcraft/blueprint.dart';
import 'package:flatmates/gridcraft/dimension_measure.dart';
import 'package:flatmates/gridcraft/twin_ls.dart';
import 'package:flatmates/router/app_router.dart';
import 'package:flatmates/screens/blueprint_examination_view.dart';
import 'package:flatmates/screens/dev_routes_screen.dart';
import 'package:flatmates/ui/dimension_chrome.dart';
import 'package:flatmates/ui/fm_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

void main() {
  const viewport = Rect.fromLTWH(0, 0, 800, 600);
  const track = DimensionTrack(
    axis: DimensionAxis.horizontal,
    start: Offset(100, 560),
    end: Offset(700, 560),
  );

  List<ProjectedVertex> sampleVertices() {
    return const [
      ProjectedVertex(world: Offset(0, 0), screen: Offset(100, 200)),
      ProjectedVertex(world: Offset(0, 2), screen: Offset(100, 320)),
      ProjectedVertex(world: Offset(3, 1), screen: Offset(400, 250)),
    ];
  }

  test('grabs start at 25% and 75% and are free', () {
    final ruler = DimensionRuler(DimensionAxis.horizontal);
    expect(ruler.grabs[0].fraction, kDimensionLowFraction);
    expect(ruler.grabs[1].fraction, kDimensionHighFraction);
    expect(ruler.grabs[0].world, isNull);
    expect(ruler.grabs[1].world, isNull);
    expect(ruler.bothStuck, isFalse);
  });

  test('a grab snaps to the nearest vertex and keeps the colinear pool', () {
    final vertices = sampleVertices();
    final hit = nearestSnap(
      axis: DimensionAxis.horizontal,
      screenAlong: 110,
      vertices: vertices,
    );
    expect(hit, isNotNull);
    expect(hit!.worldCoordinate, 0);
    expect(hit.screenAlong, 100);
    expect(hit.pool, hasLength(2));
    expect(hit.pool.map((vertex) => vertex.world.dy), [0, 2]);

    final ruler = DimensionRuler(DimensionAxis.horizontal);
    ruler.moveGrab(
      index: 0,
      screenAlong: 110,
      track: track,
      vertices: vertices,
    );
    expect(ruler.grabs[0].world, 0);
    expect(ruler.grabs[0].fraction, 0);

    ruler.moveGrab(
      index: 0,
      screenAlong: 250,
      track: track,
      vertices: vertices,
    );
    expect(ruler.grabs[0].world, isNull);
    expect(ruler.grabs[0].fraction, closeTo((250 - 100) / 600, 1e-9));
  });

  test('a pool stays visible while any colinear vertex is in view', () {
    final inside = ProjectedVertex(
      world: const Offset(0, 0),
      screen: const Offset(100, 200),
    );
    final outside = ProjectedVertex(
      world: const Offset(0, 2),
      screen: const Offset(100, 900),
    );
    final other = ProjectedVertex(
      world: const Offset(3, 1),
      screen: const Offset(400, 250),
    );
    expect(
      poolInView(
        axis: DimensionAxis.horizontal,
        worldCoordinate: 0,
        vertices: [inside, outside],
        viewport: viewport,
      ),
      isTrue,
    );
    expect(
      poolInView(
        axis: DimensionAxis.horizontal,
        worldCoordinate: 0,
        vertices: [outside],
        viewport: viewport,
      ),
      isFalse,
    );
    expect(
      poolInView(
        axis: DimensionAxis.horizontal,
        worldCoordinate: 0,
        vertices: [other],
        viewport: viewport,
      ),
      isFalse,
    );
  });

  test('the ruler stays stuck and slides while both pools are in view', () {
    final ruler = DimensionRuler(DimensionAxis.horizontal);
    ruler.grabs[0].world = 0;
    ruler.grabs[1].world = 3;
    final reset = ruler.followCamera(
      vertices: sampleVertices(),
      viewport: viewport,
      track: track,
      screenAlongOf: (world) => world == 0 ? 100.0 : 400.0,
    );
    expect(reset, isFalse);
    expect(ruler.grabs[0].stuck, isTrue);
    expect(ruler.grabs[1].stuck, isTrue);
    expect(ruler.grabs[0].fraction, closeTo(0, 1e-9));
    expect(ruler.grabs[1].fraction, closeTo(0.5, 1e-9));
  });

  test('losing either pool resets both grabs to the defaults', () {
    final ruler = DimensionRuler(DimensionAxis.horizontal);
    ruler.grabs[0].world = 0;
    ruler.grabs[0].fraction = 0.1;
    ruler.grabs[1].world = 3;
    ruler.grabs[1].fraction = 0.8;
    final vertices = [
      const ProjectedVertex(world: Offset(0, 0), screen: Offset(100, 200)),
      const ProjectedVertex(world: Offset(3, 1), screen: Offset(400, 900)),
    ];
    final reset = ruler.followCamera(
      vertices: vertices,
      viewport: viewport,
      track: track,
      screenAlongOf: (world) => world == 0 ? 100.0 : 400.0,
    );
    expect(reset, isTrue);
    expect(ruler.grabs[0].fraction, kDimensionLowFraction);
    expect(ruler.grabs[1].fraction, kDimensionHighFraction);
    expect(ruler.grabs[0].world, isNull);
    expect(ruler.grabs[1].world, isNull);
  });

  test('a free grab is left alone when the other pool is still in view', () {
    final ruler = DimensionRuler(DimensionAxis.horizontal);
    ruler.grabs[0].world = 0;
    ruler.grabs[1].fraction = 0.8;
    final reset = ruler.followCamera(
      vertices: sampleVertices(),
      viewport: viewport,
      track: track,
      screenAlongOf: (world) => 160.0,
    );
    expect(reset, isFalse);
    expect(ruler.grabs[0].world, 0);
    expect(ruler.grabs[0].fraction, closeTo(0.1, 1e-9));
    expect(ruler.grabs[1].fraction, 0.8);
    expect(ruler.grabs[1].world, isNull);
  });

  test('a lock needs both grabs stuck', () {
    final ruler = DimensionRuler(DimensionAxis.vertical);
    expect(lockDimension(ruler, 4), isNull);
    ruler.grabs[0].world = 1;
    expect(lockDimension(ruler, 4), isNull);
    ruler.grabs[1].world = 5;
    final locked = lockDimension(ruler, 4);
    expect(locked, isNotNull);
    expect(locked!.axis, DimensionAxis.vertical);
    expect(locked.low, 1);
    expect(locked.high, 5);
    expect(locked.cross, 4);
    final ends = dimensionEndpoints(locked);
    expect(ends.$1, const Offset(4, 1));
    expect(ends.$2, const Offset(4, 5));
    expect(dimensionCells(locked.low, locked.high, 1), 4);
    expect(formatDimensionCells(4), '4');
    expect(formatDimensionCells(2.5), '2.5');
  });

  test('an untracked ruler shows a dash instead of a length', () {
    final ruler = DimensionRuler(DimensionAxis.horizontal);
    expect(dimensionReadout(ruler, 1), '-');

    ruler.grabs[0].world = 0;
    expect(dimensionReadout(ruler, 1), '-');

    ruler.grabs[1].world = 3;
    expect(dimensionReadout(ruler, 1), '3');

    ruler.followCamera(
      vertices: const [
        ProjectedVertex(world: Offset(0, 0), screen: Offset(100, 900)),
        ProjectedVertex(world: Offset(3, 1), screen: Offset(400, 200)),
      ],
      viewport: viewport,
      track: track,
      screenAlongOf: (world) => world == 0 ? 100.0 : 400.0,
    );
    expect(dimensionReadout(ruler, 1), '-');
  });

  test('a tap between the grabs locks and a tap on a grab does not', () {
    const a = Offset(100, 560);
    const b = Offset(400, 560);
    expect(tapHitsMeasuredSpan(a, b, const Offset(250, 560)), isTrue);
    expect(tapHitsMeasuredSpan(a, b, a), isFalse);
    expect(
      tapHitsMeasuredSpan(
        const Offset(200, 560),
        const Offset(210, 560),
        const Offset(205, 560),
      ),
      isTrue,
    );
    expect(
      nearestSpan([
        (a: a, b: b),
        (a: const Offset(0, 0), b: const Offset(10, 0)),
      ], const Offset(250, 570)),
      0,
    );
  });

  test('the left and bottom tracks do not meet', () {
    final chrome = DimensionChrome.layout(
      viewport: const Size(800, 600),
      safe: const EdgeInsets.all(12),
    );
    final horizontal = chrome.horizontal;
    final vertical = chrome.vertical;

    expect(vertical.axis, DimensionAxis.vertical);
    expect(horizontal.axis, DimensionAxis.horizontal);
    expect(vertical.start.dx, 12 + kDimensionBand / 2);
    expect(vertical.start.dy, 12 + kDimensionBand / 2);
    expect(vertical.end.dy, 600 - 12 - kDimensionBand - kDimensionCornerGap);
    expect(horizontal.start.dx, 12 + kDimensionBand + kDimensionCornerGap);
    expect(horizontal.start.dy, 600 - 12 - kDimensionBand / 2);
    expect(horizontal.end.dx, 800 - 12 - kDimensionBand / 2);

    expect(vertical.end.dy, lessThan(horizontal.start.dy));
    expect(horizontal.start.dx, greaterThan(vertical.start.dx));
    expect(
      horizontal.start.dy - vertical.end.dy,
      kDimensionBand / 2 + kDimensionCornerGap,
    );
    expect(
      horizontal.start.dx - vertical.start.dx,
      kDimensionBand / 2 + kDimensionCornerGap,
    );

    final sharesX =
        vertical.start.dx >= horizontal.start.dx &&
        vertical.start.dx <= horizontal.end.dx;
    final sharesY =
        horizontal.start.dy >= vertical.start.dy &&
        horizontal.start.dy <= vertical.end.dy;
    expect(sharesX && sharesY, isFalse);
  });

  test('blueprint examination is on the dev menu', () {
    expect(kDevMenuRouteNames, contains('blueprint_examination'));
    final names = router.configuration.routes.whereType<GoRoute>().map(
      (route) => route.name,
    );
    expect(names, contains('blueprint_examination'));
  });

  testWidgets('scroll and pinch zoom the examination', (tester) async {
    final state = await pumpExamination(tester);
    double span() {
      final a = state.projectPlane(const Offset(0, 0))!;
      final b = state.projectPlane(const Offset(3, 0))!;
      return (b - a).distance;
    }

    final before = span();
    final center = canvasGlobal(tester, const Offset(400, 300));
    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(0, -80)),
    );
    await tester.pump();
    final zoomedIn = span();
    expect(zoomedIn, greaterThan(before * 1.1));

    await tester.sendEventToBinding(
      PointerScrollEvent(position: center, scrollDelta: const Offset(0, 120)),
    );
    await tester.pump();
    final zoomedOut = span();
    expect(zoomedOut, lessThan(zoomedIn));

    final first = await tester.startGesture(center + const Offset(-40, 0));
    final second = await tester.startGesture(center + const Offset(40, 0));
    await first.moveTo(center + const Offset(-120, 0));
    await second.moveTo(center + const Offset(120, 0));
    await tester.pump();
    expect(span(), greaterThan(zoomedOut * 1.2));
    await first.up();
    await second.up();
    await tester.pump();
  });

  testWidgets('the examination view paints a blueprint step', (tester) async {
    await pumpExamination(tester);

    expect(find.byKey(_canvasKey), findsOneWidget);
    expect(find.text('← Dev'), findsOneWidget);
    expect(
      find.byKey(const Key('blueprint-examination-steps')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.chevron_right), findsNothing);
  });

  testWidgets(
    'bottom grabs snap, and a span tap locks only when both are stuck',
    (tester) async {
      final state = await pumpExamination(tester);
      final look = state.projectPlane(const Offset(0, 0))!;

      await dragHorizontalGrab(tester, state, 0, look.dx);
      expect(
        state.projectPlane(const Offset(0, 0)),
        offsetMoreOrLessEquals(look),
      );
      expect(state.horizontalRuler.grabs[0].world, 0);
      expect(state.horizontalRuler.grabs[1].world, isNull);

      await tapMeasuredSpan(
        tester,
        state.dimensionChrome!.horizontal,
        state.horizontalRuler,
      );
      expect(state.lockedDimensions, isEmpty);
      expect(state.horizontalRuler.grabs[0].world, 0);

      final x3 = state.projectPlane(const Offset(3, 0))!;
      await dragHorizontalGrab(tester, state, 1, x3.dx);
      expect(state.horizontalRuler.bothStuck, isTrue);
      expect(
        {
          state.horizontalRuler.grabs[0].world,
          state.horizontalRuler.grabs[1].world,
        },
        {0.0, 3.0},
      );

      await tapMeasuredSpan(
        tester,
        state.dimensionChrome!.horizontal,
        state.horizontalRuler,
      );
      expect(state.lockedDimensions, hasLength(1));
      final locked = state.lockedDimensions.single;
      expect(locked.axis, DimensionAxis.horizontal);
      expect(dimensionCells(locked.low, locked.high, 1), 3);
    },
  );

  testWidgets(
    'a stuck ruler slides while its vertices stay in view, then resets',
    (tester) async {
      final state = await pumpExamination(tester);
      await stickHorizontal(tester, state);
      final before = [
        state.horizontalRuler.grabs[0].fraction,
        state.horizontalRuler.grabs[1].fraction,
      ];

      await panCanvas(tester, const Offset(-80, 0));
      expect(state.horizontalRuler.bothStuck, isTrue);
      expect(
        {
          state.horizontalRuler.grabs[0].world,
          state.horizontalRuler.grabs[1].world,
        },
        {0.0, 3.0},
      );
      expect(
        state.horizontalRuler.grabs[0].fraction,
        isNot(closeTo(before[0], 0.02)),
      );
      expect(
        state.horizontalRuler.grabs[1].fraction,
        isNot(closeTo(before[1], 0.02)),
      );

      await panCanvas(tester, const Offset(-700, 0));
      expect(state.horizontalRuler.grabs[0].world, isNull);
      expect(state.horizontalRuler.grabs[1].world, isNull);
      expect(state.horizontalRuler.grabs[0].fraction, kDimensionLowFraction);
      expect(state.horizontalRuler.grabs[1].fraction, kDimensionHighFraction);
    },
  );

  testWidgets('a locked dimension stays on the plane and leaves when tapped', (
    tester,
  ) async {
    final state = await pumpExamination(tester);
    await stickHorizontal(tester, state);
    await tapMeasuredSpan(
      tester,
      state.dimensionChrome!.horizontal,
      state.horizontalRuler,
    );
    expect(state.lockedDimensions, hasLength(1));

    await panCanvas(tester, const Offset(0, -140));
    expect(state.lockedDimensions, hasLength(1));
    final ends = dimensionEndpoints(state.lockedDimensions.single);
    final a = state.projectPlane(ends.$1)!;
    final b = state.projectPlane(ends.$2)!;
    final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    final rulerY = state.dimensionChrome!.horizontal.start.dy;
    expect(mid.dy, lessThan(rulerY - kDimensionSpanSlop));

    await tester.tapAt(canvasGlobal(tester, mid));
    await tester.pump();
    expect(state.lockedDimensions, isEmpty);
  });

  testWidgets('the left ruler snaps to a vertical pool', (tester) async {
    final state = await pumpExamination(tester);
    final y0 = state.projectPlane(const Offset(0, 0))!;
    final y2 = state.projectPlane(const Offset(0, 2))!;
    await dragVerticalGrab(tester, state, 0, y0.dy);
    await dragVerticalGrab(tester, state, 1, y2.dy);

    expect(state.verticalRuler.bothStuck, isTrue);
    expect(
      {state.verticalRuler.grabs[0].world, state.verticalRuler.grabs[1].world},
      {0.0, 2.0},
    );
    expect(state.horizontalRuler.bothStuck, isFalse);
  });

  testWidgets('the step menu lists the Ls and the side table', (tester) async {
    final state = await pumpExamination(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('blueprint-examination-steps')));
    await tester.pumpAndSettle();
    expect(find.text('Two Ls'), findsWidgets);
    expect(find.text('1 · Legs'), findsOneWidget);
    expect(find.text('2 · Tabletop'), findsOneWidget);
    expect(find.text('3 · Shelf'), findsOneWidget);
    expect(find.text('4 · Knob'), findsOneWidget);

    await tester.tap(find.text('1 · Legs'));
    await tester.pumpAndSettle();
    expect(find.text('1 · Legs'), findsOneWidget);
    final corner = state.projectPlane(const Offset(63, 0))!;
    expect(corner.dx, inInclusiveRange(0, 800));
    expect(corner.dy, inInclusiveRange(0, 600));
  });

  testWidgets('changing the level clears a locked dimension', (tester) async {
    final blueprint = GridBlueprint(
      id: 'exam',
      name: 'Exam',
      steps: [
        twinLsBlueprint().steps.first,
        const GridStep(
          id: 'next',
          label: 'Second',
          polygons: [
            [Offset(0, 0), Offset(2, 0), Offset(2, 2), Offset(0, 2)],
          ],
        ),
      ],
    );
    final state = await pumpExamination(tester, blueprint: blueprint);
    expect(find.text('Two Ls'), findsOneWidget);
    await stickHorizontal(tester, state);
    await tapMeasuredSpan(
      tester,
      state.dimensionChrome!.horizontal,
      state.horizontalRuler,
    );
    expect(state.lockedDimensions, hasLength(1));

    await tester.tap(find.byKey(const Key('blueprint-examination-steps')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second').last);
    await tester.pumpAndSettle();

    expect(find.text('Second'), findsOneWidget);
    expect(state.lockedDimensions, isEmpty);
    expect(state.horizontalRuler.grabs[0].world, isNull);
    expect(state.horizontalRuler.grabs[1].fraction, kDimensionHighFraction);
  });
}

const _canvasKey = Key('blueprint-examination-canvas');

Future<BlueprintExaminationViewState> pumpExamination(
  WidgetTester tester, {
  GridBlueprint? blueprint,
}) async {
  tester.view.physicalSize = const Size(800, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => FmThemeData(),
      child: MaterialApp(home: BlueprintExaminationView(blueprint: blueprint)),
    ),
  );
  await tester.pump();
  return tester.state(find.byType(BlueprintExaminationView));
}

Offset canvasGlobal(WidgetTester tester, Offset local) {
  final box = tester.renderObject<RenderBox>(find.byKey(_canvasKey));
  return box.localToGlobal(local);
}

Future<void> dragOnCanvas(WidgetTester tester, Offset from, Offset to) async {
  final start = canvasGlobal(tester, from);
  final end = canvasGlobal(tester, to);
  await tester.dragFrom(start, end - start);
  await tester.pump();
}

Future<void> panCanvas(WidgetTester tester, Offset delta) async {
  await tester.dragFrom(canvasGlobal(tester, const Offset(400, 250)), delta);
  await tester.pump();
}

Future<void> dragHorizontalGrab(
  WidgetTester tester,
  BlueprintExaminationViewState state,
  int index,
  double screenX,
) async {
  final track = state.dimensionChrome!.horizontal;
  final from = track.at(state.horizontalRuler.grabs[index].fraction);
  await dragOnCanvas(tester, from, Offset(screenX, track.start.dy));
}

Future<void> dragVerticalGrab(
  WidgetTester tester,
  BlueprintExaminationViewState state,
  int index,
  double screenY,
) async {
  final track = state.dimensionChrome!.vertical;
  final from = track.at(state.verticalRuler.grabs[index].fraction);
  await dragOnCanvas(tester, from, Offset(track.start.dx, screenY));
}

Future<void> stickHorizontal(
  WidgetTester tester,
  BlueprintExaminationViewState state,
) async {
  final x0 = state.projectPlane(const Offset(0, 0))!;
  final x3 = state.projectPlane(const Offset(3, 0))!;
  await dragHorizontalGrab(tester, state, 0, x0.dx);
  await dragHorizontalGrab(tester, state, 1, x3.dx);
  expect(state.horizontalRuler.bothStuck, isTrue);
}

Future<void> tapMeasuredSpan(
  WidgetTester tester,
  DimensionTrack track,
  DimensionRuler ruler,
) async {
  final a = track.at(ruler.grabs[0].fraction);
  final b = track.at(ruler.grabs[1].fraction);
  await tester.tapAt(canvasGlobal(tester, Offset.lerp(a, b, 0.5)!));
  await tester.pump();
}
