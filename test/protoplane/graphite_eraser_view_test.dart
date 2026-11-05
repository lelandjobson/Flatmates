import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/graphite_pop_effects.dart';
import 'package:flatmates/protoplane/harvest_meshes.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';
import 'graphite_eraser_test.dart' show graphiteWorld;
import 'layered_terrain_test.dart' show centerId, snapshot;

void main() {
  testWidgets('scrub updates two atlas slots per batch and bounded local walls', (
    tester,
  ) async {
    final c = graphiteWorld();
    addTearDown(c.dispose);
    final cache = HarvestMeshCache();
    addTearDown(cache.dispose);
    cache.synchronize(c.planes.values, c.landscape);
    cache.walls(c.landscape.terrain!).toList();
    final slots = cache.rasterizedTiles, walls = cache.rebuiltWalls;
    c.beginErasing();
    final times = <int>[];
    for (var row = 0; row < 16; row++) {
      final watch = Stopwatch()..start();
      c.eraseGraphite([
        (Offset(0, (row + .5) / 16), Offset(1, (row + .5) / 16)),
      ]);
      cache.synchronize(c.planes.values, c.landscape);
      cache.walls(c.landscape.terrain!).toList();
      watch.stop();
      times.add(watch.elapsedMicroseconds);
    }
    c.finishErasing();
    times.sort();
    debugPrint(
      'Graphite scrub update: median ${times[8]} us, max ${times.last} us; slots ${cache.rasterizedTiles - slots}, wall chunks ${cache.rebuiltWalls - walls}',
    );
    expect(cache.rasterizedTiles, slots + 30);
    expect(cache.rebuiltWalls, lessThanOrEqualTo(walls + 80));
    final image = cache.atlas.image;
    for (var frame = 0; frame < 120; frame++) {
      cache.synchronize(c.planes.values, c.landscape);
    }
    expect(cache.atlas.image, same(image));
    expect(c.balances[PaperMaterial.graphite], 128);
  });
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('finger eraser, pop, cancellation and release at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      final c = graphiteWorld()..leave();
      addTearDown(() {
        c.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: RepaintBoundary(
            key: const ValueKey('eraser-capture'),
            child: ProtoplaneConceptView(animateFog: false, controller: c),
          ),
        ),
      );
      await tester.pumpAndSettle();
      c.enter(centerId(c, PaperMaterial.graphite));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Eraser'), findsOneWidget);
      final before = snapshot(c);
      final camera = tester
          .widget<SceneView>(find.byType(SceneView).first)
          .scene
          .camera!;
      Offset point(double x, double y) =>
          camera.projectToScreen(c.activePlane!.point(Offset(x, y)), size)!;
      var commits = 0;
      c.onCommitted = (_) => commits++;
      Future<TestGesture> scrub() async {
        final finger = await tester.startGesture(point(.15, .5));
        await finger.moveTo(point(.85, .5));
        expect(c.balances[PaperMaterial.graphite], 0); // queued until the frame
        await tester.pump();
        expect(c.balances[PaperMaterial.graphite], greaterThan(0));
        expect(c.draft.path, isEmpty);
        return finger;
      }

      final early = await tester.startGesture(point(.15, .5));
      await early.moveTo(point(.85, .5));
      await early.cancel();
      await tester.pumpAndSettle();
      expect(snapshot(c), before);
      expect(commits, 0);
      final cancelled = await scrub();
      await cancelled.cancel();
      await tester.pumpAndSettle();
      expect(snapshot(c), before);
      expect(commits, 0);
      final multi = await scrub();
      final second = await tester.startGesture(point(.4, .3), pointer: 99);
      await tester.pump();
      expect(snapshot(c), before);
      await second.up();
      await multi.up();
      await tester.pumpAndSettle();
      final finger = await scrub();
      await tester.pump(const Duration(milliseconds: 45));
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('eraser-capture')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '/tmp/graphite-eraser-${size.width.toInt()}.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
      final pops = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<GraphitePopsPainter>()
          .single;
      expect(pops.effects.count, inInclusiveRange(1, 96));
      final balance = c.balances[PaperMaterial.graphite];
      await finger.moveTo(point(.15, .5));
      await tester.pump();
      expect(c.balances[PaperMaterial.graphite], balance);
      await finger.up();
      await tester.pumpAndSettle();
      expect(commits, 1);
      expect(pops.effects.count, 0);
      c.undo();
      await tester.pumpAndSettle();
      expect(snapshot(c), before);
      c.redo();
      await tester.pumpAndSettle();
      expect(c.balances[PaperMaterial.graphite], balance);
      expect(tester.takeException(), isNull);
      // Unmounting a view with an external controller must cancel live edits.
      c.undo();
      await tester.pumpAndSettle();
      final abandoned = await scrub();
      await tester.pumpWidget(const SizedBox());
      expect(snapshot(c), before);
      await abandoned.cancel();
    });
  }
}
