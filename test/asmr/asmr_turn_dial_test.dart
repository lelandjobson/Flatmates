import 'dart:math' as math;

import 'package:flatmates/asmr/asmr_turn_dial.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const dial = AsmrTurnDial(
    center: Offset(400, 502),
    halfLength: 200,
    pivot: Offset(400, 450),
  );

  test('pips sit at equal 10° steps up to 90°', () {
    final pips = dial.pips;
    expect(pips.first, 0);
    final right = pips.where((x) => x > 0).toList();
    for (var k = 0; k < right.length; k++) {
      final angle = math.pi / 2 - dial.angleAt(right[k]);
      expect(angle, closeTo((k + 1) * 10 * math.pi / 180, 1e-9));
      expect(pips, contains(-right[k]));
      if (k > 0) {
        expect(right[k] - right[k - 1], closeTo(right[1] - right[0], 1e-9));
      }
    }
    expect(right.last, lessThanOrEqualTo(dial.halfLength));
  });

  test('the knob follows the finger through the middle and resists at the '
      'ends', () {
    expect(dial.freeReach, closeTo(160, 1e-9));
    expect(dial.knobFor(100, cruise: true), 100);
    expect(dial.knobFor(-160, cruise: true), -160);
    final pulled = dial.knobFor(200, cruise: true);
    expect(pulled, greaterThan(160));
    expect(pulled, lessThan(200));
    expect(dial.knobFor(1000, cruise: true), lessThan(200));
    expect(
      dial.knobFor(1000, cruise: true),
      greaterThan(dial.knobFor(400, cruise: true)),
    );
    expect(
      dial.knobFor(-1000, cruise: true),
      closeTo(-dial.knobFor(1000, cruise: true), 1e-9),
    );
  });

  test('full drags reach exactly 90 degrees and clamp beyond both ends', () {
    for (final sign in [-1, 1]) {
      for (final travel in [200.0, 1000.0]) {
        final x = dial.knobFor(sign * travel);
        expect(x, sign * dial.halfLength);
        expect(
          dial.angleAt(x) - dial.angleAt(0),
          closeTo(-sign * math.pi / 2, 1e-9),
        );
      }
    }
  });

  test('the ends are the outer tenth of the bar on each side', () {
    expect(dial.inEnd(150), isFalse);
    expect(dial.inEnd(160), isFalse);
    expect(dial.inEnd(170), isTrue);
    expect(dial.inEnd(-170), isTrue);
    expect(dial.cruiseSign(170), -1);
    expect(dial.cruiseSign(-170), 1);
    expect(
      dial.angleAt(100) - dial.angleAt(0),
      closeTo(-math.pi / 4, 1e-9),
      reason: 'moving right turns the paper as the finger used to',
    );
  });

  test('the circle is taken, and the bar is not', () {
    expect(dial.grabs(const Offset(400, 502)), isTrue);
    expect(dial.grabs(const Offset(420, 510)), isTrue);
    expect(dial.grabs(const Offset(610, 502)), isFalse);
    expect(dial.grabs(const Offset(400, 540)), isFalse);
  });
}
