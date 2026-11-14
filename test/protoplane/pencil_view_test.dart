import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';

void main() {
  for (final size in [
    const Size(900, 700),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    testWidgets('light pencil, cancel, region use and undo at $size', (
      tester,
    ) async {
      final model = ProtoplaneController();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        model.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: ProtoplaneConceptView(controller: model, animateFog: false),
        ),
      );
      await tester.pumpAndSettle();
      final plane = model.planes['ground-starter-paperWhite-0-0']!;
      model.enter(plane.id);
      model.selectTool(CraftTool.pencil);
      await tester.pumpAndSettle();
      final camera = tester
          .widget<SceneView>(find.byType(SceneView).first)
          .scene
          .camera!;
      Offset screen(Offset p) =>
          camera.projectToScreen(plane.point(p, .009), size)!;
      final before = Map.of(model.balances);
      final gesture = await tester.startGesture(screen(Offset.zero));
      for (final p in [
        const Offset(1, 0),
        const Offset(1, 1),
        const Offset(0, 1),
        Offset.zero,
      ]) {
        await gesture.moveTo(screen(p));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(model.workspace.regions, isNotEmpty);
      expect(model.pencilMarks, isEmpty);
      expect(model.balances, before);
      final count = model.workspace.regions.length;
      final first = await tester.startGesture(
        screen(const Offset(.5, 0)),
        pointer: 2,
      );
      await first.moveTo(screen(const Offset(.5, .5)));
      await tester.pump();
      final second = await tester.startGesture(
        screen(const Offset(.8, .5)),
        pointer: 3,
      );
      await second.up();
      await first.up();
      await tester.pumpAndSettle();
      expect(model.workspace.regions, hasLength(count));
      final surface = model.regionSurface(plane.id)!;
      final local = surface.frame.local(plane.point(const Offset(.5, .5)));
      final target = model.workspace.at(surface.id, local)!;
      final preview = model.evaluateProgram(
        ProgramKind.place,
        target,
        surface,
        local,
      );
      expect(preview.issue, isNull);
      expect(model.applyProgram(preview), isTrue);
      expect(model.objects, hasLength(1));
      expect(model.workspace.regions.length, lessThan(count));
      model.undo();
      expect(model.objects, isEmpty);
      expect(model.workspace.regions, hasLength(count));
      model.leave();
      await tester.pumpAndSettle();
      expect(model.workspace.regions, hasLength(count));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
