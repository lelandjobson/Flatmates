import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/pencil_dwell.dart';

void main() {
  testWidgets('dot growth and shrink interpolate independently of the hold', (
    tester,
  ) async {
    final dwell = PencilDwell(const TestVSync(), (_, _) => true);
    addTearDown(dwell.dispose);
    const a = Offset.zero, b = Offset(1, 0);
    dwell.begin(a);
    expect(dwell.dotSelection[a], 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    expect(dwell.dotSelection[a], inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 70));
    expect(dwell.dotSelection[a], closeTo(1, 1e-6));
    dwell.pointAt(b);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 301));
    expect(dwell.tail, b);
    expect(dwell.dotSelection[a], 1);
    await tester.pump(const Duration(milliseconds: 70));
    expect(dwell.dotSelection[a], inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 71));
    expect(dwell.dotSelection[a] ?? 0, closeTo(0, 1e-6));
    expect(dwell.dotSelection[b], 1);
  });
  testWidgets(
    'only sustained endpoints commit; leaving, replacing and cancel reset time',
    (tester) async {
      final legs = <(Offset, Offset)>[];
      final dwell = PencilDwell(const TestVSync(), (a, b) {
        legs.add((a, b));
        return true;
      });
      addTearDown(dwell.dispose);
      const a = Offset.zero, b = Offset(1, 0), c = Offset(1, 1);
      dwell.begin(a);
      dwell.pointAt(b);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(dwell.progress, greaterThan(.5));
      expect(legs, isEmpty);
      dwell.pointAt(null);
      expect(dwell.tail, a);
      expect(dwell.progress, 0);
      dwell.pointAt(b);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      dwell.pointAt(c);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(legs, isEmpty);
      await tester.pump(const Duration(milliseconds: 101));
      expect(legs, [(a, c)]);
      expect(dwell.tail, c);
      dwell.pointAt(c);
      await tester.pump(const Duration(seconds: 2));
      expect(legs.length, 1);
      dwell.pointAt(b);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      dwell.cancel();
      await tester.pumpAndSettle();
      expect(legs.length, 1);
      expect(dwell.tail, isNull);
    },
  );
  testWidgets(
    'failed placement retains anchor and does not retry while stationary',
    (tester) async {
      var calls = 0;
      final dwell = PencilDwell(const TestVSync(), (a, b) {
        calls++;
        return false;
      });
      addTearDown(dwell.dispose);
      dwell.begin(Offset.zero);
      dwell.pointAt(const Offset(1, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 301));
      expect(calls, 1);
      expect(dwell.tail, Offset.zero);
      await tester.pump(const Duration(seconds: 2));
      expect(calls, 1);
    },
  );
}
