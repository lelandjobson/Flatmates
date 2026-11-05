import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;
import 'package:flatmates/protoplane/dev_settings.dart';
import 'package:flatmates/protoplane/focus_context.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/rendering/world_crop_box.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';
import 'construction_fixture.dart';
import 'protoplane_test.dart' show floor, draw;
import 'linear_placement_test.dart' as linear;
import 'package:flatmates/protoplane/focus_view.dart';

void main() {
  CraftPlane plane(double angle) => CraftPlane(
    id: 'test',
    origin: Vector3(2, 3, 4),
    u: Vector3(1, 0, 0),
    v: Vector3(0, math.sin(angle), math.cos(angle)),
    region: rectangle(2, 1),
    grids: [],
  );

  test(
    'orientation uses inclination, including slopes and inverted floors',
    () {
      expect(isFloorOrientation(plane(0)), isTrue);
      expect(isFloorOrientation(plane(math.pi)), isTrue);
      expect(isFloorOrientation(plane(math.pi / 18)), isTrue);
      expect(isFloorOrientation(plane(math.pi / 6)), isFalse);
      expect(isFloorOrientation(plane(math.pi / 2)), isFalse);
      expect(sameFocusOrientation(plane(0), plane(math.pi / 2)), isFalse);
      expect(sameFocusOrientation(plane(0), plane(0), upright: true), isFalse);
    },
  );

  test(
    'crop surrounds the actual world footprint and vertical wall extent',
    () {
      final horizontal = focusCropBox(
        plane(0),
        xPadding: 1,
        zPadding: 2,
        above: .8,
        below: .2,
      );
      expect(horizontal.min, Vector3(1, 2.8, 2));
      expect(horizontal.max, Vector3(5, 3.8, 7));
      final vertical = focusCropBox(
        plane(math.pi / 2),
        xPadding: 1,
        zPadding: 2,
        above: .8,
        below: .2,
      );
      expect(vertical.min.y, closeTo(2.8, 1e-9));
      expect(vertical.max.y, closeTo(4.8, 1e-9));
    },
  );

  test(
    'six clipping planes retain boundary contact and trim crossing faces',
    () {
      final box = WorldCropBox(Vector3.zero(), Vector3.all(1));
      for (var axis = 0; axis < 3; axis++) {
        final next = (axis + 1) % 3;
        Vector3 point(double a, double b) {
          final p = Vector3.all(.5);
          p[axis] = a;
          p[next] = b;
          return p;
        }

        final result = box.clip([
          point(-1, -1),
          point(2, -1),
          point(2, 2),
          point(-1, 2),
        ]);
        expect(result, hasLength(4));
        expect(result.every(box.contains), isTrue);
        expect(result.map((p) => p[axis]).toSet(), {0.0, 1.0});
        expect(box.clip([point(2, 0), point(3, 0), point(3, 1)]), isEmpty);
        final boundary = [point(0, 0), point(1, 0), point(1, 1)];
        expect(box.clip(boundary), hasLength(3));
      }
      expect(box.clip([]), isEmpty);
    },
  );

  test('context controls round trip, migrate, and validate', () {
    final s = ProtoplaneSettings()
      ..focusCropEnabled = false
      ..hideOrthogonalContext = true
      ..focusCropX = .5
      ..focusCropZ = 3
      ..focusCropAbove = 2
      ..focusCropBelow = .1;
    final loaded = ProtoplaneSettings()..load(s.toJson());
    expect(loaded.toJson(), s.toJson());
    final old = s.toJson()
      ..removeWhere(
        (k, v) => k.startsWith('focusCrop') || k == 'hideOrthogonalContext',
      );
    loaded.load(old);
    expect(loaded.focusCropEnabled, isTrue);
    expect(loaded.hideOrthogonalContext, isFalse);
    expect(loaded.focusCropAbove, 1.25);
    for (final key in [
      'focusCropX',
      'focusCropZ',
      'focusCropAbove',
      'focusCropBelow',
    ]) {
      expect(() => loaded.load(s.toJson()..[key] = -1), throwsFormatException);
      expect(
        () => loaded.load(s.toJson()..[key] = double.nan),
        throwsFormatException,
      );
    }
    expect(
      () => loaded.load(s.toJson()..['hideOrthogonalContext'] = 1),
      throwsFormatException,
    );
  });

  testWidgets('walls drawn directly on landscape share its context level', (
    tester,
  ) async {
    final c = linear.world();
    addTearDown(c.dispose);
    final ground = c.activePlane!;
    linear.draw(c, const [Offset(0, .5), Offset(1, .5)]);
    expect(c.commitDrawing(), isNotNull);
    final wall = c.objects.values.single;
    final wallPlane = c.planes[wall.planeId]!;
    expect(
      adjacentFocusContext(ground, wallPlane, c.objects, c.planes),
      isTrue,
    );
    expect(
      adjacentFocusContext(wallPlane, ground, c.objects, c.planes),
      isTrue,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ProtoplaneConceptView(controller: c, animateFog: false),
      ),
    );
    await tester.pumpAndSettle();
    c.enter(ground.id);
    await tester.pumpAndSettle();
    final scene = tester.widget<SceneView>(find.byType(SceneView).first).scene;
    expect(
      scene.meshes.firstWhere((m) => m.id == wall.id).material.opacity,
      greaterThan(0),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'anchored walls stay visible; live controls filter both orientations without editing world',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      final c = constructionWorld();
      addTearDown(() {
        c.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final f = floor(c);
      c.enter('wall-${f.id}-0');
      draw(c, [0, 1, 2, 5, 8, 7, 6, 3, 0]);
      expect(c.create(), isTrue, reason: c.error);
      final wall = c.objects.values.last;
      c.leave();
      await tester.pumpWidget(
        MaterialApp(
          home: ProtoplaneConceptView(controller: c, animateFog: false),
        ),
      );
      await tester.pumpAndSettle();
      c.enter('surface-${f.id}');
      await tester.pumpAndSettle();
      final scene = tester
          .widget<SceneView>(find.byType(SceneView).first)
          .scene;
      expect(
        scene.meshes.firstWhere((m) => m.id == wall.id).material.opacity,
        greaterThan(0),
      );
      expect(
        scene.meshes.any((m) => m.id == 'ground-starter-paperWhite-2-0'),
        isTrue,
      );
      final saved = c.toJson();
      await tester.tap(find.text('devtools'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Focus context'));
      await tester.tap(find.text('Focus context'));
      await tester.pumpAndSettle();
      final panel = tester.widget<ProtoplaneDevToolsPanel>(
        find.byType(ProtoplaneDevToolsPanel),
      );
      panel.settings.hideOrthogonalContext = true;
      panel.changed();
      await tester.pumpAndSettle();
      expect(
        scene.meshes
            .where((m) => m.id == wall.id)
            .every((m) => m.material.opacity == 0),
        isTrue,
      );
      panel.settings.hideOrthogonalContext = false;
      panel.settings.focusCropAbove = .2;
      panel.changed();
      await tester.pumpAndSettle();
      final mesh = scene.meshes.firstWhere((m) => m.id == wall.id);
      expect(mesh.material.opacity, greaterThan(0));
      expect(mesh.cropBox, isNotNull);
      final maxY = mesh.cropBox!.max.y;
      expect(mesh.geometry.vertices.any((v) => v.y > maxY), isTrue);
      panel.settings.focusCropEnabled = false;
      panel.changed();
      await tester.pumpAndSettle();
      expect(scene.meshes.firstWhere((m) => m.id == wall.id).cropBox, isNull);
      c.enter('surface-${wall.id}');
      await tester.pumpAndSettle();
      expect(
        scene.meshes.firstWhere((m) => m.id == f.id).material.opacity,
        greaterThan(0),
      );
      panel.settings.hideOrthogonalContext = true;
      panel.changed();
      await tester.pumpAndSettle();
      expect(
        scene.meshes
            .where((m) => m.id == f.id)
            .every((m) => m.material.opacity == 0),
        isTrue,
      );
      c.enter('wall-${f.id}-1');
      await tester.pumpAndSettle();
      expect(
        scene.meshes
            .where((m) => m.id == f.id)
            .every((m) => m.material.opacity == 0),
        isTrue,
        reason:
            'A wall protoplane also hides its perpendicular supporting floor',
      );
      expect(c.toJson(), saved);
      c.leave();
      await tester.pumpAndSettle();
      expect(scene.meshes.firstWhere((m) => m.id == f.id).material.opacity, 1);
      expect(scene.meshes.every((m) => m.cropBox == null), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
