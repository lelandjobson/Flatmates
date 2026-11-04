import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;
import 'package:flatmates/protoplane/completion.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/paper_effects.dart';
import 'package:flatmates/protoplane/geometry.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/rendering/scene/scene.dart';
import 'package:flatmates/rendering/scene/camera.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('double-fill placement, holes, overlap and cleanup at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final model = ProtoplaneController();
      addTearDown(model.dispose);
      final plane = model.planes['ground-4-4']!;
      final paper = CraftObject(
        id: 'effect-paper',
        planeId: plane.id,
        kind: CraftKind.floor,
        material: PaperMaterial.lines,
        depth: .12,
        region: Region(
          const [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)],
          [
            const [
              Offset(.35, .35),
              Offset(.65, .35),
              Offset(.65, .65),
              Offset(.35, .65),
            ],
          ],
        ),
      );
      final scene = Scene(globalIllumination: .9)
        ..camera = Camera(
          name: 'effects',
          position: Vector3(1.6, 1.8, 1.2),
          target: plane.point(const Offset(.5, .5)),
        );
      addTearDown(scene.dispose);
      late PaperEffects effects;
      await tester.runAsync(() async {
        effects = PaperEffects(const TestVSync(), random: math.Random(1));
      });
      addTearDown(effects.dispose);
      final result = PaperCompletion(
        action: PaperAction.placement,
        plane: plane,
        trace: paper.region.outer,
        paper: [paper],
        placedIds: {paper.id},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: const Color(0xff333333),
            body: RepaintBoundary(
              key: const ValueKey('effect-capture'),
              child: CustomPaint(
                painter: PaperEffectsPainter(effects, scene),
                size: size,
              ),
            ),
          ),
        ),
      );
      Future<void> capture(String stage) async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('effect-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '/tmp/paper-effect-${size.width.toInt()}-$stage.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.runAsync(
        () => effects.play(
          result,
          duration: const Duration(milliseconds: 400),
          shake: true,
          reducedMotion: false,
        ),
      );
      expect(effects.activeCount, 1);
      expect(effects.hiddenIds, {paper.id});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await capture('inward');
      expect(effects.shake, Offset.zero);
      expect(effects.bakedSurfaces, 0);
      await tester.pump(const Duration(milliseconds: 50));
      await capture('settle');
      expect(effects.shake, Offset.zero);
      await tester.pump(const Duration(milliseconds: 50));
      expect(effects.activeCount, 0);
      expect(effects.hiddenIds, isEmpty);
      final removed = PaperCompletion(
        action: PaperAction.removal,
        plane: plane,
        trace: paper.region.outer,
        paper: [paper],
      );
      await tester.runAsync(() async {
        await effects.play(
          removed,
          duration: const Duration(milliseconds: 400),
          shake: true,
          reducedMotion: false,
        );
        await effects.play(
          result,
          duration: const Duration(milliseconds: 400),
          shake: true,
          reducedMotion: false,
        );
      });
      expect(effects.activeCount, 2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await capture('fall');
      final baked = effects.bakedSurfaces;
      final painter = PaperEffectsPainter(effects, scene);
      final times = <int>[];
      for (var frame = 0; frame < 120; frame++) {
        scene.camera!.position.x += frame.isEven ? .01 : -.01;
        final recorder = ui.PictureRecorder();
        final watch = Stopwatch()..start();
        painter.paint(Canvas(recorder), size);
        watch.stop();
        times.add(watch.elapsedMicroseconds);
        recorder.endRecording().dispose();
      }
      times.sort();
      debugPrint(
        'Paper effects pan: median ${times[60]} us, p95 ${times[114]} us; baked surfaces $baked',
      );
      expect(effects.bakedSurfaces, baked);

      effects.clear();
      expect(effects.activeCount, 0);
      expect(effects.hiddenIds, isEmpty);
      await tester.runAsync(
        () => effects.play(
          result,
          duration: const Duration(milliseconds: 850),
          shake: false,
          reducedMotion: false,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 199));
      expect(effects.activeCount, 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(effects.activeCount, 0);
      await tester.runAsync(
        () => effects.play(
          result,
          duration: const Duration(milliseconds: 850),
          shake: true,
          reducedMotion: true,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(effects.shake, Offset.zero);
      await tester.pump(const Duration(milliseconds: 140));
      expect(effects.activeCount, 0);
      await tester.runAsync(() async {
        final pending = effects.play(
          result,
          duration: const Duration(milliseconds: 400),
          shake: true,
          reducedMotion: false,
        );
        effects.clear();
        await pending;
      });
      expect(effects.activeCount, 0);
      expect(effects.hiddenIds, isEmpty);
      model.landscape.deplete(
        plane.id,
        Region(const [
          Offset(.4, 0),
          Offset(.6, 0),
          Offset(.6, 1),
          Offset(.4, 1),
        ]),
      );
      final harvest = model.landscape.preview(plane, plane.region)!;
      await tester.runAsync(
        () => effects.play(
          PaperCompletion(
            action: PaperAction.removal,
            plane: plane,
            trace: plane.region.outer,
            harvest: harvest,
          ),
          duration: const Duration(milliseconds: 400),
          shake: true,
          reducedMotion: false,
        ),
      );
      expect(
        effects.activeCount,
        2,
        reason: 'Separated natural islands fall independently',
      );
      effects.clear();
      await tester.runAsync(() async {
        final pending = effects.play(
          result,
          duration: const Duration(milliseconds: 400),
          shake: true,
          reducedMotion: false,
        );
        await Future<void>.delayed(Duration.zero);
        effects.clear();
        await pending;
      });
      expect(effects.activeCount, 0);
      expect(effects.hiddenIds, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
