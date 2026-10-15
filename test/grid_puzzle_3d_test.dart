import 'dart:io';
import 'dart:math' as math;

import 'package:flatmates/gridcraft/blueprint.dart';
import 'package:flatmates/gridcraft/level_io.dart';
import 'package:flatmates/gridcraft/model_painter.dart';
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
  testWidgets('3D mode: focus a face, lay the paper, and it wraps', (
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
    expect(find.byKey(const Key('grid-piece-inventory')), findsNothing);

    final canvas = tester.getTopLeft(
      find.byKey(const Key('grid-puzzle-canvas')),
    );
    final viewport = tester.getSize(
      find.byKey(const Key('grid-puzzle-canvas')),
    );
    Offset screen(Vector3 world) {
      final painter = _modelPainter(tester);
      return canvas + painter.camera.camera.projectToScreen(world, viewport)!;
    }

    final painter = _modelPainter(tester);
    final wall = painter.model.faceOfRing(1)!;
    final wallCenter = screen(painter.model.worldCenter(wall));
    await tester.tapAt(wallCenter);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(wallCenter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(_modelPainter(tester).focusFace, wall);
    expect(find.byKey(const Key('grid-piece-inventory')), findsOneWidget);
    expect(_hint(tester), 'Pick a paper piece on the right.');

    await tester.tap(find.byKey(const Key('grid-inventory-paper')));
    await tester.pump();
    expect(_hint(tester), 'Slide and turn the paper until the face glows.');

    final face = _modelPainter(tester).model.faces[wall];
    final from = screen(face.world(face.centroid));
    final to = screen(face.world(face.centroid + const Offset(-3, 0)));
    await tester.timedDragFrom(
      from,
      to - from,
      const Duration(milliseconds: 300),
    );
    await tester.pump();
    expect(_modelPainter(tester).glow[wall], greaterThan(0));
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump();
    expect(_hint(tester), 'Every piece is wrapped.');
    expect(_modelPainter(tester).paperPoses.keys.toSet(), {0, 1});

    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(_modelPainter(tester).paperPoses, isEmpty);
    expect(_hint(tester), 'Pick a paper piece on the right.');

    await tester.tap(find.byKey(const Key('grid-focus-back')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(_modelPainter(tester).focusFace, isNull);

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
