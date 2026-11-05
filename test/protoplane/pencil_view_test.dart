import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/pencil.dart';
import 'package:flatmates/protoplane/pencil_ink_effects.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';
import 'pencil_test.dart' show paperWorld;
import 'unified_eraser_test.dart' show mixedEraserWorld;
import 'layered_terrain_test.dart' show snapshot, centerId;

void main() {
  testWidgets(
    'one eraser icon scrubs pencil marks and graphite in a single drag',
    (tester) async {
      final c = mixedEraserWorld()..leave();
      addTearDown(c.dispose);
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: ProtoplaneConceptView(animateFog: false, controller: c),
        ),
      );
      await tester.pumpAndSettle();
      c.enter(centerId(c, PaperMaterial.paperWhite));
      c.selectTool(CraftTool.eraser);
      await tester.pumpAndSettle();
      expect(c.paperSurface, isTrue);
      expect(c.graphitePlane, isNotNull);
      expect(find.byTooltip('Eraser'), findsOneWidget);
      final before = snapshot(c), balance = c.balances[PaperMaterial.graphite]!;
      final camera = tester
          .widget<SceneView>(find.byType(SceneView).first)
          .scene
          .camera!;
      Offset point(double x) => camera.projectToScreen(
        c.activePlane!.point(Offset(x, .5)),
        const Size(900, 700),
      )!;
      final drag = await tester.startGesture(point(.1));
      await drag.moveTo(point(.9));
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();
      expect(c.marksOn(c.activePlane!), isEmpty);
      expect(c.balances[PaperMaterial.graphite], greaterThan(balance));
      expect(c.erasing, isFalse);
      c.undo();
      await tester.pumpAndSettle();
      expect(snapshot(c), before);
      expect(find.byTooltip('Eraser'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('edge dots, chained holds, unfinished release and exact leg undo', (
    tester,
  ) async {
    final c = paperWorld();
    c.load(snapshot(c));
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
    final camera = tester
        .widget<SceneView>(find.byType(SceneView).first)
        .scene
        .camera!;
    Offset point(double x, double y) => camera.projectToScreen(
      c.activePlane!.point(Offset(x, y), .008),
      const Size(800, 600),
    )!;
    Map<String, dynamic> ledger() {
      final saved = snapshot(c);
      return {
        for (final key in [
          'pencilMarks',
          'balances',
          'graphiteMilli',
          'nextStrokeId',
        ])
          key: saved[key],
      };
    }

    final before = ledger();
    // The pointer starts just outside the paper but within the visible edge dot.
    final start = point(0, 0);
    final outside =
        start +
        (start - point(.25, .25)) / (start - point(.25, .25)).distance * 5;
    final drag = await tester.startGesture(outside);
    await drag.moveTo(point(1, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 299));
    expect(ledger(), before);
    await tester.pump(const Duration(milliseconds: 2));
    final first = ledger();
    expect(
      c.marksOn(c.activePlane!).fold<double>(0, (a, s) => a + s.length),
      closeTo(1, 1e-7),
    );
    await tester.pump(const Duration(milliseconds: 900));
    expect(ledger(), first); // Staying on the endpoint cannot charge twice.
    await drag.moveTo(point(1, 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 301));
    expect(
      c.marksOn(c.activePlane!).fold<double>(0, (a, s) => a + s.length),
      closeTo(2, 1e-7),
    );
    final second = ledger();
    await drag.moveTo(point(0, 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    await drag.up();
    await tester.pumpAndSettle();
    expect(ledger(), second);
    c.undo();
    expect(ledger(), first);
    c.undo();
    expect(ledger(), before);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

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
      final finger = await tester.startGesture(point(.25, .25), pointer: 91);
      await finger.moveTo(point(.75, .75));
      await tester.pump();
      expect(c.marksOn(c.activePlane!), isEmpty);
      final second = await tester.startGesture(point(.7, .25), pointer: 92);
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
      await tester.pump(const Duration(milliseconds: 150));
      expect(ink().dwellProgress, 0);
      expect(c.marksOn(c.activePlane!), isEmpty);
      final capture = tester.renderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary).first,
      );
      await tester.runAsync(() async {
        final image = await capture.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '/tmp/pencil-dwell-${size.width.toInt()}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pump(const Duration(milliseconds: 151));
      expect(c.marksOn(c.activePlane!), isNotEmpty);
      final confirmed = snapshot(c);
      expect(ink().effects.activeFillCount, 1);
      // A new endpoint starts its own hold without disturbing the accepted fill.
      await draw.moveTo(point(.75, .25));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(ink().effects.activeFillCount, 1);
      expect(ink().live, isNotEmpty);
      await draw.up();
      await tester.pump();
      expect(ink().live, isEmpty);
      expect(ink().effects.activeFillCount, 1);
      expect(snapshot(c), confirmed);
      await tester.pump(const Duration(milliseconds: 46));
      expect(ink().effects.activeFillCount, 0);
      expect(ink().effects.activeCount, 0);
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
