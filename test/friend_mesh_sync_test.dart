import 'package:flatmates/gameplay/flatmates/bedroom_roster.dart';
import 'package:flatmates/gameplay/friends/friend_instance.dart';
import 'package:flatmates/gameplay/friends/friend_instance_store.dart';
import 'package:flatmates/gameplay/friends/friend_mesh_sync.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_program.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flatmates/gameplay/walls/wall_store.dart';
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
    expect(body!.material.strokeEdges, isFalse);
    expect(body.position.y, 1);
    expect(body.position.x, 1);
    expect(body.position.z, 3);
    expect(body.yawThenPitch, isTrue);
    expect(body.rotation.x, 0);
    expect(body.rotation.y, 0);
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

  test('expression face sits on the body front, not above the mesh', () {
    final instance = FriendInstance(
      id: 'face-1',
      friend: kCubeboyFriend,
      position: Vector3(0, FriendMeshLayout.sitOnGroundY(tileSize: tileSize), 0),
    );
    final left = FriendMeshLayout.eyeWorld(
      instance: instance,
      left: true,
      tileSize: tileSize,
    );
    final onFace = FriendMeshLayout.faceWorld(
      instance: instance,
      face: const Offset(-0.5, 0),
      tileSize: tileSize,
    );
    expect(onFace.x, closeTo(left.x, 1e-6));
    expect(onFace.y, closeTo(left.y, 1e-6));
    expect(onFace.z, closeTo(left.z, 1e-6));
    expect(onFace.z, greaterThan(instance.position.z));
    expect(onFace.y, closeTo(instance.position.y + (35 * 2 / 120), 1e-6));
    expect(FriendMeshLayout.faceNormalWorld(instance).z, closeTo(1, 1e-6));
  });

  test('yaw +X puts the face on +X, matching body rotateY', () {
    final forward = Vector3(0, 0, 1);
    final turned = FriendMeshLayout.rotateYaw(forward, 1.5707963267948966);
    expect(turned.x, closeTo(1, 1e-9));
    expect(turned.z, closeTo(0, 1e-9));
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

  test('roster spawn is meshed only when sync runs after roster', () {
    const grid = VolumeGrid(tilesSide: 16, tileSize: tileSize);
    final volumes = VolumeStore(grid: grid);
    expect(volumes.startNew(2, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    final programs = VolumeProgramStore()
      ..assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom);
    final friends = FriendInstanceStore();
    final walls = WallStore(grid: grid);
    final scene = Scene();

    syncFriendMeshes(scene, friends, tileSize: tileSize);
    BedroomRoster.sync(
      friends: friends,
      volumes: volumes,
      programs: programs,
      walls: walls,
      grid: grid,
    );
    expect(friends.instances, hasLength(1));
    expect(scene.meshes.where((m) => m.id.startsWith('friend_')), isEmpty);

    syncFriendMeshes(scene, friends, tileSize: tileSize);
    expect(
      scene.meshById(friendBodyMeshId(friends.instances.single.id)),
      isNotNull,
    );
  });
}
