import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../geometry/geometry.dart';
import '../../geometry/prefabs/prefab_factory.dart';
import '../../rendering/iso/friend_expression.dart';
import '../../rendering/mesh.dart';
import '../../rendering/scene/scene.dart';
import '../../tiles/tiles.dart';
import '../volumes/volume.dart';
import 'friend_instance.dart';
import 'friend_instance_store.dart';

String friendBodyMeshId(String instanceId) => 'friend_${instanceId}_body';

/// Scale / sit-on-ground / eye layout for GameView friend meshes.
class FriendMeshLayout {
  /// Cubeboy occupies a 2×2 subtile footprint.
  static const int subtileSpan = 2;

  static double worldSize({
    required double tileSize,
    int subtilesPerTile = VolumeGrid.defaultSubtilesPerTile,
  }) =>
      subtileSpan * (tileSize / subtilesPerTile);

  static double geometryScale({
    required double tileSize,
    int subtilesPerTile = VolumeGrid.defaultSubtilesPerTile,
  }) =>
      calculateGeometryScale(
        GeometryPrefabs.cube,
        worldSize(tileSize: tileSize, subtilesPerTile: subtilesPerTile),
      );

  static double halfSize({
    required double tileSize,
    int subtilesPerTile = VolumeGrid.defaultSubtilesPerTile,
  }) =>
      worldSize(tileSize: tileSize, subtilesPerTile: subtilesPerTile) * 0.5;

  /// Cube is origin-centered, so the body sits on y=0 when the center is here.
  static double sitOnGroundY({
    required double tileSize,
    int subtilesPerTile = VolumeGrid.defaultSubtilesPerTile,
  }) =>
      halfSize(tileSize: tileSize, subtilesPerTile: subtilesPerTile);

  static FriendExpressionConfig scaledExpression(
    FriendExpressionConfig expr, {
    required double tileSize,
    int subtilesPerTile = VolumeGrid.defaultSubtilesPerTile,
  }) {
    final scale = geometryScale(
      tileSize: tileSize,
      subtilesPerTile: subtilesPerTile,
    );
    return expr.copyWith(
      eyeHeight: expr.eyeHeight * scale,
      eyeSpacing: expr.eyeSpacing * scale,
      eyeRadiusX: expr.eyeRadiusX * scale,
      eyeRadiusY: expr.eyeRadiusY * scale,
      eyeForwardOffset: expr.eyeForwardOffset * scale,
    );
  }

  static Vector3 eyeLocalOffset({
    required FriendExpressionConfig scaled,
    required bool left,
  }) {
    final side = left ? -1.0 : 1.0;
    return Vector3(
      side * scaled.eyeSpacing * 0.5,
      scaled.eyeHeight,
      scaled.eyeForwardOffset,
    );
  }

  /// Same convention as [Transformable] `Matrix4.rotateY`.
  static Vector3 rotateYaw(Vector3 local, double yaw) {
    final c = math.cos(yaw);
    final s = math.sin(yaw);
    return Vector3(
      local.x * c + local.z * s,
      local.y,
      -local.x * s + local.z * c,
    );
  }

  static Vector3 eyeWorld({
    required FriendInstance instance,
    required bool left,
    required double tileSize,
    int subtilesPerTile = VolumeGrid.defaultSubtilesPerTile,
  }) {
    final expr = instance.friend.expression;
    if (expr == null) return Vector3.copy(instance.position);
    final scaled = scaledExpression(
      expr,
      tileSize: tileSize,
      subtilesPerTile: subtilesPerTile,
    );
    return instance.position +
        rotateYaw(
          eyeLocalOffset(scaled: scaled, left: left),
          instance.yaw,
        );
  }
}

/// Syncs `friend_{id}_body` meshes to [store]. Eyes are 2D vector overlays.
void syncFriendMeshes(
  Scene scene,
  FriendInstanceStore store, {
  required double tileSize,
  int subtilesPerTile = VolumeGrid.defaultSubtilesPerTile,
}) {
  final wanted = <String>{};
  final scale = FriendMeshLayout.geometryScale(
    tileSize: tileSize,
    subtilesPerTile: subtilesPerTile,
  );

  for (final instance in store.instances) {
    final bodyId = friendBodyMeshId(instance.id);
    wanted.add(bodyId);

    final geometry = buildGeometry(
      GeometryFeature(
        id: bodyId,
        geometry: instance.friend.geometryType,
        scale: scale,
      ),
    );
    _upsertMesh(
      scene,
      id: bodyId,
      name: instance.friend.name,
      geometry: geometry,
      material: MaterialModel(
        color: instance.friend.color,
        doubleSided: true,
        strokeEdges: false,
      ),
      position: instance.position,
      rotation: Vector3(0, instance.yaw, 0),
    );
  }

  for (final mesh in List<Mesh>.from(scene.meshes)) {
    if (mesh.id.startsWith('friend_') && !wanted.contains(mesh.id)) {
      scene.removeMeshById(mesh.id);
    }
  }
  scene.markNeedsPaint();
}

void _upsertMesh(
  Scene scene, {
  required String id,
  required String name,
  required Geometry geometry,
  required MaterialModel material,
  required Vector3 position,
  Vector3? rotation,
}) {
  final existing = scene.meshById(id);
  if (existing == null) {
    scene.addMesh(
      Mesh(
        id: id,
        name: name,
        geometry: geometry,
        material: material,
        position: Vector3.copy(position),
        rotation: rotation == null ? null : Vector3.copy(rotation),
      ),
    );
    return;
  }
  existing.geometry = geometry;
  existing.material = material;
  existing.setPosition(position);
  if (rotation != null) existing.setRotation(rotation);
}
