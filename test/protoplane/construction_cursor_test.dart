import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'surface_fixture.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/construction.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';
import 'package:flatmates/ui/game/view_crosshair.dart';

void main() {
  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.iOS,
    TargetPlatform.android,
  ]) {
    testWidgets('construction follows the input cursor on $platform', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const size = Size(1000, 800);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final c = surfaceRoomWorld()..enableInPlaceDrawing();
      addTearDown(c.dispose);
      final ground = 'surface-${c.objects.values.single.id}-floor-in-0';
      c.enter(ground);
      for (final x in [.25, .5]) {
        final r = rectangle(.25, .5, origin: Offset(x, .25));
        expect(c.commitDrawingPath([...r.outer, r.outer.first]), isTrue);
      }
      await tester.pumpWidget(
        MaterialApp(
          home: ProtoplaneConceptView(controller: c, animateFog: false),
        ),
      );
      await tester.pumpAndSettle();
      final desktop =
          platform == TargetPlatform.macOS ||
          platform == TargetPlatform.windows;
      final scene = tester
          .widget<SceneView>(find.byType(SceneView).first)
          .scene;
      final cursor = scene.camera!.projectToScreen(
        c.planes[ground]!.point(const Offset(.5, .5)),
        size,
      )!;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      if (desktop) {
        expect(find.byType(ViewCrosshair), findsNothing);
        await mouse.addPointer(location: cursor);
        await tester.pumpAndSettle();
      } else {
        expect(
          tester.widget<ViewCrosshair>(find.byType(ViewCrosshair)).position,
          size.center(Offset.zero),
        );
      }
      await tester.tap(find.byKey(const ValueKey('construction-paper')));
      await tester.pumpAndSettle();
      dynamic evaluation() =>
          (tester
                      .widget<CustomPaint>(
                        find.byKey(const ValueKey('drawing-graph-overlay')),
                      )
                      .painter
                  as dynamic)
              .evaluation;
      if (desktop) {
        await mouse.moveTo(cursor);
        await tester.pumpAndSettle();
        expect(
          tester.widget<ViewCrosshair>(find.byType(ViewCrosshair)).position,
          cursor,
        );
        expect(evaluation().valid, isTrue);
        expect(
          (evaluation().target.point - const Offset(.5, .5)).distance,
          lessThan(.001),
        );
        final position = scene.camera!.position.clone();
        await mouse.removePointer();
        await tester.pumpAndSettle();
        expect(find.byType(ViewCrosshair), findsNothing);
        expect(evaluation(), isNull);
        final touch = await tester.createGesture(
          kind: PointerDeviceKind.touch,
          pointer: 99,
        );
        await touch.down(const Offset(16, 320));
        await tester.pump();
        expect(
          tester.widget<ViewCrosshair>(find.byType(ViewCrosshair)).position,
          size.center(Offset.zero),
        );
        await touch.cancel();
        await mouse.addPointer(location: cursor);
        await tester.pumpAndSettle();
        await mouse.down(cursor);
        await mouse.up();
        await tester.pumpAndSettle();
        expect(scene.camera!.position, position);
        expect(
          c.objects.values.last.region.contains(const Offset(.5, .5)),
          isTrue,
        );
      } else {
        final before = evaluation().target.point as Offset;
        final touch = await tester.startGesture(const Offset(16, 320));
        await tester.pump();
        expect(
          tester.widget<ViewCrosshair>(find.byType(ViewCrosshair)).position,
          size.center(Offset.zero),
        );
        expect(evaluation().target.point, before);
        await touch.up();
        await tester.pumpAndSettle();
        expect(c.objects, hasLength(2));
      }
      expect(c.constructionTool, ConstructionTool.paper);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
