import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/drawing_graph.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';

void main() {
  testWidgets(
    'pencil retraces pending segments and keep only complete pip edges',
    (tester) async {
      final c = ProtoplaneController();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ProtoplaneConceptView(controller: c, animateFog: false),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('construction-pencil')));
      await tester.pumpAndSettle();
      final camera = tester
          .widget<SceneView>(find.byType(SceneView).first)
          .scene
          .camera!;
      Offset screen(Offset p) => camera.projectToScreen(
        c.drawingSurface!.frame.point(p, .009),
        const Size(800, 600),
      )!;
      dynamic feedback() => tester
          .widget<CustomPaint>(
            find.byKey(const ValueKey('drawing-graph-overlay')),
          )
          .painter;
      for (final implement in [DrawingImplement.pencil]) {
        c.selectDrawingImplement(implement);
        await tester.pumpAndSettle();
        Offset point(double x, double y) => implement.toSurface(Offset(x, y));
        final drag = await tester.startGesture(screen(point(0, 0)));
        await drag.moveTo(screen(point(1, 0)));
        await drag.moveTo(screen(point(1, 1)));
        await tester.pump();
        expect((feedback().path as List).length, greaterThan(2));
        expect(c.surfaceGraphs, isEmpty); // Live tracing is not persisted yet.
        await drag.moveTo(screen(point(1, 0))); // Retrace through skipped pips.
        await drag.moveTo(screen(point(0, 0)));
        await tester.pump();
        expect((feedback().path as List).length, 1);
        await drag.moveTo(screen(point(1, 0))); // Draw forward again.
        await drag.up();
        await tester.pumpAndSettle();
        expect(c.surfaceGraphs.single.edges.length, 1);
        expect(c.surfaceGraphs.single.edges.single.length, closeTo(1, 1e-6));
        c.undo();
        await tester.pumpAndSettle();
        expect(c.surfaceGraphs, isEmpty);
      }
      c.selectDrawingImplement(DrawingImplement.marker);
      await tester.pumpAndSettle();
      final partial = await tester.startGesture(screen(Offset.zero));
      final between = screen(const Offset(.35, 0));
      await partial.moveTo(between);
      await tester.pump();
      expect(feedback().liveScreen, between); // Feedback updates between pips.
      expect((feedback().path as List).length, 1);
      await partial.up();
      await tester.pumpAndSettle();
      expect(c.surfaceGraphs, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('second pointer cancels an unfinished construction gesture', (
    tester,
  ) async {
    final c = ProtoplaneController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ProtoplaneConceptView(controller: c, animateFog: false),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('construction-pencil')));
    await tester.pumpAndSettle();
    final camera = tester
        .widget<SceneView>(find.byType(SceneView).first)
        .scene
        .camera!;
    Offset screen(Offset p) => camera.projectToScreen(
      c.drawingSurface!.frame.point(p, .009),
      const Size(800, 600),
    )!;
    final a = await tester.startGesture(screen(Offset.zero), pointer: 1);
    await a.moveTo(screen(const Offset(1, 0)));
    final b = await tester.startGesture(screen(const Offset(1, 1)), pointer: 2);
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(c.drawingGraphs, isEmpty);
    expect(c.objects, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
