import 'package:flatmates/gameplay/flatmates/day_action.dart';
import 'package:flatmates/gameplay/flatmates/day_action_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a new plan has three slots and locks sleep at home', () {
    const home = (4, 5);
    final plan = FlatmateDayPlan.empty('friend-1', home: home);
    expect(plan.slots, hasLength(kFlatmateDayActionSlots));
    expect(plan.slots.last.locked, isTrue);
    expect(plan.slots.last.kind, DayActionKind.sleep);
    expect(plan.slots.last.tile, home);
    expect(plan.slots.take(2).every((s) => s.isEmpty), isTrue);
  });

  test('cannot overwrite the locked sleep slot', () {
    final plan = FlatmateDayPlan.empty('friend-1', home: (0, 0));
    expect(
      plan.setSlot(
        2,
        const DayActionSlot(kind: DayActionKind.collect, tile: (1, 1)),
      ),
      isFalse,
    );
    expect(plan.slots.last.kind, DayActionKind.sleep);
  });

  test('bindHome updates sleep and ensure reuses the same plan', () {
    final store = FlatmateDayPlanStore();
    final first = store.ensure('a', home: (1, 1));
    first.setSlot(
      0,
      const DayActionSlot(kind: DayActionKind.dye, tile: (2, 2)),
    );
    final again = store.ensure('a', home: (3, 3));
    expect(identical(first, again), isTrue);
    expect(again.slots[0].kind, DayActionKind.dye);
    expect(again.slots.last.tile, (3, 3));
  });

  test('copy is independent of later slot edits', () {
    final store = FlatmateDayPlanStore();
    store.ensure('a', home: (0, 0)).setSlot(
          0,
          const DayActionSlot(kind: DayActionKind.collect, tile: (1, 0)),
        );
    final snap = store.copy();
    store.ensure('a').setSlot(
          0,
          const DayActionSlot(kind: DayActionKind.dwell, tile: (2, 0)),
        );
    expect(snap.byId('a')!.slots[0].kind, DayActionKind.collect);
    expect(store.byId('a')!.slots[0].kind, DayActionKind.dwell);
  });
}