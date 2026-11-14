import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';
import 'layered_terrain_test.dart' show centerId;

void main() {
  for (final size in [const Size(1000, 800), const Size(390, 844)]) {
    testWidgets('focus keeps camera and draws a spanning outline at $size', (
      tester,
    ) async {
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
          home: ProtoplaneConceptView(controller: c, animateFog: false),
        ),
      );
      await tester.pumpAndSettle();
      final scene = tester
          .widget<SceneView>(find.byType(SceneView).first)
          .scene;
      final camera = scene.camera!;
      final position = camera.position.clone(),
          target = camera.target.clone(),
          up = camera.up.clone();
      final fov = camera.fovDegrees;
      final before = {for (final m in scene.meshes) m.id: m.material.opacity};
      c.balances[PaperMaterial.paperWhite] = 1000;
      c.enter(centerId(c, PaperMaterial.paperWhite));
      await tester.pumpAndSettle();
      expect(camera.position, position);
      expect(camera.target, target);
      expect(camera.up, up);
      expect(camera.fovDegrees, fov);
      expect(find.byKey(const ValueKey('focus-vignette')), findsOneWidget);
      for (final m in scene.meshes) {
        if (before.containsKey(m.id)) {
          expect(m.material.opacity, before[m.id], reason: m.id);
        }
        expect(m.cropBox, isNull);
      }
      Offset screen(Offset point) =>
          camera.projectToScreen(c.activePlane!.point(point, .008), size)!;
      final drag = await tester.startGesture(
        screen(Offset.zero),
        kind: size.width > 500
            ? PointerDeviceKind.mouse
            : PointerDeviceKind.touch,
      );
      for (final point in [
        const Offset(2, 0),
        const Offset(2, 1),
        const Offset(0, 1),
        Offset.zero,
      ]) {
        await drag.moveTo(screen(point));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await drag.up();
      await tester.pumpAndSettle();
      expect(c.closed, isTrue);
      expect(c.objects, isEmpty);
      expect(find.text('Create'), findsOneWidget);
      c.selectTool(CraftTool.volume);
      await tester.pumpAndSettle();
      expect(c.previewObject!.region.area, closeTo(2, .00001));
      expect(camera.position, position);
      final cap = c.activePlane!;
      final pull = await tester.startGesture(
        screen(const Offset(1, .5)),
        kind: size.width > 500
            ? PointerDeviceKind.mouse
            : PointerDeviceKind.touch,
      );
      await pull.moveTo(
        camera.projectToScreen(cap.point(const Offset(1, .5), .15), size)!,
      );
      await tester.pump();
      await pull.up();
      await tester.pumpAndSettle();
      expect(c.previewDepth, greaterThan(.035));
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(c.objects.length, 1);
      expect(c.objects.values.single.region.area, closeTo(2, .00001));
      expect(c.objects.values.single.depth, greaterThan(.035));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
