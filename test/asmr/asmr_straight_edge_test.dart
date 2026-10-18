import 'dart:math' as math;

import 'package:flatmates/asmr/asmr_straight_edge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const edge = AsmrStraightEdge(anchor: Offset(0, 100));

  test('the rule is 50 pixels across, with an edge on each side', () {
    expect(edge.contains(const Offset(500, 124)), isTrue);
    expect(edge.contains(const Offset(-500, 76)), isTrue);
    expect(edge.contains(const Offset(0, 126)), isFalse);
    expect(edge.sideOf(const Offset(0, 200)), 1);
    expect(edge.sideOf(const Offset(0, 0)), -1);
  });

  test('a blade is held on its side, and slides along an edge near it', () {
    expect(edge.hold(const Offset(3, 110), 1), const Offset(3, 125));
    expect(edge.hold(const Offset(3, 110), -1), const Offset(3, 75));
    expect(edge.hold(const Offset(3, 131), 1, snap: 10), const Offset(3, 125));
    expect(edge.hold(const Offset(3, 140), 1, snap: 10), const Offset(3, 140));
  });

  test('a line from one side runs until it meets the rule', () {
    final (lo, hi) = edge.lineLimits(const Offset(0, 0), const Offset(0, 10));
    expect(lo, double.negativeInfinity);
    expect(hi, closeTo(7.5, 1e-9));
    final (back, ahead) = edge.lineLimits(
      const Offset(0, 0),
      const Offset(0, -10),
    );
    expect(back, closeTo(-7.5, 1e-9));
    expect(ahead, double.infinity);
    final (a, b) = edge.lineLimits(const Offset(0, 0), const Offset(10, 0));
    expect(a, double.negativeInfinity);
    expect(b, double.infinity);
  });

  test('the rotate handle sits just outside the edge', () {
    expect(edge.rotateHandle(Offset.zero), const Offset(0, 153));
  });

  test('turning the rule turns its edges', () {
    final turned = edge.copyWith(anchor: Offset.zero, angle: math.pi / 2);
    expect(turned.contains(const Offset(20, 300)), isTrue);
    expect(turned.contains(const Offset(30, 0)), isFalse);
  });
}
