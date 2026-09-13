import 'package:flatmates/gameplay/friends/friend_expression_pose.dart';
import 'package:flatmates/gameplay/friends/friend_eye_profile.dart';
import 'package:flatmates/gameplay/friends/friend_eye_profile_io.dart';
import 'package:flatmates/gameplay/friends/friend_instance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default profile leaves rest eyes unchanged', () {
    final applied = FriendEyeProfile.defaults.apply(FriendExpressionPose.rest);
    expect(
      applied.left.center.dx,
      closeTo(FriendExpressionPose.rest.left.center.dx, 1e-9),
    );
    expect(
      applied.left.ring[0].dx - applied.left.center.dx,
      closeTo(0.64, 1e-9),
    );
  });

  test('spacing pulls eyes apart and size scales the disk', () {
    final wide = const FriendEyeProfile(spacing: 2).apply(FriendExpressionPose.rest);
    expect(
      wide.right.center.dx,
      closeTo(FriendExpressionPose.rest.right.center.dx * 2, 1e-9),
    );
    final big = const FriendEyeProfile(size: 2).apply(FriendExpressionPose.rest);
    expect(
      big.left.ring[0].dx - big.left.center.dx,
      closeTo(1.28, 1e-9),
    );
  });

  test('json roundtrip and template keys', () {
    const profile = FriendEyeProfile(
      spacing: 1.2,
      size: 0.8,
      width: 1.1,
      height: 0.9,
      lift: 0.05,
    );
    final again = FriendEyeProfile.fromJson(profile.toJson());
    expect(again, profile);
    expect(eyeProfileKey(kCubeboyFriend), kCubeboyFriend.id);
    expect(eyeProfileKey(kFrogmanFriend), kFrogmanFriend.id);
    expect(eyeProfileKey(kConicoFriend), kConicoFriend.id);
  });

  test('assignment catalog stores per friend', () {
    final catalog = FriendEyeProfiles.empty.withProfile(
      kCubeboyFriend.id,
      const FriendEyeProfile(size: 1.4),
    );
    expect(catalog.forFriend(kCubeboyFriend).size, 1.4);
    expect(catalog.forFriend(kFrogmanFriend), FriendEyeProfile.defaults);
    final json = FriendEyeProfiles.fromJson(catalog.toJson());
    expect(json.forKey(kCubeboyFriend.id).size, 1.4);
  });
}
