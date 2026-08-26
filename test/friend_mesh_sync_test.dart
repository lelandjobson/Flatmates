import 'package:flatmates/gameplay/friends/friend_instance.dart';
import 'package:flatmates/gameplay/friends/friend_instance_store.dart';
import 'package:flatmates/gameplay/friends/friend_mesh_sync.dart';
import 'package:flatmates/rendering/scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  const tileSize = 8.0;

  test('cube friend is 2x2 subtiles and sits on the ground', () {
    expect(FriendMeshLayout.worldSize(tileSize: tileSize), 2);
    expect(FriendMeshLayout.geometryScale(tileSize: tileSize), 2 / 120);
    expect(FriendMeshLayout.halfSize(tileSize: tileSize), 1);
    expect(FriendMeshLayout.sitOnGroundY(tileSize: tileSize), 1);
  });

  test('sync places body only; eyes are world offsets for vector dots', () {
    final scene = Scene();
    final store = FriendInstanceStore();
    final instance = FriendInstance(
      id: 'cube-1',
      friend: kCubeboyFriend,
      position: Vector3(1, FriendMeshLayout.sitOnGroundY(tileSize: tileSize), 3),
    );
    store.add(instance);
    syncFriendMeshes(scene, store, tileSize: tileSize);

    final body = scene.meshById(friendBodyMeshId('cube-1'));
    expect(body, isNotNull);
    expect(body!.position.y, 1);
    expect(body.position.x, 1);
    expect(body.position.z, 3);
    expect(
      scene.meshes.where((m) => m.id.startsWith('friend_cube-1_eye')),
      isEmpty,
    );

    final expr = kCubeboyFriend.expression!;
    final scaled = FriendMeshLayout.scaledExpression(
      expr,
      tileSize: tileSize,
    );
    final left = FriendMeshLayout.eyeWorld(
      instance: instance,
      left: true,
      tileSize: tileSize,
    );
    final right = FriendMeshLayout.eyeWorld(
      instance: instance,
      left: false,
      tileSize: tileSize,
    );
    final leftLocal = FriendMeshLayout.eyeLocalOffset(
      scaled: scaled,
      left: true,
    );
    expect(left.x, closeTo(instance.position.x + leftLocal.x, 1e-6));
    expect(left.y, closeTo(instance.position.y + leftLocal.y, 1e-6));
    expect(left.z, closeTo(instance.position.z + leftLocal.z, 1e-6));
    expect(right.x, isNot(closeTo(left.x, 1e-6)));
    expect(scaled.eyeHeight, closeTo(35 * 2 / 120, 1e-9));
    expect(scaled.eyeForwardOffset, closeTo(62 * 2 / 120, 1e-9));
    expect(scaled.eyeRadiusX, closeTo(8 * 2 / 120, 1e-9));
  });

  test('sync removes meshes for deleted friends', () {
    final scene = Scene();
    final store = FriendInstanceStore();
    store.add(
      FriendInstance(
        id: 'gone',
        friend: kCubeboyFriend,
        position: Vector3(0, 1, 0),
      ),
    );
    syncFriendMeshes(scene, store, tileSize: tileSize);
    expect(scene.meshById(friendBodyMeshId('gone')), isNotNull);
    store.remove('gone');
    syncFriendMeshes(scene, store, tileSize: tileSize);
    expect(scene.meshById(friendBodyMeshId('gone')), isNull);
  });
}
