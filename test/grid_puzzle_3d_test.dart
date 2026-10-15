import 'dart:io';
import 'dart:math' as math;

import 'package:flatmates/gridcraft/blueprint.dart';
import 'package:flatmates/gridcraft/level_io.dart';
import 'package:flatmates/gridcraft/model_painter.dart';
import 'package:flatmates/gridcraft/painter.dart';
import 'package:flatmates/papercut/craft_v1.dart';
import 'package:flatmates/screens/grid_puzzle_view.dart';
import 'package:flatmates/ui/fm_theme.dart';
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

    final toggle = find.byKey(const Key('grid-view-mode'));
    expect(toggle, findsOneWidget);
    await tester.tap(toggle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byKey(const Key('grid-model-layer')), findsOneWidget);
    expect(find.byKey(const Key('grid-frame-model')), findsOneWidget);

    final canvasFinder = find.byKey(const Key('grid-puzzle-canvas'));
    final canvas = tester.getTopLeft(canvasFinder);
    final viewport = tester.getSize(canvasFinder);
    Offset screen(Vector3 world) {
      final painter = _modelPainter(tester);
      return canvas + painter.camera.camera.projectToScreen(world, viewport)!;
    }

    double frame() => tester
        .widget<AnimatedOpacity>(find.byKey(const Key('grid-focus-frame')))
        .opacity;

    // Orbit to look straight down, so the reticle lands on the floor.
    await tester.timedDragFrom(
      tester.getCenter(canvasFinder),
      const Offset(0, 260),
      const Duration(milliseconds: 300),
    );
    await tester.pump();
    final floor = _modelPainter(tester).model.faceOfRing(0)!;
    expect(find.byKey(const Key('grid-piece-inventory')), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 250));
    expect(_modelPainter(tester).highlight[floor], 1);
    expect(find.byKey(const Key('grid-piece-inventory')), findsOneWidget);
    expect(_hint(tester), 'Drag a paper piece onto the highlighted face.');
    expect(frame(), 0);

    // Drop the paper with its middle on its own blueprint middle.
    final face = _modelPainter(tester).model.faces[floor];
    final item = find.byKey(const Key('grid-inventory-paper'));
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
    await drag.up();
    await tester.pump();
    expect(find.byKey(const Key('grid-focus-back')), findsOneWidget);
    expect(_modelPainter(tester).glow[floor], greaterThan(0));
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump();
    expect(_hint(tester), 'Every piece is wrapped.');
    expect(_modelPainter(tester).paperPoses.keys.toSet(), {0, 1});
    expect(frame(), 1);

    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(_modelPainter(tester).paperPoses, isEmpty);
    expect(_hint(tester), 'Drag a paper piece onto the face.');

    // A tap lays the paper over the face, three cells left of home.
    await tester.tap(item);
    await tester.pump();
    expect(_hint(tester), 'Slide and turn the paper until the face glows.');

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

    // One finger off the paper pans along the face.
    final camera = _modelPainter(tester).camera;
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

    await tester.tap(toggle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byKey(const Key('grid-model-layer')), findsNothing);
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
}
