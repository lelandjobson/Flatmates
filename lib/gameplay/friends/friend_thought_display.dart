import 'friend_thought.dart';

/// Default thought-bubble visibility. Flip to opt a feature back in.
const kDefaultShowFriendFeelings = false;
const kDefaultShowFriendDesires = true;

/// Per-view checkboxes for feeling cards vs desire clouds / percolate.
class FriendThoughtDisplay {
  const FriendThoughtDisplay({
    this.showFeelings = kDefaultShowFriendFeelings,
    this.showDesires = kDefaultShowFriendDesires,
  });

  final bool showFeelings;
  final bool showDesires;

  static const desiresOnly = FriendThoughtDisplay();
  static const all = FriendThoughtDisplay(
    showFeelings: true,
    showDesires: true,
  );
  static const none = FriendThoughtDisplay(
    showFeelings: false,
    showDesires: false,
  );

  bool get showAny => showFeelings || showDesires;

  bool showsFeelingCard(FriendThought thought) =>
      showFeelings && thought.showFeelingCard;

  bool showsDesireCloud(FriendThought thought) =>
      showDesires && thought.showDesireCloud;

  bool showsPercolate(FriendThought thought) =>
      showDesires && thought.percolating && !thought.showDesireCloud;

  bool showsAny(FriendThought thought) =>
      showsFeelingCard(thought) ||
      showsDesireCloud(thought) ||
      showsPercolate(thought);

  FriendThoughtDisplay copyWith({bool? showFeelings, bool? showDesires}) {
    return FriendThoughtDisplay(
      showFeelings: showFeelings ?? this.showFeelings,
      showDesires: showDesires ?? this.showDesires,
    );
  }
}
