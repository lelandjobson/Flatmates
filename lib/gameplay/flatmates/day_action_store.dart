import '../tiles/tile_event_hub.dart';
import 'day_action.dart';

/// One friend's repeating day itinerary plus last computed hops.
class FlatmateDayPlan {
  FlatmateDayPlan({
    required this.friendId,
    required List<DayActionSlot> slots,
    List<List<(int, int)>?>? hops,
    this.firstBrokenHop,
  }) : slots = List<DayActionSlot>.from(slots),
       hops = hops == null
           ? List<List<(int, int)>?>.filled(slots.length, null)
           : List<List<(int, int)>?>.from(hops);

  factory FlatmateDayPlan.empty(String friendId, {(int, int)? home}) {
    return FlatmateDayPlan(
      friendId: friendId,
      slots: emptyDaySlots(home),
    );
  }

  final String friendId;
  final List<DayActionSlot> slots;
  final List<List<(int, int)>?> hops;
  int? firstBrokenHop;

  (int, int)? get homeTile {
    if (slots.isEmpty) return null;
    final sleep = slots.last;
    return sleep.locked ? sleep.tile : null;
  }

  void bindHome((int, int)? home) {
    if (slots.isEmpty) return;
    slots[slots.length - 1] = lockedSleepSlot(home);
  }

  bool setSlot(int index, DayActionSlot slot) {
    if (index < 0 || index >= slots.length) return false;
    if (slots[index].locked) return false;
    slots[index] = slot;
    return true;
  }

  int get summarySlotIndex {
    for (var i = 0; i < slots.length; i++) {
      if (slots[i].isProgrammed && !slots[i].locked) return i;
    }
    return slots.length - 1;
  }

  /// Concatenated hops before the first break. Includes start tile once.
  List<(int, int)> playablePath() {
    final out = <(int, int)>[];
    final limit = firstBrokenHop ?? slots.length;
    for (var i = 0; i < limit && i < hops.length; i++) {
      final hop = hops[i];
      if (hop == null || hop.isEmpty) continue;
      if (out.isEmpty) {
        out.addAll(hop);
      } else {
        out.addAll(hop.skip(1));
      }
    }
    return out;
  }

  Set<(int, int)> watchedTiles() {
    final tiles = <(int, int)>{};
    final home = homeTile;
    if (home != null) tiles.add(home);
    for (final slot in slots) {
      final tile = slot.tile;
      if (tile != null) tiles.add(tile);
    }
    for (final hop in hops) {
      if (hop == null) continue;
      tiles.addAll(hop);
    }
    return tiles;
  }

  FlatmateDayPlan copy() => FlatmateDayPlan(
        friendId: friendId,
        slots: [
          for (final slot in slots)
            DayActionSlot(
              kind: slot.kind,
              tile: slot.tile,
              locked: slot.locked,
            ),
        ],
        hops: [
          for (final hop in hops)
            hop == null ? null : List<(int, int)>.from(hop),
        ],
        firstBrokenHop: firstBrokenHop,
      );
}

class FlatmateDayPlanStore {
  final Map<String, FlatmateDayPlan> _plans = {};

  Iterable<FlatmateDayPlan> get plans => _plans.values;

  FlatmateDayPlan? byId(String friendId) => _plans[friendId];

  FlatmateDayPlan ensure(String friendId, {(int, int)? home}) {
    final existing = _plans[friendId];
    if (existing != null) {
      if (home != null) existing.bindHome(home);
      return existing;
    }
    final plan = FlatmateDayPlan.empty(friendId, home: home);
    _plans[friendId] = plan;
    return plan;
  }

  void remove(String friendId) => _plans.remove(friendId);

  void prune(Iterable<String> keepIds) {
    final keep = keepIds.toSet();
    _plans.removeWhere((id, _) => !keep.contains(id));
  }

  void restoreFrom(FlatmateDayPlanStore other) {
    _plans
      ..clear()
      ..addAll({
        for (final entry in other._plans.entries) entry.key: entry.value.copy(),
      });
  }

  FlatmateDayPlanStore copy() {
    final next = FlatmateDayPlanStore();
    next.restoreFrom(this);
    return next;
  }
}

const kDayPlanWatchKinds = {
  TileEventKind.path,
  TileEventKind.wall,
  TileEventKind.program,
  TileEventKind.volume,
};

/// Keeps [TileEventHub] subscriptions in sync with each plan's route tiles.
class DayPlanWatch {
  DayPlanWatch(this.hub, this.store);

  final TileEventHub hub;
  final FlatmateDayPlanStore store;

  void attach(
    String friendId,
    void Function(String friendId) onTouched,
  ) {
    final plan = store.byId(friendId);
    if (plan == null) {
      hub.unsubscribe(friendId);
      return;
    }
    hub.subscribe(
      id: friendId,
      tiles: plan.watchedTiles(),
      kinds: kDayPlanWatchKinds,
      onEvent: (_, _) => onTouched(friendId),
    );
  }

  void detach(String friendId) => hub.unsubscribe(friendId);

  void detachMissing(Iterable<String> keepIds) {
    final keep = keepIds.toSet();
    for (final plan in List<FlatmateDayPlan>.from(store.plans)) {
      if (!keep.contains(plan.friendId)) detach(plan.friendId);
    }
  }
}