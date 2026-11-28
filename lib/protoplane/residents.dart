import 'dart:ui';
import '../gameplay/friends/friend_instance.dart';
import '../gameplay/friends/friend_instance_store.dart';
import '../gameplay/friends/friend_mesh_sync.dart';
import '../rendering/scene/scene.dart';
import 'bedrooms.dart';
import 'models.dart';
import 'controller.dart';
import 'housing.dart';
import 'dart:math' as math;

/// Adapter for GameView's actual characters, without its volume/tile stores.
class BedroomResidents {
  final friends = FriendInstanceStore();
  static const subtiles = 32;
  final Map<String, RoomReview> _reviews = {};
  final Map<String, String> _homes = {};
  final Map<String, Offset> _walk = {}, _goals = {};
  int _walkStep = 0;
  void syncHousing(Scene scene, ProtoplaneController model) {
    _reviews
      ..clear()
      ..addEntries(model.roomReviews.map((r) => MapEntry(r.room.id, r)));
    _homes
      ..clear()
      ..addEntries(
        model.housing.tenants.values.map((t) => MapEntry(t.id, t.roomId)),
      );
    final next = <FriendInstance>[];
    for (final tenant in model.housing.tenants.values) {
      final review = _reviews[tenant.roomId];
      if (review == null) continue;
      final valid = review.reachable;
      var at = _walk[tenant.id] ?? tenant.position;
      if (valid.isNotEmpty &&
          !valid.contains(at) &&
          !_goals.containsKey(tenant.id)) {
        at = valid.first;
      }
      _walk[tenant.id] = at;
      final actor =
          friends.byId(tenant.id) ??
          FriendInstance(
            id: tenant.id,
            friend: kCubeboyFriend,
            position: review.floor.point(
              at,
              FriendMeshLayout.sitOnGroundY(
                tileSize: 1,
                subtilesPerTile: subtiles,
              ),
            ),
          );
      next.add(actor);
    }
    _walk.removeWhere((id, _) => !_homes.containsKey(id));
    _goals.removeWhere(
      (id, goal) =>
          !_homes.containsKey(id) ||
          !(_reviews[_homes[id]]?.reachable.contains(goal) ?? false),
    );
    friends.restore(next);
    syncFriendMeshes(scene, friends, tileSize: 1, subtilesPerTile: subtiles);
  }

  void tickHousing(Scene scene, double dt) {
    _walkStep++;
    for (final actor in friends.instances) {
      final review = _reviews[_homes[actor.id]];
      if (review == null || review.reachable.isEmpty) continue;
      var at = _walk[actor.id] ?? review.reachable.first;
      var goal = _goals[actor.id];
      if (goal == null) {
        final neighbors = review.reachable
            .where((p) => ((p - at).distance - RoomReview.step).abs() < .0001)
            .toList();
        if (neighbors.isEmpty) {
          at = review.reachable.first;
        } else {
          goal =
              neighbors[(_walkStep ~/ 5 +
                      actor.id.codeUnits.fold<int>(0, (a, b) => a + b)) %
                  neighbors.length];
        }
      }
      var moving = false;
      if (goal != null) {
        final delta = goal - at;
        final distance = delta.distance;
        if (distance <= dt * .12) {
          at = goal;
          _goals.remove(actor.id);
        } else {
          at += delta / distance * dt * .12;
          _goals[actor.id] = goal;
        }
        actor.yaw = math.atan2(delta.dx, -delta.dy);
        moving = true;
      }
      _walk[actor.id] = at;
      actor.position.setFrom(
        review.floor.point(
          at,
          FriendMeshLayout.sitOnGroundY(tileSize: 1, subtilesPerTile: subtiles),
        ),
      );
      actor.expression.tick(dt, moving: moving);
    }
    syncFriendMeshes(scene, friends, tileSize: 1, subtilesPerTile: subtiles);
  }

  void sync(
    Scene scene,
    Iterable<Bedroom> rooms,
    Map<String, CraftObject> objects,
    Map<String, CraftPlane> planes,
  ) {
    final next = <FriendInstance>[];
    for (final room in rooms.where((r) => r.usable && r.position != null)) {
      final floor = objects[room.floorId]!;
      final source = planes[floor.planeId]!;
      final position = source.point(
        room.position!,
        floor.depth +
            .003 +
            FriendMeshLayout.sitOnGroundY(
              tileSize: 1,
              subtilesPerTile: subtiles,
            ),
      );
      final actor =
          friends.byId(room.residentId) ??
          FriendInstance(
            id: room.residentId,
            friend: room.resident == ResidentKind.frogman
                ? kFrogmanFriend
                : kCubeboyFriend,
            position: position,
            yaw: .35,
          );
      actor.position.setFrom(position);
      actor.expression.tick(.3, moving: false);
      next.add(actor);
    }
    friends.restore(next);
    syncFriendMeshes(scene, friends, tileSize: 1, subtilesPerTile: subtiles);
  }
}
