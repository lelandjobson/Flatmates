import 'package:flatmates/gameplay/vision/map_vision.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const config = MapVisionConfig.game;
  const grid = VolumeGrid(
    tilesSide: MapVisionConfig.defaultWorldTilesSide,
    tileSize: 8,
  );

  MapVision rebuilt(Iterable<VisionSource> sources) {
    final vision = MapVision(config: config);
    vision.rebuild(grid: grid, sources: sources);
    return vision;
  }

  test('world center tile is 24,24 on the default 48 map', () {
    expect(config.centerTx, 24);
    expect(config.centerTy, 24);
    expect(config.inStartingArea(config.centerTx, config.centerTy), isTrue);
    final look = grid.tileCenter(config.centerTx, config.centerTy);
    expect(grid.tileAtWorld(look), (24, 24));
    expect(look.x, isNot(0));
    expect(look.z, isNot(0));
  });

  test('starting area is visible with no sources', () {
    final vision = rebuilt(const []);
    expect(vision.visibleTiles, hasLength(16 * 16));
    expect(vision.isVisible(config.startingOriginTx, config.startingOriginTy), isTrue);
    expect(vision.isVisible(config.startingMaxTx, config.startingMaxTy), isTrue);
    expect(
      vision.isVisible(config.startingOriginTx - 1, config.startingOriginTy),
      isFalse,
    );
    expect(
      vision.isVisible(config.startingMaxTx + 1, config.startingMaxTy),
      isFalse,
    );
  });

  test('friend Chebyshev radius 2 reveals a 5x5 including diagonals', () {
    const tx = 8;
    const ty = 8;
    final vision = rebuilt(const [
      VisionSource(tx: tx, ty: ty, radius: 2),
    ]);
    expect(vision.isVisible(tx + 2, ty + 2), isTrue);
    expect(vision.isVisible(tx + 2, ty), isTrue);
    expect(vision.isVisible(tx, ty + 2), isTrue);
    expect(vision.isVisible(tx + 3, ty), isFalse);
    expect(vision.isVisible(tx, ty + 3), isFalse);
  });

  test('structure radius 5 reaches farther than a friend', () {
    const tx = 4;
    const ty = 4;
    final vision = rebuilt(const [
      VisionSource(tx: tx, ty: ty, radius: 5),
    ]);
    expect(vision.isVisible(tx + 5, ty), isTrue);
    expect(vision.isVisible(tx + 5, ty + 5), isTrue);
    expect(vision.isVisible(tx + 6, ty), isFalse);
  });

  test('leaving a tile drops its vision unless another source covers it', () {
    const scout = VisionSource(tx: 6, ty: 20, radius: 2);
    final before = rebuilt([scout]);
    expect(before.isVisible(6, 22), isTrue);

    final after = rebuilt(const [
      VisionSource(tx: 10, ty: 20, radius: 2),
    ]);
    expect(after.isVisible(6, 22), isFalse);
    expect(after.isVisible(10, 22), isTrue);
  });

  test('starting area stays visible after sources leave', () {
    final origin = config.startingOriginTx;
    final vision = rebuilt(const []);
    expect(vision.isVisible(origin, config.startingOriginTy), isTrue);
    final moved = rebuilt(const [
      VisionSource(tx: 2, ty: 2, radius: 2),
    ]);
    expect(moved.isVisible(origin, config.startingOriginTy), isTrue);
  });

  test('vision stops at the world edge', () {
    final vision = rebuilt(const [
      VisionSource(tx: 0, ty: 0, radius: 5),
    ]);
    expect(vision.isVisible(0, 0), isTrue);
    expect(vision.isVisible(-1, 0), isFalse);
    expect(vision.visibleTiles.every((t) => grid.inBounds(t.$1, t.$2)), isTrue);
  });

  test('per-source radius can differ', () {
    final vision = rebuilt(const [
      VisionSource(tx: 2, ty: 20, radius: 1),
      VisionSource(tx: 10, ty: 20, radius: 4),
    ]);
    expect(vision.isVisible(2, 22), isFalse);
    expect(vision.isVisible(10, 24), isTrue);
  });
}
