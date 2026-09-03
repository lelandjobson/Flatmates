import 'package:flatmates/gameplay/viewers/world_plane.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_applique.dart';
import 'package:flatmates/gameplay/volumes/volume_door.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bare wall samples as -1 so the first paper is layer 0', () {
    final store = VolumeAppliqueStore();
    expect(
      store.maxLayerInRect(
        volumeId: 1,
        tx: 2,
        ty: 2,
        face: VolumeFace.posZ,
        originU: 3,
        originV: 0,
        width: 2,
        height: 4,
      ),
      -1,
    );
  });

  test('door applique sits one layer above the sampled wall', () {
    final volumes = VolumeStore();
    expect(volumes.startNew(2, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    final volume = volumes.volumes.single;
    final cell = volume.cells.single;
    final door = volumeDoorForSide(cell.box, VolumeSide.south)!;
    final appliques = VolumeAppliqueStore();
    final paper = appliques.placeOrMoveDoor(
      volume: volume,
      cell: cell,
      side: VolumeSide.south,
      door: door,
    );
    expect(paper.layer, 0);
    expect(paper.kind, VolumeAppliqueKind.door);
    expect(paper.color, kDoorAppliqueColor);
    expect(paper.originU, door.originU);
    expect(
      appliques.maxLayerInRect(
        volumeId: volume.id,
        tx: cell.tx,
        ty: cell.ty,
        face: VolumeFace.posZ,
        originU: door.originU,
        originV: 0,
        width: door.width,
        height: door.height,
      ),
      0,
    );
  });

  test('a second paper over the door samples the door and stacks above it', () {
    final volumes = VolumeStore();
    expect(volumes.startNew(2, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    final volume = volumes.volumes.single;
    final cell = volume.cells.single;
    final door = volumeDoorForSide(cell.box, VolumeSide.south)!;
    final appliques = VolumeAppliqueStore();
    appliques.placeOrMoveDoor(
      volume: volume,
      cell: cell,
      side: VolumeSide.south,
      door: door,
    );
    final stacked = appliques.add(
      VolumeApplique(
        id: 0,
        volumeId: volume.id,
        tx: cell.tx,
        ty: cell.ty,
        face: VolumeFace.posZ,
        layer: appliques.nextLayerAbove(
          cell: cell,
          volumeId: volume.id,
          face: VolumeFace.posZ,
          originU: door.originU,
          originV: 0,
          width: 1,
          height: 1,
        ),
        originU: door.originU,
        originV: 0,
        width: 1,
        height: 1,
        kind: VolumeAppliqueKind.door,
        color: kDoorAppliqueColor,
      ),
    );
    expect(stacked.layer, 1);
  });

  test('moving a door re-layers above whatever is now behind it', () {
    final volumes = VolumeStore();
    expect(volumes.startNew(2, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    final volume = volumes.volumes.single;
    final cell = volume.cells.single;
    final appliques = VolumeAppliqueStore();
    appliques.add(
      VolumeApplique(
        id: 0,
        volumeId: volume.id,
        tx: cell.tx,
        ty: cell.ty,
        face: VolumeFace.posZ,
        layer: 0,
        originU: 0,
        originV: 0,
        width: 2,
        height: 4,
        kind: VolumeAppliqueKind.door,
        color: kDoorAppliqueColor,
      ),
    );
    final moved = appliques.placeOrMoveDoor(
      volume: volume,
      cell: cell,
      side: VolumeSide.south,
      door: const VolumeDoor(
        side: VolumeSide.south,
        originU: 0,
        originY: 0,
        width: 2,
        height: 4,
      ),
    );
    expect(moved.layer, 1);
    expect(moved.originU, 0);
  });
}
