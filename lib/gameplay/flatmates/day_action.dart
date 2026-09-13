import 'package:flutter/material.dart';

/// Programmable slots in a flatmate day, plus the locked sleep at the end.
const kFlatmateDayActionSlots = 3;

/// Chebyshev radius from the bedroom home tile.
const kFlatmateActionRange = 4;

const kDayStartYellow = Color(0xFFFFE08A);
const kDayEndMidnight = Color(0xFF0D1B4C);

/// Morning → night tint for slot [index] in a day of [count] slots.
Color dayProgressColor(int index, {int count = kFlatmateDayActionSlots}) {
  if (count <= 1) return kDayEndMidnight;
  return Color.lerp(
    kDayStartYellow,
    kDayEndMidnight,
    (index / (count - 1)).clamp(0.0, 1.0),
  )!;
}

enum DayActionKind { collect, dye, dwell, sleep }

const kProgrammableDayActions = [
  DayActionKind.collect,
  DayActionKind.dye,
  DayActionKind.dwell,
];

extension DayActionKindX on DayActionKind {
  IconData get icon => switch (this) {
        DayActionKind.collect => Icons.inventory_2_outlined,
        DayActionKind.dye => Icons.palette_outlined,
        DayActionKind.dwell => Icons.chair_outlined,
        DayActionKind.sleep => Icons.bed_outlined,
      };

  String get label => switch (this) {
        DayActionKind.collect => 'Collect',
        DayActionKind.dye => 'Dye',
        DayActionKind.dwell => 'Dwell',
        DayActionKind.sleep => 'Sleep',
      };
}

/// One slot in a repeating day itinerary.
class DayActionSlot {
  const DayActionSlot({
    this.kind,
    this.tile,
    this.locked = false,
  });

  final DayActionKind? kind;
  final (int, int)? tile;
  final bool locked;

  bool get isEmpty => kind == null && !locked;

  bool get isProgrammed => kind != null && tile != null;

  DayActionSlot copyWith({
    DayActionKind? kind,
    (int, int)? tile,
    bool? locked,
    bool clearKind = false,
    bool clearTile = false,
  }) {
    return DayActionSlot(
      kind: clearKind ? null : (kind ?? this.kind),
      tile: clearTile ? null : (tile ?? this.tile),
      locked: locked ?? this.locked,
    );
  }
}

DayActionSlot lockedSleepSlot((int, int)? home) => DayActionSlot(
      kind: DayActionKind.sleep,
      tile: home,
      locked: true,
    );

List<DayActionSlot> emptyDaySlots((int, int)? home) => [
      for (var i = 0; i < kFlatmateDayActionSlots - 1; i++)
        const DayActionSlot(),
      lockedSleepSlot(home),
    ];
