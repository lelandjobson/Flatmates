import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/plane_navigation.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';

import 'construction_fixture.dart';
import 'linear_placement_test.dart' as linear;
import 'package:flatmates/protoplane/models.dart';

void main() {
  for (final size in [const Size(900, 700), const Size(390, 844)]) {
    testWidgets(
      'trackpad traverses one plane, retains draft and world pose at $size',
      (tester) async {
        final model = constructionWorld();
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          model.dispose();
        });
        await tester.pumpWidget(
          MaterialApp(
            home: ProtoplaneConceptView(animateFog: false, controller: model),
          ),
        );
        await tester.pumpAndSettle();
        final camera = tester
            .widget<SceneView>(find.byType(SceneView).first)
            .scene
            .camera!;
        final originalPosition = camera.position.clone(),
            originalTarget = camera.target.clone();
        model.enter('ground-starter-paperWhite-0-0');
        model.appendNode(0);
        final draft = model.draftKey;
        await tester.pumpAndSettle();
        final plane = model.activePlane!;
        final swipe = Offset(PlaneSwipe.threshold(size) + 10, 0);
        final expected = model.navigationGraph.inDirection(
          plane.id,
          swipe,
          camera.projectToScreen(
            plane.point(plane.region.bounds.center),
            size,
          )!,
          (p) => camera.projectToScreen(p, size),
        );
        expect(expected, isNotNull);
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.trackpad,
        );
        final at = Offset(size.width / 2, size.height / 2);
        await gesture.panZoomStart(at);
        await gesture.panZoomUpdate(at, pan: swipe * .25);
        expect(model.activePlaneId, plane.id);
        await gesture.panZoomUpdate(at, pan: swipe);
        expect(model.activePlaneId, expected);
        final previousCamera = camera.position.clone();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(camera.position.distanceTo(previousCamera), greaterThan(.01));
        await tester.pumpAndSettle();
        await gesture.panZoomUpdate(at, pan: swipe * 3);
        expect(model.activePlaneId, expected);
        await gesture.panZoomEnd();
        expect(model.drafts[draft]!.path, [0]);
        model.leave();
        await tester.pumpAndSettle();
        expect(camera.position.distanceTo(originalPosition), lessThan(1e-6));
        expect(camera.target.distanceTo(originalTarget), lessThan(1e-6));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'trackpad pinch still exits crafting without selecting a neighbor',
    (tester) async {
      final model = constructionWorld();
      addTearDown(model.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ProtoplaneConceptView(animateFog: false, controller: model),
        ),
      );
      await tester.pumpAndSettle();
      model.enter('ground-starter-paperWhite-0-0');
      await tester.pumpAndSettle();
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      const at = Offset(300, 300);
      await gesture.panZoomStart(at);
      await gesture.panZoomUpdate(at, pan: const Offset(150, 0), scale: .7);
      await tester.pumpAndSettle();
      expect(model.activePlaneId, isNull);
      await gesture.panZoomEnd();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final touch in [true, false]) {
    testWidgets(
      'floor ${touch ? 'touch' : 'trackpad'} swipe skips wall and reaches lower neighboring terrain',
      (tester) async {
        final size = touch ? const Size(390, 844) : const Size(900, 700);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        final model = linear.world();
        addTearDown(() {
          model.dispose();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final source = model.activePlane!;
        linear.draw(model, const [Offset(.5, 0), Offset(.5, 1)]);
        expect(model.commitDrawing(), isNotNull);
        final wall = model.objects.values.single;
        final terrain = model.landscape.terrain;
        String east(PaperMaterial material) => terrain.tiles.values
            .firstWhere(
              (t) =>
                  t.x == 1 &&
                  t.y == 0 &&
                  t.sheet.island == 'starter' &&
                  t.sheet.material == material,
            )
            .id;
        for (final material in [
          PaperMaterial.paperWhite,
          PaperMaterial.graphite,
        ]) {
          model.landscape.deplete(east(material), rectangle(1, 1));
        }
        final target = east(PaperMaterial.cork);
        model.leave();
        await tester.pumpWidget(
          MaterialApp(
            home: ProtoplaneConceptView(controller: model, animateFog: false),
          ),
        );
        await tester.pumpAndSettle();
        model.enter(source.id);
        await tester.pumpAndSettle();
        final camera = tester
            .widget<SceneView>(find.byType(SceneView).first)
            .scene
            .camera!;
        final center = camera.projectToScreen(
          source.point(const Offset(.5, .5)),
          size,
        )!;
        final edge = camera.projectToScreen(
          source.point(const Offset(1, .5)),
          size,
        )!;
        final delta =
            (edge - center) /
            (edge - center).distance *
            (PlaneSwipe.threshold(size) + 15);
        expect(
          model.navigationGraph.swipeNeighbors[source.id]!.any(
            (e) => e.planeId == 'surface-${wall.id}',
          ),
          isFalse,
        );
        final before = model.toJson();
        if (touch) {
          final a = await tester.startGesture(
            center - const Offset(0, 30),
            pointer: 501,
          );
          final b = await tester.startGesture(
            center + const Offset(0, 30),
            pointer: 502,
          );
          await a.moveBy(delta);
          await b.moveBy(delta);
          expect(model.activePlaneId, target);
          await a.up();
          await b.up();
        } else {
          final gesture = await tester.createGesture(
            kind: PointerDeviceKind.trackpad,
          );
          await gesture.panZoomStart(center);
          await gesture.panZoomUpdate(center, pan: delta);
          expect(model.activePlaneId, target);
          await gesture.panZoomEnd();
        }
        await tester.pumpAndSettle();
        expect(model.activePlane!.origin.y, lessThan(source.origin.y));
        expect(model.toJson(), before);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
