import 'package:flatmates/gameplay/eraser/erase_preview.dart';
import 'package:flatmates/gameplay/eraser/eraser_filter.dart';
import 'package:flatmates/gameplay/paths/path_store.dart';
import 'package:flatmates/gameplay/picking/selectable.dart';
import 'package:flatmates/gameplay/viewers/world_plane.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flatmates/gameplay/walls/wall_edge.dart';
import 'package:flatmates/gameplay/walls/wall_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('erase all on tile lists every enabled kind', () {
    final volumes = VolumeStore();
    expect(volumes.startNew(3, 3), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    final paths = PathStore(grid: volumes.grid)..addIsland(3, 3);
    final walls = WallStore(grid: volumes.grid)..add(WallEdge(3, 3, 4, 3));
    final preview = erasePreviewAt(
      tx: 3,
      ty: 3,
      filter: EraserFilter(),
      volumes: volumes,
      paths: paths,
      walls: walls,
    );
    expect(preview.hits.map((h) => h.kind), [
      SelectableKind.volume,
      SelectableKind.path,
    ]);
    expect(preview.walls, [WallEdge(3, 3, 4, 3)]);
  });

  test('primary-only preview follows the selected path', () {
    final volumes = VolumeStore();
    expect(volumes.startNew(3, 3), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    final paths = PathStore(grid: volumes.grid)..addIsland(3, 3);
    final walls = WallStore(grid: volumes.grid)..add(WallEdge(3, 3, 4, 3));
    final preview = erasePreviewAt(
      tx: 3,
      ty: 3,
      filter: EraserFilter(eraseAllOnTile: false),
      volumes: volumes,
      paths: paths,
      walls: walls,
      primary: SelectableHit.path(3, 3),
    );
    expect(preview.hits, hasLength(1));
    expect(preview.hits.single.kind, SelectableKind.path);
    expect(preview.walls, isEmpty);
  });

  test('kind filters hide disabled objects from erase-all preview', () {
    final volumes = VolumeStore();
    expect(volumes.startNew(3, 3), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    final paths = PathStore(grid: volumes.grid)..addIsland(3, 3);
    final walls = WallStore(grid: volumes.grid)..add(WallEdge(3, 3, 4, 3));
    final preview = erasePreviewAt(
      tx: 3,
      ty: 3,
      filter: EraserFilter(volumes: false, walls: false),
      volumes: volumes,
      paths: paths,
      walls: walls,
    );
    expect(preview.hits.map((h) => h.kind), [SelectableKind.path]);
    expect(preview.walls, isEmpty);
  });

  test('volume preview is the hovered cell, not the joined solid', () {
    final volumes = VolumeStore();
    expect(volumes.startNew(2, 2), isTrue);
    expect(volumes.paintAt(3, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    final volume = volumes.volumes.single;
    expect(volume.cells, hasLength(2));
    final preview = erasePreviewAt(
      tx: 3,
      ty: 2,
      filter: EraserFilter(eraseAllOnTile: false, paths: false, walls: false),
      volumes: volumes,
      paths: PathStore(grid: volumes.grid),
      walls: WallStore(grid: volumes.grid),
      primary: SelectableHit.volumeFace(
        volume.id,
        face: VolumeFace.posX,
        cell: volume.cellAt(3, 2),
      ),
    );
    expect(preview.hits, hasLength(1));
    expect(preview.hits.single.kind, SelectableKind.volume);
    expect(preview.hits.single.cell?.tx, 3);
    expect(preview.hits.single.cell?.ty, 2);
    expect(preview.hits.single.volumeId, volume.id);
  });
}
