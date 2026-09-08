import 'package:flatmates/gameplay/flatmates/flatmate_pathfinder.dart';
import 'package:flatmates/gameplay/paths/path_shape.dart';
import 'package:flatmates/gameplay/paths/path_store.dart';
import 'package:flatmates/gameplay/spawns/basement_spawn.dart';
import 'package:flatmates/gameplay/spawns/basement_spawn_mesh.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_door.dart';
import 'package:flatmates/gameplay/volumes/volume_door_sync.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flatmates/theme/world_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const grid = VolumeGrid(tilesSide: 48, tileSize: 8);

  test('cut tiles block walking; locked path does not', () {
    expect(BasementSpawn.blocksWalk(0, 0), isTrue);
    expect(BasementSpawn.blocksWalk(0, 1), isTrue);
    expect(BasementSpawn.blocksWalk(0, -1), isFalse);
    expect(BasementSpawn.blocksWalk(0, -2), isFalse);
    expect(BasementSpawn.blocksSelect(0, -1), isFalse);
    expect(BasementSpawn.blocksBuild(0, -1), isFalse);
    expect(BasementSpawn.blocksBuild(0, -2), isFalse);
    expect(BasementSpawn.isCutTile(0, -1), isFalse);
    expect(BasementSpawn.isCutTile(0, -2), isFalse);
    expect(BasementSpawn.isHiddenTile(0, -1), isTrue);
    expect(BasementSpawn.rampTiles, hasLength(4));
    expect(BasementSpawn.cutTiles, hasLength(2));
    expect(BasementSpawn.blocksWalk(0, 2), isFalse);
    expect(BasementSpawn.isLockedPath(0, 2), isTrue);
    expect(BasementSpawn.blocksBuild(0, 2), isTrue);
    expect(BasementSpawn.blocksSelect(0, 2), isTrue);
    final volumes = VolumeStore(grid: grid);
    final paths = PathStore(grid: grid);
    expect(
      canPaintPathAt(volumes: volumes, paths: paths, tx: 0, ty: 1),
      isFalse,
    );
    expect(
      canPaintPathAt(volumes: volumes, paths: paths, tx: 0, ty: 2),
      isFalse,
    );
    expect(
      canPaintPathAt(volumes: volumes, paths: paths, tx: 1, ty: 1),
      isTrue,
    );
  });

  test('locked path at (0,2) draws a north arm that meets the ramp', () {
    final paths = PathStore(grid: grid);
    paths.lockTile(0, 2);
    expect(paths.placeAndJoin(0, 2), isTrue);
    final byTile = pathFootprintsByTile(
      volumes: VolumeStore(grid: grid),
      paths: paths,
    );
    expect(byTile.containsKey((0, 2)), isTrue);
    final pieces = byTile[(0, 2)]!;
    expect(
      pieces.any(
        (p) =>
            p.originXSubtiles == 2 &&
            p.originZSubtiles == 0 &&
            p.widthSubtiles == kPathWidthSubtiles &&
            p.depthSubtiles == 2,
      ),
      isTrue,
    );
  });

  test('locked path tile cannot be removed', () {
    final paths = PathStore(grid: grid);
    paths.lockTile(0, 2);
    expect(paths.placeAndJoin(0, 2), isTrue);
    expect(paths.removeTile(0, 2), isFalse);
    expect(paths.contains(0, 2), isTrue);
    paths.restore(tiles: {}, edges: {});
    expect(paths.contains(0, 2), isTrue);
  });

  test('pathfinder cannot route across the ramp cut', () {
    final path = FlatmatePathfinder().findOnMap(
      start: (-1, 0),
      goal: (1, 0),
      grid: grid,
      volumes: VolumeStore(grid: grid),
      paths: PathStore(grid: grid),
    );
    expect(path, isNotNull);
    expect(path, isNot(contains((0, 0))));
    expect(path, isNot(contains((0, 1))));
  });

  test('pathfinder cannot destination-walk onto the ramp', () {
    final path = FlatmatePathfinder().findOnMap(
      start: (2, 2),
      goal: (0, 0),
      grid: grid,
      volumes: VolumeStore(grid: grid),
      paths: PathStore(grid: grid),
    );
    expect(path, isNull);
  });

  test('cut walls follow the four-tile ramp, not just the hole', () {
    expect(BasementSpawn.rampTileSet, containsAll(BasementSpawn.cutTileSet));
    expect(BasementSpawn.rampTileSet, containsAll(BasementSpawn.hiddenTiles));
    expect(BasementSpawn.rampTileSet.length, 4);
  });

  test('door fills the (0,0)/(0,-1) seam down to the ramp', () {
    final door = basementDoorBounds(grid);
    final z = grid.tileOrigin(0, 0).z;
    expect(BasementSpawn.doorTile, (0, -1));
    expect(z, grid.tileOrigin(0, -1).z + grid.tileSize);
    expect(door.z, z);
    expect(door.y1, 0);
    expect(door.y0, basementRampHeight(grid, z));
    expect(door.y0, lessThan(0));
    expect(door.x1 - door.x0, grid.tileSize);
  });

  test('basement door is a volume wall with a centered 2×4 opening', () {
    final spec = basementDoorSpec(grid);
    expect(spec.door.side, VolumeSide.south);
    expect(spec.door.width, kDoorWidthSubtiles);
    expect(spec.door.height, kDoorHeightSubtiles);
    expect(spec.door.originY, 0);
    expect(spec.door.originU, (grid.subtilesPerTile - kDoorWidthSubtiles) ~/ 2);
    final paper = basementDoorPaperCorners(grid);
    expect(paper, hasLength(4));
    final wall = basementDoorWallGeometry(grid);
    expect(wall.faces, isNotEmpty);
    expect(wall.faces.first, hasLength(greaterThan(4)));
    expect(basementDoorWallOutline(grid), isNotEmpty);
    final opening = basementCutDoorWall(grid);
    expect(opening.doorX1 - opening.doorX0, kDoorWidthSubtiles * grid.subtileSize);
    expect(opening.doorY1 - opening.doorY0, kDoorHeightSubtiles * grid.subtileSize);
    expect(opening.yTop, 0);
    expect(opening.color, WorldTheme.paperDiorama.volume);
    expect(opening.doorX1 - opening.doorX0, lessThan(opening.x1 - opening.x0));
    expect(opening.doorY1 - opening.doorY0, lessThan(opening.yTop - opening.yFloor));
    expect(basementDoorWallFillQuads(grid), hasLength(3));
  });

  test('ramp keeps sloping through four tiles', () {
    expect(basementRampHeight(grid, grid.tileOrigin(0, 1).z + grid.tileSize), 0);
    expect(basementRampHeight(grid, grid.tileOrigin(0, 0).z), -grid.tileSize);
    expect(basementRampHeight(grid, grid.tileOrigin(0, -1).z), -grid.tileSize * 1.5);
    expect(basementRampHeight(grid, grid.tileOrigin(0, -2).z), -grid.tileSize * 2);
  });

  test('ramp path is a centered 4-subtile corridor', () {
    final path = basementRampPathX(grid);
    final s = grid.subtileSize;
    final origin = (grid.subtilesPerTile - kPathWidthSubtiles) ~/ 2;
    expect(path.x1 - path.x0, kPathWidthSubtiles * s);
    expect(path.x0, grid.tileOrigin(0, 1).x + origin * s);
  });
}
