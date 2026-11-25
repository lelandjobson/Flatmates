import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/drawing_graph.dart';
import 'package:flatmates/protoplane/focus_tool_dock.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';
import 'layered_terrain_test.dart' show centerId;

void main() {
  for (final size in [
    const Size(1000, 800),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    testWidgets(
      'focus drawing, primed reticle placement, and line eraser at $size',
      (tester) async {
        final c = ProtoplaneController();
        addTearDown(c.dispose);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        await tester.pumpWidget(
          MaterialApp(
            home: RepaintBoundary(
              key: const ValueKey('focus-capture'),
              child: ProtoplaneConceptView(controller: c, animateFog: false),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final scene = tester
                .widget<SceneView>(find.byType(SceneView).first)
                .scene,
            camera = scene.camera!;
        final position = camera.position.clone(),
            target = camera.target.clone(),
            up = camera.up.clone(),
            lens = camera.fovDegrees;
        final opacities = {
          for (final m in scene.meshes) m.id: m.material.opacity,
        };
        c.enter(centerId(c, PaperMaterial.paperWhite));
        await tester.pumpAndSettle();
        expect(camera.position, position);
        expect(camera.target, target);
        expect(camera.up, up);
        expect(camera.fovDegrees, lens);
        for (final m in scene.meshes) {
          if (opacities.containsKey(m.id)) {
            expect(m.material.opacity, opacities[m.id]);
          }
          expect(m.cropBox, isNull);
        }
        expect(find.byKey(const ValueKey('focus-vignette')), findsOneWidget);
        final gradient = find.byKey(const ValueKey('focus-tools-gradient'));
        expect(
          tester.getSize(gradient).height,
          closeTo(size.height * .25, .01),
        );
        expect(tester.getRect(gradient).bottom, closeTo(size.height, .01));
        for (final label in [
          'Scissors',
          'Volume',
          'Place',
          'Graphite pencil',
          '3D',
        ]) {
          expect(find.byTooltip(label), findsNothing);
        }
        expect(find.byType(FocusToolDock), findsOneWidget);
        Offset screen(Offset p) => camera.projectToScreen(
          c.drawingSurface!.frame.point(p, .009),
          size,
        )!;
        final kind = size.width > 900
            ? PointerDeviceKind.mouse
            : PointerDeviceKind.touch;
        final drag = await tester.startGesture(screen(Offset.zero), kind: kind);
        for (final p in [
          const Offset(2, 0),
          const Offset(2, 2),
          const Offset(0, 2),
          Offset.zero,
        ]) {
          await drag.moveTo(screen(p));
          await tester.pump();
        }
        await drag.up();
        await tester.pumpAndSettle();
        expect(
          c.surfaceGraphs.single.faces.single.region.area,
          closeTo(4, 1e-6),
        );
        expect(c.objects, isEmpty);
        final capture = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('focus-capture')),
        );
        await tester.runAsync(() async {
          final image = await capture.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '/tmp/focus-tools-${size.width.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        c.selectFocusCard(FocusToolCard.stickerbook);
        await tester.pumpAndSettle();
        final select = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('sticker-card-0'))),
          kind: kind,
        );
        await select.up();
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Transform>(find.byKey(const ValueKey('sticker-lift-0')))
              .transform
              .storage[13],
          lessThan(0),
        );
        await tester.runAsync(() async {
          final image = await capture.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '/tmp/stickerbook-${size.width.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        final place = await tester.startGesture(
          kind == PointerDeviceKind.mouse
              ? screen(const Offset(1, 1))
              : Offset(12, size.height * .4),
          kind: kind,
        );
        await place.up();
        await tester.pumpAndSettle();
        expect(c.assemblies.length, 1, reason: c.error);
        expect(c.objects.length, 5);
        c.selectFocusCard(FocusToolCard.drawing);
        c.selectDrawingImplement(DrawingImplement.eraser);
        await tester.pumpAndSettle();
        final erase = await tester.startGesture(
          screen(const Offset(.5, -.15)),
          kind: kind,
        );
        await erase.moveTo(screen(const Offset(.5, .15)));
        await tester.pump();
        expect(c.surfaceGraphs.single.edges.length, 4);
        await erase.up();
        await tester.pumpAndSettle();
        expect(c.surfaceGraphs.single.edges.length, 3);
        expect(c.surfaceGraphs.single.faces, isEmpty);
        expect(c.objects.length, 5);
        c.undo();
        await tester.pumpAndSettle();
        expect(c.surfaceGraphs.single.edges.length, 4);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'all implements retrace pending segments and keep only complete pip edges',
    (tester) async {
      final c = ProtoplaneController();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ProtoplaneConceptView(controller: c, animateFog: false),
        ),
      );
      await tester.pumpAndSettle();
      c.enter(centerId(c, PaperMaterial.paperWhite));
      await tester.pumpAndSettle();
      final camera = tester
          .widget<SceneView>(find.byType(SceneView).first)
          .scene
          .camera!;
      Offset screen(Offset p) => camera.projectToScreen(
        c.drawingSurface!.frame.point(p, .009),
        const Size(800, 600),
      )!;
      dynamic feedback() => tester
          .widget<CustomPaint>(
            find.byKey(const ValueKey('drawing-graph-overlay')),
          )
          .painter;
      for (final implement in DrawingImplement.values.where(
        (i) => i != DrawingImplement.eraser,
      )) {
        c.selectDrawingImplement(implement);
        await tester.pumpAndSettle();
        Offset point(double x, double y) => implement.toSurface(Offset(x, y));
        final drag = await tester.startGesture(screen(point(0, 0)));
        await drag.moveTo(screen(point(1, 0)));
        await drag.moveTo(screen(point(1, 1)));
        await tester.pump();
        expect((feedback().path as List).length, greaterThan(2));
        expect(c.surfaceGraphs, isEmpty); // Live tracing is not persisted yet.
        await drag.moveTo(screen(point(1, 0))); // Retrace through skipped pips.
        await drag.moveTo(screen(point(0, 0)));
        await tester.pump();
        expect((feedback().path as List).length, 1);
        await drag.moveTo(screen(point(1, 0))); // Draw forward again.
        await drag.up();
        await tester.pumpAndSettle();
        expect(c.surfaceGraphs.single.edges.length, 1);
        expect(c.surfaceGraphs.single.edges.single.length, closeTo(1, 1e-6));
        c.undo();
        await tester.pumpAndSettle();
        expect(c.surfaceGraphs, isEmpty);
      }
      c.selectDrawingImplement(DrawingImplement.marker);
      await tester.pumpAndSettle();
      final partial = await tester.startGesture(screen(Offset.zero));
      final between = screen(const Offset(.35, 0));
      await partial.moveTo(between);
      await tester.pump();
      expect(feedback().liveScreen, between); // Feedback updates between pips.
      expect((feedback().path as List).length, 1);
      await partial.up();
      await tester.pumpAndSettle();
      expect(c.surfaceGraphs, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('second pointer cancels an unfinished construction gesture', (
    tester,
  ) async {
    final c = ProtoplaneController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ProtoplaneConceptView(controller: c, animateFog: false),
      ),
    );
    await tester.pumpAndSettle();
    c.enter(centerId(c, PaperMaterial.paperWhite));
    await tester.pumpAndSettle();
    final camera = tester
        .widget<SceneView>(find.byType(SceneView).first)
        .scene
        .camera!;
    Offset screen(Offset p) => camera.projectToScreen(
      c.drawingSurface!.frame.point(p, .009),
      const Size(800, 600),
    )!;
    final a = await tester.startGesture(screen(Offset.zero), pointer: 1);
    await a.moveTo(screen(const Offset(1, 0)));
    final b = await tester.startGesture(screen(const Offset(1, 1)), pointer: 2);
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(c.drawingGraphs, isEmpty);
    expect(c.objects, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
