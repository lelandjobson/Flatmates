import 'construction_fixture.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';
import 'package:flatmates/ui/game/view_crosshair.dart';

void main() {
  testWidgets('two finger swipe moves one adjacent plane and retains drafts', (
    tester,
  ) async {
    final model = constructionWorld();
    tester.view.physicalSize = const Size(900, 700);
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
    model.enter('ground-4-4');
    model.appendNode(0);
    final draft = model.draftKey;
    await tester.pumpAndSettle();
    final a = await tester.startGesture(const Offset(300, 310), pointer: 1);
    final b = await tester.startGesture(const Offset(300, 410), pointer: 2);
    await a.moveBy(const Offset(180, 0));
    await b.moveBy(const Offset(180, 0));
    expect(model.activePlaneId, 'ground-4-4');
    await a.moveBy(const Offset(70, 0));
    await b.moveBy(const Offset(70, 0));
    final destination = model.activePlaneId;
    expect(destination, isNot('ground-4-4'));
    expect(destination, isNotNull);
    await tester.pumpAndSettle();
    await a.moveBy(const Offset(250, 0));
    await b.moveBy(const Offset(250, 0));
    expect(model.activePlaneId, destination);
    await a.up();
    await b.up();
    expect(model.drafts[draft]!.path, [0]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('volume tap and 3D cap drag are undoable', (tester) async {
    final model = constructionWorld();
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      model.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: ProtoplaneConceptView(controller: model),
      ),
    );
    await tester.pumpAndSettle();
    model.enter('ground-4-4');
    model.beginGesture();
    for (final n in [0, 1, 2, 5, 8, 7, 6, 3, 0]) {
      model.appendNode(n);
    }
    model.finishGesture();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Volume'));
    await tester.pumpAndSettle();
    final scene = tester.widget<SceneView>(find.byType(SceneView).first).scene;
    final camera = scene.camera!, plane = model.activePlane!;
    final at = camera.projectToScreen(
      plane.point(const Offset(.5, .5)),
      const Size(900, 700),
    )!;
    await tester.tapAt(at);
    await tester.pumpAndSettle();
    expect(model.previewDepth, greaterThan(0));
    final before = model.previewDepth;
    await tester.tap(find.byTooltip('3D'));
    await tester.pumpAndSettle();
    final start = camera.projectToScreen(
      plane.point(const Offset(.5, .5), before),
      const Size(900, 700),
    )!;
    final end = camera.projectToScreen(
      plane.point(const Offset(.5, .5), before + .08),
      const Size(900, 700),
    )!;
    final drag = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await drag.moveTo(end);
    await drag.up();
    await tester.pumpAndSettle();
    expect(model.previewDepth, greaterThan(before + .04));
    model.undo();
    await tester.pumpAndSettle();
    expect(model.previewDepth, closeTo(before, 1e-6));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  Future<void> mount(
    WidgetTester tester,
    ProtoplaneController model,
    Size size,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: RepaintBoundary(
          key: const ValueKey('capture'),
          child: ProtoplaneConceptView(controller: model, entryFocusLevel: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void resetView(WidgetTester tester) {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }

  testWidgets(
    'cursor aim focuses smoothly with dim non-interactive neighbors',
    (tester) async {
      final model = constructionWorld();
      addTearDown(() {
        resetView(tester);
        model.dispose();
      });
      const size = Size(900, 700);
      await mount(tester, model, size);
      final scene = tester
          .widget<SceneView>(find.byType(SceneView).first)
          .scene;
      final camera = scene.camera!;
      final original = camera.position.clone();
      final lens = camera.fovDegrees;
      final tile = model.planes['ground-4-4']!;
      final at = camera.projectToScreen(
        tile.point(const Offset(.5, .5)),
        size,
      )!;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: at);
      await mouse.moveTo(at);
      await tester.pump();
      expect(
        tester.widget<ViewCrosshair>(find.byType(ViewCrosshair)).position,
        at,
      );
      await mouse.down(at);
      await mouse.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final midway = camera.position.clone();
      expect(model.activePlaneId, 'ground-4-4');
      final neighbor = scene.meshes.firstWhere((m) => m.id == 'ground-5-4');
      final fadingOpacity = neighbor.material.opacity;
      await tester.pumpAndSettle();
      expect(camera.fovDegrees, lens);
      expect(camera.position.distanceTo(midway), greaterThan(.01));
      expect(
        scene.meshes.firstWhere((m) => m.id == 'ground-5-4').material.opacity,
        lessThan(fadingOpacity),
      );
      expect(scene.meshes.any((m) => m.id == 'ground-7-7'), isFalse);
      final neighborAt = camera.projectToScreen(
        model.planes['ground-5-4']!.point(const Offset(.5, .5)),
        size,
      )!;
      if ((Offset.zero & size).contains(neighborAt)) {
        await mouse.down(neighborAt);
        await mouse.up();
        await tester.pumpAndSettle();
        expect(model.activePlaneId, 'ground-4-4');
      }
      model.leave();
      await tester.pumpAndSettle();
      expect(camera.position.distanceTo(original), lessThan(.00001));
      expect(scene.meshes.any((m) => m.id == 'ground-7-7'), isTrue);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'hold previous point steps back once and hover removal is undoable',
    (tester) async {
      final model = constructionWorld();
      addTearDown(() {
        resetView(tester);
        model.dispose();
      });
      const size = Size(900, 700);
      await mount(tester, model, size);
      model.enter('ground-4-4');
      model.beginGesture();
      for (final n in [0, 9, 12]) {
        model.appendNode(n);
      }
      model.finishGesture();
      await tester.pumpAndSettle();
      final camera = tester
          .widget<SceneView>(find.byType(SceneView).first)
          .scene
          .camera!;
      Offset node(int n) => camera.projectToScreen(
        model.activePlane!.point(model.grid!.nodes[n], .008),
        size,
      )!;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: node(12));
      await mouse.moveTo(node(9));
      await tester.pump(const Duration(milliseconds: 499));
      expect(model.draft.path, [0, 9, 12]);
      await tester.pump(const Duration(milliseconds: 1));
      expect(model.draft.path, [0, 9]);
      await tester.pump(const Duration(milliseconds: 800));
      expect(model.draft.path, [0, 9]);
      model.undo();
      expect(model.draft.path, [0, 9, 12]);
      await mouse.moveTo(node(9) + const Offset(1, 0));
      await tester.pump(const Duration(milliseconds: 250));
      await mouse.moveTo(node(12));
      await tester.pump(const Duration(milliseconds: 600));
      expect(model.draft.path, [0, 9, 12]);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'scrubbing newest point erases it without immediately redrawing',
    (tester) async {
      final model = constructionWorld();
      addTearDown(() {
        resetView(tester);
        model.dispose();
      });
      const size = Size(900, 700);
      await mount(tester, model, size);
      model.enter('ground-4-4');
      model.beginGesture();
      for (final n in [0, 9, 12]) {
        model.appendNode(n);
      }
      model.finishGesture();
      await tester.pumpAndSettle();
      final camera = tester
          .widget<SceneView>(find.byType(SceneView).first)
          .scene
          .camera!;
      final at = camera.projectToScreen(
        model.activePlane!.point(model.grid!.nodes[12], .008),
        size,
      )!;
      final drag = await tester.startGesture(at, kind: PointerDeviceKind.mouse);
      for (final dx in [12.0, -12.0, 12.0, 0.0]) {
        await drag.moveTo(at + Offset(dx, 0));
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(model.draft.path, [0, 9]);
      await drag.up();
      model.undo();
      expect(model.draft.path, [0, 9, 12]);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'touch backtrack can continue drawing in the same undo transaction',
    (tester) async {
      final model = constructionWorld();
      addTearDown(() {
        resetView(tester);
        model.dispose();
      });
      const size = Size(900, 700);
      await mount(tester, model, size);
      await tester.tap(find.text('devtools'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset drawing on release'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      model.enter('ground-4-4');
      await tester.pumpAndSettle();
      final camera = tester
          .widget<SceneView>(find.byType(SceneView).first)
          .scene
          .camera!;
      Offset node(int n) => camera.projectToScreen(
        model.activePlane!.point(model.grid!.nodes[n], .008),
        size,
      )!;
      final drag = await tester.startGesture(node(0));
      await drag.moveTo(node(9));
      await drag.moveTo(node(12));
      expect(model.draft.path, [0, 9, 12]);
      await drag.moveTo(node(9));
      await tester.pump(const Duration(milliseconds: 500));
      expect(model.draft.path, [0, 9]);
      await drag.moveTo(node(1));
      expect(model.draft.path, [0, 9, 1]);
      await drag.up();
      model.undo();
      expect(model.draft.path, isEmpty);
      model.redo();
      expect(model.draft.path, [0, 9, 1]);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('devtools tabs fit mobile and grid lines toggle live', (
    tester,
  ) async {
    final model = constructionWorld();
    addTearDown(() {
      resetView(tester);
      model.dispose();
    });
    await mount(tester, model, const Size(390, 844));
    await tester.tap(find.text('devtools'));
    await tester.pumpAndSettle();
    expect(find.text('Grid connection lines'), findsOneWidget);
    final resolution = find.byType(Slider).first;
    final bounds = tester.getRect(resolution);
    await tester.tapAt(Offset(bounds.right - 24, bounds.center.dy));
    await tester.pumpAndSettle();
    expect(model.planes['ground-4-4']!.grids.first.nodes.length, 36);

    await tester.tap(find.text('Grid connection lines'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lighting'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ambient GI'), findsOneWidget);
    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Wall reveal near'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'craft zoom reaches plane normal and exits only beyond entry pose',
    (tester) async {
      final model = constructionWorld();
      addTearDown(() {
        resetView(tester);
        model.dispose();
      });
      await mount(tester, model, const Size(900, 700));
      await tester.tap(find.text('devtools'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Camera'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disable focus zoom'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(450, 350));
      await tester.pumpAndSettle();
      final camera = tester
          .widget<SceneView>(find.byType(SceneView).first)
          .scene
          .camera!;
      final semi = camera.position.clone(), normal = model.activePlane!.normal;
      Future<void> scroll(double dy) async {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: const Offset(450, 350),
            scrollDelta: Offset(0, dy),
          ),
        );
        await tester.pumpAndSettle();
      }

      await scroll(-400);
      expect(
        (camera.position - camera.target).normalized().dot(normal).abs(),
        closeTo(1, 1e-6),
      );
      await scroll(150);
      expect(model.activePlane, isNotNull);
      expect(camera.position.distanceTo(semi), greaterThan(.001));
      await scroll(196.57359);
      expect(model.activePlane, isNotNull);
      expect(camera.position.distanceTo(semi), lessThan(.001));
      await scroll(60);
      expect(model.activePlane, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('focus zoom is disabled by default but outward zoom dismisses', (
    tester,
  ) async {
    final model = constructionWorld();
    addTearDown(() {
      resetView(tester);
      model.dispose();
    });
    await mount(tester, model, const Size(900, 700));
    await tester.tapAt(const Offset(450, 350));
    await tester.pumpAndSettle();
    final camera = tester
        .widget<SceneView>(find.byType(SceneView).first)
        .scene
        .camera!;
    final pose = camera.position.clone(), up = camera.up.clone();
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(450, 350),
        scrollDelta: Offset(0, -400),
      ),
    );
    await tester.pumpAndSettle();
    expect(camera.position.distanceTo(pose), lessThan(1e-6));
    expect(camera.up.distanceTo(up), lessThan(1e-6));
    expect(model.activePlane, isNotNull);
    await tester.sendEventToBinding(
      const PointerScrollEvent(
        position: Offset(450, 350),
        scrollDelta: Offset(0, 60),
      ),
    );
    await tester.pumpAndSettle();
    expect(model.activePlane, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'release toggle preserves open crafts across drags when disabled',
    (tester) async {
      final model = constructionWorld();
      addTearDown(() {
        resetView(tester);
        model.dispose();
      });
      model.enter('ground-4-4');
      model.beginGesture();
      for (final n in [0, 2, 8, 6, 0]) {
        model.appendNode(n);
      }
      model.finishGesture();
      model.create();
      final floor = model.objects.values.single;
      model.leave();
      await mount(tester, model, const Size(900, 700));
      model.enter('surface-${floor.id}');
      model.selectGrid(2);
      await tester.pumpAndSettle();
      await tester.tap(find.text('devtools'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset drawing on release'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      final camera = tester
          .widget<SceneView>(find.byType(SceneView).first)
          .scene
          .camera!;
      Offset node(int n) => camera.projectToScreen(
        model.activePlane!.point(model.grid!.nodes[n], .008),
        const Size(900, 700),
      )!;
      Future<void> draw(int a, int b) async {
        final drag = await tester.startGesture(
          node(a),
          kind: PointerDeviceKind.mouse,
        );
        await drag.moveTo(node(b));
        await drag.up();
        await tester.pumpAndSettle();
      }

      await draw(6, 7);
      expect(model.draft.path, [6, 7]);
      expect(model.objects.length, 1);
      await draw(7, 8);
      expect(model.draft.path, [6, 7, 8]);
      expect(model.objects.length, 1);
      expect(find.text('Finish'), findsOneWidget);
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();
      expect(model.objects.values.last.kind, CraftKind.screen);
      expect(model.draft.path, isEmpty);
      model.selectGrid(0);
      await tester.pumpAndSettle();
      await tester.tap(find.text('devtools'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset drawing on release'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await draw(11, 12);
      expect(model.draft.path, isEmpty);
      expect(model.objects.length, 2);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('mouse drawing keeps plane camera and creates a floor', (
    tester,
  ) async {
    final model = constructionWorld();
    addTearDown(() {
      resetView(tester);
      model.dispose();
    });
    await mount(tester, model, const Size(900, 700));
    await tester.tap(find.text('devtools'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset drawing on release'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    model.enter('ground-4-4');
    await tester.pumpAndSettle();
    final scene = tester.widget<SceneView>(find.byType(SceneView).first).scene;
    final camera = scene.camera!;
    final pose = camera.position.clone();
    final grid = model.grid!, plane = model.activePlane!;
    Offset node(int i) => camera.projectToScreen(
      plane.point(grid.nodes[i], .008),
      const Size(900, 700),
    )!;
    final gesture = await tester.startGesture(
      node(0),
      kind: PointerDeviceKind.mouse,
    );
    for (final i in [1, 2, 5, 8, 7, 6, 3, 0]) {
      await gesture.moveTo(node(i));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(model.objects.values.single.kind, CraftKind.floor);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(model.draft.path, isEmpty);
    expect(camera.position.distanceTo(pose), lessThan(.00001));
    expect(find.text('Create'), findsNothing);
    expect(model.objects.values.single.kind, CraftKind.floor);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('touch pinch exits and restores world pose', (tester) async {
    final model = constructionWorld();
    addTearDown(() {
      resetView(tester);
      model.dispose();
    });
    await mount(tester, model, const Size(900, 700));
    final scene = tester.widget<SceneView>(find.byType(SceneView).first).scene;
    final original = scene.camera!.position.clone();
    // Tap through the reticle from world mode to cache the actual map pose.
    await tester.tapAt(const Offset(450, 350));
    await tester.pumpAndSettle();
    expect(model.activePlane, isNotNull);
    final a = await tester.startGesture(const Offset(300, 300), pointer: 1);
    final b = await tester.startGesture(const Offset(600, 300), pointer: 2);
    await a.moveTo(const Offset(410, 300));
    await b.moveTo(const Offset(490, 300));
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(model.activePlane, isNull);
    expect(scene.camera!.position.distanceTo(original), lessThan(.00001));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  for (final size in [
    const Size(390, 844),
    const Size(844, 390),
    const Size(1100, 800),
  ]) {
    testWidgets('craft controls fit $size and render preview', (tester) async {
      final model = constructionWorld();
      addTearDown(() {
        resetView(tester);
        model.dispose();
      });
      await mount(tester, model, size);
      model.enter('ground-4-4');
      model.beginGesture();
      for (final n in [0, 1, 2, 5, 8, 7, 6, 3, 0]) {
        model.appendNode(n);
      }
      model.finishGesture();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('3D'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (size.width == 1100) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '/tmp/protoplane-preview.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
