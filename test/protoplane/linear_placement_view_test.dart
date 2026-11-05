import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'linear_placement_test.dart' show world;

void main() {
  testWidgets(
    'wall preview is upright, created surface offers cutting and pencil',
    (tester) async {
      const size = Size(900, 700);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      final c = world()..leave();
      addTearDown(() {
        c.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: const ValueKey('capture'),
            child: ProtoplaneConceptView(controller: c, animateFog: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final ground = c.planes.values.firstWhere(
        (p) => c.isLandscapePaper(p.id) && p.origin.x == 0 && p.origin.z == 0,
      );
      c.enter(ground.id);
      c.selectTool(CraftTool.place);
      await tester.pumpAndSettle();
      final scene = tester
          .widget<SceneView>(find.byType(SceneView).first)
          .scene;
      Offset point(Offset p) =>
          scene.camera!.projectToScreen(c.activePlane!.point(p, .008), size)!;
      final drag = await tester.startGesture(
        point(const Offset(0, .5)),
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveTo(point(const Offset(1, .5)));
      await tester.pump();
      final mesh = scene.meshes.firstWhere(
        (m) => m.id.startsWith('preview-linear'),
      );
      final ys = mesh.geometry.vertices.map((v) => v.y).toList()..sort();
      expect(ys.last - ys.first, greaterThan(.95));
      await drag.up();
      await tester.pumpAndSettle();
      expect(c.objects, hasLength(1));
      final wall = c.objects.values.single;
      c.enter('surface-${wall.id}');
      await tester.pumpAndSettle();
      expect(find.text('Height 1.00'), findsOneWidget);
      await tester.tap(find.byTooltip('Increase extent'));
      await tester.pumpAndSettle();
      expect(find.text('Height 1.25'), findsOneWidget);
      await tester.tap(find.byTooltip('Scissors'));
      await tester.pumpAndSettle();
      expect(c.editId, wall.id);
      await tester.tap(find.byTooltip('Pencil'));
      await tester.pumpAndSettle();
      expect(c.editId, isNull);
      expect(c.paperSurface, isTrue);
      expect(c.activePlaneId, 'surface-${wall.id}');
      c.balances[PaperMaterial.graphite] = 128;
      final pencil = await tester.startGesture(point(const Offset(0, .25)));
      await pencil.moveTo(point(const Offset(1, .25)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 701));
      await pencil.up();
      await tester.pumpAndSettle();
      expect(c.marksOn(c.activePlane!), isNotEmpty);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('capture')),
        );
        final image = await boundary.toImage();
        await File('/tmp/flatmates-linear-wall.png').writeAsBytes(
          (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List(),
        );
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final kind in [
    PointerDeviceKind.mouse,
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
  ]) {
    testWidgets(
      '$kind shake discards whole preview and suppresses release commit',
      (tester) async {
        const size = Size(900, 700);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        final c = world();
        final source = c.activePlaneId!;
        c.leave();
        addTearDown(() {
          c.dispose();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        await tester.pumpWidget(
          MaterialApp(
            home: ProtoplaneConceptView(controller: c, animateFog: false),
          ),
        );
        await tester.pumpAndSettle();
        c.enter(source);
        c.selectTool(CraftTool.place);
        await tester.pumpAndSettle();
        final camera = tester
            .widget<SceneView>(find.byType(SceneView).first)
            .scene
            .camera!;
        Offset point(Offset p) =>
            camera.projectToScreen(c.activePlane!.point(p, .008), size)!;
        final before = c.balances[PaperMaterial.paperWhite];
        final drag = await tester.startGesture(
          point(const Offset(0, .5)),
          kind: kind,
        );
        final at = point(const Offset(1, .5));
        await drag.moveTo(at);
        await tester.pump();
        for (final x in [16.0, -16.0, 16.0, -16.0]) {
          await drag.moveTo(at + Offset(x, 0));
          await tester.pump(const Duration(milliseconds: 80));
        }
        expect(c.draft.path, isEmpty);
        await drag.moveTo(point(const Offset(1, 1)));
        await drag.up();
        await tester.pumpAndSettle();
        expect(c.objects, isEmpty);
        expect(c.balances[PaperMaterial.paperWhite], before);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
