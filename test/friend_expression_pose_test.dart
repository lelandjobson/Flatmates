import 'package:flatmates/gameplay/friends/friend_expression_pose.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lerp hits endpoints and is reversible', () {
    final a = FriendExpressionPose.rest;
    final b = FriendExpressionPose.blink;
    final start = FriendExpressionPose.lerp(a, b, 0);
    final end = FriendExpressionPose.lerp(a, b, 1);
    expect(start.left.ring[2].dy, closeTo(a.left.ring[2].dy, 1e-9));
    expect(end.left.ring[2].dy, closeTo(b.left.ring[2].dy, 1e-9));

    const t = 0.35;
    final mid = FriendExpressionPose.lerp(a, b, t);
    final back = FriendExpressionPose.lerp(b, a, 1 - t);
    expect(mid.left.ring[0].dx, closeTo(back.left.ring[0].dx, 1e-9));
    expect(mid.left.ring[0].dy, closeTo(back.left.ring[0].dy, 1e-9));
    expect(mid.right.ring[4].dy, closeTo(back.right.ring[4].dy, 1e-9));
  });

  test('every named pose is a closed ring of the same size', () {
    final poses = [
      FriendExpressionPose.rest,
      FriendExpressionPose.blink,
      FriendExpressionPose.happy,
      FriendExpressionPose.sad,
      FriendExpressionPose.wow,
      FriendExpressionPose.sleepy,
      FriendExpressionPose.inquisitive,
      FriendExpressionPose.glance(-1),
      FriendExpressionPose.glance(1),
    ];
    for (final pose in poses) {
      expect(pose.left.ring, hasLength(kEyeRingCount));
      expect(pose.right.ring, hasLength(kEyeRingCount));
      expect(eyeBlobPath(pose.left.ring).getBounds().isEmpty, isFalse);
    }
  });

  test('happy bends up and sad bends down', () {
    final happy = FriendExpressionPose.happy.left;
    final sad = FriendExpressionPose.sad.left;
    expect(happy.ring[2].dy, greaterThan(sad.ring[2].dy));
    expect(happy.ring[6].dy, greaterThan(sad.ring[6].dy));
  });

  test('rest eyes are four times the original circle', () {
    final left = FriendExpressionPose.rest.left;
    expect(left.ring[0].dx - left.center.dx, closeTo(0.64, 1e-9));
    expect(left.ring[2].dy - left.center.dy, closeTo(0.64, 1e-9));
  });

  test('glance shifts rest along the face plane', () {
    final left = FriendExpressionPose.glance(-1);
    final right = FriendExpressionPose.glance(1);
    expect(left.left.center.dx, lessThan(FriendExpressionPose.rest.left.center.dx));
    expect(right.left.center.dx, greaterThan(FriendExpressionPose.rest.left.center.dx));
    expect(left.id, FriendExpressionId.glance);
  });
}
