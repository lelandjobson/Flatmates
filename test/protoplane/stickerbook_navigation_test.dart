import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/adjacent_grid_indicators.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/construction.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';
import 'package:flatmates/ui/game/view_crosshair.dart';
import 'layered_terrain_test.dart' show centerId;

void main() {
  testWidgets('committed lines still paint after leaving focus', (
    tester,
  ) async {
    final model = ProtoplaneController();
    addTearDown(model.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ProtoplaneConceptView(controller: model, animateFog: false),
      ),
    );
    await tester.pumpAndSettle();
    model.enter(centerId(model, PaperMaterial.paperWhite));
    expect(
      model.commitDrawingPath([const Offset(0, 0), const Offset(2, 0)]),
      isTrue,
    );
    model.leave();
    await tester.pumpAndSettle();
    final painter = tester
        .widget<CustomPaint>(
          find.byKey(const ValueKey('drawing-graph-overlay')),
        )
        .painter!;
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), const Size(800, 600));
    final picture = recorder.endRecording();
    await tester.runAsync(() async {
      final image = await picture.toImage(800, 600);
      final bytes = (await image.toByteData())!.buffer.asUint8List();
      expect(
        [for (var i = 3; i < bytes.length; i += 4) bytes[i]].any((a) => a > 0),
        isTrue,
      );
      image.dispose();
    });
    picture.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('paper preview follows camera and a drag never places', (
    tester,
  ) async {
    final model = ProtoplaneController();
    addTearDown(model.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ProtoplaneConceptView(controller: model, animateFog: false),
      ),
    );
    await tester.pumpAndSettle();
    model.enter(centerId(model, PaperMaterial.paperWhite));
    final region = rectangle(2, 2);
    expect(
      model.commitDrawingPath([...region.outer, region.outer.first]),
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('construction-paper')));
    await tester.pumpAndSettle();
    dynamic painter() => tester
        .widget<CustomPaint>(
          find.byKey(const ValueKey('drawing-graph-overlay')),
        )
        .painter;
    expect(painter().evaluation?.valid, isTrue);
    final previousTarget = painter().evaluation?.target?.planeId;
    final drag = await tester.startGesture(
      const Offset(300, 250),
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveBy(const Offset(300, 0));
    await drag.up();
    await tester.pumpAndSettle();
    expect(painter().evaluation?.target?.planeId, isNot(previousTarget));
    expect(model.assemblies, isEmpty);
    expect(model.constructionTool, ConstructionTool.paper);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets(
      'volume navigates with $kind and drawing locks the resulting pose',
      (tester) async {
        final model = ProtoplaneController();
        addTearDown(model.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: ProtoplaneConceptView(controller: model, animateFog: false),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('construction-pencil')));
        await tester.pumpAndSettle();
        final camera = tester
            .widget<SceneView>(find.byType(SceneView).first)
            .scene
            .camera!;
        final initial = camera.position.clone();
        expect(find.byType(ViewCrosshair), findsNothing);
        await tester.tap(find.byKey(const ValueKey('construction-volume')));
        await tester.pumpAndSettle();
        expect(camera.position, initial);
        expect(
          tester.widget<ViewCrosshair>(find.byType(ViewCrosshair)).position,
          const Offset(400, 300),
        );
        final pips =
            tester
                    .widget<CustomPaint>(
                      find.byKey(const ValueKey('adjacent-grid-overlay')),
                    )
                    .painter!
                as AdjacentGridPainter;
        expect(pips.enabled, isFalse);
        final drag = await tester.startGesture(
          const Offset(300, 250),
          kind: kind,
        );
        await drag.moveBy(const Offset(70, 0));
        await drag.up();
        await tester.pumpAndSettle();
        expect(camera.position, isNot(initial));
        expect(model.activePlaneId, isNull);
        expect(model.assemblies, isEmpty);
        final moved = camera.position.clone();
        await tester.tap(find.byKey(const ValueKey('construction-pencil')));
        await tester.pumpAndSettle();
        expect(camera.position, moved);
        expect(find.byType(ViewCrosshair), findsNothing);
        final drawing = await tester.startGesture(
          const Offset(300, 250),
          kind: kind,
        );
        await drawing.moveBy(const Offset(70, 0));
        await drawing.up();
        await tester.pumpAndSettle();
        expect(camera.position, moved);
        await tester.tap(find.byKey(const ValueKey('construction-volume')));
        await tester.pumpAndSettle();
        final trackpad = await tester.createGesture(
          kind: PointerDeviceKind.trackpad,
        );
        await trackpad.panZoomStart(const Offset(300, 250));
        await trackpad.panZoomUpdate(
          const Offset(300, 250),
          pan: const Offset(45, 0),
          scale: .9,
        );
        await trackpad.panZoomEnd();
        await tester.pumpAndSettle();
        expect(camera.position, isNot(moved));
        expect(model.activePlaneId, isNull);
        final beforeScroll = camera.position.clone();
        await tester.sendEventToBinding(
          const PointerScrollEvent(
            position: Offset(300, 250),
            scrollDelta: Offset(0, 60),
          ),
        );
        await tester.pumpAndSettle();
        expect(camera.position, isNot(beforeScroll));
        expect(model.activePlaneId, isNull);
        final navigated = camera.position.clone();
        model.leave();
        await tester.pumpAndSettle();
        expect((camera.position - navigated).length, lessThan(.00001));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
