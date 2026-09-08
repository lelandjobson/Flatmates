import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/vision/map_vision.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  const grid = VolumeGrid(
    tilesSide: MapVisionConfig.defaultWorldTilesSide,
    tileSize: 8,
  );

  test('signed tiles are centered on world origin', () {
    expect(grid.originTile, -24);
    expect(grid.lastTile, 23);
    expect(grid.inBounds(0, 0), isTrue);
    expect(grid.inBounds(-24, -24), isTrue);
    expect(grid.inBounds(23, 23), isTrue);
    expect(grid.inBounds(-25, 0), isFalse);
    expect(grid.inBounds(24, 0), isFalse);
  });

  test('tile (0,0) sits at world origin', () {
    final origin = grid.tileOrigin(0, 0);
    expect(origin.x, 0);
    expect(origin.z, 0);
    expect(grid.tileAtWorld(Vector3.zero()), (0, 0));
    expect(grid.tileAtWorld(Vector3(-0.1, 0, -0.1)), (-1, -1));
    expect(grid.tileAtWorld(Vector3(8, 0, 8)), (1, 1));
  });

  test('atlas pixels map signed tiles onto the 0-based landscape', () {
    expect(grid.atlasTile(-24), 0);
    expect(grid.atlasTile(0), 24);
    expect(grid.landscapePixel(0, 0), 192);
    expect(grid.landscapePixel(-24, 3), 3);
  });
}
