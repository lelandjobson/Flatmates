import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/construction.dart';
import 'package:flatmates/protoplane/room_geometry.dart';
import 'surface_construction_test.dart' show loop;
import 'package:flatmates/rendering/scene_view.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';

void main() {
  testWidgets(
    'object isolate nests a visible wall focus and restores each pose',
    (tester) async {
      final c = ProtoplaneController();
      addTearDown(c.dispose);
      expect(c.applyVolumeStroke(c.startingTile, loop(0, 0)), isTrue);
      final room = c.objects.values.single;
      await tester.pumpWidget(
        MaterialApp(
          home: ProtoplaneConceptView(controller: c, animateFog: false),
        ),
      );
      await tester.pumpAndSettle();
      final scene = tester
              .widget<SceneView>(find.byType(SceneView).first)
              .scene,
          camera = scene.camera!;
      final initial = camera.position.clone();
      final floor = c.planes['surface-${room.id}-floor-in-0']!;
      await tester.tap(find.byKey(const ValueKey('surface-select')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('selection-kind')));
      await tester.pump();
      await tester.tapAt(
        camera.projectToScreen(
          floor.point(floor.region.bounds.center),
          const Size(800, 600),
        )!,
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('surface-focus')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('surface-focus')));
      await tester.pumpAndSettle();
      final parent = camera.position.clone();
      expect(find.byKey(const ValueKey('construction-scissors')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('surface-select')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('selection-kind')));
      await tester.pump();
      final wall = c.planes['surface-${room.id}-wall-0-0-in-0']!;
      await tester.tapAt(
        camera.projectToScreen(
          wall.point(wall.region.bounds.center),
          const Size(800, 600),
        )!,
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('surface-focus')));
      await tester.pumpAndSettle();
      expect(
        (camera.position - camera.target).normalized().dot(wall.normal),
        closeTo(1, .001),
      );
      expect(
        find.byKey(const ValueKey('construction-scissors')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('construction-scissors')));
      await tester.pumpAndSettle();
      final panel = roomPanels(
        room,
        c.objectPlane(room),
      ).firstWhere((p) => p.key == wall.roomFace);
      final cut = [
        const Offset(.25, 0),
        const Offset(.75, 0),
        const Offset(.75, .75),
        const Offset(.25, .75),
      ];
      Offset screen(Offset point) => camera.projectToScreen(
        panel.frame.point(point),
        const Size(800, 600),
      )!;
      final drag = await tester.startGesture(screen(cut.first));
      for (final point in cut.skip(1)) {
        await drag.moveTo(screen(point));
        await tester.pump();
      }
      await drag.up();
      await tester.pumpAndSettle();
      expect(c.objects[room.id]!.openings.single.kind, 'flap', reason: c.error);
      await tester.tap(find.byKey(const ValueKey('construction-fold')));
      await tester.pumpAndSettle();
      await tester.tapAt(screen(const Offset(.5, .5)));
      await tester.pumpAndSettle();
      expect(c.objects[room.id]!.openings.single.kind, 'door', reason: c.error);
      for (var i = 0; i < 2; i++) {
        await tester.sendEventToBinding(
          const PointerScrollEvent(
            position: Offset(400, 300),
            scrollDelta: Offset(0, 600),
          ),
        );
      }
      await tester.pumpAndSettle();
      expect((camera.position - parent).length, lessThan(.001));
      await tester.tap(find.byKey(const ValueKey('surface-back')));
      await tester.pumpAndSettle();
      expect((camera.position - initial).length, lessThan(.001));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'marquee contains left-to-right, crosses right-to-left and repeated focus is a no-op',
    (tester) async {
      final c = ProtoplaneController();
      addTearDown(c.dispose);
      expect(c.applyVolumeStroke(c.startingTile, loop(0, 0)), isTrue);
      await tester.pumpWidget(
        MaterialApp(
          home: ProtoplaneConceptView(controller: c, animateFog: false),
        ),
      );
      await tester.pumpAndSettle();
      final camera = tester
          .widget<SceneView>(find.byType(SceneView).first)
          .scene
          .camera!;
      final before = camera.position.clone();
      await tester.tap(find.byKey(const ValueKey('surface-select')));
      await tester.pump();
      await tester.dragFrom(const Offset(390, 290), const Offset(20, 20));
      await tester.pump();
      expect(find.byKey(const ValueKey('surface-focus')), findsNothing);
      await tester.dragFrom(const Offset(410, 290), const Offset(-20, 20));
      await tester.pump();
      expect(find.byKey(const ValueKey('surface-focus')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('surface-focus')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('construction-pencil')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('surface-focus')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('surface-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('surface-back')), findsNothing);
      expect((camera.position - before).length, lessThan(.001));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final size in [
    const Size(900, 700),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    testWidgets('four pip opening, incomplete stroke and room at $size', (
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
      expect(c.constructionTool, ConstructionTool.volume);
      expect(find.byKey(const ValueKey('construction-pencil')), findsNothing);
      expect(find.byKey(const ValueKey('housing-hud')), findsNothing);
      final scene = tester
          .widget<SceneView>(find.byType(SceneView).first)
          .scene;
      final camera = scene.camera!;
      expect(
        (camera.position - camera.target).normalized().y,
        closeTo(1, .00001),
      );
      final surface = c.drawingSurfaceFor(c.startingTile)!;
      Offset at(Offset p) =>
          camera.projectToScreen(surface.frame.point(p, .009), size)!;
      final path = [
        Offset.zero,
        const Offset(1, 0),
        const Offset(1, 1),
        const Offset(0, 1),
        Offset.zero,
      ];
      var drag = await tester.startGesture(at(path.first));
      await drag.moveTo(at(path[1]));
      await drag.up();
      await tester.pumpAndSettle();
      expect(c.objects, isEmpty);
      drag = await tester.startGesture(at(path.first));
      for (final p in path.skip(1)) {
        await drag.moveTo(at(p));
        await tester.pump();
      }
      await drag.up();
      await tester.pumpAndSettle();
      expect(c.objects, hasLength(1), reason: c.error);
      expect(c.openingComplete, isTrue);
      expect(find.byKey(const ValueKey('housing-hud')), findsOneWidget);
      expect(find.byKey(const ValueKey('construction-paper')), findsOneWidget);
      expect(find.byKey(const ValueKey('construction-volume')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
