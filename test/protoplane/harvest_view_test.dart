import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('landscape harvesting, cancellation and building at $size', (
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
          theme: ThemeData.dark(),
          home: RepaintBoundary(
            key: const ValueKey('harvest-capture'),
            child: ProtoplaneConceptView(controller: model),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> capture(String stage) async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('harvest-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '/tmp/harvest-${size.width.toInt()}-$stage.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      await capture('world');
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
      Future<TestGesture> cut() async {
        final drag = await tester.startGesture(
          node(0),
          kind: size.width < size.height
              ? PointerDeviceKind.touch
              : PointerDeviceKind.mouse,
        );
        for (final n in [1, 4, 3, 0]) {
          await drag.moveTo(node(n));
          await tester.pump(const Duration(milliseconds: 40));
        }
        return drag;
      }

      final initial = model.toJson();
      final cancelled = await cut();
      expect(model.harvestPending, isTrue);
      await cancelled.cancel();
      await tester.pumpAndSettle();
      expect(model.toJson(), initial);
      final drag = await cut();
      expect(model.harvestPending, isTrue);
      await drag.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(model.harvestPending, isFalse);
      expect(model.objects, isEmpty);
      expect(model.landscape.depleted('ground-4-4'), hasLength(1));
      expect(find.byKey(const ValueKey('harvest-yield')), findsOneWidget);
      await capture('cut');
      await tester.pumpAndSettle();
      final build = await cut();
      await build.up();
      await tester.pumpAndSettle();
      expect(model.objects, hasLength(1));
      await capture('built');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
