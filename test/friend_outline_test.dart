import 'package:flatmates/gameplay/friends/friend_instance.dart';
import 'package:flatmates/gameplay/friends/friend_instance_store.dart';
import 'package:flatmates/gameplay/friends/friend_mesh_sync.dart';
import 'package:flatmates/gameplay/outlines/friend_outline.dart';
import 'package:flatmates/gameplay/outlines/outline_edges.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  const tileSize = 8.0;

  test('a cubeboy has twelve outer body edges', () {
    final instance = FriendInstance(
      id: 'cube-1',
      friend: kCubeboyFriend,
      position: Vector3(0, FriendMeshLayout.sitOnGroundY(tileSize: tileSize), 0),
    );
    final edges = buildFriendOutline(instance: instance, tileSize: tileSize);
    expect(edges, hasLength(12));
  });

  test('front-facing cube edges stay; back edges hide', () {
    final instance = FriendInstance(
      id: 'cube-1',
      friend: kCubeboyFriend,
      position: Vector3(0, FriendMeshLayout.sitOnGroundY(tileSize: tileSize), 0),
    );
    final edges = buildFriendOutline(instance: instance, tileSize: tileSize);
    final eye = Vector3(10, 8, 10);
    final visible = edges.where((e) => outlineEdgeVisible(e, eye));
    expect(visible.length, lessThan(edges.length));
    expect(visible.length, greaterThanOrEqualTo(6));
  });

  test('store outlines each friend separately', () {
    final store = FriendInstanceStore()
      ..add(
        FriendInstance(
          id: 'a',
          friend: kCubeboyFriend,
          position: Vector3(0, 1, 0),
        ),
      )
      ..add(
        FriendInstance(
          id: 'b',
          friend: kCubeboyFriend,
          position: Vector3(20, 1, 0),
        ),
      );
    expect(
      buildFriendOutlines(friends: store, tileSize: tileSize),
      hasLength(24),
    );
  });

  test('tile occupancy plus cell AABB hides a friend inside a volume', () {
    final volumes = VolumeStore();
    expect(volumes.startNew(2, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);

    final inside = volumes.grid.tileCenter(2, 2)
      ..y = FriendMeshLayout.sitOnGroundY(tileSize: volumes.grid.tileSize);
    expect(volumes.containsWorld(inside), isTrue);

    final outside = volumes.grid.tileCenter(5, 5)
      ..y = FriendMeshLayout.sitOnGroundY(tileSize: volumes.grid.tileSize);
    expect(volumes.containsWorld(outside), isFalse);

    final friends = FriendInstanceStore()
      ..add(
        FriendInstance(id: 'in', friend: kCubeboyFriend, position: inside),
      )
      ..add(
        FriendInstance(id: 'out', friend: kCubeboyFriend, position: outside),
      );
    expect(
      buildFriendOutlines(
        friends: friends,
        tileSize: volumes.grid.tileSize,
        volumes: volumes,
      ),
      hasLength(12),
    );
  });

  test('inset box on the same tile does not hide a friend outside the AABB', () {
    final volumes = VolumeStore();
    expect(volumes.startNew(2, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    final cell = volumes.volumeAt(2, 2)!.cellAt(2, 2)!;
    cell.box
      ..originXSubtiles = 6
      ..widthSubtiles = 2;

    final atTileCenter = volumes.grid.tileCenter(2, 2)
      ..y = FriendMeshLayout.sitOnGroundY(tileSize: volumes.grid.tileSize);
    expect(volumes.containsWorld(atTileCenter), isFalse);

    final friends = FriendInstanceStore()
      ..add(
        FriendInstance(
          id: 'beside',
          friend: kCubeboyFriend,
          position: atTileCenter,
        ),
      );
    expect(
      buildFriendOutlines(
        friends: friends,
        tileSize: volumes.grid.tileSize,
        volumes: volumes,
      ),
      hasLength(12),
    );
  });
}
