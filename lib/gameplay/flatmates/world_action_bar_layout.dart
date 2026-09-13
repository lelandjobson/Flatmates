import 'dart:ui';

import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../../rendering/scene/camera.dart';
import '../alerts/world_alert_layout.dart';
import '../friends/friend_instance.dart';
import 'day_action.dart';
import 'day_action_store.dart';

const kWorldActionBarLift = 3.2;

class FriendActionBar {
  const FriendActionBar({
    required this.friendId,
    required this.world,
    required this.slots,
    required this.summaryIndex,
  });

  final String friendId;
  final Vector3 world;
  final List<DayActionSlot> slots;
  final int summaryIndex;
}

class FriendActionBarPlacement {
  const FriendActionBarPlacement({
    required this.bar,
    required this.screen,
    required this.raw,
    required this.waypoint,
    required this.scale,
  });

  final FriendActionBar bar;
  final Offset screen;
  final Offset raw;
  final bool waypoint;
  final double scale;
}

FriendActionBarPlacement? placeFriendActionBar({
  required FriendActionBar bar,
  required Camera camera,
  required Size viewport,
  required Vector3 lookAt,
  required double tileSize,
}) {
  final projected = camera.projectToScreenOrEdge(bar.world, viewport);
  if (projected == null) return null;
  final scale = projected.onScreen
      ? 1.0
      : waypointDistanceScale(
          world: bar.world,
          lookAt: lookAt,
          tileSize: tileSize,
        );
  return FriendActionBarPlacement(
    bar: bar,
    screen: projected.position,
    raw: projected.raw,
    waypoint: !projected.onScreen,
    scale: scale,
  );
}

String? hitFriendActionBarId({
  required List<FriendActionBar> bars,
  required Camera camera,
  required Size viewport,
  required Offset pointer,
  required Vector3 lookAt,
  required double tileSize,
}) {
  for (final bar in bars) {
    final placed = placeFriendActionBar(
      bar: bar,
      camera: camera,
      viewport: viewport,
      lookAt: lookAt,
      tileSize: tileSize,
    );
    if (placed == null) continue;
    final count = bar.slots.length;
    final collapsed = worldAlertHitRect(
      screen: placed.screen,
      issueCount: count,
      expanded: false,
      scale: placed.scale,
    );
    final expanded = worldAlertHitRect(
      screen: placed.screen,
      issueCount: count,
      expanded: true,
      scale: placed.scale,
    );
    if (collapsed.contains(pointer) || expanded.contains(pointer)) {
      return bar.friendId;
    }
  }
  return null;
}

List<FriendActionBar> friendActionBars({
  required Iterable<FriendInstance> friends,
  required FlatmateDayPlanStore plans,
  required double tileSize,
  String? playingFriendId,
}) {
  return [
    for (final friend in friends)
      FriendActionBar(
        friendId: friend.id,
        world: Vector3(
          friend.position.x,
          friend.position.y + kWorldActionBarLift,
          friend.position.z,
        ),
        slots: (plans.byId(friend.id) ??
                FlatmateDayPlan.empty(friend.id, home: friend.bedroomTile))
            .slots,
        summaryIndex: _summaryIndex(
          friend: friend,
          plan: plans.byId(friend.id),
          playing: playingFriendId == friend.id,
        ),
      ),
  ];
}

int _summaryIndex({
  required FriendInstance friend,
  required FlatmateDayPlan? plan,
  required bool playing,
}) {
  if (plan == null) return kFlatmateDayActionSlots - 1;
  if (playing && friend.movement.isMoving) {
    final tile = friend.movement.currentTile;
    if (tile != null) {
      for (var i = 0; i < plan.slots.length; i++) {
        if (plan.slots[i].tile == tile) return i;
      }
    }
  }
  return plan.summarySlotIndex;
}