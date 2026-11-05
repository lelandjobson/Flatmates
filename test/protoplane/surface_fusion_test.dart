import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/geometry.dart';
import 'construction_fixture.dart';
import 'protoplane_test.dart' as fixtures;

void main() {
  testWidgets('joined floors render one continuous shaded mesh', (
    tester,
  ) async {
    final model = constructionWorld();
    addTearDown(model.dispose);
    final a = fixtures.floor(model);
    final b = fixtures.floor(model, tile: 'ground-5-4');
    model.leave();
    await tester.pumpWidget(
      MaterialApp(
        home: ProtoplaneConceptView(animateFog: false, controller: model),
      ),
    );
    await tester.pumpAndSettle();
    final scene = tester.widget<SceneView>(find.byType(SceneView).first).scene;
    expect(scene.meshes.where((m) => m.id == b.id), isEmpty);
    final mesh = scene.meshes.singleWhere((m) => m.id == a.id);
    expect(mesh.geometry.vertices.any((p) => p.x > 1.9), isTrue);
    expect(mesh.edgeShades, isNotEmpty);
    model.enter('surface-${a.id}');
    await tester.pumpAndSettle();
    expect(model.activePlane!.region.area, closeTo(2, 1e-6));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  test(
    'fused navigation has only outer exits and derives combined walls and upper plane',
    () {
      final model = constructionWorld();
      addTearDown(model.dispose);
      final a = fixtures.floor(model);
      final b = fixtures.floor(model, tile: 'ground-5-4');
      final root = 'surface-${a.id}', alias = 'surface-${b.id}';
      var graph = model.navigationGraph;
      expect(graph.neighbors.containsKey(alias), isFalse);
      expect(graph.neighbors[root]!.any((e) => e.planeId == alias), isFalse);
      final walls = model.planes.values
          .where(
            (p) =>
                p.wallCandidate && !model.surfaceFusion.retired.contains(p.id),
          )
          .toList();
      expect(walls, hasLength(4));
      expect(walls.map((p) => p.region.bounds.width).toList()..sort(), [
        1,
        1,
        2,
        2,
      ]);
      expect(
        graph.neighbors[root]!.map((e) => e.planeId),
        containsAll(walls.map((p) => p.id)),
      );
      final wall = walls.first;
      model.enter(wall.id);
      fixtures.draw(model, [0, 1, 2, 5, 8, 7, 6, 3, 0]);
      expect(model.create(), isTrue, reason: model.error);
      expect(model.planes['upper-${a.id}']!.region.area, closeTo(2, 1e-6));
      graph = model.navigationGraph;
      expect(
        graph.neighbors['surface-${model.objects.values.last.id}']!.map(
          (e) => e.planeId,
        ),
        contains('upper-${a.id}'),
      );
      model.undo();
      expect(model.planes.containsKey('upper-${a.id}'), isFalse);
      model.redo();
      model.load(model.toJson());
      expect(model.planes['upper-${a.id}']!.region.area, closeTo(2, 1e-6));
      expect(model.navigationGraph.neighbors.containsKey(alias), isFalse);
    },
  );
  test(
    'neighboring floors share a surface across tiles with undo and load',
    () {
      final model = constructionWorld();
      addTearDown(model.dispose);
      final a = fixtures.floor(model);
      final firstGrid = model.planes['surface-${a.id}']!.grids.first.nodes
          .toList();
      final b = fixtures.floor(model, tile: 'ground-5-4');
      final id = 'surface-${a.id}';
      expect(model.planes[id]!.region.area, closeTo(2, 1e-6));
      expect(model.objects.length, 2);
      expect(model.planes[id]!.supports.toSet(), {a.id, b.id});
      expect(
        model.planes[id]!.grids.first.nodes.take(firstGrid.length),
        firstGrid,
      );
      expect(model.planes[id]!.grids.first.nodes.any((p) => p.dx > 1), isTrue);
      final grid = model.planes[id]!.grids.first;
      final reached = <int>{0};
      var changed = true;
      while (changed) {
        changed = false;
        for (final e in grid.edges) {
          if (reached.contains(e.a) && reached.add(e.b)) changed = true;
          if (reached.contains(e.b) && reached.add(e.a)) changed = true;
        }
      }
      expect(reached.any((i) => grid.nodes[i].dx > 1), isTrue);
      model.enter('surface-${b.id}');
      expect(model.surfaceFusion.canonical[model.activePlaneId], id);
      model.undo();
      expect(model.planes[id]!.region.area, closeTo(1, 1e-6));
      model.redo();
      expect(model.planes[id]!.region.area, closeTo(2, 1e-6));
      final json = model.toJson();
      model.load(json);
      model.enter('surface-${b.id}');
      expect(model.surfaceFusion.canonical[model.activePlaneId], id);
      expect(model.activePlane!.region.area, closeTo(2, 1e-6));
    },
  );
  test('different materials and corner contacts stay separate', () {
    final model = constructionWorld();
    addTearDown(model.dispose);
    final a = fixtures.floor(model);
    model.selectPaper(PaperMaterial.blue);
    final b = fixtures.floor(model, tile: 'ground-5-4');
    expect(model.surfaceFusion.canonical, isEmpty);
    model.selectPaper(a.material);
    fixtures.floor(model, tile: 'ground-5-5');
    expect(model.surfaceFusion.canonical, isEmpty);
    expect(model.planes['surface-${b.id}']!.region.area, 1);
  });
  test('union preserves holes and excludes disjoint pieces', () {
    final a = Region(rectangle(1, 1).outer, [
      rectangle(.2, .2, origin: const Offset(.2, .2)).outer,
    ]);
    final union = a.union(rectangle(1, 1, origin: const Offset(1, 0)));
    expect(union, hasLength(1));
    expect(union.single.valid, isTrue);
    expect(union.single.holes, hasLength(1));
    expect(union.single.area, closeTo(1.96, 1e-6));
    expect(a.union(rectangle(1, 1, origin: const Offset(2, 0))), hasLength(2));
  });
}
