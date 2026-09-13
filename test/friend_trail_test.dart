import 'package:flatmates/gameplay/flatmates/flatmate_movement.dart';
import 'package:flatmates/gameplay/friends/friend_instance.dart';
import 'package:flatmates/gameplay/friends/friend_trail.dart';
import 'package:flatmates/user/friend_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

void main() {
  test('idle friends leave no ink', () {
    final trails = FriendTrailStore();
    final friend = FriendInstance(
      id: 'idle',
      friend: kCubeboyFriend,
      position: Vector3(1, 1, 2),
    );
    trails.record(friend);
    friend.position.setValues(8, 1, 2);
    trails.record(friend);
    expect(trails.isEmpty, isTrue);
  });

  test('first moving sample drops a stamp in the friend color', () {
    final trails = FriendTrailStore();
    final friend = _walker(x: 0, z: 0);
    trails.record(friend);
    final stamps = trails.stampsFor(friend.id);
    expect(stamps, hasLength(1));
    expect(stamps.first.xz, const Offset(0, 0));
    expect(stamps.first.color, kCubeboyFriend.color);
    expect(stamps.first.age, 0);
  });

  test('spacing fills the walked gap and skips tiny steps', () {
    final trails = FriendTrailStore(spacing: 0.3);
    trails.recordPoint(
      friendId: 'a',
      xz: Offset.zero,
      color: Colors.red,
      moving: true,
    );
    trails.recordPoint(
      friendId: 'a',
      xz: const Offset(0.1, 0),
      color: Colors.red,
      moving: true,
    );
    expect(trails.stampsFor('a'), hasLength(1));

    trails.recordPoint(
      friendId: 'a',
      xz: const Offset(0.9, 0),
      color: Colors.red,
      moving: true,
    );
    final xs = [for (final stamp in trails.stampsFor('a')) stamp.xz.dx];
    expect(xs, hasLength(4));
    expect(xs[0], 0);
    expect(xs[1], closeTo(0.3, 1e-9));
    expect(xs[2], closeTo(0.6, 1e-9));
    expect(xs[3], closeTo(0.9, 1e-9));
  });

  test('a teleport starts a new stroke instead of filling the gap', () {
    final trails = FriendTrailStore(spacing: 0.3, maxJump: 5);
    trails.recordPoint(
      friendId: 'a',
      xz: Offset.zero,
      color: Colors.blue,
      moving: true,
    );
    trails.recordPoint(
      friendId: 'a',
      xz: const Offset(12, 0),
      color: Colors.blue,
      moving: true,
    );
    final stamps = trails.stampsFor('a');
    expect(stamps, hasLength(2));
    expect(stamps.first.xz, Offset.zero);
    expect(stamps.last.xz, const Offset(12, 0));
  });

  test('stamps fade over two seconds then prune', () {
    final trails = FriendTrailStore(lifetime: 2);
    trails.recordPoint(
      friendId: 'a',
      xz: Offset.zero,
      color: Colors.green,
      moving: true,
    );
    trails.advance(1);
    expect(trails.stampsFor('a').single.age, 1);
    expect(friendTrailFade(age: 1, lifetime: 2), greaterThan(0.2));
    expect(
      friendTrailFade(age: 1, lifetime: 2),
      lessThan(friendTrailFade(age: 0, lifetime: 2)),
    );
    trails.advance(1);
    expect(trails.isEmpty, isTrue);
    expect(friendTrailFade(age: 2, lifetime: 2), 0);
  });

  test('ink color stays the friend hue but darker', () {
    final ink = friendTrailInkColor(kCubeboyFriend.color);
    final src = HSLColor.fromColor(kCubeboyFriend.color);
    final dst = HSLColor.fromColor(ink);
    expect(
      (dst.hue - src.hue).abs() < 8 || (dst.hue - src.hue).abs() > 352,
      isTrue,
    );
    expect(dst.lightness, lessThan(src.lightness));
  });

  test('separate friends keep separate strokes', () {
    final trails = FriendTrailStore();
    final a = _walker(id: 'a', x: 0, z: 0, friend: kCubeboyFriend);
    final b = _walker(id: 'b', x: 2, z: 4, friend: kFrogmanFriend);
    trails.record(a);
    trails.record(b);
    expect(trails.trails, hasLength(2));
    expect(trails.stampsFor('a').single.color, kCubeboyFriend.color);
    expect(trails.stampsFor('b').single.color, kFrogmanFriend.color);
  });
}

FriendInstance _walker({
  String id = 'walk',
  double x = 0,
  double z = 0,
  Friend friend = kCubeboyFriend,
}) {
  final instance = FriendInstance(
    id: id,
    friend: friend,
    position: Vector3(x, 1, z),
  );
  instance.movement.phase = MovementPhase.moving;
  return instance;
}
