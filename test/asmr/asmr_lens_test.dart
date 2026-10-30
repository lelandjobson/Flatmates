import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flatmates/asmr/asmr_lens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('straight down leaves the desk where it is', () {
    const point = Offset(120, -40);
    expect(AsmrCutLens.overhead.project(point), point);
    expect(AsmrCutLens.overhead.unproject(point), point);
    expect(AsmrCutLens.elevationFor(0), closeTo(math.pi / 2, 1e-9));
    expect(
      AsmrCutLens.overhead.deskMatrix(
        origin: Offset.zero,
        scale: 2,
        angle: 0.4,
      ),
      isNull,
    );
  });

  test(
    'a pitched lens keeps the cut fixed and brings the paper ahead back',
    () {
      final lens = AsmrCutLens(
        pivot: const Offset(400, 450),
        focal: 800,
        elevation: AsmrCutLens.horizonElevation,
      );
      expect(lens.project(const Offset(400, 450)), const Offset(400, 450));
      final ahead = lens.project(const Offset(400, 350));
      expect(ahead.dx, closeTo(400, 1e-6));
      expect(ahead.dy, greaterThan(350));
      expect(ahead.dy, lessThan(450));
      final back = lens.unproject(ahead);
      expect(back.dx, closeTo(400, 1e-4));
      expect(back.dy, closeTo(350, 1e-4));

      const near = Offset(480, 520);
      final wider = lens.project(near);
      expect(wider.dx, greaterThan(484));
      expect(
        lens.unproject(wider),
        offsetMoreOrLessEquals(near, epsilon: 1e-3),
      );
    },
  );

  test('the desk matrix matches the lens', () {
    final lens = AsmrCutLens(
      pivot: const Offset(400, 450),
      focal: AsmrCutLens.focalPixels(35, 600),
      elevation: AsmrCutLens.elevationFor(0.7),
    );
    const origin = Offset(380, 310);
    const scale = 2.4;
    const angle = 0.35;
    final matrix = lens.deskMatrix(origin: origin, scale: scale, angle: angle);
    expect(matrix, isNotNull);
    for (final desk in const [
      Offset.zero,
      Offset(40, -20),
      Offset(-15, 30),
      Offset(8, 8),
    ]) {
      final flat = origin + _spin(desk, angle) * scale;
      expect(_apply(matrix!, desk), offsetMoreOrLessEquals(lens.project(flat)));
    }
  });
}

Offset _spin(Offset v, double angle) {
  final c = math.cos(angle);
  final s = math.sin(angle);
  return Offset(c * v.dx - s * v.dy, s * v.dx + c * v.dy);
}

Offset _apply(Float64List m, Offset p) {
  final x = p.dx;
  final y = p.dy;
  final w = m[3] * x + m[7] * y + m[15];
  return Offset(
    (m[0] * x + m[4] * y + m[12]) / w,
    (m[1] * x + m[5] * y + m[13]) / w,
  );
}
