import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/program_stickerbook.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';

void main() {
  for (final focused in [false, true]) {
    testWidgets(
      'sticker drop is atomic and invalid drop retains its region, focus=$focused',
      (tester) async {
        final model = ProtoplaneController(unlimitedPaper: true);
        const size = Size(1000, 800);
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
        if (focused) {
          model.enter(plane.id);
          await tester.pumpAndSettle();
        }
        final surface = model.regionSurface(plane.id)!;
        final region = LightRegion(
          'drop',
          surface.id,
          mapRegion(plane.region, plane, surface.frame),
        );
        model.workspace.regions[region.id] = region;
        Future<void> drop() async {
          await tester.sendKeyEvent(LogicalKeyboardKey.slash);
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const ValueKey('program-search')),
            'house',
          );
          await tester.pumpAndSettle();
          final camera = tester
              .widget<SceneView>(find.byType(SceneView).first)
              .scene
              .camera!;
          final point = camera.projectToScreen(
            plane.point(const Offset(.5, .5), .009),
            size,
          )!;
          final gesture = await tester.startGesture(
            tester.getCenter(find.byKey(const ValueKey('program-house'))),
            kind: focused
                ? ui.PointerDeviceKind.touch
                : ui.PointerDeviceKind.mouse,
          );
          await gesture.moveTo(point);
          await tester.pump();
          await gesture.up();
          await tester.pumpAndSettle();
        }

        await drop();
        expect(model.objects, hasLength(6));
        expect(model.workspace.regions, isEmpty);
        expect(model.activePlaneId, focused ? plane.id : null);
        model.undo();
        await tester.pumpAndSettle();
        expect(model.objects, isEmpty);
        expect(model.workspace.regions, hasLength(1));
        model.unlimitedPaper = false;
        final before = model.toJson().toString();
        await drop();
        expect(model.programIssue, ProgramIssue.paper);
        expect(model.toJson().toString(), before);
        expect(model.workspace.regions, hasLength(1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final size in [
    const Size(1100, 800),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    testWidgets('stickerbook keyboard selection and layout $size', (
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
          home: RepaintBoundary(
            key: const ValueKey('capture'),
            child: ProtoplaneConceptView(controller: model, animateFog: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Orbit'), findsOneWidget);
      expect(find.byTooltip('Light pencil'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('program-stickerbook')), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (size.width == 1100) {
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('capture')),
          );
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '/tmp/flatmates-stickerbook.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.enterText(
        find.byKey(const ValueKey('program-search')),
        'house',
      );
      await tester.pump();
      expect(find.byType(ProgramSticker), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(model.selectedProgram, ProgramKind.house);
      expect(find.byKey(const ValueKey('program-stickerbook')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('program-stickerbook')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(model.selectedProgram, ProgramKind.volume);
      for (final modifier in [
        LogicalKeyboardKey.metaLeft,
        LogicalKeyboardKey.controlLeft,
      ]) {
        await tester.sendKeyDownEvent(modifier);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
        await tester.sendKeyUpEvent(modifier);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('program-stickerbook')),
          findsOneWidget,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('light pencil draws in the world and survives focusing', (
    tester,
  ) async {
    final model = ProtoplaneController();
    const size = Size(1000, 800);
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
    model.selectTool(CraftTool.pencil);
    await tester.pump();
    final scene = tester.widget<SceneView>(find.byType(SceneView).first).scene;
    final plane = model.planes['ground-starter-paperWhite-0-0']!;
    final points =
        [
              const Offset(0, 0),
              const Offset(1, 0),
              const Offset(1, 1),
              const Offset(0, 1),
              const Offset(0, 0),
            ]
            .map(
              (p) => scene.camera!.projectToScreen(plane.point(p, .009), size)!,
            )
            .toList();
    final gesture = await tester.startGesture(points.first);
    for (final point in points.skip(1)) {
      await gesture.moveTo(point);
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(model.workspace.regions, isNotEmpty);
    expect(model.activePlaneId, isNull);
    final count = model.workspace.regions.length;
    model.enter(plane.id);
    await tester.pumpAndSettle();
    model.leave();
    await tester.pumpAndSettle();
    expect(model.workspace.regions, hasLength(count));
    expect(model.pencilMarks, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
