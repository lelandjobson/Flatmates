import 'dart:io';
import 'dart:math' as math;

import 'package:flatmates/gridcraft/blueprint.dart';
import 'package:flatmates/gridcraft/craft_collection.dart';
import 'package:flatmates/gridcraft/craft_collection_painter.dart';
import 'package:flatmates/gridcraft/folded_model.dart';
import 'package:flatmates/gridcraft/level_io.dart';
import 'package:flatmates/gridcraft/model_painter.dart';
import 'package:flatmates/gridcraft/painter.dart';
import 'package:flatmates/papercut/craft_v1.dart';
import 'package:flatmates/screens/grid_puzzle_view.dart';
import 'package:flatmates/ui/fm_theme.dart';
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

void main() {
  testWidgets('3D mode: the reticle preselects, a drop focuses and wraps', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final directory = Directory.systemTemp.createTempSync('puzzle-3d');
    addTearDown(() => directory.delete(recursive: true));
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => FmThemeData(),
        child: MaterialApp(
          home: GridPuzzleView(
            initial: _domino(),
            store: LevelStore(directory: directory),
            crafts: [_dominoCraft()],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

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

    double frame() => tester
        .widget<AnimatedOpacity>(find.byKey(const Key('grid-focus-frame')))
        .opacity;

    // The model floats over the desk.
    final model = _modelPainter(tester).model;
    expect(model.bounds.min.z, greaterThan(1));
    expect(_modelPainter(tester).desk, isNotNull);

    // A double-tap on the grey desk paper focuses the desk; from there the
    // paper drags into the inventory.
    final deskPaper = screen(Vector3(0.8, 0.8, 0));
    await tester.tapAt(deskPaper);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(deskPaper);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      _hint(tester),
      'Slide paper on the desk, or drag it right to stow it.',
    );
    expect(frame(), 1);
    await tester.timedDragFrom(
      deskPaper,
      tester.getCenter(column) - deskPaper,
      const Duration(milliseconds: 400),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(item, findsOneWidget);
    await tester.tap(find.byKey(const Key('grid-focus-back')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Orbit to look straight down, so the reticle lands on the floor.
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
    expect(frame(), 0);

    // Drop the paper with its middle on its own blueprint middle.
    final face = _modelPainter(tester).model.faces[floor];
    final drag = await tester.startGesture(tester.getCenter(item));
    await drag.moveBy(const Offset(-40, 0));
    await tester.pump();
    await drag.moveTo(screen(face.world(const Offset(5, 2.5))));
    await tester.pump();
    final preview = tester
        .widget<CustomPaint>(find.byKey(const Key('grid-model-layer')))
        .foregroundPainter;
    expect(preview, isA<GridPuzzlePainter>());
    expect((preview! as GridPuzzlePainter).sheet.pieces, hasLength(1));
    final scoreBefore = score();
    await drag.up();
    await tester.pump();
    expect(find.byKey(const Key('grid-focus-back')), findsOneWidget);
    expect(_modelPainter(tester).glow[floor], greaterThan(0));
    final focusedHalf = _modelPainter(tester).camera.framedHalfHeightMm;
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump();
    expect(_hint(tester), 'Every piece is wrapped.');
    expect(_modelPainter(tester).paperPoses.keys.toSet(), {0, 1});

    // The wrap backs the camera out and turns it once around the model,
    // then scores.
    expect(find.byKey(const Key('grid-focus-back')), findsNothing);
    await tester.pump(const Duration(milliseconds: 500));
    final camera = _modelPainter(tester).camera;
    final backedOut = camera.camera.position.clone();
    expect(camera.framedHalfHeightMm, greaterThan(focusedHalf));
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

    // Back over the floor, a tap lays the paper on it, three cells left of
    // home.
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
    expect(_hint(tester), 'Slide and turn the paper until the face glows.');
    expect(find.byKey(const Key('grid-place-turn-left')), findsNothing);

    // Paper in hand goes back to the inventory, by Stow or by dragging it
    // onto the inventory. Focus stays on the face either way.
    final stow = find.byKey(const Key('grid-focus-stow'));
    expect(stow, findsOneWidget);
    expect(column, findsOneWidget);
    expect(item, findsNothing);
    await tester.tap(stow);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(item, findsOneWidget);
    expect(stow, findsNothing);
    expect(find.byKey(const Key('grid-focus-back')), findsOneWidget);
    expect(_hint(tester), 'Drag a paper piece onto the face.');
    await tester.tap(item);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(item, findsNothing);
    final handPainter =
        tester
                .widget<CustomPaint>(find.byKey(const Key('grid-model-layer')))
                .foregroundPainter!
            as GridPuzzlePainter;
    final handRect = pointBounds(handPainter.sheet.pieces.single.vertices);
    final held = screen(
      face.world(Offset(handRect.left + 1, handRect.center.dy)),
    );
    await tester.timedDragFrom(
      held,
      tester.getCenter(column) - held,
      const Duration(milliseconds: 400),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(item, findsOneWidget);
    expect(find.byKey(const Key('grid-focus-back')), findsOneWidget);
    expect(_modelPainter(tester).paperPoses, isEmpty);
    expect(_modelPainter(tester).loose, isEmpty);
    await tester.tap(item);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The rotate icon on the paper opens a ring around it. Dragging the ring
    // a quarter of the way round turns the paper a quarter turn, and dragging
    // it back puts the paper exactly where it was.
    Rect inHand() {
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const Key('grid-model-layer')),
                  )
                  .foregroundPainter!
              as GridPuzzlePainter;
      return pointBounds(painter.sheet.pieces.single.vertices);
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
    expect(inHand(), flat);
    await tester.tap(
      find.descendant(of: gimbal, matching: find.byIcon(Icons.close)),
    );
    await tester.pump();
    expect(gimbal, findsNothing);
    expect(find.byKey(const Key('grid-place-rotate')), findsOneWidget);

    // A double-tap away from the face and its paper leaves focus, and the
    // paper stays loose on the face.
    final empty = canvas + Offset(24, viewport.height * 0.45);
    await tester.tapAt(empty);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(empty);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('grid-focus-back')), findsNothing);
    expect(frame(), 0);
    expect(_modelPainter(tester).loose, hasLength(1));

    // Tapping the loose paper focuses the face with it in hand.
    await tester.tapAt(screen(face.world(const Offset(2, 2.5))));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('grid-focus-back')), findsOneWidget);
    expect(_hint(tester), 'Slide and turn the paper until the face glows.');

    // Tapping the paper again completes a double-tap on the focused face's
    // paper, which flies the camera square onto the face.
    expect(camera.viewDirection.dot(model.outwardNormal(floor)), lessThan(0.9));
    await tester.tapAt(screen(face.world(const Offset(2, 2.5))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(
      camera.viewDirection.dot(model.outwardNormal(floor)),
      closeTo(1, 1e-6),
    );
    expect(find.byKey(const Key('grid-focus-back')), findsOneWidget);

    // One finger off the paper pans along the face.
    final before = camera.target;
    await tester.timedDragFrom(
      canvas + Offset(60, viewport.height * 0.3),
      const Offset(-80, 0),
      const Duration(milliseconds: 200),
    );
    await tester.pump();
    expect((camera.target - before).length, greaterThan(0.5));
    expect((camera.target.z - before.z).abs(), lessThan(1e-6));

    // Sliding the paper home matches and wraps.
    final from = screen(face.world(const Offset(2, 2.5)));
    final to = screen(face.world(const Offset(5, 2.5)));
    await tester.timedDragFrom(
      from,
      to - from,
      const Duration(milliseconds: 300),
    );
    await tester.pump();
    expect(_modelPainter(tester).glow[floor], greaterThan(0));
    await tester.pump(const Duration(milliseconds: 1000));
    expect(_hint(tester), 'Every piece is wrapped.');

    // Wrapping the same island again turns the camera but scores nothing.
    await tester.pump(const Duration(milliseconds: 2300));
    await tester.pump();
    expect(score(), scoreBefore + 100);

    await tester.tap(toggle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byKey(const Key('grid-model-layer')), findsNothing);
  });

  testWidgets('double-tapping desk paper focuses the desk, then crafts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final directory = Directory.systemTemp.createTempSync('puzzle-3d-craft');
    addTearDown(() => directory.delete(recursive: true));
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => FmThemeData(),
        child: MaterialApp(
          home: GridPuzzleView(
            initial: _domino(),
            store: LevelStore(directory: directory),
            crafts: [_dominoCraft()],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('grid-view-mode')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    final canvasFinder = find.byKey(const Key('grid-puzzle-canvas'));
    final canvas = tester.getTopLeft(canvasFinder);
    final viewport = tester.getSize(canvasFinder);
    final camera = _modelPainter(tester).camera;
    final paper =
        canvas + camera.camera.projectToScreen(Vector3(0.8, 0.8, 0), viewport)!;

    Future<void> doubleTap() async {
      await tester.tapAt(paper);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(paper);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    await doubleTap();
    expect(
      _hint(tester),
      'Slide paper on the desk, or drag it right to stow it.',
    );
    expect(find.byKey(const Key('grid-model-layer')), findsOneWidget);

    await doubleTap();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byKey(const Key('grid-model-layer')), findsNothing);
    expect(find.byKey(const Key('grid-focus-back')), findsNothing);
  });

  testWidgets('3D pans keep the grabbed point under the pointer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final directory = Directory.systemTemp.createTempSync('puzzle-3d-pan');
    addTearDown(() => directory.delete(recursive: true));
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => FmThemeData(),
        child: MaterialApp(
          home: GridPuzzleView(
            initial: _domino(),
            store: LevelStore(directory: directory),
            crafts: [_dominoCraft()],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
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
      final ray = camera.camera.unprojectRay(at - canvas, viewport)!;
      final hit = pickFace(model, ray.origin, ray.direction)!;
      return ray.pointAt(hit.distance);
    }

    void expectUnder(Vector3 point, Offset at) {
      final seen = camera.camera.projectToScreen(point, viewport)!;
      expect((canvas + seen - at).distance, lessThan(0.5));
      expect((camera.viewDirection - look).length, lessThan(1e-9));
    }

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
    expect(find.byKey(const Key('grid-focus-back')), findsNothing);

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

    // Two fingers pan too, holding what is under their middle once the pan
    // begins.
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
  });

  testWidgets('a level without a craft has no 3D toggle', (tester) async {
    final directory = Directory.systemTemp.createTempSync('puzzle-3d-none');
    addTearDown(() => directory.delete(recursive: true));
    final plain = _domino();
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => FmThemeData(),
        child: MaterialApp(
          home: GridPuzzleView(
            initial: GridBlueprint(
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
            store: LevelStore(directory: directory),
            crafts: [_dominoCraft()],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
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
    await tester.tapAt(deskPaper);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(deskPaper);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.timedDragFrom(
      deskPaper,
      tester.getCenter(column) - deskPaper,
      const Duration(milliseconds: 400),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(item, findsOneWidget);
    await tester.tap(find.byKey(const Key('grid-focus-back')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
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
}
