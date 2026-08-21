import 'package:flatmates/gameplay/viewers/focus_crop.dart';
import 'package:flatmates/gameplay/viewers/focus_region.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  const grid = VolumeGrid(tilesSide: 16, tileSize: 8);

  FocusCrop isolation() {
    final region = FocusRegion.aroundTile(grid: grid, tx: 4, ty: 5);
    return FocusCrop.fromIsolation(
      region: region,
      grid: grid,
      contentMaxY: grid.subtileSize * 6,
    );
  }

  test('isolation crop matches the focused tiles and content height', () {
    final crop = isolation();
    expect(crop.minSx, 3 * 8);
    expect(crop.maxSx, 6 * 8);
    expect(crop.minSz, 4 * 8);
    expect(crop.maxSz, 7 * 8);
    expect(crop.minSy, 0);
    expect(crop.maxSy, 6);
  });

  test('handles shrink in subtile steps and cannot grow past isolation', () {
    final bounds = isolation();
    var crop = bounds;
    crop = crop.applyHandleDelta(
      handle: CropHandle.posX,
      delta: -grid.subtileSize * 3,
      grid: grid,
      bounds: bounds,
    );
    expect(crop.maxSx, bounds.maxSx - 3);
    crop = crop.applyHandleDelta(
      handle: CropHandle.posX,
      delta: grid.subtileSize * 20,
      grid: grid,
      bounds: bounds,
    );
    expect(crop.maxSx, bounds.maxSx);
  });

  test('negY raises the floor but not past the lid or below isolation', () {
    final bounds = isolation();
    var crop = bounds.applyHandleDelta(
      handle: CropHandle.negY,
      delta: -grid.subtileSize * 2,
      grid: grid,
      bounds: bounds,
    );
    expect(crop.minSy, 2);
    expect(crop.includesGround, isFalse);
    crop = crop.applyHandleDelta(
      handle: CropHandle.negY,
      delta: grid.subtileSize * 50,
      grid: grid,
      bounds: bounds,
    );
    expect(crop.minSy, 0);
  });

  test('cannot collapse below one subtile', () {
    final bounds = isolation();
    var crop = bounds;
    crop = crop.applyHandleDelta(
      handle: CropHandle.posX,
      delta: -grid.subtileSize * 100,
      grid: grid,
      bounds: bounds,
    );
    expect(crop.width, FocusCrop.minExtent);
  });

  test('world AABB round-trips through subtile indices', () {
    final crop = isolation();
    final min = crop.worldMin(grid);
    final max = crop.worldMax(grid);
    expect(max.x - min.x, closeTo(3 * grid.tileSize, 1e-6));
    expect(
      crop.intersectsWorld(
        min + Vector3(1, 1, 1),
        max - Vector3(1, 1, 1),
        grid,
      ),
      isTrue,
    );
  });
}
