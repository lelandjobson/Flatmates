import 'recipe_fixture.dart';
import 'package:flatmates/protoplane/geometry.dart';
import 'dart:ui';
import 'package:flatmates/protoplane/pencil.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/controller.dart';

/// Construction regressions start after resource collection, with enough paper
/// for their multi-story fixtures. Harvest tests use fresh worlds directly.
ProtoplaneController constructionWorld() {
  final model = ProtoplaneController();
  final plane = model.planes['ground-starter-paperWhite-0-0']!;
  model.landscape.deplete(plane.id, plane.region);
  // A persisted construction lattice, retaining the original half-tile IDs.
  for (final plane in model.planes.values.toList()) {
    final half = lattice(plane.id, plane.region);
    final fine = lattice(plane.id, plane.region, count: 5);
    final nodes = [...half.nodes];
    final remap = <int>[];
    for (final point in fine.nodes) {
      var index = nodes.indexOf(point);
      if (index < 0) {
        index = nodes.length;
        nodes.add(point);
      }
      remap.add(index);
    }
    model.planes[plane.id] = plane.withGrids([
      CraftGrid(
        id: plane.id,
        name: 'Construction',
        nodes: nodes,
        edges: fine.edges.map((e) => GridEdge(remap[e.a], remap[e.b])).toList(),
        recipes: half.recipes,
      ),
    ]);
  }
  for (final color in model.balances.keys) {
    model.balances[color] = 12800;
  }
  model.setImpliedProtoplanes(true);
  model.selectTool(CraftTool.place);
  return model;
}

/// Author test paths by position so drawing-graph indices may change as pencil
/// intersections are added or material is removed.
void drawPoints(ProtoplaneController c, List<Offset> points) {
  if (points.length > 3 && (points.first - points.last).distance < 1e-6) {
    points = simplifyRing(points.sublist(0, points.length - 1));
    points = [...points, points.first];
  }
  if (c.paperSurface) {
    final segments = [
      for (var i = 1; i < points.length; i++)
        PencilSegment(points[i - 1], points[i]),
    ];
    bool available() {
      final g = c.grid!;
      final ids = points
          .map((p) => g.nodes.indexWhere((n) => (n - p).distance < 1e-6))
          .toList();
      return !ids.contains(-1) &&
          [
            for (var i = 1; i < ids.length; i++)
              g.connection(ids[i - 1], ids[i]),
          ].every((e) => e != null);
    }

    if (!available()) {
      if (!c.commitMarks(segments)) {
        throw StateError('Cannot author marks: ${c.error}');
      }
    }
  }
  c.beginGesture();
  for (final p in points) {
    final index = c.grid!.nodes.indexWhere((n) => (n - p).distance < 1e-6);
    if (index < 0 || !c.appendNode(index)) {
      throw StateError('Cannot draw $p: ${c.error}');
    }
  }
  c.finishGesture();
}

List<Offset> recipePoints(ProtoplaneController c, CraftKind kind) {
  final region = c.activePlane!.region;
  final grids = [
    ...floorGrids('fixture', region, 42),
    bedroomGrid('fixture', region),
  ];
  final grid = grids.firstWhere((g) => g.examples.containsKey(kind));
  return grid.trace(grid.examples[kind]!);
}
