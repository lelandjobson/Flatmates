import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../geometry/prefabs/prefab_factory.dart';
import '../../user/friend_provider.dart';

/// Cubeboy template used by GameView debug placement.
const kCubeboyFriend = Friend(
  id: 'b2c9f5e1-7a3d-4f8b-9c6e-1d4a8b2f7e3c',
  name: 'Cubeboy',
  geometryType: GeometryPrefabs.cube,
  stats: FriendStats(tileSpeed: 10.0),
  color: Colors.lightGreenAccent,
);

/// A 3D friend placed in GameView. Not part of the iso / [FriendManager] path.
class FriendInstance {
  FriendInstance({
    required this.id,
    required this.friend,
    required Vector3 position,
    this.yaw = 0,
  }) : position = Vector3.copy(position);

  final String id;
  final Friend friend;
  final Vector3 position;
  double yaw;

  FriendInstance clone() => FriendInstance(
        id: id,
        friend: friend,
        position: position,
        yaw: yaw,
      );
}

/// Templates placeable in GameView. Unknown ids fall back to Cubeboy.
Friend friendTemplateById(String id) {
  if (id == kCubeboyFriend.id) return kCubeboyFriend;
  return kCubeboyFriend;
}
