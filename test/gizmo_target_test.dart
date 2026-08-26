import 'package:flatmates/gameplay/friends/friend_instance.dart';
import 'package:flatmates/gameplay/friends/friend_instance_store.dart';
import 'package:flatmates/gameplay/friends/friend_mesh_sync.dart';
import 'package:flatmates/gameplay/gizmo/gizmo_resolver.dart';
import 'package:flatmates/gameplay/gizmo/gizmo_target.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  test('volume cell meshes share one gizmo group', () {
    expect(
      sameGizmoGroup(volumeCellMeshId(1, 5, 5), volumeCellMeshId(1, 6, 5)),
      isTrue,
    );
    expect(
      sameGizmoGroup(volumeCellMeshId(1, 5, 5), volumeCellMeshId(2, 5, 5)),
      isFalse,
    );
  });

  test('friend body meshes with different ids are different groups', () {
    expect(
      sameGizmoGroup(friendBodyMeshId('abc'), friendBodyMeshId('abc')),
      isTrue,
    );
    expect(
      sameGizmoGroup(friendBodyMeshId('abc'), friendBodyMeshId('other')),
      isFalse,
    );
  });

  test('resolver maps volume and friend mesh ids to grouped targets', () {
    final volumes = VolumeStore();
    final volume = Volume(
      id: 1,
      cells: [
        VolumeCell(tx: 5, ty: 5, box: BoxPrimitive()),
        VolumeCell(tx: 6, ty: 5, box: BoxPrimitive()),
      ],
    );
    volumes.volumes.add(volume);

    final friends = FriendInstanceStore();
    friends.add(
      FriendInstance(
        id: 'cube-1',
        friend: kCubeboyFriend,
        position: Vector3(0, 1, 0),
      ),
    );

    final fromA = resolveGizmoTarget(
      meshId: volumeCellMeshId(1, 5, 5),
      friends: friends,
      volumes: volumes,
      tileSize: 8,
    );
    final fromB = resolveGizmoTarget(
      meshId: volumeCellMeshId(1, 6, 5),
      friends: friends,
      volumes: volumes,
      tileSize: 8,
    );
    expect(fromA, isA<VolumeGizmoTarget>());
    expect(fromB, isA<VolumeGizmoTarget>());
    expect(fromA!.id, fromB!.id);
    expect(fromA.id, 'volume:1');

    final body = resolveGizmoTarget(
      meshId: friendBodyMeshId('cube-1'),
      friends: friends,
      volumes: volumes,
      tileSize: 8,
    );
    expect(body, isA<FriendGizmoTarget>());
    expect(body!.id, 'friend:cube-1');

    expect(
      resolveGizmoTarget(
        meshId: 'path_3_3_0',
        friends: friends,
        volumes: volumes,
        tileSize: 8,
      ),
      isNull,
    );
  });
}
