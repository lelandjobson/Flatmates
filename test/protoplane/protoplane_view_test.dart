import 'construction_fixture.dart';
import 'package:flatmates/gestures/gesture_debug.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/dev_settings.dart';
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
      MaterialApp(
        home: ProtoplaneConceptView(animateFog: false, controller: model),
      ),
    );
    await tester.pumpAndSettle();
    model.enter('ground-starter-paperWhite-0-0');
    model.appendNode(0);
    final draft = model.draftKey;
    await tester.pumpAndSettle();
    final a = await tester.startGesture(const Offset(300, 310), pointer: 1);
    final b = await tester.startGesture(const Offset(300, 410), pointer: 2);
    await a.moveBy(const Offset(40, 0));
    await b.moveBy(const Offset(40, 0));
    expect(model.activePlaneId, 'ground-starter-paperWhite-0-0');
    await a.moveBy(const Offset(70, 0));
    await b.moveBy(const Offset(70, 0));
    final destination = model.activePlaneId;
    expect(destination, isNot('ground-starter-paperWhite-0-0'));
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
        home: ProtoplaneConceptView(animateFog: false, controller: model),
      ),
    );
    await tester.pumpAndSettle();
    model.enter('ground-starter-paperWhite-0-0');
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
          child: ProtoplaneConceptView(
            animateFog: false,
            controller: model,
            entryFocusLevel: 0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void resetView(WidgetTester tester) {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }

  testWidgets('cursor aim focuses smoothly with dim adjacent Paper tiles', (
    tester,
  ) async {
    final model = ProtoplaneController();
    addTearDown(() {
      resetView(tester);
      model.dispose();
    });
    const size = Size(900, 700);
    await mount(tester, model, size);
    final scene = tester.widget<SceneView>(find.byType(SceneView).first).scene;
    final camera = scene.camera!;
    final original = camera.position.clone();
    final lens = camera.fovDegrees;
    final farId = model.landscape.terrain.tiles.values
        .firstWhere((t) => t.sheet.island == 'northeast')
        .id;
    final tile = model.planes['ground-starter-paperWhite-0-0']!;
    final at = camera.projectToScreen(tile.point(const Offset(.5, .5)), size)!;
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
    expect(model.activePlaneId, 'ground-starter-paperWhite-0-0');
    final neighbor = scene.meshes.firstWhere(
      (m) => m.id == 'ground-starter-paperWhite-1-0',
    );
    final fadingOpacity = neighbor.material.opacity;
    await tester.pumpAndSettle();
    expect(camera.fovDegrees, lens);
    expect(camera.position.distanceTo(midway), greaterThan(.01));
    expect(
      scene.meshes
          .firstWhere((m) => m.id == 'ground-starter-paperWhite-1-0')
          .material
          .opacity,
      lessThan(fadingOpacity),
    );
    expect(scene.meshes.any((m) => m.id == farId), isFalse);
    final neighborAt = camera.projectToScreen(
      model.planes['ground-starter-paperWhite-1-0']!.point(
        const Offset(.5, .5),
      ),
      size,
    )!;
    if ((Offset.zero & size).contains(neighborAt)) {
      await mouse.down(neighborAt);
      await mouse.up();
      await tester.pumpAndSettle();
      expect(model.activePlaneId, 'ground-starter-paperWhite-1-0');
    }
    model.leave();
    await tester.pumpAndSettle();
    expect(camera.position.distanceTo(original), lessThan(.00001));
    expect(scene.meshes.any((m) => m.id == farId), isTrue);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('hovering over past nodes never erases a stroke', (tester) async {
    final model = constructionWorld();
    addTearDown(() {
      resetView(tester);
      model.dispose();
    });
    const size = Size(900, 700);
    await mount(tester, model, size);
    model.enter('ground-starter-paperWhite-0-0');
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
    expect(model.draft.path, [0, 9, 12]);
    await tester.pump(const Duration(milliseconds: 800));
    expect(model.draft.path, [0, 9, 12]);
    expect(model.draft.path, [0, 9, 12]);
    await mouse.moveTo(node(9) + const Offset(1, 0));
    await tester.pump(const Duration(milliseconds: 250));
    await mouse.moveTo(node(12));
    await tester.pump(const Duration(milliseconds: 600));
    expect(model.draft.path, [0, 9, 12]);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'pointer shaking cancels the entire Place stroke without committing',
    (tester) async {
      final model = constructionWorld();
      addTearDown(() {
        resetView(tester);
        model.dispose();
      });
      const size = Size(900, 700);
      await mount(tester, model, size);
      model.enter('ground-starter-paperWhite-0-0');
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
      expect(model.draft.path, isEmpty);
      await drag.up();
      expect(model.objects, isEmpty);
      expect(model.draft.path, isEmpty);
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
      model.enter('ground-starter-paperWhite-0-0');
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
      expect(model.draft.path, isEmpty);
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
    expect(
      model.planes['ground-starter-paperWhite-0-0']!.grids.first.nodes.length,
      36,
    );

    await tester.tap(find.text('Grid connection lines'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Lighting'));
    await tester.tap(find.text('Lighting'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ambient GI'), findsOneWidget);
    await tester.ensureVisible(find.text('Camera'));
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
      await tester.ensureVisible(find.text('Camera'));
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
    'release commits valid open crafts and discards invalid drafts even with reset disabled',
    (tester) async {
      final model = constructionWorld();
      addTearDown(() {
        resetView(tester);
        model.dispose();
      });
      model.enter('ground-starter-paperWhite-0-0');
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
      expect(model.draft.path, isEmpty);
      expect(model.objects.values.last.kind, CraftKind.wall);
      expect(model.objects.length, greaterThanOrEqualTo(2));
      model.enter('ground-starter-paperWhite-1-0');
      await tester.pumpAndSettle();
      await draw(0, 1);
      expect(model.draft.path, isEmpty);
      expect(model.objects.length, greaterThanOrEqualTo(2));
      await tester.tap(find.text('devtools'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset drawing on release'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      await draw(1, 2);
      expect(model.draft.path, isEmpty);
      expect(model.objects.length, greaterThanOrEqualTo(2));
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets('loop closure can be withdrawn before release with $kind', (
      tester,
    ) async {
      final model = constructionWorld();
      addTearDown(() {
        resetView(tester);
        model.dispose();
      });
      await mount(tester, model, const Size(900, 700));
      model.setProtoplaneCells(3);
      model.enter('ground-starter-paperWhite-0-0');
      await tester.pumpAndSettle();
      final camera = tester
          .widget<SceneView>(find.byType(SceneView).first)
          .scene
          .camera!;
      Offset node(int n) => camera.projectToScreen(
        model.activePlane!.point(model.grid!.nodes[n], .008),
        const Size(900, 700),
      )!;
      final drag = await tester.startGesture(node(5), kind: kind);
      for (final n in [6, 10, 9, 5]) {
        await drag.moveTo(node(n));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(model.closed, isTrue);
      expect(model.objects, isEmpty);
      // Small motion within the closing snap zone retains closure.
      await drag.moveTo(node(5) + const Offset(2, 0));
      expect(model.closed, isTrue);
      // Reverse the actual closing edge before continuing in a new direction.
      await drag.moveTo(node(9));
      await drag.moveTo(node(8));
      await tester.pump();
      expect(model.draft.path, [5, 6, 10, 9, 8]);
      expect(model.closed, isFalse);
      for (final n in [4, 5]) {
        await drag.moveTo(node(n));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(model.closed, isTrue);
      expect(model.objects, isEmpty);
      await drag.up();
      await tester.pumpAndSettle();
      expect(model.objects.values.single.kind, CraftKind.floor);
      model.undo();
      expect(model.objects, isEmpty);
      expect(model.draft.path, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final valid in [true, false]) {
    testWidgets(
      'closed stroke whites only when valid and fades for 750ms ($valid)',
      (tester) async {
        final model = constructionWorld();
        addTearDown(() {
          resetView(tester);
          model.dispose();
        });
        if (!valid) {
          model.enter('ground-starter-paperWhite-0-0');
          model.beginGesture();
          for (final n in [0, 1, 4, 3, 0]) {
            model.appendNode(n);
          }
          model.finishGesture();
          model.create();
          model.leave();
        }
        await mount(tester, model, const Size(900, 700));
        model.enter('ground-starter-paperWhite-0-0');
        await tester.pumpAndSettle();
        final camera = tester
            .widget<SceneView>(find.byType(SceneView).first)
            .scene
            .camera!;
        Offset node(int n) => camera.projectToScreen(
          model.activePlane!.point(model.grid!.nodes[n], .008),
          const Size(900, 700),
        )!;
        Future<List<int>> pixel() async {
          // Safe-zone framing can move when the validation banner appears.
          // Follow the same point on the stroke rather than a stale screen pixel.
          final mid = node(0) * .7 + node(1) * .3, delta = node(1) - node(0);
          final sample = mid + Offset(-delta.dy, delta.dx) / delta.distance * 2;
          final paint = tester
              .widget<CustomPaint>(
                find.byKey(const ValueKey('craft-grid-overlay')),
              )
              .painter!;
          final recorder = ui.PictureRecorder();
          paint.paint(Canvas(recorder), const Size(900, 700));
          final picture = recorder.endRecording();
          final result = await tester.runAsync(() async {
            final image = await picture.toImage(900, 700);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            final offset = (sample.dy.round() * 900 + sample.dx.round()) * 4;
            final result = bytes!.buffer.asUint8List().sublist(
              offset,
              offset + 4,
            );
            image.dispose();
            return result;
          });
          picture.dispose();
          return result!;
        }

        final restingAlpha = (await pixel())[3];
        final drag = await tester.startGesture(
          node(0),
          kind: PointerDeviceKind.mouse,
        );
        for (final n in [1, 4, 3, 0]) {
          await drag.moveTo(node(n));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pump(const Duration(milliseconds: 120));
        final before = await pixel();
        if (valid) {
          expect(before[0], greaterThan(240));
          expect(before[2], greaterThan(240));
        } else {
          expect(before[1], greaterThan(before[0]));
          expect(before[2], lessThan(50));
        }
        await drag.up();
        await tester.pump();
        final released = await pixel();
        await tester.pump(const Duration(milliseconds: 375));
        final fading = await pixel();
        expect(fading[3], lessThan(released[3]));
        expect(fading[3], greaterThan(0));
        await tester.pump(const Duration(milliseconds: 375));
        // Wider context framing brings the selected-dot glow closer to the
        // sample. Allow a <3% antialiased tail after the stroke disappears.
        expect((await pixel())[3], lessThanOrEqualTo(restingAlpha + 8));
        final dynamic overlay = tester
            .widget<CustomPaint>(
              find.byKey(const ValueKey('craft-grid-overlay')),
            )
            .painter;
        expect(overlay.lineOpacity, 0);
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'gesture debug uses actual swipe verdict and retains released trace',
    (tester) async {
      final model = constructionWorld();
      addTearDown(() {
        resetView(tester);
        model.dispose();
      });
      await mount(tester, model, const Size(900, 700));
      await tester.tap(find.text('devtools'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Camera'));
      await tester.tap(find.text('Camera'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gesture overlay'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(GestureDebugOverlay), findsOneWidget);
      model.enter('ground-starter-paperWhite-0-0');
      await tester.pumpAndSettle();
      final a = await tester.startGesture(const Offset(300, 310), pointer: 41);
      final b = await tester.startGesture(const Offset(300, 410), pointer: 42);
      await a.moveBy(const Offset(110, 0));
      await b.moveBy(const Offset(110, 0));
      await a.up();
      await b.up();
      await tester.pumpAndSettle();
      final debug = tester
          .widget<GestureDebugOverlay>(find.byType(GestureDebugOverlay))
          .debug;
      expect(debug.phase, 'Released');
      expect(debug.contacts.length, 2);
      expect(debug.verdict, 'Swipe Right / E');
      expect(model.activePlaneId, isNot('ground-starter-paperWhite-0-0'));
      await tester.pump(const Duration(seconds: 2));
      expect(debug.contacts.length, 2);
      final next = await tester.startGesture(
        const Offset(450, 350),
        pointer: 43,
      );
      expect(debug.contacts.keys, [43]);
      await next.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('devtools'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Camera'));
      await tester.tap(find.text('Camera'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gesture overlay'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(GestureDebugOverlay), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final size in [
    const Size(390, 844),
    const Size(844, 390),
    const Size(1100, 800),
  ]) {
    testWidgets(
      'docked devtools leave world and focused scene pannable at $size',
      (tester) async {
        final model = constructionWorld();
        addTearDown(() {
          resetView(tester);
          model.dispose();
        });
        await mount(tester, model, size);
        final camera = tester
            .widget<SceneView>(find.byType(SceneView).first)
            .scene
            .camera!;
        Future<List<int>> scenePixel() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('capture')),
          );
          return (await tester.runAsync(() async {
            final image = await boundary.toImage();
            final data = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!.buffer.asUint8List();
            final offset =
                ((size.height * .65).floor() * size.width.toInt() +
                    size.width.toInt() -
                    12) *
                4;
            final pixel = data.sublist(offset, offset + 4);
            image.dispose();
            return pixel;
          }))!;
        }

        final colorBefore = await scenePixel();
        final barriersBefore = find.byType(ModalBarrier).evaluate().length;
        await tester.tap(find.text('devtools'));
        await tester.pumpAndSettle();
        expect(find.byType(ModalBarrier).evaluate().length, barriersBefore);
        expect(
          await scenePixel(),
          colorBefore,
          reason: 'Opening devtools must not dim the scene',
        );
        final panel = find.byKey(const ValueKey('protoplane-devtools-panel'));
        var rect = tester.getRect(panel);
        expect(rect.left, lessThan(30));
        expect(rect.right, lessThan(size.width * .6));
        expect(
          rect.top,
          greaterThan(tester.getRect(find.byTooltip('Back')).bottom),
        );
        await tester.ensureVisible(find.text('Lighting'));
        await tester.tap(find.text('Lighting'));
        await tester.pumpAndSettle();
        final before = camera.target.clone();
        Offset point() => Offset(
          (tester.getRect(panel).right + size.width - 80) / 2,
          tester.getRect(panel).center.dy,
        );
        final world = await tester.startGesture(
          point(),
          kind: PointerDeviceKind.mouse,
        );
        await world.moveBy(const Offset(24, 12));
        await world.up();
        await tester.pumpAndSettle();
        expect(camera.target.distanceTo(before), greaterThan(.001));
        expect(find.text('Ambient GI'), findsOneWidget);
        await tester.ensureVisible(find.text('Style'));
        await tester.tap(find.text('Style'));
        await tester.pumpAndSettle();
        final strength = find.byKey(const ValueKey('Texture strength'));
        final styleList = find
            .ancestor(
              of: find.text('Background'),
              matching: find.byType(ListView),
            )
            .first;
        await tester.scrollUntilVisible(
          strength,
          80,
          scrollable: find
              .descendant(of: styleList, matching: find.byType(Scrollable))
              .first,
        );
        await tester.pumpAndSettle();
        await tester.drag(strength, const Offset(-20, 0));
        await tester.pumpAndSettle();
        final pendingStrength = tester.widget<Slider>(strength).value;
        final settings = tester
            .widget<ProtoplaneDevToolsPanel>(
              find.byType(ProtoplaneDevToolsPanel),
            )
            .settings;
        expect(pendingStrength, isNot(settings.paperTextureStrength));
        model.enter('ground-starter-paperWhite-0-0');
        await tester.pumpAndSettle();
        rect = tester.getRect(panel);
        final footer = tester.getRect(
          find.byKey(ValueKey(model.activePlaneId)),
        );
        expect(rect.bottom, lessThan(footer.top));
        expect(
          rect.top,
          greaterThan(tester.getRect(find.byTooltip('Back')).bottom),
        );
        final position = camera.position.clone(),
            target = camera.target.clone(),
            snapshot = model.toJson();
        final focus = await tester.startGesture(
          point(),
          kind: PointerDeviceKind.mouse,
        );
        await focus.moveBy(const Offset(24, 12));
        await focus.up();
        await tester.pumpAndSettle();
        expect(camera.target.distanceTo(target), greaterThan(.001));
        expect(
          (camera.position - position).distanceTo(camera.target - target),
          lessThan(1e-6),
        );
        expect(model.toJson(), snapshot);
        expect(model.draft.path, isEmpty);
        expect(tester.widget<Slider>(strength).value, pendingStrength);
        expect(settings.paperTextureStrength, .6);

        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(find.byType(ProtoplaneDevToolsPanel), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

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
    model.enter('ground-starter-paperWhite-0-0');
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
    expect(model.objects, isEmpty);
    expect(model.drawingReady, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(model.objects, isEmpty);
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
      model.enter('ground-starter-paperWhite-0-0');
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
