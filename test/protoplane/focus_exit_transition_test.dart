import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';

void main() {
  for (final exit in ['trackpad', 'touch', 'leave']) {
    testWidgets('Paper landscape $exit exit interpolates back to world', (
      tester,
    ) async {
      final model = ProtoplaneController();
      addTearDown(model.dispose);
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
      final world = camera.position.clone(), target = camera.target.clone();
      model.enter(
        model.planes.keys.firstWhere((id) => id.startsWith('ground-')),
      );
      await tester.pumpAndSettle();
      final focused = camera.position.clone();
      expect(focused.distanceTo(world), greaterThan(1));
      if (exit == 'trackpad') {
        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.trackpad,
        );
        const at = Offset(400, 300);
        await gesture.panZoomStart(at);
        await gesture.panZoomUpdate(at, scale: .7);
        // Trackpads commonly end (or send another sample) before the next frame.
        await gesture.panZoomUpdate(at, scale: .65);
        await gesture.panZoomEnd();
      } else if (exit == 'touch') {
        final a = await tester.startGesture(const Offset(250, 300), pointer: 1);
        final b = await tester.startGesture(const Offset(550, 300), pointer: 2);
        await a.moveTo(const Offset(350, 300));
        await b.moveTo(const Offset(450, 300));
        await a.up();
        await b.up();
      } else {
        model.leave();
      }
      expect(model.activePlane, isNull);
      expect(
        camera.position.distanceTo(focused),
        lessThan(1e-6),
        reason: 'exit must begin at the displayed focus pose',
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 325));
      expect(camera.position.distanceTo(focused), greaterThan(.1));
      expect(
        camera.position.distanceTo(world),
        greaterThan(.1),
        reason: 'the camera must pass through intermediate poses',
      );
      await tester.pumpAndSettle();
      expect(camera.position.distanceTo(world), lessThan(1e-6));
      expect(camera.target.distanceTo(target), lessThan(1e-6));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
