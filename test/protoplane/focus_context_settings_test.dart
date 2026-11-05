import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/dev_settings.dart';
import 'package:flatmates/protoplane/focus_view.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';
import 'construction_fixture.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/models.dart';
import 'layered_terrain_test.dart' show centerId;

void main() {
  test('context settings persist, migrate and reject invalid ranges', () {
    final s = ProtoplaneSettings();
    expect(s.focusContextTiles, 2);
    expect(s.focusContextOpacity, .35);
    s.focusContextTiles = 3;
    s.focusContextOpacity = .6;
    final loaded = ProtoplaneSettings()..load(s.toJson());
    expect(loaded.focusContextTiles, 3);
    expect(loaded.focusContextOpacity, .6);
    final old = s.toJson()
      ..remove('focusContextTiles')
      ..remove('focusContextOpacity');
    loaded.load(old);
    expect(loaded.focusContextTiles, 2);
    expect(loaded.focusContextOpacity, .35);
    expect(
      () => loaded.load(s.toJson()..['focusContextTiles'] = -1),
      throwsFormatException,
    );
    expect(
      () => loaded.load(s.toJson()..['focusContextOpacity'] = 1.1),
      throwsFormatException,
    );
  });
  test('context radius includes diagonal neighbors but excludes next ring', () {
    final c = constructionWorld();
    addTearDown(c.dispose);
    final p = c.planes['ground-starter-paperWhite-0-0']!;
    bool visible(String id, int tiles) => adjacentFocusContext(
      p,
      c.planes[id]!,
      c.objects,
      c.planes,
      tiles: tiles,
    );
    expect(visible('ground-starter-paperWhite-1-1', 1), isTrue);
    expect(visible('ground-starter-paperWhite-2-0', 1), isFalse);
    expect(visible('ground-starter-paperWhite-2-0', 2), isTrue);
    expect(visible('ground-starter-paperWhite-1-0', 0), isFalse);
  });
  testWidgets(
    'focused terrain includes adjacent exposed cork at context opacity',
    (tester) async {
      final c = ProtoplaneController();
      addTearDown(c.dispose);
      final terrain = c.landscape.terrain;
      String tile(PaperMaterial material, int x) => terrain.tiles.values
          .firstWhere(
            (t) =>
                t.sheet.island == 'starter' &&
                t.x == x &&
                t.y == 0 &&
                t.sheet.material == material,
          )
          .id;
      for (final material in [
        PaperMaterial.paperWhite,
        PaperMaterial.graphite,
      ]) {
        c.landscape.deplete(tile(material, 1), rectangle(1, 1));
      }
      final cork = tile(PaperMaterial.cork, 1);
      final white = centerId(c, PaperMaterial.paperWhite);
      expect(
        adjacentFocusContext(
          c.planes[white]!,
          c.planes[cork]!,
          c.objects,
          c.planes,
          terrain: terrain,
        ),
        isTrue,
      );
      expect(
        adjacentFocusContext(
          c.planes[white]!,
          c.planes[cork]!,
          c.objects,
          c.planes,
          terrain: terrain,
          tiles: 0,
        ),
        isFalse,
      );
      expect(
        adjacentFocusContext(
          c.planes[cork]!,
          c.planes[white]!,
          c.objects,
          c.planes,
          terrain: terrain,
        ),
        isTrue,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ProtoplaneConceptView(
            animateFog: false,
            controller: c,
            entryFocusLevel: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();
      c.enter(white);
      await tester.pumpAndSettle();
      final scene = tester
          .widget<SceneView>(find.byType(SceneView).first)
          .scene;
      expect(
        scene.meshes.firstWhere((m) => m.id == cork).material.opacity,
        closeTo(.35, 1e-6),
      );
      c.leave();
      await tester.pumpAndSettle();
      expect(
        scene.meshes.firstWhere((m) => m.id == cork).material.opacity,
        closeTo(1, 1e-6),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'neighbor remains visible and fades continuously during traversal',
    (tester) async {
      final c = ProtoplaneController();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ProtoplaneConceptView(
            animateFog: false,
            controller: c,
            entryFocusLevel: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();
      c.enter('ground-starter-paperWhite-0-0');
      await tester.pumpAndSettle();
      final scene = tester
          .widget<SceneView>(find.byType(SceneView).first)
          .scene;
      double opacity(String id) =>
          scene.meshes.firstWhere((m) => m.id == id).material.opacity;
      expect(opacity('ground-starter-paperWhite-1-0'), closeTo(.35, 1e-6));
      final border = c.activePlane!.region.bounds.inflate(1);
      for (final local in [
        border.topLeft,
        border.topRight,
        border.bottomLeft,
        border.bottomRight,
      ]) {
        final point = scene.camera!.projectToScreen(
          c.activePlane!.point(local),
          const Size(800, 600),
        )!;
        expect(point.dx, inInclusiveRange(0, 800));
        expect(point.dy, inInclusiveRange(0, 600));
      }
      final start = scene.camera!.position.clone();
      c.enter('ground-starter-paperWhite-1-0');
      expect(opacity('ground-starter-paperWhite-1-0'), closeTo(.35, 1e-6));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 325));
      expect(opacity('ground-starter-paperWhite-1-0'), greaterThan(.35));
      expect(opacity('ground-starter-paperWhite-1-0'), lessThan(1));
      expect(scene.camera!.position.distanceTo(start), greaterThan(.01));
      await tester.pumpAndSettle();
      expect(opacity('ground-starter-paperWhite-1-0'), closeTo(1, 1e-6));
      expect(opacity('ground-starter-paperWhite-0-0'), closeTo(.35, 1e-6));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
