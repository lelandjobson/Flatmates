import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/construction.dart';
import 'package:flatmates/protoplane/construction_toolbar.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/parcel_overlay.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';
import 'package:flatmates/ui/game/view_crosshair.dart';

void main() {
  for (final size in [
    const Size(1000, 800),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    testWidgets('three tool workflow at $size', (tester) async {
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
            key: const ValueKey('capture'),
            child: ProtoplaneConceptView(controller: c, animateFog: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(c.constructionTool, isNull);
      expect(find.byType(ConstructionToolbar), findsOneWidget);
      expect(find.byKey(const ValueKey('stickerbook-card')), findsNothing);
      final scene = tester
          .widget<SceneView>(find.byType(SceneView).first)
          .scene;
      final camera = scene.camera!;
      final pose = camera.position.clone();
      await tester.tap(find.byKey(const ValueKey('construction-pencil')));
      await tester.pumpAndSettle();
      expect(c.constructionTool, ConstructionTool.pencil, reason: c.error);
      expect(camera.position, pose);
      expect(find.byType(ViewCrosshair), findsNothing);
      final grid = c.focusDrawingGrid!;
      expect(
        grid.nodes.every((p) => p.dx == p.dx.round() && p.dy == p.dy.round()),
        isTrue,
      );
      Offset screen(Offset p) =>
          camera.projectToScreen(c.drawingSurface!.frame.point(p, .009), size)!;
      final stroke = await tester.startGesture(screen(Offset.zero));
      for (final p in [
        const Offset(1, 0),
        const Offset(1, 1),
        const Offset(0, 1),
        Offset.zero,
      ]) {
        await stroke.moveTo(screen(p));
        await tester.pump();
      }
      await stroke.up();
      await tester.pumpAndSettle();
      expect(c.drawingGraphs.values.single.faces, hasLength(1));
      expect(camera.position, pose);
      Future<void> aimAt(CraftObject object) async {
        final top = c.planes['surface-${object.id}']!;
        final center = top.point(top.region.bounds.center);
        for (var i = 0; i < 4; i++) {
          final at = camera.projectToScreen(center, size)!;
          final pan = await tester.createGesture(
            kind: PointerDeviceKind.trackpad,
          );
          await pan.panZoomStart(size.center(Offset.zero));
          await pan.panZoomUpdate(
            size.center(Offset.zero),
            pan: size.center(Offset.zero) - at,
          );
          await pan.panZoomEnd();
          await tester.pumpAndSettle();
        }
      }

      await tester.tap(find.byKey(const ValueKey('construction-paper')));
      await tester.pumpAndSettle();
      expect(c.activePlaneId, isNull);
      expect(camera.position, pose);
      expect(
        scene.meshes.any((m) => m.id.startsWith('sticker-preview-')),
        isTrue,
      );
      final paletteCapture = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('capture')),
      );
      await tester.runAsync(() async {
        final image = await paletteCapture.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '/tmp/construction-palette-${size.width.toInt()}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.tapAt(Offset(16, size.height * .4));
      await tester.pumpAndSettle();
      expect(
        c.objects.values.single.constructionName,
        'building mat',
        reason: c.error,
      );
      expect(find.text('building mat'), findsOneWidget);
      await aimAt(c.objects.values.single);
      await tester.tap(find.byKey(const ValueKey('construction-volume')));
      await tester.pumpAndSettle();
      expect(
        scene.meshes.any((m) => m.id.startsWith('sticker-preview-')),
        isTrue,
      );
      await tester.tapAt(Offset(16, size.height * .4));
      await tester.pumpAndSettle();
      expect(
        c.objects.values.single.kind,
        CraftKind.solidVolume,
        reason: c.error,
      );
      expect(find.text('building volume'), findsOneWidget);
      await aimAt(c.objects.values.single);
      await tester.tap(find.byKey(const ValueKey('construction-paper')));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('paper-material-wheel')),
        const Offset(-64, 0),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(Offset(16, size.height * .4));
      await tester.pumpAndSettle();
      expect(
        c.objects.values.last.constructionName,
        'cloth sheet',
        reason: c.error,
      );
      expect(find.text('cloth sheet'), findsOneWidget);
      await aimAt(c.objects.values.last);
      await tester.tap(find.byKey(const ValueKey('construction-volume')));
      await tester.pumpAndSettle();
      await tester.tapAt(Offset(16, size.height * .4));
      await tester.pumpAndSettle();
      expect(
        c.objects.values.last.kind,
        CraftKind.inflatedCloth,
        reason: c.error,
      );
      expect(c.objects.values.last.depth, .05);
      expect(find.text('blanket'), findsOneWidget);
      await aimAt(c.objects.values.last);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('blanket'), findsOneWidget);
      final capture = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('capture')),
      );
      await tester.runAsync(() async {
        final image = await capture.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '/tmp/construction-${size.width.toInt()}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      final drag = await tester.startGesture(
        Offset(size.width * .5, size.height * .4),
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveBy(const Offset(60, 0));
      await drag.up();
      await tester.pumpAndSettle();
      expect(camera.position, isNot(pose));
      expect(c.objects.length, 2);
      await tester.tap(find.byKey(const ValueKey('construction-volume')));
      await tester.pumpAndSettle();
      expect(c.constructionTool, isNull);
      c.undo();
      await tester.pumpAndSettle();
      expect(c.objects.values.last.constructionName, 'cloth sheet');
      c.redo();
      await tester.pumpAndSettle();
      expect(c.objects.values.last.constructionName, 'blanket');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'parcel shopping suppresses construction and pencil stays locked during scroll',
    (tester) async {
      final c = ProtoplaneController();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ProtoplaneConceptView(controller: c, animateFog: false),
        ),
      );
      await tester.pumpAndSettle();
      final scene = tester
          .widget<SceneView>(find.byType(SceneView).first)
          .scene;
      await tester.tap(find.byKey(const ValueKey('construction-pencil')));
      await tester.pumpAndSettle();
      final pose = scene.camera!.position.clone();
      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(400, 300),
          scrollDelta: Offset(0, 1000),
        ),
      );
      await tester.pumpAndSettle();
      expect(scene.camera!.position, pose);
      expect(c.constructionTool, ConstructionTool.pencil);
      await tester.tap(find.byKey(const ValueKey('construction-volume')));
      await tester.pumpAndSettle();
      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(400, 300),
          scrollDelta: Offset(0, 1000),
        ),
      );
      await tester.pumpAndSettle();
      final overlay =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('parcel-overlay')),
                  )
                  .painter!
              as ParcelPainter;
      expect(overlay.shopping, isTrue);
      expect(
        scene.meshes.any((m) => m.id.startsWith('sticker-preview-')),
        isFalse,
      );
      await tester.tapAt(const Offset(400, 300));
      await tester.pumpAndSettle();
      expect(c.objects, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
