import 'package:flatmates/gameplay/eraser/eraser_filter.dart';
import 'package:flatmates/gameplay/eraser/world_eraser.dart';
import 'package:flatmates/gameplay/paths/path_store.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flatmates/gameplay/walls/wall_edge.dart';
import 'package:flatmates/gameplay/walls/wall_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

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
}
