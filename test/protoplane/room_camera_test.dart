import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';
import 'surface_construction_test.dart' show loop;

void main() {
  for (final size in [
    const Size(900, 700),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    testWidgets('room framing, adjacent swipe and stepped pinch at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final c = ProtoplaneController();
      addTearDown(c.dispose);
      expect(c.applyVolumeStroke(c.startingTile, loop(0, 0)), isTrue);
      final first = c.objects.values.single;
      expect(c.applyVolumeStroke(c.startingTile, loop(1, 0)), isTrue);
      final second = c.objects.values.last;
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
      final initial = camera.position.clone();
      final floor = c.planes['surface-${first.id}-floor-in-0']!;
      final projected = floor.region.outer
          .map((p) => camera.projectToScreen(floor.point(p), size)!)
          .toList();
      final width =
          projected.map((p) => p.dx).reduce((a, b) => a > b ? a : b) -
          projected.map((p) => p.dx).reduce((a, b) => a < b ? a : b);
      expect(width, greaterThan(size.shortestSide * .3));
      for (final p in projected) {
        expect((Offset.zero & size).deflate(12).contains(p), isTrue);
      }
      expect(
        scene.meshes.where(
          (m) => m.id.startsWith('ground-') || m.id.startsWith('terrain-wall-'),
        ),
        isEmpty,
      );
      await tester.dragFrom(size.center(Offset.zero), const Offset(80, 0));
      await tester.pumpAndSettle();
      expect((camera.position - initial).length, lessThan(.001));
      Future<void> panZoom(Offset pan, double scale) async {
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.trackpad,
        );
        final at = size.center(Offset.zero);
        await gesture.panZoomStart(at);
        await gesture.panZoomUpdate(at, pan: pan, scale: scale);
        await gesture.panZoomEnd();
        await tester.pumpAndSettle();
      }

      final a = await tester.startGesture(
        size.center(Offset.zero) - const Offset(0, 60),
        pointer: 1,
      );
      final b = await tester.startGesture(
        size.center(Offset.zero) + const Offset(0, 60),
        pointer: 2,
      );
      await a.moveBy(const Offset(-120, 0));
      await b.moveBy(const Offset(-120, 0));
      await a.up();
      await b.up();
      await tester.pumpAndSettle();
      final center = c.objectPlane(second).point(second.region.bounds.center);
      expect((camera.target - center).length, lessThan(.001));
      final close = (camera.position - camera.target).length;
      await panZoom(Offset.zero, .65);
      final neighborhood = (camera.position - camera.target).length;
      expect(neighborhood, greaterThan(close));
      await panZoom(Offset.zero, .65);
      expect(
        (camera.position - camera.target).length,
        greaterThanOrEqualTo(16),
      );
      await panZoom(Offset.zero, 1.5);
      await panZoom(Offset.zero, 1.5);
      expect((camera.position - camera.target).length, closeTo(close, .01));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
