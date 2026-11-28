import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/construction.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';
import 'surface_fixture.dart';

void main() {
  for (final size in [
    const Size(1000, 800),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    testWidgets('surface tools create indoor cloth and fold it at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final c = surfaceRoomWorld();
      addTearDown(c.dispose);
      final room = c.objects.values.single;
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: const ValueKey('capture'),
            child: ProtoplaneConceptView(controller: c, animateFog: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scene = tester
              .widget<SceneView>(find.byType(SceneView).first)
              .scene,
          camera = scene.camera!;
      final floor = c.planes['surface-${room.id}-floor-in-0']!;
      final before = camera.position.clone();
      expect(find.byKey(const ValueKey('construction-volume')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('construction-pencil')));
      await tester.pumpAndSettle();
      Offset screen(Offset p) =>
          camera.projectToScreen(floor.point(p, .009), size)!;
      final r = rectangle(.5, .5, origin: const Offset(.25, .25));
      final stroke = await tester.startGesture(screen(r.outer.first));
      for (final p in [...r.outer.skip(1), r.outer.first]) {
        await stroke.moveTo(screen(p));
        await tester.pump();
      }
      await stroke.up();
      await tester.pumpAndSettle();
      expect(c.surfaceGraphs.single.faces, hasLength(1));
      expect(camera.position, before);
      await tester.tap(find.byKey(const ValueKey('construction-paper')));
      await tester.pumpAndSettle();
      expect(c.constructionPaper, ConstructionPaper.cloth);
      expect(
        scene.meshes.any((m) => m.id.startsWith('sticker-preview-')),
        isTrue,
      );
      await tester.tapAt(size.center(Offset.zero));
      await tester.pumpAndSettle();
      expect(c.objects.values.last.kind, CraftKind.paperSheet, reason: c.error);
      expect(c.balances[PaperMaterial.paperGreen], 4);
      await tester.tap(find.byKey(const ValueKey('surface-select')));
      await tester.pump();
      await tester.tapAt(size.center(Offset.zero));
      await tester.pump();
      expect(find.byKey(const ValueKey('construction-paper')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('construction-fold')));
      await tester.pumpAndSettle();
      await tester.tapAt(size.center(Offset.zero));
      await tester.pumpAndSettle();
      expect(
        c.objects.values.last.kind,
        CraftKind.inflatedCloth,
        reason: c.error,
      );
      expect(c.objects.values.last.depth, .05);
      expect(camera.position, before);
      expect(tester.takeException(), isNull);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('capture')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '/tmp/surface-room-${size.width.toInt()}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
    });
  }
}
