import 'package:flatmates/gameplay/flatmates/day_action.dart';
import 'package:flatmates/gameplay/flatmates/flatmate_range.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('action range is a 4-tile square around the bedroom', () {
    expect(kFlatmateActionRange, 4);
    expect(inFlatmateRange((6, 2), (2, 2)), isTrue);
    expect(inFlatmateRange((7, 2), (2, 2)), isFalse);
    expect(flatmateRangeTiles((2, 2)), hasLength(81));
  });

  test('world corners are a square 9 tiles on a side', () {
    const tileSize = 8.0;
    final corners = flatmateRangeWorldCorners((2, 2), tileSize: tileSize);
    expect(corners, hasLength(4));
    expect(corners[0].x, (2 - 4) * tileSize);
    expect(corners[0].z, (2 - 4) * tileSize);
    expect(corners[2].x, (2 + 4 + 1) * tileSize);
    expect(corners[2].z, (2 + 4 + 1) * tileSize);
    final width = corners[1].x - corners[0].x;
    final depth = corners[2].z - corners[1].z;
    expect(width, 9 * tileSize);
    expect(depth, width);
  });

  test('outside dim path punches a hole for the range quad', () {
    const viewport = Size(200, 100);
    final hole = [
      const Offset(40, 20),
      const Offset(160, 20),
      const Offset(160, 80),
      const Offset(40, 80),
    ];
    final path = flatmateRangeOutsidePath(viewport: viewport, quad: hole);
    expect(path, isNotNull);
    expect(path!.fillType, PathFillType.evenOdd);
    expect(path.contains(const Offset(20, 10)), isTrue);
    expect(path.contains(const Offset(100, 50)), isFalse);
    expect(flatmateRangeOutsidePath(viewport: viewport, quad: hole.take(3).toList()), isNull);
  });
}
