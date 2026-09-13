import 'package:flatmates/gameplay/friends/friend_expression_player.dart';
import 'package:flatmates/gameplay/friends/friend_expression_pose.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('opacity fades in when idle and out when moving', () {
    final player = FriendExpressionPlayer(seed: 'fade', firstHold: 10);
    expect(player.opacity, 0);
    player.tick(kExpressionFadeSeconds, moving: false);
    expect(player.opacity, closeTo(1, 1e-6));
    player.tick(kExpressionFadeSeconds, moving: true);
    expect(player.opacity, closeTo(0, 1e-6));
  });

  test('presenting keeps the face up while moving', () {
    final player = FriendExpressionPlayer(seed: 'show', firstHold: 10)
      ..presenting = true;
    player.tick(kExpressionFadeSeconds, moving: true);
    expect(player.opacity, closeTo(1, 1e-6));
  });

  test('play blends away from rest and back', () {
    final player = FriendExpressionPlayer(seed: 'cut', firstHold: 10);
    player.tick(kExpressionFadeSeconds, moving: false);
    player.play(FriendExpressionId.blink, duration: 0.2);
    player.tick(0.1, moving: false);
    expect(player.isBlending, isTrue);
    expect(
      player.current.left.ring[2].dy,
      isNot(closeTo(FriendExpressionPose.rest.left.ring[2].dy, 1e-6)),
    );
    player.tick(0.15, moving: false);
    expect(
      player.current.left.ring[2].dy,
      closeTo(FriendExpressionPose.blink.left.ring[2].dy, 1e-6),
    );
    player.play(FriendExpressionId.rest, duration: 0.1);
    player.tick(0.12, moving: false);
    expect(
      player.current.left.ring[2].dy,
      closeTo(FriendExpressionPose.rest.left.ring[2].dy, 1e-6),
    );
    expect(player.current.id, FriendExpressionId.rest);
  });

  test('idle director leaves rest after the first hold', () {
    final player = FriendExpressionPlayer(seed: 'idle', firstHold: 0);
    player.tick(0.05, moving: false);
    expect(player.to.id, isNot(FriendExpressionId.rest));
    expect(player.isBlending, isTrue);
  });
}
