import 'dart:ui';
import '../gameplay/friends/friend_instance.dart';
import '../gameplay/friends/friend_instance_store.dart';
import '../gameplay/friends/friend_mesh_sync.dart';
import '../rendering/scene/scene.dart';
import 'bedrooms.dart';
import 'models.dart';
import 'controller.dart';
import 'housing.dart';
import 'room_geometry.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;
import 'dart:math' as math;

/// Adapter for GameView's actual characters, without its volume/tile stores.
class BedroomResidents {
  final friends = FriendInstanceStore();
  static const subtiles = 32;
  final Map<String, RoomReview> _reviews = {};
  final Map<String, String> _homes = {};
  final Map<String, Offset> _walk = {}, _goals = {};
  final Map<Offset, List<Offset>> _neighbors = {};
  final Map<Offset, double> _heights = {};
  final Map<String, List<Offset>> _roomNodes = {};
  int _walkStep = 0;
  Offset _world(RoomReview r, Offset p) {
    final w = r.floor.point(p);
    return Offset(w.x, w.z);
  }

  void _navigation(ProtoplaneController model) {
    _neighbors.clear();
    _heights.clear();
    _roomNodes.clear();
    for (final review in _reviews.values) {
      final lookup = <String, Offset>{};
      String key(Offset p) =>
          '${(p.dx / RoomReview.step).round()},${(p.dy / RoomReview.step).round()}';
      for (final p in review.reachable) {
        final w = _world(review, p);
        lookup[key(p)] = w;
        _neighbors[w] = [];
        _heights[w] = review.floor.point(p).y;
      }
      _roomNodes[review.room.id] = lookup.values.toList();
      for (final p in review.reachable) {
        final w = _world(review, p);
        for (final d in const [
          Offset(RoomReview.step, 0),
          Offset(-RoomReview.step, 0),
          Offset(0, RoomReview.step),
          Offset(0, -RoomReview.step),
        ]) {
          final neighbor = lookup[key(p + d)];
          if (neighbor != null) _neighbors[w]!.add(neighbor);
        }
      }
    }
    for (final wall in model.walls.where((w) => w.shared)) {
      final a = wall.sides.first, b = wall.sides.last;
      for (final door in model.objects[a.room]!.openings.where(
        (o) => o.wall == a.panel.key && o.kind == 'door',
      )) {
        final mouth = doorwayCenter(door.region);
        if (mouth == null || mouth.dx < a.start || mouth.dx > a.end) continue;
        final world = a.panel.frame.point(mouth);
        if (!model.objects[b.room]!.openings.any(
          (d) =>
              d.wall == b.panel.key &&
              d.kind == 'door' &&
              d.region.contains(b.panel.frame.local(world)),
        )) {
          continue;
        }
        final nodes = <Offset>[];
        for (final side in [a, b]) {
          final entry = world - side.panel.frame.normal * .08;
          final at = Offset(entry.x, entry.z);
          final candidates =
              (_roomNodes[side.room] ?? [])
                  .where((p) => (p - at).distance < .13)
                  .toList()
                ..sort(
                  (x, y) => (x - at).distance.compareTo((y - at).distance),
                );
          if (candidates.isNotEmpty) nodes.add(candidates.first);
        }
        if (nodes.length == 2) {
          _neighbors[nodes[0]]!.add(nodes[1]);
          _neighbors[nodes[1]]!.add(nodes[0]);
        }
      }
    }
  }

  void syncHousing(Scene scene, ProtoplaneController model) {
    _reviews
      ..clear()
      ..addEntries(model.roomReviews.map((r) => MapEntry(r.room.id, r)));
    _navigation(model);
    _homes
      ..clear()
      ..addEntries(
        model.housing.tenants.values.map((t) => MapEntry(t.id, t.roomId)),
      );
    final next = <FriendInstance>[];
    for (final tenant in model.housing.tenants.values) {
      final review = _reviews[tenant.roomId];
      if (review == null) continue;
      final valid = _roomNodes[tenant.roomId]!;
      var at = _walk[tenant.id] ?? _world(review, tenant.position);
      if (valid.isNotEmpty &&
          !_neighbors.containsKey(at) &&
          !_goals.containsKey(tenant.id)) {
        at = valid.first;
      }
      _walk[tenant.id] = at;
      final actor =
          friends.byId(tenant.id) ??
          FriendInstance(
            id: tenant.id,
            friend: kCubeboyFriend,
            position: Vector3(
              at.dx,
              (_heights[at] ?? review.floor.origin.y) +
                  FriendMeshLayout.sitOnGroundY(
                    tileSize: 1,
                    subtilesPerTile: subtiles,
                  ),
              at.dy,
            ),
          );
      next.add(actor);
    }
    _walk.removeWhere((id, _) => !_homes.containsKey(id));
    _goals.removeWhere(
      (id, goal) => !_homes.containsKey(id) || !_neighbors.containsKey(goal),
    );
    friends.restore(next);
    syncFriendMeshes(scene, friends, tileSize: 1, subtilesPerTile: subtiles);
  }

  void tickHousing(Scene scene, double dt) {
    _walkStep++;
    for (final actor in friends.instances) {
      final review = _reviews[_homes[actor.id]];
      if (review == null || review.reachable.isEmpty) continue;
      var at = _walk[actor.id] ?? _roomNodes[review.room.id]!.first;
      var goal = _goals[actor.id];
      if (goal == null) {
        final neighbors = _neighbors[at] ?? <Offset>[];
        if (neighbors.isEmpty) {
          at = _roomNodes[review.room.id]!.first;
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
        Vector3(
          at.dx,
          (_heights[goal] ?? _heights[at] ?? review.floor.origin.y) +
              FriendMeshLayout.sitOnGroundY(
                tileSize: 1,
                subtilesPerTile: subtiles,
              ),
          at.dy,
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
