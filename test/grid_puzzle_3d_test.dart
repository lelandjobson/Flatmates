import 'dart:io';
import 'dart:math' as math;

import 'package:flatmates/gridcraft/blueprint.dart';
import 'package:flatmates/gridcraft/craft_collection.dart';
import 'package:flatmates/gridcraft/craft_collection_painter.dart';
import 'package:flatmates/gridcraft/folded_model.dart';
import 'package:flatmates/gridcraft/level_io.dart';
import 'package:flatmates/gridcraft/model_painter.dart';
import 'package:flatmates/gridcraft/painter.dart';
import 'package:flatmates/gridcraft/pattern_paper_painter.dart';
import 'package:flatmates/gridcraft/wrap_cut.dart';
import 'package:flatmates/papercut/craft_v1.dart';
import 'package:flatmates/screens/grid_puzzle_view.dart';
import 'package:flatmates/ui/grid/piece_inventory.dart';
import 'package:flatmates/ui/fm_theme.dart';
import 'package:flatmates/ui/game/view_crosshair.dart';
import 'package:flatmates/ui/rotation_gizmo.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

/// Two 5×5 squares. The left one is the root; the right one folds up about
/// x = 5.
CraftV1 _dominoCraft() {
  final identity = [
    for (var r = 0; r < 4; r++)
      for (var c = 0; c < 4; c++) r == c ? 1.0 : 0.0,
  ];
  Map<String, dynamic> face(
    int index,
    List<List<double>> loop,
    Map<String, dynamic> transform,
  ) => {
    'id': 's1_p0_i0_f$index',
    'flatmates.surfaceId': '$index',
    if (index == 1) 'flatmates.foldParentSurfaceId': '0',
    'flatmates.pieceKey': 'craft_Domino#0',
    'flatmates.islandId': '0',
    'flatmates.craftingStep': '1',
    'flatLoops': [
      [
        for (final point in [...loop, loop.first]) [point[0], point[1], 0.0],
      ],
    ],
    'transform': transform,
  };
  return CraftV1.fromJson({
    'version': 1,
    'craft': 'craft_Domino',
    'faces': [
      face(
        0,
        [
          [0, 0],
          [5, 0],
          [5, 5],
          [0, 5],
        ],
        {'type': 'movement', 'forward': identity, 'inverse': identity},
      ),
      face(
        1,
        [
          [5, 0],
          [10, 0],
          [10, 5],
          [5, 5],
        ],
        {
          'type': 'rotation',
          'axis': [5.0, 0.0, 0.0, 5.0, 5.0, 0.0],
          'angleRadians': '${math.pi / 2}',
        },
      ),
    ],
    'edges': [
      {
        'flatmates.role': 'fold',
        'flatmates.craftingStep': '1',
        'curve': [
          [5.0, 0.0, 0.0],
          [5.0, 5.0, 0.0],
        ],
        'faceA': 's1_p0_i0_f0',
        'faceB': 's1_p0_i0_f1',
      },
    ],
  });
}

/// The paper is exactly the domino, so the fresh sheet is its cut-out.
GridBlueprint _domino() => const GridBlueprint(
  id: 'domino',
  name: 'Domino',
  steps: [
    GridStep(
      id: 'domino',
      label: 'Domino',
      paperMargin: 0,
      polygons: [
        [Offset(0, 0), Offset(5, 0), Offset(5, 5), Offset(0, 5)],
        [Offset(5, 0), Offset(10, 0), Offset(10, 5), Offset(5, 5)],
      ],
      edgeStyles: [
        [
          EdgeStyle.penned,
          EdgeStyle.penciled,
          EdgeStyle.penned,
          EdgeStyle.penned,
        ],
        [
          EdgeStyle.penned,
          EdgeStyle.penned,
          EdgeStyle.penned,
          EdgeStyle.penciled,
        ],
      ],
      craft: CraftLink(id: 'craft_Domino', step: 1),
    ),
  ],
);

ModelPainter _modelPainter(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.byKey(const Key('grid-model-layer')),
  );
  return paint.painter! as ModelPainter;
}

String _hint(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('grid-model-hint'))).data ?? '';

/// The dot grid drawn on a face while paper moves on it.
GridPuzzlePainter? _faceDots(WidgetTester tester) =>
    tester.widget<CustomPaint>(find.byKey(const Key('grid-model-dots'))).painter
        as GridPuzzlePainter?;

/// The desk under the model.
GridPuzzlePainter _desk(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.painter)
    .whereType<GridPuzzlePainter>()
    .firstWhere((painter) => painter.plane == null);

WrapCutPainter _wrapPainter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(find.byKey(const Key('grid-model-layer')))
            .foregroundPainter!
        as WrapCutPainter;

WrapPaperLayer _wrapLayer(WidgetTester tester) =>
    _wrapPainter(tester).layers.single;

Future<void> _click(WidgetTester tester, Offset at) async {
  await tester.tapAt(at, kind: PointerDeviceKind.mouse);
  await tester.pump();
}

Future<void> _mouseDrag(WidgetTester tester, Offset from, Offset by) async {
  final mouse = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
  for (var i = 1; i <= 8; i++) {
    await mouse.moveTo(from + by * (i / 8));
    await tester.pump();
  }
  await mouse.up();
  await tester.pump();
}

double _angle(Vector3 a, Vector3 b) =>
    math.acos(a.normalized().dot(b.normalized()).clamp(-1.0, 1.0));

Future<void> _open(
  WidgetTester tester,
  String name,
  GridBlueprint level,
) async {
  tester.view.physicalSize = const Size(900, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final directory = Directory.systemTemp.createTempSync(name);
  addTearDown(() => directory.delete(recursive: true));
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => FmThemeData(),
      child: MaterialApp(
        home: GridPuzzleView(
          initial: level,
          store: LevelStore(directory: directory),
          crafts: [_dominoCraft()],
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  test('next-cut dots pulse in order through each cycle', () {
    const window = 0.28;
    expect(nextDotPulse(0, 3, window / 2), closeTo(1, 1e-9));
    expect(nextDotPulse(1, 3, window / 2), 0);
    expect(nextDotPulse(2, 3, window / 2), 0);
    final second = 1 / 3 + window / 2;
    expect(nextDotPulse(1, 3, second), closeTo(1, 1e-9));
    expect(nextDotPulse(0, 3, second), 0);
    expect(nextDotPulse(0, 3, 1 + window / 2), closeTo(1, 1e-9));
  });

  testWidgets('3D mode: the aim selects paper, a drop wraps', (tester) async {
    await _open(tester, 'puzzle-3d', _domino());

    final canvasFinder = find.byKey(const Key('grid-puzzle-canvas'));
    final canvas = tester.getTopLeft(canvasFinder);
    final viewport = tester.getSize(canvasFinder);
    final column = find.byKey(const Key('grid-inventory'));
    final item = find.byKey(const Key('grid-inventory-paper'));

    // On the flat desk the inventory bar floats in with the select tool, and
    // the paper drags into it.
    expect(column, findsNothing);
    await tester.tap(find.byIcon(Icons.near_me));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(column, findsOneWidget);
    expect(find.text('INVENTORY'), findsOneWidget);
    expect(item, findsNothing);
    final barRight = tester.getTopRight(column).dx;
    expect(barRight, lessThanOrEqualTo(tester.getTopRight(canvasFinder).dx));
    await tester.timedDragFrom(
      tester.getCenter(canvasFinder),
      tester.getCenter(column) - tester.getCenter(canvasFinder),
      const Duration(milliseconds: 400),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(item, findsOneWidget);

    // Dragging it back out lays it on the desk again.
    final out = await tester.startGesture(tester.getCenter(item));
    await out.moveBy(const Offset(-40, 0));
    await tester.pump();
    await out.moveTo(tester.getCenter(canvasFinder));
    await tester.pump();
    await out.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(item, findsNothing);

    final toggle = find.byKey(const Key('grid-view-mode'));
    expect(toggle, findsOneWidget);
    await tester.tap(toggle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byKey(const Key('grid-model-layer')), findsOneWidget);
    expect(find.byKey(const Key('grid-frame-model')), findsOneWidget);
    expect(find.byKey(const Key('grid-focus-frame')), findsNothing);

    Offset screen(Vector3 world) {
      final painter = _modelPainter(tester);
      return canvas + painter.camera.camera.projectToScreen(world, viewport)!;
    }

    int score() => int.parse(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const Key('grid-score')),
              matching: find.byType(Text),
            ),
          )
          .data!,
    );

    // The model floats over the desk.
    final model = _modelPainter(tester).model;
    expect(model.bounds.min.z, greaterThan(1));
    expect(_modelPainter(tester).desk, isNotNull);

    // A click selects the desk paper under the cursor; dragging it then
    // slides it onto the inventory.
    final deskPaper = screen(Vector3(0.8, 0.8, 0));
    await _click(tester, deskPaper);
    expect(
      _hint(tester),
      'Drag to slide the paper, or onto the inventory to stow it.',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await _mouseDrag(tester, deskPaper, tester.getCenter(column) - deskPaper);
    await tester.pump(const Duration(milliseconds: 300));
    expect(_desk(tester).sheet.pieces, isEmpty);
    expect(_desk(tester).pickedPiece, isNull);

    // With nothing selected a drag orbits; look straight down, so the
    // reticle lands on the floor.
    await tester.timedDragFrom(
      tester.getCenter(canvasFinder),
      const Offset(0, 260),
      const Duration(milliseconds: 300),
    );
    await tester.pump();
    final floor = _modelPainter(tester).model.faceOfRing(0)!;
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 250));
    expect(_modelPainter(tester).highlight[floor], 1);
    expect(find.byKey(const Key('grid-piece-inventory')), findsOneWidget);
    expect(_hint(tester), 'Drag a paper piece onto the highlighted face.');

    // Drop the paper with its middle on its own blueprint middle. The
    // floor's dot grid shows while it moves.
    final face = _modelPainter(tester).model.faces[floor];
    expect(_faceDots(tester), isNull);
    final drag = await tester.startGesture(tester.getCenter(item));
    await drag.moveBy(const Offset(-40, 0));
    await tester.pump();
    await drag.moveTo(screen(face.world(const Offset(5, 2.5))));
    await tester.pump();
    expect(_modelPainter(tester).loose, hasLength(1));
    expect(_faceDots(tester)!.gridOpacity, closeTo(0.45, 1e-9));
    final scoreBefore = score();
    await drag.up();
    await tester.pump();
    expect(_modelPainter(tester).glow[floor], greaterThan(0));
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump();
    expect(_hint(tester), 'Every piece is wrapped.');
    expect(_modelPainter(tester).paperPoses.keys.toSet(), {0, 1});
    expect(_faceDots(tester), isNull);

    // The wrap turns the camera once around the model, then scores.
    await tester.pump(const Duration(milliseconds: 500));
    final camera = _modelPainter(tester).camera;
    final backedOut = camera.camera.position.clone();
    await tester.pump(const Duration(milliseconds: 800));
    expect((camera.camera.position - backedOut).length, greaterThan(20));
    expect(score(), scoreBefore);
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();
    expect(score(), scoreBefore + 100);
    expect(find.byKey(const Key('grid-score-gain')), findsOneWidget);
    expect((camera.camera.position - backedOut).length, lessThan(2));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byKey(const Key('grid-score-gain')), findsNothing);

    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(_modelPainter(tester).paperPoses, isEmpty);
    expect(item, findsOneWidget);

    // Back over the floor, a tap on the inventory lays the paper on it,
    // selected, three cells left of home.
    await tester.timedDragFrom(
      tester.getCenter(canvasFinder),
      const Offset(0, 260),
      const Duration(milliseconds: 300),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 250));
    expect(_modelPainter(tester).highlight[floor], 1);
    await tester.tap(item);
    await tester.pump();
    expect(_hint(tester), 'Drag to slide the paper until the face glows.');
    expect(_modelPainter(tester).loose.single.selected, isTrue);
    expect(find.byKey(const Key('grid-place-turn-left')), findsNothing);

    // Selected paper goes back to the inventory, by Stow or by dragging it
    // onto the inventory.
    final stow = find.byKey(const Key('grid-stow'));
    expect(stow, findsOneWidget);
    expect(column, findsOneWidget);
    expect(item, findsNothing);
    await tester.tap(stow);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(item, findsOneWidget);
    expect(stow, findsNothing);
    expect(_hint(tester), 'Drag a paper piece onto the highlighted face.');
    await tester.tap(item);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(item, findsNothing);

    Rect inHand() {
      final ring = _modelPainter(tester).loose.single.ring;
      return pointBounds([for (final point in ring) Offset(point.x, point.y)]);
    }

    final held = screen(
      Vector3(inHand().left + 1, inHand().center.dy, face.worldRing()[0].z),
    );
    await tester.timedDragFrom(
      held,
      tester.getCenter(column) - held,
      const Duration(milliseconds: 400),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(item, findsOneWidget);
    expect(_modelPainter(tester).paperPoses, isEmpty);
    expect(_modelPainter(tester).loose, isEmpty);
    await tester.tap(item);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The rotate icon on the paper opens a ring around it. Dragging the ring
    // a quarter of the way round turns the paper a quarter turn, and dragging
    // it back puts the paper exactly where it was.
    void expectRect(Rect actual, Rect expected) {
      expect(actual.left, closeTo(expected.left, 1e-9));
      expect(actual.top, closeTo(expected.top, 1e-9));
      expect(actual.right, closeTo(expected.right, 1e-9));
      expect(actual.bottom, closeTo(expected.bottom, 1e-9));
    }

    final flat = inHand();
    expect(find.byKey(const Key('grid-place-gimbal')), findsNothing);
    await tester.tap(find.byKey(const Key('grid-place-rotate')));
    await tester.pump();
    final gimbal = find.byKey(const Key('grid-place-gimbal'));
    expect(gimbal, findsOneWidget);
    expect(find.byKey(const Key('grid-place-rotate')), findsNothing);
    Offset onRing(double degrees) {
      final ring = tester.widget<RotationGizmo>(gimbal);
      final angle =
          ring.screenRefAngle + ring.rotationSign * degrees * math.pi / 180;
      return canvas +
          ring.center +
          Offset(math.cos(angle), math.sin(angle)) * ring.ringRadius;
    }

    Future<void> sweep(double from, double to) async {
      final hand = await tester.startGesture(onRing(from));
      for (var i = 1; i <= 6; i++) {
        await hand.moveTo(onRing(from + (to - from) * i / 6));
        await tester.pump();
      }
      await hand.up();
      await tester.pump();
    }

    await sweep(0, 90);
    final turned = inHand();
    expect(turned.width, closeTo(flat.height, 1e-9));
    expect(turned.height, closeTo(flat.width, 1e-9));
    expect(turned.center.dx, closeTo(flat.center.dx, 0.5 + 1e-9));
    await sweep(90, 0);
    expectRect(inHand(), flat);
    await tester.tap(
      find.descendant(of: gimbal, matching: find.byIcon(Icons.close)),
    );
    await tester.pump();
    expect(gimbal, findsNothing);
    expect(find.byKey(const Key('grid-place-rotate')), findsOneWidget);

    // A click away from the paper lets go of it; it stays on the face.
    await _click(tester, canvas + Offset(24, viewport.height * 0.45));
    expect(_modelPainter(tester).loose.single.selected, isFalse);
    expect(find.byKey(const Key('grid-place-rotate')), findsNothing);
    expect(stow, findsNothing);

    // A touch picks with the reticle, wherever the finger lands.
    await tester.tapAt(canvas + Offset(40, viewport.height * 0.6));
    await tester.pump();
    expect(_modelPainter(tester).loose.single.selected, isTrue);
    expect(_hint(tester), 'Drag to slide the paper until the face glows.');

    // Double-clicking selected paper lets go of it.
    final onPaper = screen(face.world(const Offset(2, 2.5)));
    await _click(tester, onPaper);
    await tester.pump(const Duration(milliseconds: 60));
    await _click(tester, onPaper);
    expect(_modelPainter(tester).loose.single.selected, isFalse);
    expect(_modelPainter(tester).loose.single.outline, greaterThan(0.9));

    // Unselected, a drag on the paper orbits and leaves it be.
    final ring = [..._modelPainter(tester).loose.single.ring];
    final eye = camera.camera.position.clone();
    await tester.timedDragFrom(
      onPaper,
      const Offset(-80, 0),
      const Duration(milliseconds: 200),
    );
    await tester.pump();
    expect((camera.camera.position - eye).length, greaterThan(1));
    expect(_modelPainter(tester).loose.single.ring, ring);

    // Its outline is fading out meanwhile. A click selects it again, the
    // outline fading back in from there.
    final fading = _modelPainter(tester).loose.single.outline;
    expect(fading, inExclusiveRange(0, 0.9));
    final from = screen(face.world(const Offset(2, 2.5)));
    await _click(tester, from);
    expect(_modelPainter(tester).loose.single.selected, isTrue);
    expect(_modelPainter(tester).loose.single.outline, closeTo(fading, 0.1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_modelPainter(tester).loose.single.outline, closeTo(1, 1e-9));

    // Selected, a drag slides it; home, it matches and wraps. The floor's
    // dots show at once and fade out after.
    final to = screen(face.world(const Offset(5, 2.5)));
    final slide = await tester.startGesture(from);
    for (var i = 1; i <= 6; i++) {
      await slide.moveTo(from + (to - from) * (i / 6));
      await tester.pump();
      if (i > 1) expect(_faceDots(tester)!.gridOpacity, closeTo(0.45, 1e-9));
    }
    await slide.up();
    await tester.pump();
    expect(_modelPainter(tester).glow[floor], greaterThan(0));
    await tester.pump(const Duration(milliseconds: 150));
    expect(_faceDots(tester)!.gridOpacity, inExclusiveRange(0, 0.45));
    await tester.pump(const Duration(milliseconds: 850));
    expect(_hint(tester), 'Every piece is wrapped.');
    expect(_faceDots(tester), isNull);

    // Wrapping the same island again turns the camera but scores nothing.
    await tester.pump(const Duration(milliseconds: 2300));
    await tester.pump();
    expect(score(), scoreBefore + 100);

    await tester.tap(toggle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byKey(const Key('grid-model-layer')), findsNothing);
  });

  testWidgets('desk paper selects with a fading outline, slides on its dots', (
    tester,
  ) async {
    await _open(tester, 'puzzle-3d-desk', _domino());
    await tester.tap(find.byKey(const Key('grid-view-mode')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    final canvasFinder = find.byKey(const Key('grid-puzzle-canvas'));
    final canvas = tester.getTopLeft(canvasFinder);
    final viewport = tester.getSize(canvasFinder);
    final camera = _modelPainter(tester).camera;
    Offset screen(Offset desk) =>
        canvas +
        camera.camera.projectToScreen(Vector3(desk.dx, desk.dy, 0), viewport)!;

    // A click selects the paper under the cursor. Its fill stays put while
    // the outline fades in.
    final paper = screen(const Offset(0.8, 0.8));
    expect(_desk(tester).pickedPiece, isNull);
    expect(_desk(tester).gridOpacity, 0);
    await _click(tester, paper);
    expect(_desk(tester).pickedPiece, 0);
    expect(_desk(tester).pickedOutline, lessThan(0.2));
    expect(_desk(tester).sheet.pieces.single.color.a, 1);
    await tester.pump(const Duration(milliseconds: 120));
    expect(_desk(tester).pickedOutline, inExclusiveRange(0, 1));
    expect(_desk(tester).sheet.pieces.single.color.a, 1);
    await tester.pump(const Duration(milliseconds: 200));
    expect(_desk(tester).pickedOutline, closeTo(1, 1e-9));

    // Dragging slides it, the desk dots showing at once and fading after.
    final mouse = await tester.startGesture(
      paper,
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveTo(paper + const Offset(0, 4));
    await tester.pump();
    expect(_desk(tester).gridOpacity, closeTo(0.45, 1e-9));
    for (var i = 1; i <= 6; i++) {
      await mouse.moveTo(paper + Offset(0, 4 + 20.0 * i));
      await tester.pump();
    }
    await mouse.up();
    await tester.pump();
    final moved = _desk(tester).sheet.pieces.single.separation;
    expect(moved, isNot(Offset.zero));
    expect(_desk(tester).gridOpacity, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 500));
    expect(_desk(tester).gridOpacity, 0);
    expect(_desk(tester).pickedPiece, 0);

    // Double-clicking it lets go.
    final there = screen(const Offset(0.8, 0.8) + moved);
    await _click(tester, there);
    await tester.pump(const Duration(milliseconds: 60));
    await _click(tester, there);
    expect(_desk(tester).pickedPiece, isNull);
    expect(find.byKey(const Key('grid-model-layer')), findsOneWidget);
  });

  testWidgets('DevTools forces the cursor or the reticle for any pointer', (
    tester,
  ) async {
    await _open(tester, 'puzzle-3d-aim', _domino());
    await tester.tap(find.byKey(const Key('grid-view-mode')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    final canvasFinder = find.byKey(const Key('grid-puzzle-canvas'));
    final canvas = tester.getTopLeft(canvasFinder);
    final viewport = tester.getSize(canvasFinder);
    final camera = _modelPainter(tester).camera;
    final paper =
        canvas + camera.camera.projectToScreen(Vector3(0.8, 0.8, 0), viewport)!;
    final reticle = find.byType(ViewCrosshair);

    // By default a hovering mouse aims taps. The reticle stays up and alone
    // preselects, so paper dragged in from the inventory lands where it
    // points.
    await tester.pump(const Duration(milliseconds: 400));
    final highlight = {..._modelPainter(tester).highlight};
    final deskHighlight = _modelPainter(tester).deskHighlight;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: canvas + const Offset(30, 600));
    await mouse.moveTo(paper);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(reticle, findsOneWidget);
    expect(_hint(tester), 'Click paper to select it. Drag to orbit.');
    expect(_modelPainter(tester).highlight, highlight);
    expect(_modelPainter(tester).deskHighlight, deskHighlight);

    Future<void> aim(String mode) async {
      await tester.tap(find.text('devtools'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('grid-dev-section')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Input').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(Key('grid-aim-$mode')));
      await tester.pump();
      await tester.tap(find.text('devtools'));
      await tester.pump();
    }

    // Mobile: the mouse no longer aims taps.
    await aim('reticle');
    await mouse.moveTo(paper + const Offset(4, 0));
    await tester.pump();
    expect(reticle, findsOneWidget);
    expect(_hint(tester), 'Aim at and tap paper to select it. Drag to orbit.');
    await mouse.removePointer();

    // PC: a touch aims where it lands, so it picks the paper under it.
    await aim('cursor');
    expect(_desk(tester).pickedPiece, isNull);
    await tester.tapAt(paper);
    await tester.pump();
    expect(reticle, findsOneWidget);
    expect(_desk(tester).pickedPiece, 0);
  });

  testWidgets('3D pans move by the drag and keep the grabbed point', (
    tester,
  ) async {
    await _open(tester, 'puzzle-3d-pan', _domino());
    await tester.tap(find.byKey(const Key('grid-view-mode')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    final canvasFinder = find.byKey(const Key('grid-puzzle-canvas'));
    final canvas = tester.getTopLeft(canvasFinder);
    final viewport = tester.getSize(canvasFinder);
    final model = _modelPainter(tester).model;
    final camera = _modelPainter(tester).camera;
    final look = camera.viewDirection;

    Vector3 under(Offset at) {
      final ray = camera.camera.unprojectRay(
        at - tester.getTopLeft(canvasFinder),
        tester.getSize(canvasFinder),
      )!;
      final hit = pickFace(model, ray.origin, ray.direction)!;
      return ray.pointAt(hit.distance);
    }

    void expectUnder(Vector3 point, Offset at) {
      final seen = camera.camera.projectToScreen(
        point,
        tester.getSize(canvasFinder),
      )!;
      expect(
        (tester.getTopLeft(canvasFinder) + seen - at).distance,
        lessThan(0.5),
      );
      expect((camera.viewDirection - look).length, lessThan(1e-9));
    }

    // Over nothing, the view slides only as far as the pointer moves: no
    // jump on the first move.
    final open = canvas + Offset(viewport.width * 0.15, viewport.height * 0.25);
    final start = camera.target.clone();
    final empty = await tester.startGesture(
      open,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await empty.moveTo(open + const Offset(-5, 0));
    await tester.pump();
    await empty.moveTo(open + const Offset(-10, 0));
    await tester.pump();
    final first = (camera.target - start).length;
    await empty.moveTo(open + const Offset(-15, 0));
    await tester.pump();
    await empty.moveTo(open + const Offset(-20, 0));
    await tester.pump();
    expect(first, greaterThan(0));
    expect((camera.target - start).length / first, closeTo(2, 0.05));
    await empty.up();
    await tester.pump(const Duration(milliseconds: 400));

    // A right drag slides the view; what was under the press stays under the
    // cursor, and the camera does not turn.
    final wall = model.faceOfRing(1)!;
    final press =
        canvas +
        camera.camera.projectToScreen(model.worldCenter(wall), viewport)!;
    final grabbed = under(press);
    final mouse = await tester.startGesture(
      press,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    var at = press;
    for (var i = 0; i < 6; i++) {
      at += const Offset(-14, 9);
      await mouse.moveTo(at);
      await tester.pump();
    }
    expectUnder(grabbed, at);
    await mouse.up();
    await tester.pump(const Duration(milliseconds: 400));

    // A middle drag pans the same way.
    final middleFrom = camera.target;
    final middle = await tester.startGesture(
      at,
      kind: PointerDeviceKind.mouse,
      buttons: kMiddleMouseButton,
    );
    final regrabbed = under(at);
    for (var i = 0; i < 4; i++) {
      at += const Offset(10, -6);
      await middle.moveTo(at);
      await tester.pump();
    }
    expectUnder(regrabbed, at);
    expect((camera.target - middleFrom).length, greaterThan(0.1));
    await middle.up();
    await tester.pump(const Duration(milliseconds: 400));

    // Two fingers pan too, even with paper selected, holding what is under
    // their middle.
    await _click(
      tester,
      canvas + camera.camera.projectToScreen(Vector3(0.8, 0.8, 0), viewport)!,
    );
    expect(_desk(tester).pickedPiece, 0);
    final separation = _desk(tester).sheet.pieces.single.separation;
    at =
        canvas +
        camera.camera.projectToScreen(model.worldCenter(wall), viewport)! -
        const Offset(25, 0);
    final spread = const Offset(30, 0);
    final a = await tester.startGesture(at - spread, pointer: 7);
    final b = await tester.startGesture(at + spread, pointer: 8);
    await a.moveBy(const Offset(50, 0));
    await b.moveBy(const Offset(50, 0));
    await tester.pump();
    at += const Offset(50, 0);
    final held = under(at);
    for (var i = 0; i < 5; i++) {
      await a.moveBy(const Offset(-12, 10));
      await b.moveBy(const Offset(-12, 10));
      await tester.pump();
      at += const Offset(-12, 10);
    }
    expectUnder(held, at);
    await a.up();
    await b.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(_desk(tester).sheet.pieces.single.separation, separation);
    expect(_desk(tester).pickedPiece, 0);
  });

  testWidgets('a level without a craft has no 3D toggle', (tester) async {
    final plain = _domino();
    await _open(
      tester,
      'puzzle-3d-none',
      GridBlueprint(
        id: plain.id,
        name: plain.name,
        steps: [
          GridStep(
            id: 'plain',
            label: 'Plain',
            polygons: plain.steps.single.polygons,
          ),
        ],
      ),
    );
    expect(find.byKey(const Key('grid-view-mode')), findsNothing);
  });

  testWidgets('a craft collection names, pans, enters, and takes back crafts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final directory = Directory.systemTemp.createTempSync('puzzle-3d-room');
    addTearDown(() => directory.delete(recursive: true));
    final store = LevelStore(directory: directory);
    await tester.runAsync(() => store.save(_domino()));
    final collection = CraftCollection.fromJson({
      'id': 'yard',
      'name': 'Yard',
      'camera': {
        'at': [0, 0, 0],
        'turn': -90,
        'tilt': 35,
        'halfHeight': 12,
      },
      'geometry': [
        {
          'type': 'polygon',
          'rings': [
            [
              [-20, -20, -0.05],
              [20, -20, -0.05],
              [20, 20, -0.05],
              [-20, 20, -0.05],
            ],
          ],
        },
      ],
      'crafts': [
        {
          'puzzle': 'domino',
          'at': [0, 0],
          'turn': 30,
        },
      ],
    });
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => FmThemeData(),
        child: MaterialApp(
          home: GridPuzzleView(
            store: store,
            crafts: [_dominoCraft()],
            craftCollection: collection,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final canvasFinder = find.byKey(const Key('grid-puzzle-canvas'));
    final canvas = tester.getTopLeft(canvasFinder);
    final viewport = tester.getSize(canvasFinder);
    final room = find.byKey(const Key('grid-craft-collection'));
    CraftCollectionPainter painter() =>
        tester.widget<CustomPaint>(room).painter! as CraftCollectionPainter;
    double nameShown() => tester
        .widget<AnimatedOpacity>(find.byKey(const Key('grid-craft-name-fade')))
        .opacity;
    String name() =>
        tester.widget<Text>(find.byKey(const Key('grid-craft-name'))).data!;
    Offset onDomino() {
      final craft = painter().crafts.single.model;
      final floor = craft.faceOfRing(0)!;
      return canvas +
          painter().camera.camera.projectToScreen(
            craft.worldCenter(floor),
            viewport,
          )!;
    }

    Offset? ground(Offset screen) =>
        painter().camera.planePoint(screen - canvas, viewport);

    // The collection opens with the 2D chrome hidden, and the reticle on
    // the domino names it.
    expect(room, findsOneWidget);
    expect(find.byKey(const Key('grid-view-mode')), findsNothing);
    expect(find.byKey(const Key('grid-collection-button')), findsNothing);
    expect(find.byKey(const Key('grid-puzzle-button')), findsNothing);
    expect(find.byKey(const Key('grid-model-layer')), findsNothing);
    expect(find.text('Yard'), findsOneWidget);
    expect(name(), 'Domino');
    expect(nameShown(), 1);
    expect(painter().crafts.single.hover, 1);
    expect(painter().crafts.single.finished, isFalse);

    // A drag pans the ground point under the press along with the pointer,
    // and enters nothing.
    final press = canvas + Offset(viewport.width / 2, viewport.height * 0.75);
    final grabbed = ground(press)!;
    final target = painter().camera.target;
    await tester.timedDragFrom(
      press,
      const Offset(-400, -60),
      const Duration(milliseconds: 300),
    );
    await tester.pump();
    expect(find.byKey(const Key('grid-model-layer')), findsNothing);
    expect(room, findsOneWidget);
    expect((painter().camera.target - target).length, greaterThan(1));
    expect(painter().camera.target.z, closeTo(target.z, 1e-9));
    expect(
      (ground(press + const Offset(-400, -60))! - grabbed).distance,
      lessThan(1e-6),
    );
    expect(painter().crafts.single.hover, 0);
    await tester.pump(const Duration(milliseconds: 300));
    expect(nameShown(), 0);

    // Only the reticle picks: a hovering mouse, or a tap, on the domino off
    // the reticle neither names it nor enters it.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: onDomino());
    await tester.pump();
    expect(painter().crafts.single.hover, 0);
    await mouse.removePointer();
    await tester.tapAt(onDomino());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.byKey(const Key('grid-model-layer')), findsNothing);
    expect(nameShown(), 0);

    // Panning back puts the domino under the reticle again.
    await tester.timedDragFrom(
      press + const Offset(-400, -60),
      const Offset(400, 60),
      const Duration(milliseconds: 300),
    );
    await tester.pump();
    expect((painter().camera.target - target).length, lessThan(1e-6));
    expect(painter().crafts.single.hover, 1);

    // A short tap anywhere flies into the reticle's craft, in its own 3D
    // view.
    final away = canvas + Offset(40, viewport.height * 0.8);
    final roomPose = painter().camera.camera.position.clone();
    await tester.tapAt(away);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(room, findsOneWidget);
    expect(painter().crafts.single.opacity, 1);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(room, findsNothing);
    expect(find.byKey(const Key('grid-model-layer')), findsOneWidget);
    expect(find.text('Domino'), findsOneWidget);
    final back = find.byKey(const Key('grid-craft-collection-back'));
    expect(back, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));

    // Its back button flies out to where the collection was left.
    await tester.tap(back);
    await tester.pump();
    expect(room, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();
    expect(find.byKey(const Key('grid-model-layer')), findsNothing);
    expect(
      (painter().camera.camera.position - roomPose).length,
      lessThan(1e-6),
    );

    // Back in, wrapping the domino returns to the collection with it drawn
    // as paper.
    await tester.tapAt(away);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump(const Duration(milliseconds: 500));
    Offset screen(Vector3 world) =>
        canvas +
        _modelPainter(tester).camera.camera.projectToScreen(world, viewport)!;
    final column = find.byKey(const Key('grid-inventory'));
    final item = find.byKey(const Key('grid-inventory-paper'));
    final deskPaper = screen(Vector3(0.8, 0.8, 0));
    await _click(tester, deskPaper);
    await tester.pump(const Duration(milliseconds: 400));
    await _mouseDrag(tester, deskPaper, tester.getCenter(column) - deskPaper);
    await tester.pump(const Duration(milliseconds: 300));
    expect(_desk(tester).sheet.pieces, isEmpty);
    await tester.timedDragFrom(
      tester.getCenter(canvasFinder),
      const Offset(0, 260),
      const Duration(milliseconds: 300),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 250));
    final model = _modelPainter(tester).model;
    final face = model.faces[model.faceOfRing(0)!];
    final drag = await tester.startGesture(tester.getCenter(item));
    await drag.moveBy(const Offset(-40, 0));
    await tester.pump();
    await drag.moveTo(screen(face.world(const Offset(5, 2.5))));
    await tester.pump();
    await drag.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump();
    expect(_hint(tester), 'Every piece is wrapped.');
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(room, findsOneWidget);
    expect(find.byKey(const Key('grid-model-layer')), findsNothing);
    expect(painter().crafts.single.finished, isTrue);
    expect(
      (painter().camera.camera.position - roomPose).length,
      lessThan(1e-6),
    );
  });

  testWidgets('a pattern level cuts the net out of pattern paper in 3D', (
    tester,
  ) async {
    final domino = _domino();
    final level = domino.copyWith(
      steps: [
        domino.steps.single.copyWith(
          pattern: const CutPattern(
            period: Offset(5, 5),
            segments: [
              (Offset(0, 0), Offset(5, 0)),
              (Offset(0, 0), Offset(0, 5)),
            ],
            sheet: Rect.fromLTWH(-10, -2, 25, 9),
          ),
        ),
      ],
    );
    await _open(tester, 'puzzle-pattern', level);
    await tester.pump();

    // The level opens on the model, with no flat view and no desk.
    expect(find.byKey(const Key('grid-model-layer')), findsOneWidget);
    expect(find.byKey(const Key('grid-view-mode')), findsNothing);
    expect(_modelPainter(tester).desk, isNull);

    final canvasFinder = find.byKey(const Key('grid-puzzle-canvas'));
    final canvas = tester.getTopLeft(canvasFinder);
    final viewport = tester.getSize(canvasFinder);
    Offset screen(Vector3 world) {
      final painter = _modelPainter(tester);
      return canvas + painter.camera.camera.projectToScreen(world, viewport)!;
    }

    int score() => int.parse(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const Key('grid-score')),
              matching: find.byType(Text),
            ),
          )
          .data!,
    );

    // The sheet waits in the inventory. Over the floor, a tap lays it there,
    // selected and flashing in, with the floor's cell on the pattern lit.
    await tester.timedDragFrom(
      tester.getCenter(canvasFinder),
      const Offset(0, 260),
      const Duration(milliseconds: 300),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 250));
    final item = find.byKey(const Key('grid-inventory-sheet'));
    expect(item, findsOneWidget);
    await tester.tap(item);
    await tester.pump();
    expect(
      _hint(tester),
      'Drag to slide the paper, then cut it with the scissors.',
    );
    final model = _modelPainter(tester).model;
    final floor = model.faceOfRing(0)!;
    final face = model.faces[floor];
    expect(_wrapLayer(tester).cut.flaps, hasLength(1));
    expect(_wrapLayer(tester).outline, lessThan(0.2));
    expect(_wrapLayer(tester).opacity, 1);
    expect(_wrapLayer(tester).aligned, isTrue);
    expect(alignedCell(_wrapLayer(tester).cut, 0), isNotNull);
    await tester.pump(const Duration(milliseconds: 300));
    final greening = _wrapPainter(tester).alignedFade[floor]!;
    expect(greening, inExclusiveRange(0, 1));
    expect(_wrapLayer(tester).outline, closeTo(1, 1e-9));
    await tester.pump(const Duration(milliseconds: 600));
    expect(_wrapPainter(tester).alignedFade[floor], 1);

    // The edge glow waits for the blade.
    expect(_modelPainter(tester).edgeGlow[floor], isNull);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('grid-model-tools')),
        matching: find.byIcon(Icons.content_cut),
      ),
    );
    await tester.pump();
    expect(
      _hint(tester),
      'Aim at and tap a red ring or the pattern paper to set the blade.',
    );

    // Rings suggest starts at the floor's vertices, and the start a tap
    // would take shows under the aim.
    final floorEdges = face.outline;
    expect(_wrapLayer(tester).starts, hasLength(floorEdges.length));
    final corner = screen(face.world(const Offset(0.2, 0.3)));
    await tester.sendEventToBinding(
      PointerHoverEvent(kind: PointerDeviceKind.mouse, position: corner),
    );
    await tester.pump();
    expect(_wrapLayer(tester).aimedStart, Offset.zero);

    // A click on a ring sets the blade there.
    final ring = _wrapLayer(tester).starts.first;
    final paperToWorld = _wrapLayer(tester).cut.flapToWorld(0);
    await _click(
      tester,
      screen(paperToWorld.transformed3(Vector3(ring.dx, ring.dy, 0))) +
          const Offset(6, 4),
    );
    expect(_wrapLayer(tester).cut.blade, ring);
    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(_wrapLayer(tester).cut.blade, isNull);

    // A click near the floor's corner sets the blade on the pattern there,
    // and the camera orbits round to it, on the same lens.
    final camera = _modelPainter(tester).camera;
    await _click(tester, screen(face.world(const Offset(0.2, 0.3))));
    expect(
      _hint(tester),
      'Tap a red dot, or toward a line, to cut. Drag to look around.',
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(camera.focalLengthMm, closeTo(50, 0.1));
    expect(_modelPainter(tester).edgeGlow[floor], 1);

    WrapCut cut() => _wrapLayer(tester).cut;

    // The follow view looks square at the blade's face from the paper's
    // side, turned 80% of the way to the blade as seen from the model's
    // middle.
    Vector3 followView(double pull) {
      final at = cut().flapToWorld(0).transformed3(Vector3.zero());
      final square = cut().flapNormal(0);
      if (square.dot(camera.camera.position - at) < 0) square.negate();
      final toward = (at - model.center).normalized();
      return (square + (toward - square) * pull).normalized();
    }

    expect(_angle(camera.viewDirection, followView(0.8)), lessThan(0.05));
    expect(_angle(followView(0.8), followView(0)), greaterThan(0.1));

    // The zoom closes in until every next cut fits, inside the frame.
    final opening = camera
        .frameSphere(model.center, model.radius * 1.3, viewport)
        .halfHeight;
    expect(cut().options(), isNotEmpty);
    expect(camera.framedHalfHeightMm, lessThan(opening * 0.9));
    for (final option in cut().options()) {
      final at = cut()
          .flapToWorld(cut().flapAfter(option))
          .transformed3(Vector3(option.end.dx, option.end.dy, 0));
      final projected = camera.camera.projectToScreen(at, viewport);
      expect(projected, isNotNull);
      expect(projected!.dx, greaterThan(viewport.width * 0.04));
      expect(projected.dx, lessThan(viewport.width * 0.96));
      expect(projected.dy, greaterThan(viewport.height * 0.04));
      expect(projected.dy, lessThan(viewport.height * 0.96));
    }

    // DevTools' Blade pull sets how far: none looks square at the face.
    await tester.tap(find.text('devtools'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('grid-dev-section')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Camera').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.drag(
      find.byKey(const Key('grid-cut-follow')),
      const Offset(-400, 0),
    );
    await tester.pump();
    expect(find.text('0%'), findsOneWidget);
    await tester.tap(find.text('devtools'));
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(_angle(camera.viewDirection, followView(0)), lessThan(0.05));

    // Each tap cuts toward its side of the blade. The cut starts where the
    // blade was set down.
    Future<void> cutTo(Offset to) async {
      final at = cut();
      final from = at.blade!;
      final step = (to - from) / (to - from).distance;
      final toWorld = at.flapToWorld(at.bladeFlap(from, step));
      Offset paper(Offset point) =>
          screen(toWorld.transformed3(Vector3(point.dx, point.dy, 0)));
      final a = paper(from);
      final b = paper(from + step);
      await tester.tapAt(a + (b - a) / (b - a).distance * 80);
      await tester.pump();
      for (var i = 0; i < 24; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(cut().blade, to);
      expect(_wrapLayer(tester).path.first, Offset.zero);
    }

    // Red dots mark the next vertex of a pattern line. A tap well clear of
    // the dot, as when the tool bar covers it, still takes it.
    expect(cut().blade, Offset.zero);
    final next = _wrapLayer(tester).next;
    expect({
      for (final step in next) step.at,
    }, containsAll(const [Offset(5, 0), Offset(0, 5), Offset(-5, 0)]));
    expect(next.every((step) => !step.travel), isTrue);
    final east = next.singleWhere((step) => step.at == const Offset(5, 0));
    await tester.tapAt(
      screen(cut().flapToWorld(east.flap).transformed3(Vector3(5, 0, 0))) +
          const Offset(0, -64),
    );
    await tester.pump();
    expect(_wrapLayer(tester).next, isEmpty);
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(cut().blade, const Offset(5, 0));
    expect(_wrapLayer(tester).next, isNotEmpty);
    expect(cut().folds, isEmpty);

    // Past the wall's edge the paper stays flat.
    await cutTo(const Offset(10, 0));
    expect(cut().folds, isEmpty);

    // The fold tool keeps the cut at its blade. A tap there cuts nothing.
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('grid-model-tools')),
        matching: find.byIcon(Icons.flip),
      ),
    );
    await tester.pump();
    expect(
      _hint(tester),
      'Drag along an edge of the model to fold the paper over it.',
    );
    expect(cut().blade, const Offset(10, 0));
    await tester.tapAt(screen(face.world(const Offset(2, 2))));
    await tester.pump(const Duration(milliseconds: 400));
    expect(cut().blade, const Offset(10, 0));
    expect(_modelPainter(tester).edgeGlow[floor] ?? 0, lessThan(0.01));

    // A line dragged near the wall's edge, a little askew, takes that edge.
    final edgeFrom = screen(face.world(const Offset(4.8, 0.6)));
    final edgeTo = screen(face.world(const Offset(4.9, 4.4)));
    final drag = await tester.startGesture(edgeFrom);
    for (var i = 1; i <= 8; i++) {
      await drag.moveTo(Offset.lerp(edgeFrom, edgeTo, i / 8)!);
      await tester.pump();
    }
    expect(_wrapPainter(tester).foldLine, isNotNull);
    final aim = _wrapPainter(tester).foldAim!;
    for (final end in [aim.$1, aim.$2]) {
      expect(
        [
          face.world(const Offset(5, 0)),
          face.world(const Offset(5, 5)),
        ].any((corner) => (corner - end).length < 1e-6),
        isTrue,
      );
    }
    await drag.up();
    await tester.pump();

    // The paper folds up onto the wall, and the edge glows in and out.
    expect(cut().folds, hasLength(1));
    expect(cut().flaps[1].face, model.faceOfRing(1));
    expect(cut().flaps[cut().bladeOn!].face, model.faceOfRing(1));
    expect(_wrapPainter(tester).foldLine, isNull);
    await tester.pump(const Duration(milliseconds: 150));
    expect(_wrapPainter(tester).foldEdge, isNotNull);
    expect(_wrapPainter(tester).foldEdgeGlow, greaterThan(0.8));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_wrapPainter(tester).foldEdge, isNull);

    // Back to the scissors, the cut carries on from the blade.
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('grid-model-tools')),
        matching: find.byIcon(Icons.content_cut),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await cutTo(const Offset(10, 5));
    await cutTo(const Offset(5, 5));
    await cutTo(const Offset(0, 5));

    // Mid-cut, a drag peeks around the face on a spring, held to a limit,
    // and springs back to the follow view on release. It cuts nothing.
    final follow = camera.viewDirection.clone();
    final blade = cut().blade;
    final peekFrom =
        canvas + Offset(viewport.width * 0.3, viewport.height * 0.4);
    final peek = await tester.startGesture(peekFrom);
    var furthest = 0.0;
    for (var i = 1; i <= 8; i++) {
      await peek.moveTo(peekFrom + Offset(30.0 * i, 0));
      await tester.pump();
      furthest = math.max(furthest, _angle(camera.viewDirection, follow));
    }
    expect(furthest, greaterThan(0.2));
    expect(furthest, lessThan(0.8));
    await peek.up();
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(_angle(camera.viewDirection, follow), lessThan(0.03));
    expect(cut().blade, blade);
    final before = score();

    // Closing the loop finishes the cut: the net wraps both faces.
    final last = cut();
    final step = const Offset(0, -1);
    final toWorld = last.flapToWorld(last.bladeFlap(last.blade!, step));
    Offset paper(Offset point) =>
        screen(toWorld.transformed3(Vector3(point.dx, point.dy, 0)));
    final a = paper(last.blade!);
    final b = paper(last.blade! + step);
    await tester.tapAt(a + (b - a) / (b - a).distance * 80);
    await tester.pump();

    // Extra paper fades out. Faces the kept paper covers hide under it.
    // Then leftover is in the inventory, a ring flashes around it, and
    // the drawer closes.
    var faded = false;
    var hid = false;
    String? leftoverId;
    for (var i = 0; i < 80 && find.text('+200').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 25));
      final painter = _modelPainter(tester);
      expect(painter.fadingPatches, isEmpty);
      final layers = _wrapPainter(tester).layers;
      if (layers.any((l) => l.opaque)) {
        expect(painter.covered[floor] ?? 0, greaterThan(0.9));
        hid = true;
      }
      final leftover = layers.where((l) => !l.opaque);
      if (leftover.isEmpty) continue;
      leftoverId = leftover.single.piece.id;
      if (leftover.single.opacity < 0.85) faded = true;
    }
    expect(hid, isTrue);
    expect(faded, isTrue);
    expect(find.text('+200'), findsOneWidget);
    expect(
      {for (final patch in _modelPainter(tester).patches) patch.face},
      {floor, model.faceOfRing(1)},
    );
    expect(_modelPainter(tester).fadingPatches, isEmpty);
    expect(_modelPainter(tester).covered, {
      floor: 1.0,
      model.faceOfRing(1)!: 1.0,
    });
    expect(score(), before + 200);
    expect(leftoverId, isNotNull);
    var opened = false;
    var flashed = false;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 25));
      if (find.byKey(const Key('grid-inventory')).evaluate().isEmpty) {
        continue;
      }
      opened = true;
      expect(find.byKey(Key('grid-inventory-$leftoverId')), findsOneWidget);
      final inventory = tester.widget<PieceInventory>(
        find.byType(PieceInventory),
      );
      if (inventory.flashId == leftoverId &&
          inventory.flash > 0.1 &&
          inventory.flash < 1) {
        flashed = true;
      }
    }
    expect(opened, isTrue);
    expect(flashed, isTrue);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
    expect(find.byKey(const Key('grid-inventory')), findsNothing);
    expect(_hint(tester), 'Every face is wrapped.');
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(camera.focalLengthMm, closeTo(50, 0.1));
    expect(_modelPainter(tester).edgeGlow, isEmpty);

    // Undo puts the whole sheet back in hand and takes the score back.
    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(_modelPainter(tester).patches, isEmpty);
    expect(score(), before);
  });
}
