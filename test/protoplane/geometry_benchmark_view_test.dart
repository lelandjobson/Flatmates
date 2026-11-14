import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';
import 'construction_fixture.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('benchmark batches and full-width mobile dock at $size', (
      tester,
    ) async {
      final model = constructionWorld();
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
          home: ProtoplaneConceptView(controller: model, animateFog: false),
        ),
      );
      await tester.pumpAndSettle();
      final before = jsonEncode(model.toJson());
      await tester.tap(find.text('devtools'));
      await tester.pumpAndSettle();
      final dock = tester.getRect(
        find.byKey(const ValueKey('docked-devtools')),
      );
      expect(dock.width, size.width - 24);
      await tester.ensureVisible(find.text('Benchmark'));
      await tester.tap(find.text('Benchmark'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add 100 walls'));
      await tester.pumpAndSettle();
      final scene = tester
          .widget<SceneView>(find.byType(SceneView).first)
          .scene;
      expect(scene.meshes.where((m) => m.name == 'Benchmark wall').length, 100);
      await tester.ensureVisible(find.text('Add 100 volumes'));
      await tester.tap(find.text('Add 100 volumes'));
      await tester.pumpAndSettle();
      expect(
        scene.meshes.where((m) => m.name == 'Benchmark volume').length,
        100,
      );
      await tester.ensureVisible(find.text('Expand map ×2'));
      await tester.tap(find.text('Expand map ×2'));
      await tester.pumpAndSettle();
      expect(
        scene
            .meshById('benchmark-ground')!
            .geometry
            .vertices
            .map((p) => p.x)
            .reduce((a, b) => a > b ? a : b),
        32,
      );
      await tester.ensureVisible(find.text('Reset benchmark'));
      await tester.tap(find.text('Reset benchmark'));
      await tester.pumpAndSettle();
      expect(scene.meshes.where((m) => m.id.startsWith('benchmark-')), isEmpty);
      expect(jsonEncode(model.toJson()), before);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
