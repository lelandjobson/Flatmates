import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'bedroom_fixture.dart';

void main() {
  testWidgets(
    'resident is visible, room chip opens furnishing and comfort fits mobile',
    (tester) async {
      final f = BedroomFixture();
      f.c.leave();
      tester.view.physicalSize = const Size(900, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        f.c.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: RepaintBoundary(
            key: const ValueKey('bedroom-capture'),
            child: ProtoplaneConceptView(controller: f.c),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 flatmate'), findsOneWidget);
      final scene = tester
          .widget<SceneView>(find.byType(SceneView).first)
          .scene;
      expect(
        scene.meshes.where((m) => m.id.startsWith('friend_')),
        hasLength(1),
      );
      await tester.tap(find.byType(ActionChip));
      await tester.pumpAndSettle();
      expect(find.textContaining('Comfort 40/100'), findsOneWidget);
      await tester.tap(find.byTooltip('3D'));
      await tester.pumpAndSettle();
      expect(
        scene.meshes.where((m) => m.id.startsWith('friend_')),
        hasLength(1),
      );
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('bedroom-capture')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '/tmp/bedroom-preview.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Comfort 40/100'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
