import 'package:flatmates/gameplay/landscape_cover.dart';
import 'package:flatmates/gameplay/paths/path_store.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('path island covers the centered 4x4, not the whole tile', () {
    final volumes = VolumeStore();
    final grid = volumes.grid;
    final paths = PathStore(grid: grid);
    expect(paths.addIsland(0, 0), isTrue);
    final covered = coveredGroundPixels(volumes: volumes, paths: paths);
    expect(covered, hasLength(16));
    expect(covered.contains((grid.landscapePixel(0, 2), grid.landscapePixel(0, 2))), isTrue);
    expect(covered.contains((grid.landscapePixel(0, 5), grid.landscapePixel(0, 5))), isTrue);
    expect(covered.contains((grid.landscapePixel(0, 0), grid.landscapePixel(0, 0))), isFalse);
    expect(covered.contains((grid.landscapePixel(0, 7), grid.landscapePixel(0, 7))), isFalse);
  });

  test('volume box covers its subtile footprint', () {
    final volumes = VolumeStore();
    final grid = volumes.grid;
    final paths = PathStore(grid: grid);
    expect(volumes.startNew(1, 1), isTrue);
    final covered = coveredGroundPixels(volumes: volumes, paths: paths);
    expect(covered, hasLength(8 * 8));
    expect(covered.contains((grid.landscapePixel(1, 0), grid.landscapePixel(1, 0))), isTrue);
    expect(covered.contains((grid.landscapePixel(1, 7), grid.landscapePixel(1, 7))), isTrue);
    expect(covered.contains((grid.landscapePixel(0, 7), grid.landscapePixel(0, 7))), isFalse);
  });

  test('in_out door covers dest island and volume-facing stub', () {
    final volumes = VolumeStore();
    final grid = volumes.grid;
    final paths = PathStore(grid: grid);
    expect(volumes.startNew(0, 0), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    volumes.toggleAccess(VolumeSide.east);
    expect(volumes.confirmAccess(), isTrue);
    final covered = coveredGroundPixels(volumes: volumes, paths: paths);
    expect(covered.contains((grid.landscapePixel(1, 2), grid.landscapePixel(0, 2))), isTrue);
    expect(covered.contains((grid.landscapePixel(1, 0), grid.landscapePixel(0, 2))), isTrue);
    expect(covered.contains((grid.landscapePixel(1, 0), grid.landscapePixel(0, 0))), isFalse);
  });
}
