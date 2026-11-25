import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:flatmates/protoplane/drawing_graph.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/geometry.dart';
import 'package:flatmates/protoplane/pencil.dart';

CraftPlane frame() => CraftPlane(
  id: 'test',
  origin: Vector3.zero(),
  u: Vector3(1, 0, 0),
  v: Vector3(0, 0, -1),
  region: rectangle(4, 4),
  grids: const [],
);
List<PencilSegment> outline(Region r) => [
  for (final (a, b) in edges(r.outer)) PencilSegment(a, b),
];
void main() {
  test(
    'rectangle has four erasable sides despite grid pips and separate strokes',
    () {
      final g = DrawingGraph('test', DrawingImplement.pencil, frame(), [
        const PencilSegment(Offset(0, 0), Offset(.5, 0)),
        const PencilSegment(Offset(.5, 0), Offset(1, 0)),
        ...outline(rectangle(1, 1)).skip(1),
      ]);
      expect(g.edges.length, 4);
      expect(g.faces.length, 1);
      expect(g.faces.single.region.area, 1);
      final hits = g.intersections(const Offset(.5, -.2), const Offset(.5, .2));
      expect(hits.length, 1);
      g.replace(
        g.edges.where((e) => !hits.contains(drawingEdgeKey(e))).toList(),
      );
      expect(g.faces, isEmpty);
      expect(g.edges.length, 3);
    },
  );
  test('crossings form atomic faces and erasure merges neighbors', () {
    final g = DrawingGraph('test', DrawingImplement.pen, frame(), [
      ...outline(rectangle(2, 2)),
      const PencilSegment(Offset(1, 0), Offset(1, 2)),
      const PencilSegment(Offset(0, 1), Offset(2, 1)),
    ]);
    expect(g.faces.length, 4);
    expect(g.faces.every((f) => (f.region.area - 1).abs() < 1e-6), isTrue);
    final hits = g.intersections(const Offset(.8, .5), const Offset(1.2, .5));
    expect(hits.length, 1);
    g.replace(g.edges.where((e) => !hits.contains(drawingEdgeKey(e))).toList());
    expect(g.faces.length, 3);
  });
  test(
    'nested disconnected loops preserve annular faces and duplicates do not multiply edges',
    () {
      final lines = [
        ...outline(rectangle(3, 3)),
        ...outline(rectangle(1, 1, origin: const Offset(1, 1))),
      ];
      final g = DrawingGraph('test', DrawingImplement.marker, frame(), [
        ...lines,
        ...lines,
      ]);
      expect(g.edges.length, 8);
      expect(g.faces.length, 2);
      expect(g.faces.map((f) => f.region.area).toList()..sort(), [1, 8]);
      expect(
        g.faces.firstWhere((f) => f.region.area > 1).region.holes.length,
        1,
      );
    },
  );
  test('grid clips holes and rotated axes remain orthogonal', () {
    final p = CraftPlane(
      id: 'test',
      origin: Vector3.zero(),
      u: Vector3(1, 0, 0),
      v: Vector3(0, 0, -1),
      region: Region(rectangle(2, 2).outer, [
        rectangle(.5, .5, origin: const Offset(.75, .75)).outer,
      ]),
      grids: const [],
    );
    final surface = DrawingSurface('test', p, []);
    for (final implement in DrawingImplement.values.where(
      (i) => i != DrawingImplement.eraser,
    )) {
      final grid = surface.grid(implement);
      for (final edge in grid.edges) {
        final d = implement.toLattice(grid.nodes[edge.b] - grid.nodes[edge.a]);
        expect(d.dx.abs() < 1e-6 || d.dy.abs() < 1e-6, isTrue);
        expect(
          p.region.contains((grid.nodes[edge.a] + grid.nodes[edge.b]) / 2),
          isTrue,
        );
      }
    }
  });
  test(
    'eraser includes endpoints and collinear overlap but preview is not cumulative',
    () {
      final g = DrawingGraph(
        'test',
        DrawingImplement.pencil,
        frame(),
        outline(rectangle(1, 1)),
      );
      expect(
        g.intersections(const Offset(-1, 0), const Offset(0, 0)).length,
        2,
      );
      expect(
        g.intersections(const Offset(.2, 0), const Offset(.8, 0)).length,
        1,
      );
      expect(
        g.intersections(const Offset(.2, .2), const Offset(.8, .2)),
        isEmpty,
      );
      expect(g.edges.length, 4);
    },
  );
}
