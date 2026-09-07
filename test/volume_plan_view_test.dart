import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_box_mesh.dart';
import 'package:flatmates/gameplay/volumes/volume_datum.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flatmates/rendering/scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

VolumeStore _groundAndUpper() {
  final volumes = VolumeStore();
  expect(volumes.paintAt(2, 2), isTrue);
  expect(volumes.paintAt(3, 2), isTrue);
  expect(volumes.volumes, hasLength(1));
  volumes.volumes.add(
    Volume(
      id: 99,
      datum: 1,
      cells: [VolumeCell(tx: 6, ty: 6, box: BoxPrimitive())],
    ),
  );
  return volumes;
}

void main() {
  test('plan view hides every mass above the focused datum, even zoomed out', () {
    expect(
      volumeHiddenAboveDatum(volumeDatum: 1, currentDatum: 0),
      isTrue,
    );
    expect(
      volumeHiddenAboveDatum(volumeDatum: 0, currentDatum: 0),
      isFalse,
    );
    expect(
      volumeAboveCurrentDatum(
        volumeDatum: 1,
        currentDatum: 0,
        zoomedIn: false,
      ),
      isFalse,
    );

    final volumes = _groundAndUpper();
    expect(
      hiddenVolumeIdsAboveDatum(volumes: volumes.visibleVolumes, datum: 0),
      {99},
    );
    expect(
      hideCeilingVolumeIdsAtDatum(volumes: volumes.visibleVolumes, datum: 0),
      {volumes.volumes.first.id},
    );
    expect(
      hideCeilingVolumeIdsAtDatum(volumes: volumes.visibleVolumes, datum: 1),
      {99},
    );
  });

  test('plan view drops upper-story meshes and all roofs on the focused story', () {
    final volumes = _groundAndUpper();
    final groundId = volumes.volumes.first.id;
    final scene = Scene();
    addTearDown(scene.dispose);
    syncVolumeMeshes(
      scene,
      volumes,
      hiddenByDatumVolumeIds: hiddenVolumeIdsAboveDatum(
        volumes: volumes.visibleVolumes,
        datum: 0,
      ),
      hideCeilingVolumeIds: hideCeilingVolumeIdsAtDatum(
        volumes: volumes.visibleVolumes,
        datum: 0,
      ),
    );
    expect(scene.meshById(volumeMeshId(99, 6, 6)), isNull);
    expect(scene.meshById(volumeMeshId(groundId, 2, 2)), isNotNull);
    expect(scene.meshById(volumeMeshId(groundId, 3, 2)), isNotNull);
  });
}
