import 'dart:math' as math;

import 'package:flatmates/gameplay/friends/friend_facing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  test('nearest path align picks the smallest absolute turn', () {
    expect(
      FriendFacing.nearestPathAlign(0.2, math.pi / 2),
      closeTo(0, 1e-9),
    );
    expect(
      FriendFacing.nearestPathAlign(1.4, math.pi / 2),
      closeTo(math.pi / 2, 1e-9),
    );
    expect(
      FriendFacing.shortestDelta(0.1, -0.1).abs(),
      lessThan(FriendFacing.shortestDelta(0.1, math.pi).abs()),
    );
  });

  test('camera facing is atan2 on the XZ plane', () {
    final yaw = FriendFacing.cameraFacingYaw(
      Vector3.zero(),
      Vector3(1, 10, 0),
    );
    expect(yaw, closeTo(math.pi / 2, 1e-9));
    expect(
      FriendFacing.cameraFacingYaw(Vector3.zero(), Vector3(0, 10, 0)),
      isNull,
    );
  });

  test('start turn snaps to the path tangent when inertia is 0', () {
    final facing = FriendFacing(seed: 'a', yaw: 0.2);
    facing.tick(
      0.2,
      moving: true,
      travelYaw: math.pi / 2,
      cameraYaw: 0,
    );
    expect(facing.yaw, closeTo(math.pi / 2, 1e-6));
  });

  test('after stop, waits before turning to the camera', () {
    final facing = FriendFacing(seed: 'pause', yaw: 0);
    facing.tick(0.01, moving: true, travelYaw: 0, cameraYaw: math.pi / 2);
    facing.tick(0.01, moving: false, travelYaw: 0, cameraYaw: math.pi / 2);
    expect(facing.isWaitingToFaceCamera, isTrue);
    expect(facing.yaw, closeTo(0, 1e-6));
    facing.tick(0.4, moving: false, travelYaw: 0, cameraYaw: math.pi / 2);
    expect(facing.isWaitingToFaceCamera, isTrue);
    facing.tick(2.1, moving: false, travelYaw: 0, cameraYaw: math.pi / 2);
    expect(facing.isWaitingToFaceCamera, isFalse);
    expect(facing.yaw, closeTo(math.pi / 2, 1e-6));
  });

  test('idle friends wait then face the camera after it rotates', () {
    final facing = FriendFacing(seed: 'orbit', yaw: 0);
    facing.tick(0.01, moving: false, travelYaw: 0, cameraYaw: 0);
    expect(facing.isWaitingToFaceCamera, isFalse);
    facing.tick(0.01, moving: false, travelYaw: 0, cameraYaw: math.pi / 2);
    expect(facing.isWaitingToFaceCamera, isTrue);
    expect(facing.yaw, closeTo(0, 1e-6));
    facing.tick(2.1, moving: false, travelYaw: 0, cameraYaw: math.pi / 2);
    expect(facing.yaw, closeTo(math.pi / 2, 1e-6));
  });
}
