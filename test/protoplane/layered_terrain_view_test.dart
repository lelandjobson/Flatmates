import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/harvest_meshes.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'layered_terrain_test.dart' show centerId, drawTile, snapshot;

void main() {
  testWidgets('atlas updates columns only, stable pans and restore signatures', (
    tester,
  ) async {
    final c = ProtoplaneController();
    final cache = HarvestMeshCache();
    addTearDown(c.dispose);
    addTearDown(cache.dispose);
    final before = snapshot(c);
    cache.synchronize(c.planes.values, c.landscape);
    final initial = cache.rasterizedTiles;
    final wallMeshes = cache.walls(c.landscape.terrain).toList();
    expect(wallMeshes.length, greaterThan(6));
    final initialWalls = cache.rebuiltWalls;
    final image = cache.atlas.image;
    final watch = Stopwatch()..start();
    for (var i = 0; i < 120; i++) {
      cache.synchronize(c.planes.values, c.landscape);
    }
    watch.stop();
    // ignore: avoid_print
    print(
      'Layered terrain 120 cache-only pan checks: ${watch.elapsedMilliseconds} ms; $initial slots',
    );
    expect(cache.rasterizedTiles, initial);
    expect(cache.atlas.image, same(image));
    final id = centerId(c, PaperMaterial.paperWhite);
    c.enter(id);
    drawTile(c);
    c.commitDrawing();
    cache.synchronize(c.planes.values, c.landscape);
    cache.walls(c.landscape.terrain).toList();
    expect(cache.rasterizedTiles, initial + 3);
    expect(cache.rebuiltWalls, initialWalls + 1);
    c.undo();
    expect(snapshot(c), before);
    cache.synchronize(c.planes.values, c.landscape);
    expect(cache.rasterizedTiles, initial + 6);
    c.redo();
    cache.synchronize(c.planes.values, c.landscape);
    expect(cache.rasterizedTiles, initial + 9);
  });
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('Paper island rendering and release tools at $size', (
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
          theme: ThemeData.dark(),
          home: RepaintBoundary(
            key: const ValueKey('islands-capture'),
            child: ProtoplaneConceptView(animateFog: false, controller: c),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> capture(String stage) async {
        expect(tester.takeException(), isNull);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('islands-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '/tmp/paper-islands-${size.width.toInt()}-$stage.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('world');
      final worldScene = tester
          .widget<SceneView>(find.byType(SceneView).first)
          .scene;
      final painter = ScenePainter(scene: worldScene);
      final timings = <int>[];
      final textures = worldScene.meshes
          .where((m) => m.planarTexture != null)
          .map((m) => m.planarTexture!.atlas.image)
          .toList();
      for (var frame = 0; frame < 120; frame++) {
        worldScene.camera!.position.x += frame.isEven ? .01 : -.01;
        final recorder = ui.PictureRecorder();
        final timer = Stopwatch()..start();
        painter.paint(Canvas(recorder), size);
        timer.stop();
        timings.add(timer.elapsedMicroseconds);
        recorder.endRecording().dispose();
      }
      timings.sort();
      debugPrint(
        'Paper world pan ${size.width}: median ${timings[60]} us, p95 ${timings[114]} us',
      );
      expect(
        worldScene.meshes
            .where((m) => m.planarTexture != null)
            .map((m) => m.planarTexture!.atlas.image)
            .toList(),
        textures,
      );
      final id = centerId(c, PaperMaterial.paperWhite);
      c.enter(id);
      await tester.pumpAndSettle();
      final camera = tester
          .widget<SceneView>(find.byType(SceneView).first)
          .scene
          .camera!;
      Offset point(Offset local) =>
          camera.projectToScreen(c.activePlane!.point(local, .008), size)!;
      final nodes = c.grid!.nodes;
      final step = nodes
          .where((p) => p.dx > 0)
          .map((p) => p.dx)
          .reduce((a, b) => a < b ? a : b);
      final path = [
        Offset.zero,
        Offset(step, 0),
        Offset(step, step),
        Offset(0, step),
        Offset.zero,
      ];
      final gesture = await tester.startGesture(point(path.first));
      for (final p in path.skip(1)) {
        await gesture.moveTo(point(p));
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(c.drawingReady, isTrue);
      expect(c.balances[PaperMaterial.paperWhite], 256);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(c.balances[PaperMaterial.paperWhite], greaterThan(256));
      await capture('cut');
      final graphite = centerId(c, PaperMaterial.graphite);
      // Tap the exposed lower material away from grid nodes, including while focused.
      final exposed = c.landscape.terrain.exposed(graphite).first;
      final target = c.planes[graphite]!.point(exposed.bounds.center);
      await tester.tapAt(camera.projectToScreen(target, size)!);
      await tester.pumpAndSettle();
      expect(c.activePlaneId, centerId(c, PaperMaterial.paperWhite));
      await capture('graphite');
      c.selectTool(CraftTool.place);
      expect(find.byTooltip('Place'), findsOneWidget);
      c.leave();
      await tester.pumpAndSettle();
      await capture('world-cut');
      // Layered holes, not permanent backing.
      for (final material in paperMaterials) {
        final p = c.planes[centerId(c, material)]!;
        final result = c.landscape.preview(p, rectangle(1, 1));
        if (result != null) c.landscape.collect(result);
      }
      c.enter(centerId(c, PaperMaterial.cork));
      await tester.pumpAndSettle();
      await capture('hole');
      await tester.pumpWidget(const SizedBox());
    });
  }
}
