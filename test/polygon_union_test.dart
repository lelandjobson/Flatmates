import 'dart:ui';

import 'package:flatmates/geometry/polygon_union.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('adjacent equal rects union to one outer loop', () {
    final a = [
      const Offset(0, 0),
      const Offset(8, 0),
      const Offset(8, 8),
      const Offset(0, 8),
    ];
    final b = [
      const Offset(8, 0),
      const Offset(16, 0),
      const Offset(16, 8),
      const Offset(8, 8),
    ];
    final loops = unionPolygons([a, b]);
    expect(loops, hasLength(1));
    expect(_loopLength(loops.single), closeTo(48, 1e-4));
  });

  test('T-junction rects drop the overlapping inner seam', () {
    final large = [
      const Offset(0, 0),
      const Offset(16, 0),
      const Offset(16, 8),
      const Offset(0, 8),
    ];
    final inset = [
      const Offset(0, 8),
      const Offset(7, 8),
      const Offset(7, 16),
      const Offset(0, 16),
    ];
    final loops = unionPolygons([large, inset]);
    expect(loops, hasLength(1));
    // 16+8+9+8+7+16 = 64. A leftover inner seam would add 7 or 16.
    expect(_loopLength(loops.single), closeTo(64, 1e-4));
  });
}

double _loopLength(List<Offset> loop) {
  var length = 0.0;
  for (var i = 0; i < loop.length; i++) {
    length += (loop[i] - loop[(i + 1) % loop.length]).distance;
  }
  return length;
}
