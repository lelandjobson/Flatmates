import 'package:flatmates/crafting/placed_paper.dart';
import 'package:flatmates/gameplay/paint/face_paint_store.dart';
import 'package:flatmates/gameplay/viewers/world_plane.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_solid.dart';
import 'package:flatmates/gameplay/volumes/volume_solid_sync.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flatmates/gameplay/walls/wall_edge.dart';
import 'package:flatmates/gameplay/walls/wall_store.dart';
import 'package:flutter_test/flutter_test.dart';

Volume _mass(VolumeStore store) {
  expect(store.volumes, hasLength(1));
  return store.volumes.single;
}

void main() {
  test('2x1 merge swallows the shared wall and keeps other exteriors', () {
    final volumes = VolumeStore();
    expect(volumes.paintAt(1, 1), isTrue);
    expect(volumes.paintAt(2, 1), isTrue);
    final volume = _mass(volumes);
    final solid = resolveVolumeSolid(volume, volumes.grid);

    expect(solid.indoorTiles, {(1, 1), (2, 1)});
    expect(solid.holeTiles, isEmpty);
    expect(solid.isHandleFullyInternal(1, 1, VolumeHandle.posX), isTrue);
    expect(solid.isHandleFullyInternal(2, 1, VolumeHandle.negX), isTrue);
    expect(solid.isHandleFullyInternal(1, 1, VolumeHandle.negX), isFalse);
    expect(solid.isHandleFullyInternal(2, 1, VolumeHandle.posX), isFalse);
    expect(solid.isHandleFullyInternal(1, 1, VolumeHandle.posZ), isFalse);
    expect(solid.isHandleFullyInternal(1, 1, VolumeHandle.negZ), isFalse);
    expect(solid.courtyardWalls(), isEmpty);
  });

  test('removing the center of a 3x3 makes a donut with courtyard walls', () {
    final volumes = VolumeStore();
    for (var ty = 1; ty <= 3; ty++) {
      for (var tx = 1; tx <= 3; tx++) {
        expect(volumes.paintAt(tx, ty), isTrue);
      }
    }
    expect(volumes.commitKeepFocus(), isTrue);
    expect(volumes.volumes.single.cells, hasLength(9));
    expect(volumes.removeCellAt(2, 2), isTrue);
    final volume = _mass(volumes);
    final solid = resolveVolumeSolid(volume, volumes.grid);

    expect(solid.indoorTiles, hasLength(8));
    expect(solid.indoorTiles.contains((2, 2)), isFalse);
    expect(solid.holeTiles, {(2, 2)});

    expect(solid.isHandleFullyInternal(2, 1, VolumeHandle.posZ), isFalse);
    expect(
      solid.surfaceAt(2, 1, VolumeHandle.posZ)?.enclosure,
      VolumeEnclosure.courtyard,
    );
    expect(
      solid.surfaceAt(2, 3, VolumeHandle.negZ)?.enclosure,
      VolumeEnclosure.courtyard,
    );
    expect(
      solid.surfaceAt(1, 2, VolumeHandle.posX)?.enclosure,
      VolumeEnclosure.courtyard,
    );
    expect(
      solid.surfaceAt(3, 2, VolumeHandle.negX)?.enclosure,
      VolumeEnclosure.courtyard,
    );
    expect(solid.courtyardWalls(), hasLength(4));

    expect(solid.isHandleFullyInternal(1, 1, VolumeHandle.posX), isTrue);
    expect(solid.isHandleFullyInternal(1, 1, VolumeHandle.posZ), isTrue);
    expect(
      solid.surfaceAt(1, 1, VolumeHandle.negX)?.enclosure,
      VolumeEnclosure.outer,
    );
  });

  test('height mismatch only swallows the overlapping wall rectangle', () {
    final volumes = VolumeStore();
    expect(volumes.paintAt(2, 2), isTrue);
    expect(volumes.paintAt(3, 2), isTrue);
    final volume = _mass(volumes);
    final short = volume.cellAt(3, 2)!;
    short.box.heightSubtiles = 3;
    final solid = resolveVolumeSolid(volume, volumes.grid);

    expect(solid.isHandleFullyInternal(3, 2, VolumeHandle.negX), isTrue);
    expect(solid.isHandleFullyInternal(2, 2, VolumeHandle.posX), isFalse);
    final leftover = solid.surfaceAt(2, 2, VolumeHandle.posX);
    expect(leftover, isNotNull);
    expect(leftover!.isComplete, isFalse);
    expect(leftover.remainingArea, 8 * 3);
    expect(leftover.enclosure, VolumeEnclosure.outer);
  });

  test('paint on a swallowed face is pruned; new courtyard faces stay empty', () {
    final volumes = VolumeStore();
    final paint = FacePaintStore();
    expect(volumes.paintAt(1, 1), isTrue);
    expect(volumes.paintAt(2, 1), isTrue);
    volumes.commitKeepFocus();
    final left = volumes.volumes.single.cellAt(1, 1)!;
    final canvas = paint.canvasFor(
      volumeId: volumes.volumes.single.id,
      cell: left,
      face: VolumeFace.posX,
    );
    expect(canvas.paint(0, 0, PaperColor.pink), isTrue);
    expect(paint.canvases, hasLength(1));

    paint.prune(volumes);
    expect(paint.canvases, isEmpty);

    for (var ty = 1; ty <= 3; ty++) {
      for (var tx = 1; tx <= 3; tx++) {
        volumes.paintAt(tx, ty);
      }
    }
    volumes.commitKeepFocus();
    volumes.removeCellAt(2, 2);
    final ring = volumes.volumes.single;
    final south = ring.cellAt(2, 1)!;
    paint.canvasFor(
      volumeId: ring.id,
      cell: south,
      face: VolumeFace.posZ,
    ).paint(1, 1, PaperColor.yellow);
    paint.prune(volumes);
    final courtyard = paint.canvases[FacePaintKey(
      volumeId: ring.id,
      tx: 2,
      ty: 1,
      face: VolumeFace.posZ,
    )];
    expect(courtyard, isNotNull);
    expect(courtyard!.colorAt(1, 1), PaperColor.yellow);

    final swallowed = paint.canvases[FacePaintKey(
      volumeId: ring.id,
      tx: 1,
      ty: 1,
      face: VolumeFace.posX,
    )];
    expect(swallowed, isNull);
  });

  test('walls on a now-shared edge are removed', () {
    final volumes = VolumeStore();
    final walls = WallStore(grid: volumes.grid);
    expect(volumes.paintAt(1, 1), isTrue);
    volumes.commitKeepFocus();
    expect(
      walls.add(WallEdge(2, 1, 2, 2)),
      isTrue,
    );
    expect(volumes.paintAt(2, 1), isTrue);
    volumes.commitKeepFocus();
    expect(stripSharedVolumeWalls(walls, volumes), 1);
    expect(walls.edges, isEmpty);
  });

  test('internal door flags are cleared after a merge', () {
    final volumes = VolumeStore();
    expect(volumes.paintAt(1, 1), isTrue);
    volumes.commitKeepFocus();
    final first = volumes.volumes.single;
    expect(
      volumes.placeDoor(
        volume: first,
        cell: first.cells.single,
        side: VolumeSide.east,
        originU: 3,
      ),
      isTrue,
    );
    expect(volumes.paintAt(2, 1), isTrue);
    volumes.commitKeepFocus();
    final merged = volumes.volumes.single;
    final solid = resolveVolumeSolid(merged, volumes.grid);
    clearInternalDoors(merged, solid);
    expect(merged.cellAt(1, 1)!.accessibleSides.contains(VolumeSide.east), isFalse);
    expect(merged.cellAt(1, 1)!.doorOrigins.containsKey(VolumeSide.east), isFalse);
  });
}
