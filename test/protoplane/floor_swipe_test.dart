import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:flatmates/protoplane/geometry.dart';
import 'package:flatmates/protoplane/layered_terrain.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/plane_navigation.dart';

void main() {
  TerrainSheet sheet(
    String id,
    double x,
    double y,
    double height, {
    Region? footprint,
  }) => TerrainSheet(
    id,
    'island',
    PaperMaterial.paperWhite,
    footprint ?? rectangle(1, 1, origin: Offset(x, y)),
    height,
    .01,
  );
  PlaneNavigationGraph graph(LayeredTerrain terrain) => PlaneNavigationGraph(
    {for (final t in terrain.tiles.values) t.id: t.plane()},
    {},
    terrain: terrain,
    surfaceRegions: (p) => terrain.exposed(p.id),
  );
  String? go(PlaneNavigationGraph g, String id, Offset direction) =>
      g.inDirection(
        id,
        direction,
        const Offset(.5, .5),
        (p) => Offset(p.x, -p.z),
      );

  test(
    'landscape swipes step one column up or down regardless of elevation',
    () {
      final terrain = LayeredTerrain([
        sheet('start', 0, 0, 0),
        sheet('east', 1, 0, -6),
        sheet('south', 0, 1, 8),
        sheet('far', 2, 0, 0),
        sheet('diagonal', 1, 1, 0),
      ]);
      final g = graph(terrain), source = 'ground-start-0-0';
      expect(go(g, source, const Offset(1, 0)), 'ground-east-1-0');
      expect(go(g, source, const Offset(0, 1)), 'ground-south-0-1');
      expect(g.swipeNeighbors[source]!.map((e) => e.planeId).toSet(), {
        'ground-east-1-0',
        'ground-south-0-1',
      });
      expect(
        g.neighbors[source],
        isNull,
        reason: 'The 3D topology is unchanged',
      );
      final reverse = g.inDirection(
        'ground-east-1-0',
        const Offset(-1, 0),
        const Offset(1.5, .5),
        (p) => Offset(p.x, -p.z),
      );
      expect(reverse, source);
    },
  );

  test('no empty or depleted destination, diagonal jump, or gap skipping', () {
    final terrain = LayeredTerrain([
      sheet('start', 0, 0, 0),
      sheet('empty', 1, 0, 4),
      sheet('far', 2, 0, 0),
      sheet('diagonal', 1, 1, 0),
    ]);
    terrain.deplete('ground-empty-1-0', rectangle(1, 1));
    final g = graph(terrain);
    expect(go(g, 'ground-start-0-0', const Offset(1, 0)), isNull);
    expect(g.swipeNeighbors['ground-start-0-0'] ?? [], isEmpty);
  });

  test(
    'partial interior geometry is reachable; highest exposed layer wins',
    () {
      final terrain = LayeredTerrain([
        sheet('start', 0, 0, 0),
        sheet('lower', 1, 0, -3),
        sheet(
          'scrap',
          1,
          0,
          2,
          footprint: rectangle(.2, .2, origin: const Offset(1.4, .4)),
        ),
      ]);
      expect(
        go(graph(terrain), 'ground-start-0-0', const Offset(1, 0)),
        'ground-scrap-1-0',
      );
      terrain.deplete('ground-scrap-1-0', rectangle(1, 1));
      expect(
        go(graph(terrain), 'ground-start-0-0', const Offset(1, 0)),
        'ground-lower-1-0',
      );
      terrain.deplete('ground-lower-1-0', rectangle(1, 1));
      expect(
        go(graph(terrain), 'ground-start-0-0', const Offset(1, 0)),
        isNull,
      );
    },
  );

  test(
    'floor swipes filter walls and slopes while wall exits remain available',
    () {
      CraftPlane floor(String id, double x, {double height = 0}) => CraftPlane(
        id: id,
        origin: Vector3(x, height, 0),
        u: Vector3(1, 0, 0),
        v: Vector3(0, 0, -1),
        region: rectangle(1, 1),
        grids: [],
      );
      final a = floor('a', 0),
          b = floor('b', 1),
          upper = floor('upper', 1, height: 3);
      final wall = CraftPlane(
        id: 'wall',
        origin: Vector3(1, 0, 0),
        u: Vector3(0, 0, -1),
        v: Vector3(0, 1, 0),
        region: rectangle(1, 1),
        grids: [],
      );
      final g = PlaneNavigationGraph({
        for (final p in [a, b, wall, upper]) p.id: p,
      }, {});
      expect(g.neighbors['a']!.map((e) => e.planeId), contains('wall'));
      expect(go(g, 'a', const Offset(1, 0)), 'b');
      expect(g.swipeNeighbors['a']!.map((e) => e.planeId).toSet(), {'b'});
      expect(g.swipeNeighbors['wall']!.map((e) => e.planeId), contains('a'));
      final wallOnly = PlaneNavigationGraph({'a': a, 'wall': wall}, {});
      expect(go(wallOnly, 'a', const Offset(1, 0)), isNull);
      final slope = CraftPlane(
        id: 'slope',
        origin: Vector3(1, 0, 0),
        u: Vector3(.5, .8660254, 0),
        v: Vector3(0, 0, -1),
        region: rectangle(1, 1),
        grids: [],
      );
      final sloped = PlaneNavigationGraph({'a': a, 'slope': slope}, {});
      expect(sloped.neighbors['a'], isNotEmpty);
      expect(go(sloped, 'a', const Offset(1, 0)), isNull);
    },
  );
}
