import 'construction_fixture.dart';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/dev_settings.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';

void main() {
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

  testWidgets('world touch regions orbit and pan while pinch only zooms', (
    tester,
  ) async {
    final model = constructionWorld();
    addTearDown(() {
      resetView(tester);
      model.dispose();
    });
    await mount(tester, model, const Size(900, 700));
    final camera = tester
        .widget<SceneView>(find.byType(SceneView).first)
        .scene
        .camera!;
    final target = camera.target.clone();
    final position = camera.position.clone();
    final orbit = await tester.startGesture(const Offset(800, 610));
    await orbit.moveBy(const Offset(60, -250));
    await orbit.up();
    expect(camera.target, target);
    expect((camera.position - position).length, greaterThan(.01));
    final bottom = await tester.startGesture(const Offset(600, 500));
    await bottom.moveBy(const Offset(60, -200));
    await bottom.up();
    expect((camera.target - target).length, greaterThan(.01));
    final beforePinch = camera.target.clone();
    final direction = (camera.position - camera.target).normalized();
    final distance = (camera.position - camera.target).length;
    final a = await tester.startGesture(const Offset(500, 250), pointer: 1);
    final b = await tester.startGesture(const Offset(500, 450), pointer: 2);
    await a.moveBy(const Offset(40, -30));
    await b.moveBy(const Offset(40, 30));
    await a.up();
    await b.up();
    expect(camera.target, beforePinch);
    expect(
      (camera.position - camera.target).normalized().dot(direction),
      closeTo(1, 1e-6),
    );
    expect((camera.position - camera.target).length, lessThan(distance));
    await tester.pumpWidget(const SizedBox());
  });

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
        if (size.shortestSide >= 600) {
          expect(
            await scenePixel(),
            colorBefore,
            reason: 'Opening devtools must not dim the scene',
          );
        }
        final panel = find.byKey(const ValueKey('protoplane-devtools-panel'));
        var rect = tester.getRect(panel);
        expect(rect.left, lessThan(30));
        if (size.shortestSide < 600) {
          expect(rect.width, size.width - 24);
        } else {
          expect(rect.right, lessThan(size.width * .6));
        }
        expect(
          rect.top,
          greaterThan(tester.getRect(find.byTooltip('Back')).bottom),
        );
        await tester.ensureVisible(find.text('Lighting'));
        await tester.tap(find.text('Lighting'));
        await tester.pumpAndSettle();
        final before = camera.target.clone();
        Offset point() => Offset(
          size.shortestSide < 600
              ? size.width - 4
              : (tester.getRect(panel).right + size.width - 80) / 2,
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
        expect(rect.bottom, lessThan(size.height));
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
}
