import 'package:flatmates/gameplay/volumes/volume_partition.dart';
import 'package:flatmates/gameplay/volumes/volume_partition_mesh.dart';
import 'package:flatmates/gameplay/volumes/volume_program.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flatmates/rendering/scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

bool _evenOddContains(List<Vector3> ring, double x, double y) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final yi = ring[i].y;
    final yj = ring[j].y;
    final xi = ring[i].x;
    final xj = ring[j].x;
    final intersect =
        ((yi > y) != (yj > y)) &&
        (x < (xj - xi) * (y - yi) / (yj - yi + 0.0) + xi);
    if (intersect) inside = !inside;
  }
  return inside;
}

void main() {
  test('partition mesh is 5 high with a door punch-out', () {
    final volumes = VolumeStore();
    expect(volumes.paintAt(2, 2), isTrue);
    expect(volumes.paintAt(3, 2), isTrue);
    final programs = VolumeProgramStore()
      ..assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom);
    final partition = collectProgramPartitions(volumes, programs).single;
    final geom = partitionWallGeometry(
      partition: partition,
      grid: volumes.grid,
      id: partition.meshId,
    );

    expect(geom.vertices, hasLength(8));
    expect(geom.faces.single, hasLength(8));
    expect(
      geom.vertices.every((v) => v.y <= kPartitionHeightSubtiles + 1e-9),
      isTrue,
    );
    expect(geom.vertices.any((v) => (v.y - 5).abs() < 1e-9), isTrue);
    expect(geom.vertices.any((v) => (v.y - 4).abs() < 1e-9), isTrue);

    final doorZ = volumes.grid.tileOrigin(2, 2).z + 4;
    final doorY = 2.0;
    final planeX = volumes.grid.tileOrigin(3, 2).x;
    expect(
      geom.vertices.every((v) => (v.x - planeX).abs() < 1e-9),
      isTrue,
    );
    final ring = [
      for (final i in geom.faces.single)
        Vector3(geom.vertices[i].z, geom.vertices[i].y, 0),
    ];
    expect(_evenOddContains(ring, doorZ, doorY), isFalse);
    expect(_evenOddContains(ring, doorZ, 4.5), isTrue);
  });

  test('synced partitions stay ghosted at 50% and are never omitted', () {
    final volumes = VolumeStore();
    expect(volumes.paintAt(2, 2), isTrue);
    expect(volumes.paintAt(3, 2), isTrue);
    final programs = VolumeProgramStore()
      ..assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom);
    final scene = Scene();
    addTearDown(scene.dispose);
    syncPartitionMeshes(scene, volumes, programs);
    final mesh = scene.meshById(partitionMeshId(2, 2, 3, 2));
    expect(mesh, isNotNull);
    expect(mesh!.material.opacity, kPartitionOpacity);
    expect(mesh.material.doubleSided, isTrue);
    expect(mesh.geometry.vertices.map((v) => v.y).reduce((a, b) => a > b ? a : b),
        closeTo(5, 1e-9));
  });

  test('hidden-by-datum volumes do not emit partition meshes', () {
    final volumes = VolumeStore();
    expect(volumes.paintAt(2, 2), isTrue);
    expect(volumes.paintAt(3, 2), isTrue);
    final programs = VolumeProgramStore()
      ..assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom);
    final scene = Scene();
    addTearDown(scene.dispose);
    syncPartitionMeshes(
      scene,
      volumes,
      programs,
      hiddenByDatumVolumeIds: {volumes.volumes.single.id},
    );
    expect(scene.meshById(partitionMeshId(2, 2, 3, 2)), isNull);
  });
}
