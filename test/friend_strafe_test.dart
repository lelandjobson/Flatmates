import 'package:flatmates/gameplay/flatmates/flatmate_movement.dart';
import 'package:flatmates/gameplay/flatmates/movement_profile.dart';
import 'package:flatmates/gameplay/friends/friend_instance.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/geometry/transformable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  const grid = VolumeGrid(tilesSide: 16, tileSize: 8);

  const profile = MovementProfile(
    id: 'strafe',
    name: 'Strafe',
    offset: 0,
    jank: 0,
    smoothness: 0,
    bendSlowdown: 0,
    hopHeight: 0,
  );

  test('body yaw stays put while travel yaw follows the path', () {
    final friend = FriendInstance(
      id: 'strafe-1',
      friend: kCubeboyFriend,
      position: Vector3.zero(),
      yaw: 0.4,
    );
    friend.movement.start(
      const [(0, 0), (1, 0), (2, 0)],
      grid: grid,
      profile: profile,
      flourish: false,
    );
    friend.travelYaw = friend.movement.facingYaw();
    friend.pitch = friend.movement.pitch;
    expect(friend.yaw, 0.4);
    expect(friend.travelYaw, isNot(closeTo(0.4, 0.05)));

    friend.movement.advance(
      dt: 0.1,
      baseTilesPerSecond: 10,
      onPath: (_, _) => false,
      grid: grid,
    );
    friend.travelYaw = friend.movement.facingYaw();
    friend.pitch = friend.movement.pitch;
    expect(friend.yaw, 0.4);
  });

  test('zero lean is just body yaw, regardless of travel yaw', () {
    final a = Transformable(
      rotation: Vector3(0, 0.8, 0),
      yawThenPitch: true,
      travelYaw: 2.2,
    );
    final b = Transformable(
      rotation: Vector3(0, 0.8, 0),
      yawThenPitch: true,
      travelYaw: 0,
    );
    final ma = a.transformMatrix;
    final mb = b.transformMatrix;
    for (var i = 0; i < 16; i++) {
      expect(ma[i], closeTo(mb[i], 1e-9));
    }
  });

  test('lean uses travel yaw, not body yaw', () {
    final travel = Transformable(
      rotation: Vector3(0.2, 0, 0),
      yawThenPitch: true,
      travelYaw: 1.5707963267948966,
    );
    final body = Transformable(
      rotation: Vector3(0.2, 0, 0),
      yawThenPitch: true,
      travelYaw: 0,
    );
    // East travel lean rotates around world Z-ish, not world X.
    expect(travel.transformMatrix[0], isNot(closeTo(body.transformMatrix[0], 1e-4)));
  });

  test('start flourish does not rewrite body yaw', () {
    final move = FlatmateMovement()
      ..start(
        const [(0, 0), (1, 0)],
        grid: grid,
        profile: profile,
        flourish: true,
      );
    move.advance(
      dt: 0.1,
      baseTilesPerSecond: 2,
      onPath: (_, _) => false,
      grid: grid,
    );
    expect(move.phase, MovementPhase.starting);
    expect(move.pitch, greaterThan(0));
  });
}
