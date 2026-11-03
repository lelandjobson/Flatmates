import '../gameplay/friends/friend_instance.dart';
import '../gameplay/friends/friend_instance_store.dart';
import '../gameplay/friends/friend_mesh_sync.dart';
import '../rendering/scene/scene.dart';
import 'bedrooms.dart';
import 'models.dart';

/// Adapter for GameView's actual characters, without its volume/tile stores.
class BedroomResidents {
  final friends = FriendInstanceStore();
  static const subtiles = 32;
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
