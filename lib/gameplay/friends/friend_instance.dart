import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../geometry/prefabs/prefab_factory.dart';
import '../../user/friend_provider.dart';
import '../flatmates/flatmate_movement.dart';
import 'friend_expression_player.dart';
import 'friend_eye_profile.dart';
import 'friend_facing.dart';
import 'friend_thought.dart';

/// GameView scene object: a placed friend that walks tile routes.
typedef Flatmate = FriendInstance;

/// Cubeboy template used by GameView debug placement.
const kCubeboyFriend = Friend(
  id: 'b2c9f5e1-7a3d-4f8b-9c6e-1d4a8b2f7e3c',
  name: 'Cubeboy',
  geometryType: GeometryPrefabs.cube,
  stats: FriendStats(tileSpeed: 2.5),
  color: Colors.lightGreenAccent,
);

const kFrogmanFriend = Friend(
  id: 'a7f3e8d2-4b6c-4a9f-8e2d-5c1b3a7f9e4d',
  name: 'Frogman',
  geometryType: GeometryPrefabs.frog,
  stats: FriendStats(tileSpeed: 2.5),
  color: Colors.lightBlueAccent,
);

const kConicoFriend = Friend(
  id: 'c3d0a6f2-8b4e-5a9c-0d7f-2e5b9c3a8f1d',
  name: 'Conico',
  geometryType: GeometryPrefabs.cone,
  stats: FriendStats(tileSpeed: 2.5),
  color: Colors.amberAccent,
);

const kBedroomFriendTemplates = [
  kCubeboyFriend,
  kFrogmanFriend,
  kConicoFriend,
];

const kBedroomFriendColors = [
  Colors.lightGreenAccent,
  Colors.lightBlueAccent,
  Colors.amberAccent,
  Color(0xFFFF8A80),
  Color(0xFF80D8FF),
  Color(0xFFB388FF),
  Color(0xFFCCFF90),
  Color(0xFFFFD180),
];

/// A 3D [Flatmate] placed in GameView. Not part of the iso / [FriendManager] path.
class FriendInstance {
  FriendInstance({
    required this.id,
    required this.friend,
    required Vector3 position,
    double yaw = 0,
    this.pitch = 0,
    this.travelYaw = 0,
    this.presenting = false,
    this.bedroomTile,
    Set<(int, int)>? bedroomTiles,
  })  : position = Vector3.copy(position),
        bedroomTiles =
            bedroomTiles == null ? <(int, int)>{} : Set<(int, int)>.from(bedroomTiles),
        expression = FriendExpressionPlayer(seed: id),
        facing = FriendFacing(seed: id, yaw: yaw),
        thought = FriendThought(seed: id);

  final String id;
  final Friend friend;
  final Vector3 position;
  double get yaw => facing.yaw;
  set yaw(double value) => facing.yaw = value;
  final FriendFacing facing;
  double pitch;
  double travelYaw;
  bool presenting;
  (int, int)? bedroomTile;
  final Set<(int, int)> bedroomTiles;
  final FlatmateMovement movement = FlatmateMovement();
  final FriendExpressionPlayer expression;
  final FriendThought thought;
  FriendEyeProfile eyeProfile = FriendEyeProfile.defaults;

  bool get hasBedroom => bedroomTile != null || bedroomTiles.isNotEmpty;

  FriendInstance clone() {
    final next = FriendInstance(
      id: id,
      friend: friend,
      position: position,
      yaw: yaw,
      pitch: pitch,
      travelYaw: travelYaw,
      presenting: presenting,
      bedroomTile: bedroomTile,
      bedroomTiles: bedroomTiles,
    );
    next.thought.copyFrom(thought);
    next.eyeProfile = eyeProfile;
    return next;
  }
}

/// Templates placeable in GameView. Unknown ids fall back to Cubeboy.
Friend friendTemplateById(String id) {
  for (final friend in kBedroomFriendTemplates) {
    if (friend.id == id) return friend;
  }
  return kCubeboyFriend;
}

/// Template id used to store / look up an eye profile.
String eyeProfileKey(Friend friend) {
  for (final template in kBedroomFriendTemplates) {
    if (template.geometryType == friend.geometryType) return template.id;
  }
  return kCubeboyFriend.id;
}
