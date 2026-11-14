import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/stroke_preview.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';

const size = Size(1000, 800);
Future<ProtoplaneController> mount(WidgetTester tester) async {
  final model = ProtoplaneController(unlimitedPaper: true);
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
  return model;
}

void main() {
  for (final focused in [false, true]) {
    for (final program in [ProgramKind.cut, ProgramKind.place]) {
      testWidgets(
        'toolbar ${program.name} drops onto regions, focused=$focused',
        (tester) async {
          final model = await mount(tester);
          final plane = model.planes['ground-starter-paperWhite-0-0']!;
          if (focused) {
            model.enter(plane.id);
            await tester.pumpAndSettle();
          }
          final surface = model.regionSurface(plane.id)!;
          model.workspace.regions['target'] = LightRegion(
            'target',
            surface.id,
            mapRegion(plane.region, plane, surface.frame),
          );
          final before = model.toJson().toString();
          final camera = tester
              .widget<SceneView>(find.byType(SceneView).first)
              .scene
              .camera!;
          final target = camera.projectToScreen(
            plane.point(const Offset(.5, .5), .009),
            size,
          )!;
          final icon = find.byTooltip(
            program == ProgramKind.cut ? 'Scissors' : 'Place',
          );
          final gesture = await tester.startGesture(
            tester.getCenter(icon),
            kind: focused
                ? ui.PointerDeviceKind.touch
                : ui.PointerDeviceKind.mouse,
          );
          await gesture.moveTo(target);
          await tester.pump();
          await gesture.up();
          await tester.pumpAndSettle();
          expect(model.programIssue, isNull);
          expect(model.workspace.regions, isEmpty);
          if (program == ProgramKind.cut) {
            expect(model.landscape.terrain.remainingInTile(plane.id), isEmpty);
          } else {
            expect(model.objects, hasLength(1));
            expect(model.objects.values.single.kind, CraftKind.floor);
          }
          model.undo();
          await tester.pumpAndSettle();
          expect(model.toJson().toString(), before);
          expect(model.workspace.regions, hasLength(1));
          // A tap retains the direct gesture tool instead of selecting its program.
          await tester.tap(icon);
          await tester.pump();
          expect(
            model.tool,
            program == ProgramKind.cut ? CraftTool.scissors : CraftTool.place,
          );
          expect(model.selectedProgram, isNull);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets(
    'light pencil shares animated pips and live cursor feedback with direct tools',
    (tester) async {
      final model = await mount(tester);
      final plane = model.planes['ground-starter-paperWhite-0-0']!;
      model.enter(plane.id);
      await tester.pumpAndSettle();
      final original = tester
          .widget<CustomPaint>(find.byKey(const ValueKey('craft-grid-overlay')))
          .painter!;
      model.selectTool(CraftTool.pencil);
      await tester.pumpAndSettle();
      dynamic feedback() => tester
          .widget<CustomPaint>(
            find.byKey(const ValueKey('region-drawing-feedback')),
          )
          .painter!;
      expect(feedback().runtimeType, original.runtimeType);
      expect(feedback().lineColor, lightPencilColor);
      final camera = tester
          .widget<SceneView>(find.byType(SceneView).first)
          .scene
          .camera!;
      Offset screen(Offset p) =>
          camera.projectToScreen(plane.point(p, .009), size)!;
      final gesture = await tester.startGesture(
        screen(Offset.zero),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 35));
      final dynamic initial = feedback();
      final node = (initial.pathOverride as List<int>).single;
      expect(initial.dotSelection[node], greaterThan(0));
      expect(initial.dotSelection[node], lessThan(1));
      final pointer = screen(const Offset(.2, 0));
      await gesture.moveTo(pointer);
      await tester.pump(const Duration(milliseconds: 16));
      final dynamic partial = feedback();
      expect(partial.livePointer, pointer);
      expect(partial.pathOverride, hasLength(1));
      expect(
        liveStrokePreview(
          grid: partial.gridOverride,
          path: partial.pathOverride,
          pointer: partial.livePointer,
          project: (p) => camera.projectToScreen(
            (partial.planeOverride as CraftPlane).point(p, .009),
            size,
          ),
        ),
        hasLength(2),
      );
      await gesture.moveTo(screen(const Offset(.5, 0)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(feedback().segmentPulse, greaterThan(0));
      expect(feedback().pathOverride.length, greaterThan(1));
      for (final p in [
        const Offset(.5, .5),
        const Offset(0, .5),
        Offset.zero,
      ]) {
        await gesture.moveTo(screen(p));
        await tester.pump();
      }
      expect(feedback().ready, isTrue);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(model.workspace.regions, isNotEmpty);
      expect(model.pencilMarks, isEmpty);
      model.leave();
      await tester.pumpAndSettle();
      expect(model.tool, CraftTool.orbit);
      expect(model.selectedProgram, isNull);
      final count = model.workspace.regions.length;
      // Orbit can refocus immediately, with no intervening tool selection.
      final tap = await tester.startGesture(
        screen(const Offset(.7, .7)),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tap.up();
      await tester.pumpAndSettle();
      expect(model.activePlaneId, isNotNull);
      expect(model.workspace.regions, hasLength(count));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'world drawing uses the same feedback and leaves the camera fixed',
    (tester) async {
      final model = await mount(tester);
      final plane = model.planes['ground-starter-paperWhite-0-0']!;
      final camera = tester
          .widget<SceneView>(find.byType(SceneView).first)
          .scene
          .camera!;
      final before = camera.position.clone();
      model.selectTool(CraftTool.pencil);
      await tester.pump();
      Offset screen(Offset p) =>
          camera.projectToScreen(plane.point(p, .009), size)!;
      final gesture = await tester.startGesture(
        screen(Offset.zero),
        kind: ui.PointerDeviceKind.mouse,
      );
      await gesture.moveTo(screen(const Offset(.5, 0)));
      await tester.pump();
      final dynamic painter = tester
          .widget<CustomPaint>(
            find.byKey(const ValueKey('region-drawing-feedback')),
          )
          .painter!;
      expect(painter.runtimeType.toString(), '_GridPainter');
      expect(painter.livePointer, screen(const Offset(.5, 0)));
      expect(camera.position.distanceTo(before), lessThan(1e-6));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        model.workspace.lines.values.any((lines) => lines.isNotEmpty),
        isTrue,
      );
      expect(model.activePlaneId, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
