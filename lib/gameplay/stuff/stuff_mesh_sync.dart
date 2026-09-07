import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../geometry/geometry.dart';
import '../../rendering/mesh.dart';
import '../../rendering/scene/scene.dart';
import '../volumes/volume_store.dart';
import 'stuff_catalog.dart';
import 'stuff_geometry.dart';
import 'stuff_hull.dart';
import 'stuff_instance.dart';
import 'stuff_store.dart';

const kStuffValidColor = Color(0xFFD8C4A0);
const kStuffInvalidColor = Color(0xFFE53935);
const kStuffGhostAlpha = 0.5;

String stuffMeshId(String id) => 'stuff_$id';

void syncStuffMeshes(
  Scene scene,
  StuffStore store, {
  VolumeStore? volumes,
  StuffInstance? ghost,
}) {
  final wanted = <String>{};
  for (final item in store.items) {
    final id = stuffMeshId(item.id);
    wanted.add(id);
    final valid = volumes == null || stuffIsValid(item, volumes);
    _upsert(
      scene,
      id: id,
      item: item,
      color: valid ? kStuffValidColor : kStuffInvalidColor,
    );
  }
  if (ghost != null) {
    const id = 'stuff_ghost';
    wanted.add(id);
    _upsert(
      scene,
      id: id,
      item: ghost,
      color: kStuffValidColor,
      opacity: kStuffGhostAlpha,
    );
  }
  for (final mesh in List<Mesh>.from(scene.meshes)) {
    if (mesh.id.startsWith('stuff_') && !wanted.contains(mesh.id)) {
      scene.removeMeshById(mesh.id);
    }
  }
  scene.markNeedsPaint();
}

void _upsert(
  Scene scene, {
  required String id,
  required StuffInstance item,
  required Color color,
  double opacity = 1,
}) {
  final geometry = stuffGeometry(item.specId);
  final euler = stuffEuler(item.face, item.yaw);
  final material = MaterialModel(
    color: color,
    doubleSided: true,
    wireframe: false,
    strokeEdges: false,
    opacity: opacity,
  );
  final existing = scene.meshById(id);
  if (existing == null) {
    scene.addMesh(
      Mesh(
        id: id,
        name: item.spec?.label ?? 'Stuff',
        geometry: geometry,
        material: material,
        position: Vector3.copy(item.origin),
        rotation: Vector3.copy(euler),
      ),
    );
    return;
  }
  existing.geometry = geometry;
  existing.material = material;
  existing.setPosition(item.origin);
  existing.setRotation(euler);
}
