import 'package:flatmates/theme/world_theme.dart';
import 'package:flatmates/gameplay/paths/path_store.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_applique.dart';
import 'package:flatmates/gameplay/volumes/volume_door.dart';
import 'package:flatmates/gameplay/volumes/volume_door_sync.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flatmates/gameplay/walls/wall_edge.dart';
import 'package:flatmates/gameplay/walls/wall_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('outdoor path alone does not open a door', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    final appliques = VolumeAppliqueStore();
    expect(volumes.startNew(2, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    expect(paths.placeAndJoin(3, 2), isTrue);

    expect(
      syncVolumeDoorsFromPaths(
        volumes: volumes,
        paths: paths,
        appliques: appliques,
      ),
      isFalse,
    );
    expect(volumes.volumes.single.cells.single.accessibleSides, isEmpty);
    expect(appliques.items, isEmpty);
  });

  test('path tool may click a volume only when an outdoor path is adjacent', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    expect(volumes.startNew(2, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    expect(
      canPaintPathAt(volumes: volumes, paths: paths, tx: 2, ty: 2),
      isFalse,
    );
    expect(paths.placeAndJoin(3, 2), isTrue);
    expect(
      canPaintPathAt(volumes: volumes, paths: paths, tx: 2, ty: 2),
      isTrue,
    );
  });

  test('path on the volume plus outdoor neighbor opens a door', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    final appliques = VolumeAppliqueStore();
    expect(volumes.startNew(2, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    expect(paths.placeAndJoin(3, 2), isTrue);
    expect(paths.placeAndJoin(2, 2), isTrue);

    expect(
      syncVolumeDoorsFromPaths(
        volumes: volumes,
        paths: paths,
        appliques: appliques,
      ),
      isTrue,
    );
    final cell = volumes.volumes.single.cells.single;
    expect(cell.accessibleSides, {VolumeSide.east});
    expect(cell.doorOrigins[VolumeSide.east], 3);
    final paper = appliques.doorOn(
      volumeId: volumes.volumes.single.id,
      tx: 2,
      ty: 2,
      side: VolumeSide.east,
    );
    expect(paper, isNotNull);
    expect(paper!.layer, 0);
    expect(paper.color, kDoorAppliqueColor);
    expect(paper.color, WorldTheme.paperDiorama.path);
    expect(paper.originU, 3);
  });

  test('corner outdoor path does not open a door', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    final appliques = VolumeAppliqueStore();
    expect(volumes.startNew(2, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    expect(paths.placeAndJoin(3, 1), isTrue);
    expect(paths.placeAndJoin(2, 2), isTrue);

    expect(
      syncVolumeDoorsFromPaths(
        volumes: volumes,
        paths: paths,
        appliques: appliques,
      ),
      isFalse,
    );
    expect(volumes.volumes.single.cells.single.accessibleSides, isEmpty);
    expect(appliques.items, isEmpty);
  });

  test('door opens only on the side whose shared neighbor already has a path',
      () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    final appliques = VolumeAppliqueStore();
    expect(volumes.startNew(2, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    expect(paths.placeAndJoin(3, 2), isTrue);
    expect(paths.placeAndJoin(3, 1), isTrue);
    expect(paths.placeAndJoin(2, 2), isTrue);

    syncVolumeDoorsFromPaths(
      volumes: volumes,
      paths: paths,
      appliques: appliques,
    );
    expect(
      volumes.volumes.single.cells.single.accessibleSides,
      {VolumeSide.east},
    );
  });

  test('wall on the boundary removes the door', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    final walls = WallStore(grid: volumes.grid);
    final appliques = VolumeAppliqueStore();
    expect(volumes.startNew(2, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    expect(paths.placeAndJoin(3, 2), isTrue);
    expect(paths.placeAndJoin(2, 2), isTrue);
    syncVolumeDoorsFromPaths(
      volumes: volumes,
      paths: paths,
      appliques: appliques,
      walls: walls,
    );
    expect(volumes.volumes.single.cells.single.accessibleSides, isNotEmpty);

    final edge = WallEdge(3, 2, 3, 3);
    expect(isVolumePathBoundary(edge, volumes), isTrue);
    expect(volumeDoorAcross(edge, volumes), isTrue);
    expect(walls.add(edge), isTrue);
    expect(paths.severAcross(edge), isTrue);
    expect(
      syncVolumeDoorsFromPaths(
        volumes: volumes,
        paths: paths,
        appliques: appliques,
        walls: walls,
      ),
      isTrue,
    );
    expect(volumes.volumes.single.cells.single.accessibleSides, isEmpty);
    expect(appliques.items, isEmpty);
  });

  test('placing a path on the volume again clears the wall and restores the door',
      () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    final walls = WallStore(grid: volumes.grid);
    final appliques = VolumeAppliqueStore();
    expect(volumes.startNew(2, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    expect(paths.placeAndJoin(3, 2), isTrue);
    expect(paths.placeAndJoin(2, 2), isTrue);
    syncVolumeDoorsFromPaths(
      volumes: volumes,
      paths: paths,
      appliques: appliques,
      walls: walls,
    );
    final edge = WallEdge(3, 2, 3, 3);
    walls.add(edge);
    paths.severAcross(edge);
    syncVolumeDoorsFromPaths(
      volumes: volumes,
      paths: paths,
      appliques: appliques,
      walls: walls,
    );
    expect(volumes.volumes.single.cells.single.accessibleSides, isEmpty);

    expect(paths.placeAndJoin(2, 2, walls: walls), isTrue);
    expect(walls.contains(edge), isFalse);
    syncVolumeDoorsFromPaths(
      volumes: volumes,
      paths: paths,
      appliques: appliques,
      walls: walls,
    );
    expect(
      volumes.volumes.single.cells.single.accessibleSides,
      {VolumeSide.east},
    );
  });

  test('removing the outdoor path removes the door', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    final appliques = VolumeAppliqueStore();
    expect(volumes.startNew(2, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    expect(paths.placeAndJoin(3, 2), isTrue);
    expect(paths.placeAndJoin(2, 2), isTrue);
    syncVolumeDoorsFromPaths(
      volumes: volumes,
      paths: paths,
      appliques: appliques,
    );
    expect(paths.removeTile(3, 2), isTrue);
    expect(
      syncVolumeDoorsFromPaths(
        volumes: volumes,
        paths: paths,
        appliques: appliques,
      ),
      isTrue,
    );
    expect(volumes.volumes.single.cells.single.accessibleSides, isEmpty);
    expect(appliques.items, isEmpty);
  });

  test('path tool on a volume with no outdoor neighbor is a no-op', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    expect(volumes.startNew(2, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    expect(
      canPaintPathAt(volumes: volumes, paths: paths, tx: 2, ty: 2),
      isFalse,
    );
    expect(paths.placeAndJoin(2, 2), isTrue);
    expect(
      syncVolumeDoorsFromPaths(
        volumes: volumes,
        paths: paths,
        appliques: VolumeAppliqueStore(),
      ),
      isFalse,
    );
    expect(volumes.volumes.single.cells.single.accessibleSides, isEmpty);
  });

  test('volume on a path tile evicts that path and does not auto-door', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    final appliques = VolumeAppliqueStore();
    expect(paths.placeAndJoin(2, 2), isTrue);
    expect(paths.placeAndJoin(3, 2), isTrue);
    expect(volumes.startNew(2, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    expect(paths.removeTile(2, 2), isTrue);
    expect(paths.contains(2, 2), isFalse);
    expect(paths.contains(3, 2), isTrue);
    syncVolumeDoorsFromPaths(
      volumes: volumes,
      paths: paths,
      appliques: appliques,
    );
    expect(volumes.volumes.single.cells.single.accessibleSides, isEmpty);
  });

  test('painting a path onto the volume opens a door', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    final appliques = VolumeAppliqueStore();
    expect(volumes.startNew(2, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    expect(paths.paintStroke((1, 2), (2, 2)), isTrue);
    expect(paths.contains(1, 2), isTrue);
    expect(paths.contains(2, 2), isTrue);
    syncVolumeDoorsFromPaths(
      volumes: volumes,
      paths: paths,
      appliques: appliques,
    );
    expect(
      volumes.volumes.single.cells.single.accessibleSides,
      {VolumeSide.west},
    );
  });

  test('shared interior sides never get a path door', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    final appliques = VolumeAppliqueStore();
    expect(volumes.startNew(1, 1), isTrue);
    expect(volumes.paintAt(2, 1), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    expect(paths.placeAndJoin(3, 1), isTrue);
    expect(paths.placeAndJoin(2, 1), isTrue);
    syncVolumeDoorsFromPaths(
      volumes: volumes,
      paths: paths,
      appliques: appliques,
    );
    final west = volumes.volumes.single.cellAt(1, 1)!;
    final east = volumes.volumes.single.cellAt(2, 1)!;
    expect(west.accessibleSides.contains(VolumeSide.east), isFalse);
    expect(east.accessibleSides, {VolumeSide.east});
  });

  test('moving a path-backed door keeps it and updates the applique', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    final appliques = VolumeAppliqueStore();
    expect(volumes.startNew(2, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    expect(paths.placeAndJoin(3, 2), isTrue);
    expect(paths.placeAndJoin(2, 2), isTrue);
    syncVolumeDoorsFromPaths(
      volumes: volumes,
      paths: paths,
      appliques: appliques,
    );
    final volume = volumes.volumes.single;
    final cell = volume.cells.single;
    expect(
      volumes.placeDoor(
        volume: volume,
        cell: cell,
        side: VolumeSide.east,
        originU: 0,
      ),
      isTrue,
    );
    appliques.placeOrMoveDoor(
      volume: volume,
      cell: cell,
      side: VolumeSide.east,
      door: volumeDoorForSide(cell.box, VolumeSide.east, originU: 0)!,
    );
    syncVolumeDoorsFromPaths(
      volumes: volumes,
      paths: paths,
      appliques: appliques,
    );
    expect(cell.doorOrigins[VolumeSide.east], 0);
    expect(
      appliques.doorOn(volumeId: volume.id, tx: 2, ty: 2, side: VolumeSide.east)!
          .originU,
      0,
    );
  });
}
