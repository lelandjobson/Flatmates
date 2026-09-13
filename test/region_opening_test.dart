import 'package:flatmates/gameplay/paths/path_store.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/walls/region_opening.dart';
import 'package:flatmates/gameplay/walls/wall_edge.dart';
import 'package:flatmates/gameplay/walls/wall_regions.dart';
import 'package:flatmates/gameplay/walls/wall_store.dart';
import 'package:flutter_test/flutter_test.dart';

void encloseRect(WallStore walls, int x0, int y0, int x1, int y1) {
  for (var x = x0; x < x1; x++) {
    walls.add(WallEdge(x, y0, x + 1, y0));
    walls.add(WallEdge(x, y1, x + 1, y1));
  }
  for (var y = y0; y < y1; y++) {
    walls.add(WallEdge(x0, y, x0, y + 1));
    walls.add(WallEdge(x1, y, x1, y + 1));
  }
}

void main() {
  test('stroke across a yard cuts both sides and skips interior tiles', () {
    final walls = WallStore();
    encloseRect(walls, 2, 2, 5, 3);
    final regions = computeEnclosedRegions(walls);
    expect(regions.single.tiles, {(2, 2), (3, 2), (4, 2)});
    final paths = PathStore();
    expect(
      paths.paintStroke(
        (1, 2),
        (5, 2),
        walls: walls,
        regions: regions,
      ),
      isTrue,
    );
    expect(paths.contains(1, 2), isTrue);
    expect(paths.contains(5, 2), isTrue);
    expect(paths.contains(2, 2), isFalse);
    expect(paths.contains(3, 2), isFalse);
    expect(paths.contains(4, 2), isFalse);
    expect(paths.hasEdge(1, 2, 2, 2), isFalse);
    expect(walls.lookup(WallEdge(2, 2, 2, 3))?.kind, WallKind.cutFence);
    expect(walls.lookup(WallEdge(5, 2, 5, 3))?.kind, WallKind.cutFence);
    expect(computeEnclosedRegions(walls).single.tiles, {(2, 2), (3, 2), (4, 2)});
  });

  test('removing the approach path restores a solid fence', () {
    final walls = WallStore();
    encloseRect(walls, 3, 2, 4, 3);
    final regions = computeEnclosedRegions(walls);
    final paths = PathStore()..addIsland(4, 2);
    expect(
      paths.placeAndJoin(3, 2, walls: walls, regions: regions),
      isTrue,
    );
    expect(walls.lookup(WallEdge(4, 2, 4, 3))?.kind, WallKind.cutFence);
    expect(paths.removeTile(4, 2), isTrue);
    expect(
      syncRegionOpeningsFromPaths(
        walls: walls,
        paths: paths,
        regions: regions,
      ),
      isTrue,
    );
    expect(walls.lookup(WallEdge(4, 2, 4, 3))?.kind, WallKind.fence);
  });

  test('paintStroke starting on the yard tile cuts and does not pave', () {
    final walls = WallStore();
    encloseRect(walls, 3, 2, 4, 3);
    final regions = computeEnclosedRegions(walls);
    final paths = PathStore()..addIsland(4, 2);
    expect(
      paths.paintStroke((3, 2), (3, 2), walls: walls, regions: regions),
      isTrue,
    );
    expect(paths.contains(3, 2), isFalse);
    expect(paths.contains(4, 2), isTrue);
    expect(walls.lookup(WallEdge(4, 2, 4, 3))?.kind, WallKind.cutFence);
  });

  test('populate south yard click cuts the north fence and stays outside', () {
    final grid = const VolumeGrid(tilesSide: 48, tileSize: 8);
    final walls = WallStore(grid: grid);
    walls.add(WallEdge(3, 3, 3, 4));
    walls.add(WallEdge(3, 3, 4, 3));
    walls.add(WallEdge(3, 4, 4, 4));
    walls.add(WallEdge(4, 3, 5, 3));
    walls.add(WallEdge(4, 4, 5, 4));
    walls.add(WallEdge(5, 3, 5, 4));
    final regions = computeEnclosedRegions(walls);
    expect(
      regions.any((region) => region.tiles.containsAll({(3, 3), (4, 3)})),
      isTrue,
    );
    final paths = PathStore(grid: grid)
      ..addIsland(3, 2)
      ..addIsland(4, 2);
    expect(
      regionOpeningWallAt(
        tx: 3,
        ty: 3,
        paths: paths,
        walls: walls,
        regions: regions,
      ),
      WallEdge(3, 3, 4, 3),
    );
    expect(
      paths.placeAndJoin(3, 3, walls: walls, regions: regions),
      isTrue,
    );
    expect(paths.contains(3, 3), isFalse);
    expect(paths.contains(3, 2), isTrue);
    expect(walls.lookup(WallEdge(3, 3, 4, 3))?.kind, WallKind.cutFence);
    expect(computeEnclosedRegions(walls).single.tiles, {(3, 3), (4, 3)});
  });

  test('regionOpeningWallAt finds the gate from either side', () {
    final walls = WallStore();
    encloseRect(walls, 3, 2, 4, 3);
    final regions = computeEnclosedRegions(walls);
    final paths = PathStore()..addIsland(4, 2);
    expect(
      regionOpeningWallAt(
        tx: 3,
        ty: 2,
        paths: paths,
        walls: walls,
        regions: regions,
      ),
      WallEdge(4, 2, 4, 3),
    );
    expect(
      regionOpeningWallAt(
        tx: 4,
        ty: 2,
        paths: paths,
        walls: walls,
        regions: regions,
      ),
      WallEdge(4, 2, 4, 3),
    );
  });
}
