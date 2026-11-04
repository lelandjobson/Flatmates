import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/plane_navigation.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';

import 'construction_fixture.dart';

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
          MaterialApp(home: ProtoplaneConceptView(controller: model)),
        );
        await tester.pumpAndSettle();
        final camera = tester
            .widget<SceneView>(find.byType(SceneView).first)
            .scene
            .camera!;
        final originalPosition = camera.position.clone(),
            originalTarget = camera.target.clone();
        model.enter('ground-4-4');
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
        MaterialApp(home: ProtoplaneConceptView(controller: model)),
      );
      await tester.pumpAndSettle();
      model.enter('ground-4-4');
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
}
