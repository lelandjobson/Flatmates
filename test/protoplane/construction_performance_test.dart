import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';
import 'housing_test.dart' show makeRoom, cutDoor, addBlanket;

// Repeatable CPU/widget benchmark, not a device GPU/FPS measurement.
// flutter test test/protoplane/construction_performance_test.dart --reporter expanded
void main() {
  testWidgets('occupied room navigation and construction CPU benchmark', (
    tester,
  ) async {
    final c = ProtoplaneController()..enableInPlaceDrawing();
    addTearDown(c.dispose);
    final room = makeRoom(c);
    cutDoor(c, room);
    addBlanket(c, room);
    c.leave();
    c.constructionTool = null;
    await tester.pumpWidget(
      MaterialApp(
        home: ProtoplaneConceptView(controller: c, animateFog: false),
      ),
    );
    await tester.pumpAndSettle();
    final scene = tester.widget<SceneView>(find.byType(SceneView).first).scene;
    final camera = scene.camera!;
    final roof = c.planes['surface-${room.id}-roof-out-0']!;
    await tester.tapAt(
      camera.projectToScreen(
        roof.point(roof.region.bounds.center),
        const Size(800, 600),
      )!,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('exit-room')), findsOneWidget);
    for (final tool in ['navigation', 'paper']) {
      if (tool == 'paper') {
        await tester.tap(find.byKey(const ValueKey('construction-paper')));
        await tester.pumpAndSettle();
      }

      final samples = <int>[];
      for (var i = 0; i < 40; i++) {
        final watch = Stopwatch()..start();
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: const Offset(400, 300),
            scrollDelta: Offset(0, i.isEven ? 1 : -1),
          ),
        );
        await tester.pump(const Duration(milliseconds: 16));
        watch.stop();
        if (i >= 10) samples.add(watch.elapsedMicroseconds);
      }
      samples.sort();
      debugPrint(
        'CONSTRUCTION CPU $tool: median=${samples[15]}us p95=${samples[28]}us meshes=${scene.meshes.length}',
      );
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
