import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/fog_overlay.dart';
import 'package:flatmates/protoplane/fog_settings.dart';
import 'package:flatmates/protoplane/harvest_meshes.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/rendering/scene/scene.dart';
import 'package:flatmates/rendering/scene/camera.dart';
import 'package:flatmates/rendering/scene_view.dart';

class _CountPainter extends ScenePainter {
  _CountPainter({required super.scene});
  static int paints = 0;
  @override
  void paint(Canvas canvas, Size size) {
    paints++;
    super.paint(canvas, size);
  }
}

void main() {
  testWidgets(
    'cloud ticks repaint only the overlay; pan and styles reuse masks and atlas',
    (tester) async {
      final c = ProtoplaneController(preset: WorldPreset.paper);
      final fog = FogSettings();
      final scene = Scene();
      final camera = Camera(
        name: 'test',
        position: Vector3(-10, 12, 10),
        target: Vector3(2, 0, -2),
        fovDegrees: 50,
      );
      scene.camera = camera;
      final cache = HarvestMeshCache();
      scene.setMeshes([
        for (final p in c.planes.values) cache.mesh(p, c.landscape),
        ...cache.walls(c.landscape.terrain!),
      ]);
      addTearDown(() {
        scene.dispose();
        cache.dispose();
        c.dispose();
      });
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, set) {
              update = set;
              return Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: CustomPaint(painter: _CountPainter(scene: scene)),
                  ),
                  FogOverlay(
                    model: c,
                    camera: camera,
                    settings: fog,
                    cameraChanges: scene,
                  ),
                ],
              );
            },
          ),
        ),
      );
      for (
        var attempt = 0;
        attempt < 40 && FogDiagnostics.shaderPaints == 0;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(FogDiagnostics.shaderPaints, greaterThan(0));
      final masks = FogField.builds,
          slots = cache.rasterizedTiles,
          paints = _CountPainter.paints;
      final shaderPaints = FogDiagnostics.shaderPaints;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(_CountPainter.paints, paints);
      expect(FogDiagnostics.shaderError, isNull);
      expect(FogDiagnostics.shaderPaints, greaterThan(shaderPaints));
      for (var i = 0; i < 12; i++) {
        camera.position.x += .01;
        scene.markNeedsPaint();
        await tester.pump(const Duration(milliseconds: 16));
      }
      update(() => fog.theme = FogTheme.charcoal);
      await tester.pump(const Duration(milliseconds: 16));
      expect(FogField.builds, masks);
      expect(cache.rasterizedTiles, slots);
      c.revealAllAreas();
      expect(FogField.builds, masks + 1);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(seconds: 1));
      c.clearWorld();
      expect(FogField.builds, masks + 2);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    for (final fallback in [false, true]) {
      testWidgets('fog themes and fallback at $size ($fallback)', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        final c = ProtoplaneController(preset: WorldPreset.paper);
        final scene = Scene(), cache = HarvestMeshCache(), fog = FogSettings();
        final camera = Camera(
          name: 'capture',
          position: Vector3(-11, 14, 11),
          target: Vector3(2, 0, -2),
          fovDegrees: 50,
        );
        scene.camera = camera;
        scene.setMeshes([
          for (final p in c.planes.values) cache.mesh(p, c.landscape),
          ...cache.walls(c.landscape.terrain!),
        ]);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          c.dispose();
          cache.dispose();
          scene.dispose();
        });
        late StateSetter update;
        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, set) {
                update = set;
                return RepaintBoundary(
                  key: const ValueKey('fog-capture'),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const ColoredBox(color: Color(0xff765184)),
                      RepaintBoundary(child: SceneView(scene: scene)),
                      FogOverlay(
                        model: c,
                        camera: camera,
                        settings: fog,
                        cameraChanges: scene,
                        animate: false,
                        useShader: !fallback,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        for (final theme in FogTheme.values) {
          update(() => fog.theme = theme);
          await tester.pump();
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('fog-capture')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await File(
              '/tmp/fog-${size.width.toInt()}-${theme.name}-$fallback.png',
            ).writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
