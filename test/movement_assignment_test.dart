import 'package:flatmates/gameplay/flatmates/movement_assignment.dart';
import 'package:flatmates/gameplay/flatmates/movement_profile.dart';
import 'package:flatmates/gameplay/friends/friend_instance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('assigning a friend replaces their previous pattern', () {
    final first = MovementAssignments.empty.assign(
      friendId: kCubeboyFriend.id,
      patternId: 'smooth1',
    );
    final second = first.assign(
      friendId: kCubeboyFriend.id,
      patternId: 'slow1',
    );
    expect(second.patternIdFor(kCubeboyFriend.id), 'slow1');
    expect(second.friendIdsFor('smooth1'), isEmpty);
    expect(second.friendIdsFor('slow1'), [kCubeboyFriend.id]);
  });

  test('two friends can share a pattern, but a friend has only one', () {
    final map = MovementAssignments.empty
        .assign(friendId: kCubeboyFriend.id, patternId: 'smooth1')
        .assign(friendId: kFrogmanFriend.id, patternId: 'smooth1')
        .assign(friendId: kFrogmanFriend.id, patternId: 'slow1');
    expect(map.patternIdFor(kCubeboyFriend.id), 'smooth1');
    expect(map.patternIdFor(kFrogmanFriend.id), 'slow1');
    expect(map.friendIdsFor('smooth1'), [kCubeboyFriend.id]);
  });

  test('JSON round-trips assignments', () {
    final original = MovementAssignments({
      kCubeboyFriend.id: 'smooth1',
      kConicoFriend.id: 'slow1',
    });
    expect(MovementAssignments.fromJson(original.toJson()), original);
  });

  test('duplicate id is unique and does not reuse the source', () {
    expect(movementPatternCopyId('smooth1', ['smooth1']), 'smooth1-copy');
    expect(
      movementPatternCopyId('smooth1', ['smooth1', 'smooth1-copy']),
      'smooth1-copy-2',
    );
    expect(movementPatternCopyName('Smooth1'), 'Smooth1 copy');
  });

  test('duplicate leaves the original friend assignment on the source pattern', () {
    final assignments = MovementAssignments({
      kCubeboyFriend.id: 'smooth1',
    });
    final copyId = movementPatternCopyId('smooth1', ['smooth1']);
    expect(assignments.patternIdFor(kCubeboyFriend.id), 'smooth1');
    expect(assignments.friendIdsFor(copyId), isEmpty);
  });

  test('movementPatternsByFriend uses assignment then fallback', () {
    const smooth = MovementProfile(id: 'smooth1', name: 'Smooth1');
    const fallback = MovementProfile(id: 'default', name: 'Default');
    final mapped = movementPatternsByFriend(
      assignments: MovementAssignments({
        kCubeboyFriend.id: 'smooth1',
        kFrogmanFriend.id: 'missing',
      }),
      catalog: const [smooth, fallback],
      fallback: fallback,
    );
    expect(mapped[kCubeboyFriend.id], smooth);
    expect(mapped[kFrogmanFriend.id], fallback);
    expect(mapped[kConicoFriend.id], fallback);
  });
}
