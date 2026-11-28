import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/construction.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';
import 'housing_test.dart' show makeRoom, draw;

void main() {
  testWidgets(
    'room background fades and double tapping exits without a camera jump',
    (tester) async {
      final c = ProtoplaneController()..enableInPlaceDrawing();
      addTearDown(c.dispose);
      final room = makeRoom(c);
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
      final before = camera.position.clone();
      double shade() => tester
          .widget<ColoredBox>(
            find.byKey(const ValueKey('room-background-shade')),
          )
          .color
          .a;
      expect(shade(), 0);
      final roof = c.planes['surface-${room.id}-roof-out-0']!;
      await tester.tapAt(
        camera.projectToScreen(
          roof.point(roof.region.bounds.center),
          const Size(800, 600),
        )!,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 175));
      expect(shade(), greaterThan(0));
      expect(shade(), lessThan(.16));
      await tester.pumpAndSettle();
      expect(shade(), closeTo(.16, .005));
      final floor = c.planes['surface-${room.id}-floor-in-0']!;
      final inside = camera.projectToScreen(
        floor.point(floor.region.bounds.center),
        const Size(800, 600),
      )!;
      await tester.tapAt(inside);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(inside);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('exit-room')), findsOneWidget);
      const background = Offset(80, 200);
      await tester.dragFrom(background, const Offset(25, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('exit-room')), findsOneWidget);
      await tester.tapAt(background);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('exit-room')), findsOneWidget);
      await tester.tapAt(background);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(background);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('exit-room')), findsNothing);
      expect(shade(), 0);
      expect((camera.position - before).length, lessThan(.0001));
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Scissors previews the wall removal and commits only a stationary click',
    (tester) async {
      final c = ProtoplaneController()..enableInPlaceDrawing();
      addTearDown(c.dispose);
      final room = makeRoom(c);
      final wallId = 'surface-${room.id}-wall-0-0-out-0';
      draw(c, wallId, rectangle(.25, .5, origin: const Offset(.25, 0)));
      await tester.pumpWidget(
        MaterialApp(
          home: ProtoplaneConceptView(controller: c, animateFog: false),
        ),
      );
      await tester.pumpAndSettle();
      final scene = tester
          .widget<SceneView>(find.byType(SceneView).first)
          .scene;
      final wall = c.planes[wallId]!;
      void aim() {
        final point = wall.point(const Offset(.375, .25));
        scene.camera!.setPosition(point + wall.normal * 3);
        scene.camera!.setTarget(point);
        scene.camera!.setUp(wall.v);
        c.clearError();
      }

      aim();
      await tester.tap(find.byKey(const ValueKey('construction-scissors')));
      await tester.pumpAndSettle();
      expect(c.constructionTool, ConstructionTool.scissors);
      expect(scene.meshes.any((m) => m.id == 'sticker-preview-cut'), isTrue);
      expect(c.objects[room.id]!.openings, isEmpty);
      await tester.dragFrom(const Offset(400, 300), const Offset(40, 0));
      await tester.pumpAndSettle();
      expect(c.objects[room.id]!.openings, isEmpty);
      aim();
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(400, 300));
      await tester.pumpAndSettle();
      expect(c.objects[room.id]!.openings.single.kind, 'door');
      expect(c.constructionTool, ConstructionTool.scissors);
      expect(scene.meshes.any((m) => m.id == 'sticker-preview-cut'), isFalse);
      c.undo();
      await tester.pumpAndSettle();
      expect(c.objects[room.id]!.openings, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'undoing inflation exits room focus and restores the incoming pose',
    (tester) async {
      final c = ProtoplaneController()..enableInPlaceDrawing();
      addTearDown(c.dispose);
      final room = makeRoom(c);
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
      final before = camera.position.clone();
      final roof = c.planes['surface-${room.id}-roof-out-0']!;
      await tester.tapAt(
        camera.projectToScreen(
          roof.point(roof.region.bounds.center),
          const Size(800, 600),
        )!,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('exit-room')), findsOneWidget);
      c.undo();
      await tester.pumpAndSettle();
      expect(c.objects[room.id]!.kind, CraftKind.paperSheet);
      expect(find.byKey(const ValueKey('exit-room')), findsNothing);
      expect((camera.position - before).length, lessThan(.0001));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
