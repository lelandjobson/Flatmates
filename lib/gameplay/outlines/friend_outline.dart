import 'package:vector_math/vector_math_64.dart';

import '../../geometry/geometry.dart';
import '../../geometry/prefabs/prefab_factory.dart';
import '../../tiles/tiles.dart';
import '../friends/friend_instance.dart';
import '../friends/friend_instance_store.dart';
import '../friends/friend_mesh_sync.dart';
import '../volumes/volume.dart';
import '../volumes/volume_store.dart';
import 'outline_edges.dart';

final Map<(GeometryPrefabs, int), List<OutlineQuad>> _localQuads = {};

/// Outer edges of each friend body, in world space.
List<OutlineEdge> buildFriendOutlines({
  required FriendInstanceStore friends,
  required double tileSize,
  int subtilesPerTile = VolumeGrid.defaultSubtilesPerTile,
  VolumeStore? volumes,
}) {
  final edges = <OutlineEdge>[];
  for (final instance in friends.instances) {
    if (volumes != null && volumes.containsWorld(instance.position)) {
      continue;
    }
    edges.addAll(
      buildFriendOutline(
        instance: instance,
        tileSize: tileSize,
        subtilesPerTile: subtilesPerTile,
      ),
    );
  }
  return edges;
}

/// Outer crease / silhouette candidates for one friend.
List<OutlineEdge> buildFriendOutline({
  required FriendInstance instance,
  required double tileSize,
  int subtilesPerTile = VolumeGrid.defaultSubtilesPerTile,
}) {
  return collectOuterEdges(
    friendWorldQuads(
      instance: instance,
      tileSize: tileSize,
      subtilesPerTile: subtilesPerTile,
    ),
  );
}

List<OutlineQuad> friendWorldQuads({
  required FriendInstance instance,
  required double tileSize,
  int subtilesPerTile = VolumeGrid.defaultSubtilesPerTile,
}) {
  final scale = FriendMeshLayout.geometryScale(
    tileSize: tileSize,
    subtilesPerTile: subtilesPerTile,
  );
  final yaw = instance.yaw;
  return [
    for (final quad in _localBodyQuads(instance.friend.geometryType, scale))
      OutlineQuad(
        points: [
          for (final p in quad.points)
            instance.position + FriendMeshLayout.rotateYaw(p, yaw),
        ],
        normal: FriendMeshLayout.rotateYaw(quad.normal, yaw),
      ),
  ];
}

List<OutlineQuad> _localBodyQuads(GeometryPrefabs type, double scale) {
  final key = (type, (scale * 1e6).round());
  return _localQuads.putIfAbsent(key, () {
    final geometry = buildGeometry(
      GeometryFeature(
        id: 'friend_outline_$type',
        geometry: type,
        scale: scale,
      ),
    );
    final quads = <OutlineQuad>[];
    for (final face in geometry.faces) {
      if (face.length < 3) continue;
      final points = [for (final i in face) Vector3.copy(geometry.vertices[i])];
      quads.add(OutlineQuad(points: points, normal: _faceNormal(points)));
    }
    return quads;
  });
}

Vector3 _faceNormal(List<Vector3> points) {
  final a = points[1] - points[0];
  final b = points[2] - points[0];
  final n = a.cross(b);
  if (n.length2 < 1e-12) return Vector3(0, 1, 0);
  return n.normalized();
}
