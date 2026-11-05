import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;
import 'package:flatmates/protoplane/adjacent_grid_indicators.dart';
import 'package:flatmates/geometry/geometry.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/meshes.dart';
import 'package:flatmates/rendering/scene/camera.dart';
import 'package:flatmates/rendering/scene/scene.dart';
import 'package:flatmates/rendering/world_crop_box.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';
import 'layered_terrain_test.dart' show centerId;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'indicators match swipe destinations, omit active tile and preserve state',
    () {
      final c = ProtoplaneController();
      addTearDown(c.dispose);
      c.enter(centerId(c, PaperMaterial.paperWhite));
      final before = c.toJson(), undo = c.canUndo;
      final indicators = adjacentGridIndicators(c);
      expect(indicators, hasLength(4));
      expect(
        indicators.map((i) => i.plane.id).toSet(),
        c.navigationGraph.swipeNeighbors[c.activePlaneId]!
            .map((n) => n.planeId)
            .toSet(),
      );
      expect(
        indicators.every(
          (i) => i.plane.id != c.activePlaneId && i.nodes.isNotEmpty,
        ),
        isTrue,
      );
      expect(c.toJson(), before);
      expect(c.canUndo, undo);
      c.leave();
      expect(adjacentGridIndicators(c), isEmpty);
    },
  );

  test(
    'no dots in holes, empty columns, or on buried layers; lower neighbors work',
    () {
      final c = ProtoplaneController();
      addTearDown(c.dispose);
      final terrain = c.landscape.terrain;
      String tile(PaperMaterial material, int x) => terrain.tiles.values
          .firstWhere(
            (t) =>
                t.x == x &&
                t.y == 0 &&
                t.sheet.island == 'starter' &&
                t.sheet.material == material,
          )
          .id;
      for (final material in [
        PaperMaterial.paperWhite,
        PaperMaterial.graphite,
      ]) {
        c.landscape.deplete(tile(material, -1), rectangle(1, 1));
      }
      c.landscape.deplete(
        tile(PaperMaterial.paperWhite, 1),
        rectangle(.5, .5, origin: const Offset(.25, .25)),
      );
      c.enter(centerId(c, PaperMaterial.paperWhite));
      final indicators = adjacentGridIndicators(c);
      expect(
        indicators.map((i) => i.plane.id),
        contains(tile(PaperMaterial.cork, -1)),
      );
      final east = indicators.singleWhere(
        (i) => i.plane.id == tile(PaperMaterial.paperWhite, 1),
      );
      expect(east.nodes, isNot(contains(const Offset(.5, .5))));
      expect(
        east.nodes.every(
          (n) => c.surfaceRegions(east.plane).any((r) => r.contains(n)),
        ),
        isTrue,
      );
      expect(
        indicators.map((i) => i.plane.id),
        isNot(contains(tile(PaperMaterial.graphite, 1))),
      );
    },
  );

  test(
    'surrounding source grid does not show through the focused floor piece',
    () {
      final c = ProtoplaneController();
      addTearDown(c.dispose);
      final source = c.planes[centerId(c, PaperMaterial.paperWhite)]!;
      final region = rectangle(.5, .5, origin: const Offset(.25, .25));
      c.objects['floor-test'] = CraftObject(
        id: 'floor-test',
        planeId: source.id,
        kind: CraftKind.floor,
        region: region,
        material: PaperMaterial.paperWhite,
        depth: 0,
      );
      c.planes['surface-floor-test'] = CraftPlane(
        id: 'surface-floor-test',
        owner: 'floor-test',
        origin: source.origin,
        u: source.u,
        v: source.v,
        region: region,
        grids: [lattice('floor-test', region)],
      );
      c.enter('surface-floor-test');
      final surrounding = adjacentGridIndicators(
        c,
      ).singleWhere((i) => i.plane.id == source.id);
      expect(surrounding.nodes, isNot(contains(const Offset(.5, .5))));
      expect(surrounding.nodes, contains(Offset.zero));
    },
  );

  test('wall focus has no surrounding floor dot grid', () {
    final c = ProtoplaneController();
    addTearDown(c.dispose);
    c.planes['vertical-test'] = CraftPlane(
      id: 'vertical-test',
      origin: Vector3.zero(),
      u: Vector3(1, 0, 0),
      v: Vector3(0, 1, 0),
      region: rectangle(1, 1),
      grids: [lattice('vertical-test', rectangle(1, 1))],
    );
    c.enter('vertical-test');
    expect(adjacentGridIndicators(c), isEmpty);
  });

  test(
    'dots render with context, respect crop/opacity, and hide in preview',
    () async {
      final c = ProtoplaneController();
      addTearDown(c.dispose);
      c.enter(centerId(c, PaperMaterial.paperWhite));
      final camera = Camera(
        name: 'dots',
        position: Vector3(.5, 5, -.5),
        target: Vector3(.5, 0, -.5),
        up: Vector3(0, 0, -1),
      );
      final scene = Scene()..camera = camera;
      addTearDown(scene.dispose);
      scene.setMeshes([
        for (final i in adjacentGridIndicators(c)) planeMesh(i.plane),
      ]);
      Future<int> pixels({bool enabled = true, double opacity = 1}) async {
        final recorder = ui.PictureRecorder();
        AdjacentGridPainter(
          c,
          camera,
          scene,
          enabled: enabled,
          opacity: opacity,
        ).paint(Canvas(recorder), const Size(400, 400));
        final picture = recorder.endRecording();
        final image = await picture.toImage(400, 400);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        var count = 0;
        for (var i = 3; i < bytes.lengthInBytes; i += 4) {
          if (bytes.getUint8(i) > 0) count++;
        }
        image.dispose();
        picture.dispose();
        return count;
      }

      expect(await pixels(), greaterThan(0));
      expect(await pixels(enabled: false), 0);
      expect(await pixels(opacity: 0), 0);
      for (final m in scene.meshes) {
        m.cropBox = WorldCropBox(
          Vector3(100, 100, 100),
          Vector3(101, 101, 101),
        );
      }
      expect(await pixels(), 0);
      for (final m in scene.meshes) {
        m.cropBox = null;
        m.material = MaterialModel(color: Colors.white, opacity: 0);
      }
      expect(await pixels(), 0);
    },
  );

  for (final size in [const Size(390, 844), const Size(900, 700)]) {
    testWidgets('adjacent dots are passive and switch off in 3D at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      final c = ProtoplaneController();
      addTearDown(() {
        c.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: ProtoplaneConceptView(controller: c, animateFog: false),
        ),
      );
      await tester.pumpAndSettle();
      c.enter(centerId(c, PaperMaterial.paperWhite));
      await tester.pumpAndSettle();
      final layer = find.byKey(const ValueKey('adjacent-grid-overlay'));
      AdjacentGridPainter painter() =>
          tester.widget<CustomPaint>(layer).painter! as AdjacentGridPainter;
      expect(painter().enabled, isTrue);
      expect(painter().opacity, 1);
      expect(
        tester
            .widget<IgnorePointer>(
              find
                  .ancestor(of: layer, matching: find.byType(IgnorePointer))
                  .first,
            )
            .ignoring,
        isTrue,
      );
      await tester.tap(find.byTooltip('3D'));
      await tester.pumpAndSettle();
      expect(painter().enabled, isFalse);
      await tester.tap(find.byTooltip('Grid'));
      await tester.pumpAndSettle();
      expect(painter().enabled, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
