import 'package:flatmates/gameplay/friends/friend_desire.dart';
import 'package:flatmates/gameplay/friends/friend_feeling.dart';
import 'package:flatmates/gameplay/friends/friend_thought.dart';
import 'package:flatmates/gameplay/friends/friend_thought_display.dart';
import 'package:flutter_test/flutter_test.dart';

FriendThought _thought() {
  return FriendThought(seed: 'display', assignDemo: false)
    ..setFeeling(feelingById('happy'))
    ..setDesire(desireById('snack'));
}

void main() {
  test('defaults hide feelings and keep desires', () {
    expect(kDefaultShowFriendFeelings, isFalse);
    expect(kDefaultShowFriendDesires, isTrue);
    expect(const FriendThoughtDisplay().showFeelings, isFalse);
    expect(const FriendThoughtDisplay().showDesires, isTrue);
  });

  test('display flags gate feeling cards without changing thought state', () {
    final thought = _thought()..hovered = true;
    expect(thought.showFeelingCard, isTrue);
    expect(thought.showDesireCloud, isTrue);

    const off = FriendThoughtDisplay();
    expect(off.showsFeelingCard(thought), isFalse);
    expect(off.showsDesireCloud(thought), isTrue);
    expect(off.showsPercolate(thought), isFalse);

    const on = FriendThoughtDisplay.all;
    expect(on.showsFeelingCard(thought), isTrue);
    expect(on.showsDesireCloud(thought), isTrue);
  });

  test('hiding desires also hides percolate teasers', () {
    final thought = _thought();
    expect(thought.percolating, isTrue);
    expect(const FriendThoughtDisplay().showsPercolate(thought), isTrue);
    expect(
      const FriendThoughtDisplay(showDesires: false).showsPercolate(thought),
      isFalse,
    );
    expect(FriendThoughtDisplay.none.showsAny(thought), isFalse);
  });
}
