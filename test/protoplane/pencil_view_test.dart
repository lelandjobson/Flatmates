import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/pencil.dart';
import 'package:flatmates/protoplane/pencil_ink_effects.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';
import 'pencil_test.dart' show paperWorld;

void main() {
  for (final size in [
    const Size(900, 700),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    testWidgets('pencil drag, second finger, stamp and eraser at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final c = paperWorld()..leave();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ProtoplaneConceptView(animateFog: false, controller: c),
        ),
      );
      await tester.pumpAndSettle();
      c.enter('surface-paper');
      c.selectTool(CraftTool.pencil);
      await tester.pumpAndSettle();
      final scene = tester
          .widget<SceneView>(find.byType(SceneView).first)
          .scene;
      Offset point(double x, double y) => scene.camera!.projectToScreen(
        c.activePlane!.point(Offset(x, y)),
        size,
      )!;
      final finger = await tester.startGesture(point(.25, .25));
      await finger.moveTo(point(.75, .75));
      await tester.pump();
      expect(c.previewMarks, isNotEmpty);
      final second = await tester.startGesture(point(.7, .25), pointer: 2);
      await tester.pump();
      expect(c.previewMarks, isEmpty);
      expect(c.balances[PaperMaterial.graphite], 128);
      await second.up();
      await finger.up();
      await tester.pumpAndSettle();
      final draw = await tester.startGesture(point(.25, .25));
      await draw.moveTo(point(.75, .75));
      await tester.pump();
      PencilInkPainter ink() =>
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('pencil-ink-overlay')),
                  )
                  .painter!
              as PencilInkPainter;
      expect(ink().live, isNotEmpty);
      await draw.up();
      await tester.pump();
      expect(ink().live, isEmpty);
      expect(ink().effects.activeCount, 1);
      expect(c.marksOn(c.activePlane!), isNotEmpty);
      await tester.pumpAndSettle();
      expect(ink().effects.activeCount, 0);
      expect(c.marksOn(c.activePlane!), isNotEmpty);
      expect(scene.meshes.any((m) => m.pencilShades.isNotEmpty), isTrue);
      c.commitMarks(PencilMotif.parallel.segments());
      await tester.pumpAndSettle();
      expect(find.text('motif discovered · Parallel lines'), findsOneWidget);
      c.selectMotif(PencilMotif.parallel);
      c.rotateMotif();
      await tester.pumpAndSettle();
      await tester.tapAt(point(.5, .5));
      await tester.pumpAndSettle();
      expect(c.discoveredMotifs, contains(PencilMotif.crosshatch));
      c.selectTool(CraftTool.eraser);
      await tester.pumpAndSettle();
      final before = c.marksOn(c.activePlane!).length;
      final erase = await tester.startGesture(point(.25, .25));
      await erase.moveTo(point(.75, .75));
      await erase.up();
      await tester.pumpAndSettle();
      expect(c.marksOn(c.activePlane!).length, lessThan(before));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
