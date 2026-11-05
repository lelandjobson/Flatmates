import 'package:flatmates/protoplane/models.dart';
import 'dart:io';
import 'package:flutter/services.dart';
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
      final feedback = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            feedback.add(call.arguments as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
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
            child: ProtoplaneConceptView(animateFog: false, controller: model),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> capture(String stage) async {
        // Paint the frame scheduled by post-layout safe-zone measurement.
        await tester.pump();
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
      model.enter('ground-starter-paperWhite-0-0');
      await tester.pumpAndSettle();
      final camera = tester
          .widget<SceneView>(find.byType(SceneView).first)
          .scene
          .camera!;
      Offset node(int n) => camera.projectToScreen(
        model.activePlane!.point(
          lattice('test', rectangle(1, 1)).nodes[n],
          .008,
        ),
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
      expect(model.harvestPending, isFalse);
      expect(model.drawingReady, isTrue);
      expect(feedback, isEmpty);
      await cancelled.cancel();
      await tester.pumpAndSettle();
      expect(model.toJson(), initial);
      final drag = await cut();
      expect(model.harvestPending, isFalse);
      expect(model.drawingReady, isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(model.toJson(), initial);
      expect(feedback, isEmpty);
      await drag.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(model.harvestPending, isFalse);
      expect(feedback, ['HapticFeedbackType.mediumImpact']);
      expect(model.objects, isEmpty);
      expect(
        model
            .landscape
            .terrain
            .tiles['ground-starter-paperWhite-0-0']!
            .sheet
            .cuts,
        isNotEmpty,
      );
      expect(find.byKey(const ValueKey('harvest-yield')), findsOneWidget);
      await capture('cut');
      await tester.pumpAndSettle();
      model.selectTool(CraftTool.place);
      model.selectPaper(PaperMaterial.paperWhite);
      final build = await cut();
      await build.up();
      await tester.pumpAndSettle();
      expect(model.objects, hasLength(1));
      expect(feedback, [
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.lightImpact',
      ]);
      await capture('built');
      final object = model.objects.values.single;
      model.enter(object.planeId, editObject: object.id);
      model.setDepth(.1);
      expect(model.applyEdit(), isTrue);
      model.leave();
      await tester.pumpAndSettle();
      await capture('pattern-3d');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
