import 'package:flatmates/gameplay/landscape_cover.dart';
import 'package:flatmates/gameplay/paths/path_store.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('path island covers the centered 4x4, not the whole tile', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    expect(paths.addIsland(0, 0), isTrue);
    final covered = coveredGroundPixels(volumes: volumes, paths: paths);
    expect(covered, hasLength(16));
    expect(covered.contains((2, 2)), isTrue);
    expect(covered.contains((5, 5)), isTrue);
    expect(covered.contains((0, 0)), isFalse);
    expect(covered.contains((7, 7)), isFalse);
  });

  test('volume box covers its subtile footprint', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    expect(volumes.startNew(1, 1), isTrue);
    final covered = coveredGroundPixels(volumes: volumes, paths: paths);
    expect(covered, hasLength(8 * 8));
    expect(covered.contains((8, 8)), isTrue);
    expect(covered.contains((15, 15)), isTrue);
    expect(covered.contains((7, 7)), isFalse);
  });

  test('in_out door covers dest island and volume-facing stub', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    expect(volumes.startNew(0, 0), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    volumes.toggleAccess(VolumeSide.east);
    expect(volumes.confirmAccess(), isTrue);
    final covered = coveredGroundPixels(volumes: volumes, paths: paths);
    expect(covered.contains((8 + 2, 2)), isTrue);
    expect(covered.contains((8, 2)), isTrue);
    expect(covered.contains((8, 0)), isFalse);
  });
}
