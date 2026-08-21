import 'package:flatmates/gameplay/paths/path_store.dart';
import 'package:flatmates/gameplay/viewers/focus_region.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const grid = VolumeGrid(tilesSide: 16, tileSize: 8);

  test('tile click focuses a clamped 3x3', () {
    final mid = FocusRegion.aroundTile(grid: grid, tx: 4, ty: 5);
    expect(mid.contains(4, 5), isTrue);
    expect(mid.contains(3, 4), isTrue);
    expect(mid.contains(5, 6), isTrue);
    expect(mid.contains(2, 5), isFalse);
    expect(mid.tiles.length, 9);

    final corner = FocusRegion.aroundTile(grid: grid, tx: 0, ty: 0);
    expect(corner.minTx, 0);
    expect(corner.minTy, 0);
    expect(corner.maxTx, 1);
    expect(corner.maxTy, 1);
    expect(corner.tiles.length, 4);
  });

  test('volume focus includes the volume tiles plus one tile of padding', () {
    final volumes = VolumeStore(grid: grid);
    expect(volumes.startNew(2, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    volumes.toggleAccess(VolumeSide.east);
    expect(volumes.confirmAccess(), isTrue);
    final grow = volumes.growCandidates().firstWhere((c) => c.tx == 3 && c.ty == 2);
    expect(volumes.startGrow(grow), isTrue);
    expect(volumes.confirmEdit(), isTrue);

    final volume = volumes.volumes.single;
    final region = FocusRegion.aroundVolume(grid: grid, volume: volume);
    expect(region.contains(2, 2), isTrue);
    expect(region.contains(3, 2), isTrue);
    expect(region.contains(1, 1), isTrue);
    expect(region.contains(4, 3), isTrue);
    expect(region.contains(0, 2), isFalse);
    expect(region.contains(5, 2), isFalse);
  });

  test('content AABB covers focused tiles', () {
    final volumes = VolumeStore(grid: grid);
    final paths = PathStore(grid: grid);
    final region = FocusRegion.aroundTile(grid: grid, tx: 1, ty: 1);
    final (min, max) = region.contentAabb(
      grid: grid,
      volumes: volumes,
      paths: paths,
    );
    final origin = grid.tileOrigin(0, 0);
    expect(min.x, closeTo(origin.x, 1e-6));
    expect(min.z, closeTo(origin.z, 1e-6));
    expect(max.x - min.x, closeTo(grid.tileSize * 3, 1e-6));
    expect(max.z - min.z, closeTo(grid.tileSize * 3, 1e-6));
  });
}
