import 'package:flatmates/gameplay/flatmates/day_action.dart';
import 'package:flatmates/gameplay/flatmates/day_action_store.dart';
import 'package:flatmates/gameplay/flatmates/day_router.dart';
import 'package:flatmates/gameplay/graph/connection_graph.dart';
import 'package:flatmates/gameplay/paths/path_store.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flatmates/gameplay/walls/wall_edge.dart';
import 'package:flatmates/gameplay/walls/wall_regions.dart';
import 'package:flatmates/gameplay/walls/wall_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final grid = const VolumeGrid(tilesSide: 32, tileSize: 8);
  final router = DayRouter();

  VolumeStore emptyVolumes() => VolumeStore(grid: grid);

  VolumeStore bedroomAt((int, int) tile, {VolumeSide door = VolumeSide.east}) {
    final volumes = emptyVolumes();
    volumes.volumes.add(
      Volume(
        id: 1,
        cells: [
          VolumeCell(
            tx: tile.$1,
            ty: tile.$2,
            box: BoxPrimitive(),
            accessibleSides: {door},
          ),
        ],
      ),
    );
    return volumes;
  }

  test('rejects an action that is not path-adjacent', () {
    final home = (2, 2);
    expect(
      router.canProgramAction(
        tile: (6, 6),
        home: home,
        paths: PathStore(grid: grid),
      ),
      isFalse,
    );
  });

  test('rejects an action outside the Chebyshev-4 range', () {
    final paths = PathStore(grid: grid)..addIsland(20, 2);
    expect(
      router.canProgramAction(
        tile: (20, 2),
        home: (2, 2),
        paths: paths,
      ),
      isFalse,
    );
  });

  test('walks indoor to a door then along path edges', () {
    final home = (2, 2);
    final volumes = bedroomAt(home);
    final paths = PathStore(grid: grid)
      ..connect(3, 2, 4, 2)
      ..connect(4, 2, 5, 2);
    final hop = router.findHop(
      start: home,
      goal: (5, 2),
      grid: grid,
      volumes: volumes,
      paths: paths,
    );
    expect(hop, isNotNull);
    expect(hop!.first, home);
    expect(hop.last, (5, 2));
    expect(hop, containsAllInOrder([(2, 2), (3, 2), (4, 2), (5, 2)]));
  });

  test('an island path cannot reach a disconnected action', () {
    final home = (2, 2);
    final volumes = bedroomAt(home);
    final paths = PathStore(grid: grid)
      ..connect(3, 2, 4, 2)
      ..addIsland(6, 2);
    final hop = router.findHop(
      start: home,
      goal: (6, 2),
      grid: grid,
      volumes: volumes,
      paths: paths,
    );
    expect(hop, isNull);
  });

  test('stops further hops after the first broken one', () {
    final home = (2, 2);
    final volumes = bedroomAt(home);
    final paths = PathStore(grid: grid)
      ..connect(3, 2, 4, 2)
      ..connect(4, 2, 5, 2);
    final plan = FlatmateDayPlan(
      friendId: 'f',
      slots: [
        const DayActionSlot(kind: DayActionKind.collect, tile: (5, 2)),
        const DayActionSlot(kind: DayActionKind.dye, tile: (8, 8)),
        lockedSleepSlot(home),
      ],
    );
    router.compute(
      plan,
      home: home,
      grid: grid,
      volumes: volumes,
      paths: paths,
    );
    expect(plan.firstBrokenHop, 1);
    expect(plan.hops[0], isNotNull);
    expect(plan.hops[1], isNull);
    expect(plan.hops[2], isNull);
    expect(plan.playablePath().last, (5, 2));
  });

  test('cannot leave a volume through a sealed wall', () {
    final home = (4, 4);
    final volumes = bedroomAt(home);
    final paths = PathStore(grid: grid)
      ..connect(3, 4, 3, 3)
      ..connect(3, 3, 4, 3)
      ..connect(4, 3, 5, 3)
      ..connect(5, 3, 5, 4);
    final throughWall = router.findHop(
      start: home,
      goal: (3, 4),
      grid: grid,
      volumes: volumes,
      paths: paths,
    );
    expect(throughWall, isNotNull);
    expect(throughWall!.first, home);
    expect(throughWall[1], (5, 4));
    for (var i = 0; i < throughWall.length - 1; i++) {
      expect(
        {throughWall[i], throughWall[i + 1]},
        isNot(unorderedEquals([(4, 4), (3, 4)])),
      );
    }
  });

  test('a sealed bedroom cannot reach an outdoor action', () {
    final home = (2, 2);
    final volumes = bedroomAt(home, door: VolumeSide.east);
    volumes.volumes.single.cells.single.accessibleSides.clear();
    final paths = PathStore(grid: grid)..connect(3, 2, 4, 2);
    expect(
      router.findHop(
        start: home,
        goal: (4, 2),
        grid: grid,
        volumes: volumes,
        paths: paths,
      ),
      isNull,
    );
  });

  test('walks outdoor path through a region opening onto a yard tile', () {
    final home = (2, 2);
    final volumes = bedroomAt(home);
    final walls = WallStore(grid: grid);
    walls.add(WallEdge(5, 2, 6, 2));
    walls.add(WallEdge(6, 2, 6, 3));
    walls.add(WallEdge(5, 3, 6, 3));
    walls.add(WallEdge(5, 2, 5, 3));
    expect(walls.cut(WallEdge(5, 2, 5, 3)), isTrue);
    final regions = computeEnclosedRegions(walls);
    expect(regions.single.tiles, {(5, 2)});
    final paths = PathStore(grid: grid)
      ..connect(3, 2, 4, 2);
    paths.addIsland(4, 2);
    final graph = ConnectionGraph.build(
      volumes: volumes,
      paths: paths,
      walls: walls,
      regions: regions,
    );
    final hop = router.findHop(
      start: home,
      goal: (5, 2),
      grid: grid,
      volumes: volumes,
      paths: paths,
      walls: walls,
      regions: regions,
      graph: graph,
      goalNeedsPath: false,
    );
    expect(hop, isNotNull);
    expect(hop!.first, home);
    expect(hop.last, (5, 2));
    expect(hop, containsAllInOrder([(4, 2), (5, 2)]));
  });

  test('a two-gate yard splices region tiles into the hop', () {
    final home = (1, 2);
    final volumes = bedroomAt(home, door: VolumeSide.east);
    final walls = WallStore(grid: grid);
    for (var x = 3; x < 6; x++) {
      walls.add(WallEdge(x, 2, x + 1, 2));
      walls.add(WallEdge(x, 3, x + 1, 3));
    }
    walls.add(WallEdge(3, 2, 3, 3));
    walls.add(WallEdge(6, 2, 6, 3));
    expect(walls.cut(WallEdge(3, 2, 3, 3)), isTrue);
    expect(walls.cut(WallEdge(6, 2, 6, 3)), isTrue);
    final regions = computeEnclosedRegions(walls);
    expect(regions.single.tiles, {(3, 2), (4, 2), (5, 2)});
    final paths = PathStore(grid: grid)
      ..addIsland(2, 2)
      ..addIsland(6, 2);
    final graph = ConnectionGraph.build(
      volumes: volumes,
      paths: paths,
      walls: walls,
      regions: regions,
    );
    final hop = router.findHop(
      start: home,
      goal: (6, 2),
      grid: grid,
      volumes: volumes,
      paths: paths,
      walls: walls,
      regions: regions,
      graph: graph,
    );
    expect(hop, isNotNull);
    expect(hop!.first, home);
    expect(hop.last, (6, 2));
    expect(hop, containsAllInOrder([(3, 2), (4, 2), (5, 2)]));
  });

  test('sleep hop returns home along the path graph', () {
    final home = (2, 2);
    final volumes = bedroomAt(home);
    final paths = PathStore(grid: grid)
      ..connect(3, 2, 4, 2)
      ..connect(4, 2, 5, 2);
    final plan = FlatmateDayPlan(
      friendId: 'f',
      slots: [
        const DayActionSlot(kind: DayActionKind.dwell, tile: (5, 2)),
        const DayActionSlot(),
        lockedSleepSlot(home),
      ],
    );
    router.compute(
      plan,
      home: home,
      grid: grid,
      volumes: volumes,
      paths: paths,
    );
    expect(plan.firstBrokenHop, isNull);
    expect(plan.hops[2], isNotNull);
    expect(plan.hops[2]!.first, (5, 2));
    expect(plan.hops[2]!.last, home);
  });
}