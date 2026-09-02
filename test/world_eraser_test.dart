import 'package:flatmates/gameplay/eraser/eraser_filter.dart';
import 'package:flatmates/gameplay/eraser/world_eraser.dart';
import 'package:flatmates/gameplay/paths/path_store.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flatmates/gameplay/walls/wall_edge.dart';
import 'package:flatmates/gameplay/walls/wall_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('filter checkboxes skip disabled kinds', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid)..addIsland(2, 2);
    final walls = WallStore(grid: volumes.grid)..add(WallEdge(2, 2, 3, 2));
    final world = walls.vertexWorld(2, 2);
    final center = world + (walls.vertexWorld(3, 2) - world) * 0.5;
    expect(
      eraseWorld(
        world: center,
        radius: volumes.grid.tileSize,
        filter: EraserFilter(walls: false, paths: true, volumes: false),
        walls: walls,
        paths: paths,
        volumes: volumes,
      ),
      isTrue,
    );
    expect(walls.contains(WallEdge(2, 2, 3, 2)), isTrue);
    expect(paths.contains(2, 2), isFalse);
  });

  test('volume cells under the brush are removed', () {
    final volumes = VolumeStore();
    expect(volumes.startNew(4, 4), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    volumes.toggleAccess(VolumeSide.south);
    expect(volumes.confirmAccess(), isTrue);
    final walls = WallStore(grid: volumes.grid);
    final paths = PathStore(grid: volumes.grid);
    final center = volumes.grid.tileCenter(4, 4);
    expect(
      eraseWorld(
        world: center,
        radius: 1,
        filter: EraserFilter(),
        walls: walls,
        paths: paths,
        volumes: volumes,
      ),
      isTrue,
    );
    expect(volumes.volumes, isEmpty);
  });

  test('eraseAtTile removes path, wall, and volume on that tile', () {
    final volumes = VolumeStore();
    expect(volumes.startNew(3, 3), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    final paths = PathStore(grid: volumes.grid)..addIsland(3, 3);
    final walls = WallStore(grid: volumes.grid)..add(WallEdge(3, 3, 4, 3));
    expect(
      eraseAtTile(
        grid: volumes.grid,
        tx: 3,
        ty: 3,
        filter: EraserFilter(),
        walls: walls,
        paths: paths,
        volumes: volumes,
      ),
      isTrue,
    );
    expect(volumes.volumeAt(3, 3), isNull);
    expect(paths.contains(3, 3), isFalse);
    expect(walls.contains(WallEdge(3, 3, 4, 3)), isFalse);
  });

  test('eraseAtTile removes only that path tile, not its neighbors', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid)
      ..placeAndJoin(3, 3)
      ..placeAndJoin(4, 3);
    expect(paths.hasEdge(3, 3, 4, 3), isTrue);
    expect(
      eraseAtTile(
        grid: volumes.grid,
        tx: 3,
        ty: 3,
        filter: EraserFilter(walls: false, volumes: false),
        walls: WallStore(grid: volumes.grid),
        paths: paths,
        volumes: volumes,
      ),
      isTrue,
    );
    expect(paths.contains(3, 3), isFalse);
    expect(paths.contains(4, 3), isTrue);
    expect(paths.hasEdge(3, 3, 4, 3), isFalse);
  });
}
