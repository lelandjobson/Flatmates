import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../rendering/mesh.dart';
import '../../rendering/scene/scene.dart';
import '../../geometry/geometry.dart';
import '../volumes/volume_store.dart';
import '../volumes/volume_box_mesh.dart';
import 'path_shape.dart';
import 'path_store.dart';

const _kPathColor = Color(0xFFBCAAA4);
const kPathHeight = 0.35;

String pathMeshId(int tx, int ty, int piece) => 'path_${tx}_${ty}_$piece';

/// Syncs low path boxes on [scene] to match user paths and in_out door stubs.
void syncPathMeshes(Scene scene, PathStore store, VolumeStore volumes) {
  final wanted = <String>{};
  final grid = store.grid;
  final s = grid.subtileSize;
  final byTile = pathFootprintsByTile(volumes: volumes, paths: store);

  for (final entry in byTile.entries) {
    final (tx, ty) = entry.key;
    final origin = grid.tileOrigin(tx, ty);
    final pieces = entry.value;
    for (var i = 0; i < pieces.length; i++) {
      final p = pieces[i];
      final id = pathMeshId(tx, ty, i);
      wanted.add(id);
      final min = Vector3(
        origin.x + p.originXSubtiles * s,
        0,
        origin.z + p.originZSubtiles * s,
      );
      final max = Vector3(
        origin.x + (p.originXSubtiles + p.widthSubtiles) * s,
        kPathHeight,
        origin.z + (p.originZSubtiles + p.depthSubtiles) * s,
      );
      final geometry = volumeBoxGeometry(min: min, max: max, id: id);
      final existing = scene.meshById(id);
      if (existing == null) {
        scene.addMesh(
          Mesh(
            id: id,
            name: 'Path',
            geometry: geometry,
            material: const MaterialModel(
              color: _kPathColor,
              wireframe: true,
              doubleSided: true,
            ),
          ),
        );
      } else {
        existing.geometry = geometry;
        existing.material = const MaterialModel(
          color: _kPathColor,
          wireframe: true,
          doubleSided: true,
        );
      }
    }
  }

  for (final mesh in List<Mesh>.from(scene.meshes)) {
    if (mesh.id.startsWith('path_') && !wanted.contains(mesh.id)) {
      scene.removeMeshById(mesh.id);
    }
  }
  scene.markNeedsPaint();
}
