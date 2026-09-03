import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../geometry/geometry.dart';
import '../../rendering/mesh.dart';
import '../../rendering/scene/scene.dart';
import '../../theme/world_theme.dart';
import 'wall_edge.dart';
import 'wall_store.dart';

/// Short fence: about one-fifth of a full volume height.
const kFenceHeight = 1.25;

String wallMeshId(WallEdge edge) =>
    'wall_${edge.x0}_${edge.y0}_${edge.x1}_${edge.y1}';

/// Degenerate AABB of the fence plane (zero thickness across the edge).
(Vector3 min, Vector3 max) wallWorldAabb(WallStore store, WallEdge edge) {
  final a = store.vertexWorld(edge.x0, edge.y0);
  final b = store.vertexWorld(edge.x1, edge.y1);
  if (edge.isHorizontal) {
    final z = a.z;
    final minX = a.x < b.x ? a.x : b.x;
    final maxX = a.x < b.x ? b.x : a.x;
    return (Vector3(minX, 0, z), Vector3(maxX, kFenceHeight, z));
  }
  final x = a.x;
  final minZ = a.z < b.z ? a.z : b.z;
  final maxZ = a.z < b.z ? b.z : a.z;
  return (Vector3(x, 0, minZ), Vector3(x, kFenceHeight, maxZ));
}

/// One vertical quad along [edge]. Drawn double-sided so corners meet on a
/// shared vertex instead of overlapping boxes.
Geometry wallFaceGeometry({
  required Vector3 a,
  required Vector3 b,
  required String id,
}) {
  return Geometry(
    id: id,
    name: 'WallFace',
    vertices: [
      Vector3(a.x, 0, a.z),
      Vector3(b.x, 0, b.z),
      Vector3(b.x, kFenceHeight, b.z),
      Vector3(a.x, kFenceHeight, a.z),
    ],
    faces: const [
      [0, 1, 2, 3],
    ],
  );
}

/// Syncs fence planes on [scene] to match [store].
void syncWallMeshes(
  Scene scene,
  WallStore store, {
  Color? color,
}) {
  final wanted = <String>{};
  final wallColor = color ?? WorldTheme.paperDiorama.wall;
  for (final edge in store.edges) {
    final id = wallMeshId(edge);
    wanted.add(id);
    final a = store.vertexWorld(edge.x0, edge.y0);
    final b = store.vertexWorld(edge.x1, edge.y1);
    final geometry = wallFaceGeometry(a: a, b: b, id: id);
    final material = MaterialModel(
      color: wallColor,
      wireframe: false,
      strokeEdges: false,
      doubleSided: true,
    );
    final existing = scene.meshById(id);
    if (existing == null) {
      scene.addMesh(
        Mesh(
          id: id,
          name: 'Wall',
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
    if (mesh.id.startsWith('wall_') && !wanted.contains(mesh.id)) {
      scene.removeMeshById(mesh.id);
    }
  }
  scene.markNeedsPaint();
}

/// Tiles that share [edge], used for focus-visibility.
List<(int, int)> tilesTouchingWall(WallEdge edge) {
  if (edge.isHorizontal) {
    return [
      (edge.x0, edge.y0 - 1),
      (edge.x0, edge.y0),
    ];
  }
  if (edge.isVertical) {
    return [
      (edge.x0 - 1, edge.y0),
      (edge.x0, edge.y0),
    ];
  }
  return const [];
}

WallEdge? wallEdgeFromMeshId(String id) {
  final parts = id.split('_');
  if (parts.length != 5 || parts[0] != 'wall') return null;
  final x0 = int.tryParse(parts[1]);
  final y0 = int.tryParse(parts[2]);
  final x1 = int.tryParse(parts[3]);
  final y1 = int.tryParse(parts[4]);
  if (x0 == null || y0 == null || x1 == null || y1 == null) return null;
  return WallEdge(x0, y0, x1, y1);
}
