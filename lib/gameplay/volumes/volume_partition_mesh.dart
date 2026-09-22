import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../geometry/geometry.dart';
import '../../rendering/mesh.dart';
import '../../rendering/scene/scene.dart';
import '../../theme/world_theme.dart';
import 'volume.dart';
import 'volume_door.dart';
import 'volume_partition.dart';
import 'volume_program.dart';
import 'volume_store.dart';

/// 5-high partition with a centered door punch-out.
Geometry partitionWallGeometry({
  required ProgramPartition partition,
  required VolumeGrid grid,
  required String id,
}) {
  final s = grid.subtileSize;
  final origin = grid.tileOrigin(partition.tx0, partition.ty0);
  final y0 = 0.0;
  final yH = kPartitionHeightSubtiles * s;
  final u0 = partition.u0 * s;
  final u1 = partition.u1 * s;
  final door = partition.door;

  late final double plane;
  late final double along0;
  late final double along1;
  late final Vector3 Function(double along, double y) point;
  switch (partition.side) {
    case VolumeSide.east:
      plane = origin.x + grid.tileSize;
      along0 = origin.z + u0;
      along1 = origin.z + u1;
      point = (along, y) => Vector3(plane, y, along);
    case VolumeSide.south:
      plane = origin.z + grid.tileSize;
      along0 = origin.x + u0;
      along1 = origin.x + u1;
      point = (along, y) => Vector3(along, y, plane);
    case VolumeSide.west:
    case VolumeSide.north:
      throw ArgumentError.value(
        partition.side,
        'side',
        'Partitions are stored on the east or south of the lesser tile',
      );
  }

  final vertices = <Vector3>[];
  final faces = <List<int>>[];

  void poly(List<Vector3> pts) {
    if (pts.length < 3) return;
    final i = vertices.length;
    vertices.addAll(pts);
    faces.add([for (var k = 0; k < pts.length; k++) i + k]);
  }

  if (door == null || !_doorOverlapsWall(partition, door)) {
    poly([
      point(along0, y0),
      point(along0, yH),
      point(along1, yH),
      point(along1, y0),
    ]);
  } else {
    final d0 = _originAlong(partition, grid, door.originU);
    final d1 = _originAlong(partition, grid, door.originU + door.width);
    final yD1 = (door.originY + door.height) * s;
    switch (partition.side) {
      case VolumeSide.east:
        poly([
          point(along0, y0),
          point(along0, yH),
          point(along1, yH),
          point(along1, y0),
          point(d1, y0),
          point(d1, yD1),
          point(d0, yD1),
          point(d0, y0),
        ]);
      case VolumeSide.south:
        poly([
          point(along0, y0),
          point(d0, y0),
          point(d0, yD1),
          point(d1, yD1),
          point(d1, y0),
          point(along1, y0),
          point(along1, yH),
          point(along0, yH),
        ]);
      case VolumeSide.west:
      case VolumeSide.north:
        break;
    }
  }

  return Geometry(
    id: id,
    name: 'ProgramPartition',
    vertices: vertices,
    faces: faces,
  );
}

double _originAlong(ProgramPartition partition, VolumeGrid grid, int u) {
  final origin = grid.tileOrigin(partition.tx0, partition.ty0);
  final s = grid.subtileSize;
  return switch (partition.side) {
    VolumeSide.east || VolumeSide.west => origin.z + u * s,
    VolumeSide.north || VolumeSide.south => origin.x + u * s,
  };
}

bool _doorOverlapsWall(ProgramPartition partition, VolumeDoor door) {
  final lo = partition.u0 > door.originU ? partition.u0 : door.originU;
  final hi = partition.u1 < door.originU + door.width
      ? partition.u1
      : door.originU + door.width;
  return hi > lo;
}

/// Syncs one double-sided ghost mesh per program partition.
void syncPartitionMeshes(
  Scene scene,
  VolumeStore volumes,
  VolumeProgramStore programs, {
  Color? color,
  Set<int> hiddenByDatumVolumeIds = const {},
}) {
  final wanted = <String>{};
  final fill = color ?? WorldTheme.paperDiorama.volume;
  for (final partition in collectProgramPartitions(volumes, programs)) {
    if (hiddenByDatumVolumeIds.contains(partition.volumeId)) continue;
    final id = partition.meshId;
    wanted.add(id);
    final geometry = partitionWallGeometry(
      partition: partition,
      grid: volumes.grid,
      id: id,
    );
    final material = MaterialModel(
      color: fill,
      opacity: kPartitionOpacity,
      doubleSided: true,
      strokeEdges: true,
    );
    final existing = scene.meshById(id);
    if (existing == null) {
      scene.addMesh(
        Mesh(
          id: id,
          name: 'Partition',
          geometry: geometry,
          material: material,
        ),
      );
    } else {
      existing.geometry = geometry;
      existing.material = material;
    }
  }
  for (final mesh in List<Mesh>.from(scene.meshes)) {
    if (mesh.id.startsWith('partition_') && !wanted.contains(mesh.id)) {
      scene.removeMeshById(mesh.id);
    }
  }
  scene.markNeedsPaint();
}
