import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../geometry/geometry.dart';
import '../../geometry/geometries.dart';
import '../../rendering/mesh.dart';
import '../../rendering/scene/scene.dart';
import '../../theme/world_theme.dart';
import 'volume.dart';
import 'volume_door.dart';
import 'volume_store.dart';

String volumeMeshId(int volumeId, int tx, int ty) => 'volume_${volumeId}_${tx}_$ty';

Geometry volumeBoxGeometry({
  required Vector3 min,
  required Vector3 max,
  required String id,
  List<VolumeDoor> doors = const [],
  double subtileSize = 1,
}) {
  if (doors.isEmpty) {
    return Geometry(
      id: id,
      name: 'VolumeBox',
      vertices: [
        Vector3(min.x, min.y, min.z),
        Vector3(max.x, min.y, min.z),
        Vector3(max.x, max.y, min.z),
        Vector3(min.x, max.y, min.z),
        Vector3(min.x, min.y, max.z),
        Vector3(max.x, min.y, max.z),
        Vector3(max.x, max.y, max.z),
        Vector3(min.x, max.y, max.z),
      ],
      faces: GeometryBuilders.cubeFaces,
    );
  }

  final vertices = <Vector3>[
    Vector3(min.x, min.y, min.z),
    Vector3(max.x, min.y, min.z),
    Vector3(max.x, max.y, min.z),
    Vector3(min.x, max.y, min.z),
    Vector3(min.x, min.y, max.z),
    Vector3(max.x, min.y, max.z),
    Vector3(max.x, max.y, max.z),
    Vector3(min.x, max.y, max.z),
  ];
  final faces = <List<int>>[];
  final holed = {for (final door in doors) door.side};

  if (!holed.contains(VolumeSide.north)) {
    faces.add(List<int>.from(GeometryBuilders.cubeFaces[0]));
  }
  if (!holed.contains(VolumeSide.south)) {
    faces.add(List<int>.from(GeometryBuilders.cubeFaces[1]));
  }
  faces.add(List<int>.from(GeometryBuilders.cubeFaces[2])); // -Y floor
  faces.add(List<int>.from(GeometryBuilders.cubeFaces[3])); // +Y
  if (!holed.contains(VolumeSide.east)) {
    faces.add(List<int>.from(GeometryBuilders.cubeFaces[4]));
  }
  if (!holed.contains(VolumeSide.west)) {
    faces.add(List<int>.from(GeometryBuilders.cubeFaces[5]));
  }

  void poly(List<Vector3> pts) {
    final cleaned = <Vector3>[];
    for (final p in pts) {
      if (cleaned.isEmpty || cleaned.last.distanceTo(p) > 1e-8) {
        cleaned.add(p);
      }
    }
    if (cleaned.length >= 2 &&
        cleaned.first.distanceTo(cleaned.last) <= 1e-8) {
      cleaned.removeLast();
    }
    if (cleaned.length < 3) return;
    final i = vertices.length;
    vertices.addAll(cleaned);
    faces.add([for (var k = 0; k < cleaned.length; k++) i + k]);
  }

  for (final door in doors) {
    final s = subtileSize;
    final yD0 = min.y + door.originY * s;
    final yD1 = yD0 + door.height * s;
    switch (door.side) {
      case VolumeSide.east:
        {
          final x = max.x;
          final zD0 = min.z + door.originU * s;
          final zD1 = zD0 + door.width * s;
          poly([
            Vector3(x, min.y, min.z),
            Vector3(x, max.y, min.z),
            Vector3(x, max.y, max.z),
            Vector3(x, min.y, max.z),
            Vector3(x, min.y, zD1),
            Vector3(x, yD1, zD1),
            Vector3(x, yD1, zD0),
            Vector3(x, min.y, zD0),
          ]);
        }
      case VolumeSide.west:
        {
          final x = min.x;
          final zD0 = min.z + door.originU * s;
          final zD1 = zD0 + door.width * s;
          poly([
            Vector3(x, min.y, max.z),
            Vector3(x, max.y, max.z),
            Vector3(x, max.y, min.z),
            Vector3(x, min.y, min.z),
            Vector3(x, min.y, zD0),
            Vector3(x, yD1, zD0),
            Vector3(x, yD1, zD1),
            Vector3(x, min.y, zD1),
          ]);
        }
      case VolumeSide.south:
        {
          final z = max.z;
          final xD0 = min.x + door.originU * s;
          final xD1 = xD0 + door.width * s;
          poly([
            Vector3(min.x, min.y, z),
            Vector3(xD0, min.y, z),
            Vector3(xD0, yD1, z),
            Vector3(xD1, yD1, z),
            Vector3(xD1, min.y, z),
            Vector3(max.x, min.y, z),
            Vector3(max.x, max.y, z),
            Vector3(min.x, max.y, z),
          ]);
        }
      case VolumeSide.north:
        {
          final z = min.z;
          final xD0 = min.x + door.originU * s;
          final xD1 = xD0 + door.width * s;
          poly([
            Vector3(min.x, min.y, z),
            Vector3(min.x, max.y, z),
            Vector3(max.x, max.y, z),
            Vector3(max.x, min.y, z),
            Vector3(xD1, min.y, z),
            Vector3(xD1, yD1, z),
            Vector3(xD0, yD1, z),
            Vector3(xD0, min.y, z),
          ]);
        }
    }
  }

  return Geometry(
    id: id,
    name: 'VolumeBox',
    vertices: vertices,
    faces: faces,
  );
}

/// Syncs wireframe box meshes on [scene] to match [store].
void syncVolumeMeshes(
  Scene scene,
  VolumeStore store, {
  Color? committed,
  Color? draftColor,
}) {
  final wanted = <String>{};
  final draft = store.draftVolume;

  for (final volume in store.visibleVolumes) {
    final isDraftVolume = identical(volume, draft);
    for (final cell in volume.cells) {
      final id = volumeMeshId(volume.id, cell.tx, cell.ty);
      wanted.add(id);
      final isDraftCell =
          isDraftVolume && store.draftCell?.tx == cell.tx && store.draftCell?.ty == cell.ty;
      final min = cell.box.worldMin(store.grid, cell.tx, cell.ty);
      final max = cell.box.worldMax(store.grid, cell.tx, cell.ty);
      final doors = exteriorDoors(volume, cell).toList();
      final geometry = volumeBoxGeometry(
        min: min,
        max: max,
        id: id,
        doors: doors,
        subtileSize: store.grid.subtileSize,
      );
      final color = isDraftCell
          ? (draftColor ?? WorldTheme.paperDiorama.volumeDraft)
          : (committed ?? WorldTheme.paperDiorama.volume);
      final existing = scene.meshById(id);
      if (existing == null) {
        scene.addMesh(
          Mesh(
            id: id,
            name: 'Volume',
            geometry: geometry,
            material: MaterialModel(
              color: color,
              wireframe: true,
              doubleSided: true,
            ),
          ),
        );
      } else {
        existing.geometry = geometry;
        existing.material = MaterialModel(
          color: color,
          wireframe: true,
          doubleSided: true,
        );
      }
    }
  }

  for (final mesh in List<Mesh>.from(scene.meshes)) {
    if (mesh.id.startsWith('volume_') && !wanted.contains(mesh.id)) {
      scene.removeMeshById(mesh.id);
    }
  }
  scene.markNeedsPaint();
}
