import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const grid = VolumeGrid(tilesSide: 16, tileSize: 8);

  test('a face can inset at most two subtles from the tile edge', () {
    final box = BoxPrimitive();
    box.applyHandleDelta(
      grid: grid,
      tx: 0,
      ty: 0,
      handle: VolumeHandle.posX,
      delta: -8,
    );
    expect(box.originXSubtiles, 0);
    expect(box.widthSubtiles, 6);

    box.applyHandleDelta(
      grid: grid,
      tx: 0,
      ty: 0,
      handle: VolumeHandle.negX,
      delta: -8,
    );
    expect(box.originXSubtiles, 2);
    expect(box.widthSubtiles, 4);
    expect(box.originXSubtiles + box.widthSubtiles, 6);

    box.applyHandleDelta(
      grid: grid,
      tx: 0,
      ty: 0,
      handle: VolumeHandle.posX,
      delta: -8,
    );
    expect(box.originXSubtiles, 2);
    expect(box.widthSubtiles, 4);
    expect(box.originXSubtiles + box.widthSubtiles, 6);
  });

  test('clampToTile pulls a half-tile box back onto the center 4×4', () {
    final box = BoxPrimitive(
      widthSubtiles: 4,
      depthSubtiles: 4,
      originXSubtiles: 0,
      originZSubtiles: 4,
    )..clampToTile();
    expect(box.originXSubtiles, 0);
    expect(box.widthSubtiles, 6);
    expect(box.originZSubtiles, 2);
    expect(box.depthSubtiles, 6);
  });
}
