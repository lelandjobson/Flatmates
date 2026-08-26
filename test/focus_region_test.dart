import 'package:flatmates/gameplay/paths/path_store.dart';
import 'package:flatmates/gameplay/viewers/focus_region.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flatmates/gameplay/walls/wall_regions.dart';
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

  test('C-shaped volume isolates a padded rectangle that fills the mouth', () {
    final volume = Volume(
      id: 1,
      cells: [
        VolumeCell(tx: 2, ty: 1, box: BoxPrimitive()),
        VolumeCell(tx: 3, ty: 1, box: BoxPrimitive()),
        VolumeCell(tx: 4, ty: 1, box: BoxPrimitive()),
        VolumeCell(tx: 2, ty: 2, box: BoxPrimitive()),
        VolumeCell(tx: 2, ty: 3, box: BoxPrimitive()),
        VolumeCell(tx: 3, ty: 3, box: BoxPrimitive()),
        VolumeCell(tx: 4, ty: 3, box: BoxPrimitive()),
      ],
    );
    final region = FocusRegion.aroundVolume(grid: grid, volume: volume);
    expect(region.minTx, 1);
    expect(region.minTy, 0);
    expect(region.maxTx, 5);
    expect(region.maxTy, 4);
    expect(region.contains(3, 2), isTrue);
    expect(region.contains(4, 2), isTrue);
    expect(region.contains(0, 1), isFalse);
  });

  test('wall region click isolates the region bbox plus one tile', () {
    final yard = WallRegion({(2, 2), (3, 2), (2, 3), (3, 3)});
    final region = isolateFocusRegion(
      grid: grid,
      tx: 3,
      ty: 2,
      wallRegions: [yard],
    );
    expect(region.minTx, 1);
    expect(region.minTy, 1);
    expect(region.maxTx, 4);
    expect(region.maxTy, 4);
    expect(region.contains(4, 4), isTrue);
    expect(region.contains(0, 2), isFalse);
  });

  test('C-shaped wall region still isolates a rectangle', () {
    final mouth = WallRegion({
      (2, 1),
      (3, 1),
      (4, 1),
      (2, 2),
      (2, 3),
      (3, 3),
      (4, 3),
    });
    final region = isolateFocusRegion(
      grid: grid,
      tx: 4,
      ty: 1,
      wallRegions: [mouth],
    );
    expect(region.contains(3, 2), isTrue);
    expect(region.contains(4, 2), isTrue);
    expect(region.minTx, 1);
    expect(region.maxTx, 5);
    expect(region.minTy, 0);
    expect(region.maxTy, 4);
  });

  test('bare tile click stays a clamped 3x3', () {
    final region = isolateFocusRegion(grid: grid, tx: 4, ty: 5);
    expect(region.tiles.length, 9);
    expect(region.contains(3, 4), isTrue);
    expect(region.contains(2, 5), isFalse);
  });

  test('volume click wins over a wall region on the same tile', () {
    final volume = Volume(
      id: 1,
      cells: [
        VolumeCell(tx: 2, ty: 2, box: BoxPrimitive()),
        VolumeCell(tx: 3, ty: 2, box: BoxPrimitive()),
      ],
    );
    final yard = WallRegion({(1, 1), (2, 1), (3, 1), (1, 2), (2, 2), (3, 2)});
    final region = isolateFocusRegion(
      grid: grid,
      tx: 2,
      ty: 2,
      volume: volume,
      wallRegions: [yard],
    );
    expect(region.minTx, 1);
    expect(region.maxTx, 4);
    expect(region.minTy, 1);
    expect(region.maxTy, 3);
    expect(region.contains(0, 0), isFalse);
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
