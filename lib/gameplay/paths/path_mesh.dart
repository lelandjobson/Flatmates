import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../rendering/mesh.dart';
import '../../rendering/scene/scene.dart';
import '../../geometry/geometry.dart';
import '../../theme/world_theme.dart';
import '../volumes/volume_store.dart';
import 'path_shape.dart';
import 'path_store.dart';

/// Paths are ground-plane outlines, not extruded boxes.
const kPathHeight = 0.0;

String pathMeshId(int tx, int ty, int piece) => 'path_${tx}_${ty}_$piece';

/// Ground-plane rectangle. Winding faces +Y so the isometric camera sees it.
Geometry pathOutlineGeometry({
  required Vector3 min,
  required Vector3 max,
  required String id,
}) {
  final y = min.y;
  return Geometry(
    id: id,
    name: 'PathOutline',
    vertices: [
      Vector3(min.x, y, min.z),
      Vector3(max.x, y, min.z),
      Vector3(max.x, y, max.z),
      Vector3(min.x, y, max.z),
    ],
    faces: const [
      [0, 3, 2, 1],
    ],
  );
}

/// Syncs flat path outlines on [scene] to match user paths and in_out door stubs.
void syncPathMeshes(
  Scene scene,
  PathStore store,
  VolumeStore volumes, {
  Color? color,
}) {
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
        kPathHeight,
        origin.z + p.originZSubtiles * s,
      );
      final max = Vector3(
        origin.x + (p.originXSubtiles + p.widthSubtiles) * s,
        kPathHeight,
        origin.z + (p.originZSubtiles + p.depthSubtiles) * s,
      );
      final geometry = pathOutlineGeometry(min: min, max: max, id: id);
      final pathColor = color ?? WorldTheme.paperDiorama.path;
      final material = MaterialModel(
        color: pathColor,
        wireframe: false,
        doubleSided: true,
        strokeEdges: false,
        surfaceGrid: false,
      );
      final existing = scene.meshById(id);
      if (existing == null) {
        scene.addMesh(
          Mesh(
            id: id,
            name: 'Path',
            geometry: geometry,
            material: material,
            groundPlane: true,
          ),
        );
      } else {
        existing.geometry = geometry;
        existing.material = material;
        existing.groundPlane = true;
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
