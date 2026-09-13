import 'package:flatmates/gameplay/friends/friend_desire.dart';
import 'package:flatmates/gameplay/friends/friend_feeling.dart';
import 'package:flatmates/gameplay/friends/friend_instance.dart';
import 'package:flatmates/gameplay/friends/friend_mesh_sync.dart';
import 'package:flatmates/gameplay/friends/friend_thought.dart';
import 'package:flatmates/gameplay/friends/friend_thought_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  FriendThought emptyThought() => FriendThought(seed: 't', assignDemo: false);

  test('new friends get a seed-stable demo thought', () {
    final a = FriendInstance(
      id: 'same',
      friend: kCubeboyFriend,
      position: Vector3.zero(),
    );
    final b = FriendInstance(
      id: 'same',
      friend: kCubeboyFriend,
      position: Vector3.zero(),
    );
    expect(a.thought.feeling, isNotNull);
    expect(a.thought.feeling?.id, b.thought.feeling?.id);
    expect(a.thought.desire?.id, b.thought.desire?.id);
  });

  test('desires percolate; feelings do not', () {
    final thought = emptyThought()
      ..setFeeling(feelingById('happy'))
      ..setDesire(desireById('snack'));
    expect(thought.percolating, isTrue);
    expect(thought.showDesireCloud, isFalse);
    thought.tick(0.1, inView: true, hovered: true);
    expect(thought.showDesireCloud, isTrue);
    expect(thought.showFeelingCard, isTrue);

    thought.setDesire(null);
    expect(thought.percolating, isFalse);
    expect(thought.showDesireCloud, isFalse);
  });

  test('feeling stays hidden until the in-view gate and delay elapse', () {
    final thought = emptyThought()..setFeeling(feelingById('sad'));
    thought.debugSetGates(inViewNeed: 1.0, delayNeed: 1.0);
    thought.tick(0.5, inView: true, hovered: false);
    expect(thought.showFeelingCard, isFalse);
    expect(thought.isWatchingInView, isTrue);

    thought.tick(0.6, inView: true, hovered: false);
    expect(thought.isWaitingToShowFeeling, isTrue);
    expect(thought.showFeelingCard, isFalse);

    thought.tick(1.1, inView: true, hovered: false);
    expect(thought.isAutoShowingFeeling, isTrue);
    expect(thought.showFeelingCard, isTrue);
  });

  test('auto-shown feeling hides after five seconds unless hovered', () {
    final thought = emptyThought()..setFeeling(feelingById('happy'));
    thought.debugSetGates(inViewNeed: 0.1, delayNeed: 0.1);
    thought.tick(0.2, inView: true, hovered: false);
    thought.tick(0.2, inView: true, hovered: false);
    expect(thought.isAutoShowingFeeling, isTrue);

    thought.tick(2.0, inView: true, hovered: true);
    expect(thought.isAutoShowingFeeling, isTrue);

    thought.tick(5.1, inView: true, hovered: false);
    expect(thought.isAutoShowingFeeling, isFalse);
    expect(thought.showFeelingCard, isFalse);
  });

  test('leaving view cancels a pending show; hover can still open it', () {
    final thought = emptyThought()..setFeeling(feelingById('curious'));
    thought.debugSetGates(inViewNeed: 0.2, delayNeed: 2.0);
    thought.tick(0.3, inView: true, hovered: false);
    expect(thought.isWaitingToShowFeeling, isTrue);

    thought.tick(0.1, inView: false, hovered: false);
    expect(thought.isWaitingToShowFeeling, isFalse);
    expect(thought.showFeelingCard, isFalse);

    thought.tick(0.1, inView: false, hovered: true);
    expect(thought.showFeelingCard, isTrue);
  });

  test('thought seat is halfway between the crown and the old high lift', () {
    const tileSize = 8.0;
    final friend = FriendInstance(
      id: 'head',
      friend: kCubeboyFriend,
      position: Vector3(0, FriendMeshLayout.sitOnGroundY(tileSize: tileSize), 0),
    );
    final low = friend.position.y +
        FriendMeshLayout.halfSize(tileSize: tileSize) +
        kPercolateAboveHead;
    final high = friend.position.y + kThoughtBubbleLift;
    expect(
      thoughtAnchor(friend, tileSize: tileSize).y,
      closeTo((low + high) * 0.5, 1e-9),
    );
    expect(
      percolateAnchor(friend, tileSize: tileSize).y,
      thoughtAnchor(friend, tileSize: tileSize).y,
    );
  });

  test('clone keeps the assigned feeling and desire', () {
    final src = FriendInstance(
      id: 'clone',
      friend: kCubeboyFriend,
      position: Vector3.zero(),
    )..thought.setFeeling(feelingById('love'))
      ..thought.setDesire(desireById('music'));
    final copy = src.clone();
    expect(copy.thought.feeling?.id, 'love');
    expect(copy.thought.desire?.id, 'music');
  });
}
