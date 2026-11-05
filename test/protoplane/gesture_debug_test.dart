import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flatmates/gestures/gesture_debug.dart';
import 'package:flatmates/protoplane/plane_navigation.dart';
import 'package:flatmates/protoplane/dev_settings.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('overlay keeps two-pointer verdict readable at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final d = GestureDebug();
      addTearDown(d.dispose);
      d.down(1, const Offset(100, 200));
      d.down(2, const Offset(100, 300));
      d.move(1, const Offset(190, 200));
      d.move(2, const Offset(190, 300));
      d.recognition(swipe: const Offset(90, 0), zooming: false, consumed: true);
      d.end(1);
      d.end(2);
      final safe = Rect.fromLTRB(40, 140, size.width - 40, size.height - 100);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GestureDebugOverlay(debug: d, safeZone: safe),
          ),
        ),
      );
      final panel = tester.getRect(
        find.byKey(const ValueKey('gesture-debug-readout')),
      );
      final verdict = tester.getRect(find.text('Verdict: Swipe Right / E'));
      expect(panel.top, greaterThanOrEqualTo(safe.top));
      expect(panel.bottom, lessThanOrEqualTo(safe.bottom));
      expect(verdict.bottom, lessThanOrEqualTo(panel.bottom));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  test(
    'pointer colors/identity and released positions last until the next down',
    () {
      final d = GestureDebug();
      addTearDown(d.dispose);
      d.down(10, const Offset(20, 30));
      d.move(10, const Offset(30, 50));
      d.end(10, at: const Offset(35, 60));
      expect(d.phase, 'Released');
      expect(d.contacts[10]!.delta, const Offset(15, 30));
      d.move(10, const Offset(90, 90));
      expect(d.contacts[10]!.end, const Offset(35, 60));
      d.down(20, const Offset(50, 50));
      expect(d.contacts.keys, [20]);
      expect(d.contacts[20]!.index, 0);
      d.down(30, const Offset(100, 50));
      expect(d.contacts[30]!.index, 1);
      d.end(20);
      expect(d.contacts.length, 2);
      expect(d.phase, 'Active');
      d.end(30);
      expect(d.phase, 'Released');
    },
  );
  test(
    'debug verdict follows the real swipe recognizer and remains latched',
    () {
      final d = GestureDebug();
      addTearDown(d.dispose);
      final swipe = PlaneSwipe();
      d.down(1, const Offset(100, 200));
      d.move(1, const Offset(120, 200));
      d.down(2, const Offset(120, 300));
      swipe.start(d.contacts.values.map((p) => p.end));
      d.move(1, const Offset(220, 200));
      d.move(2, const Offset(220, 300));
      final result = swipe.update(d.contacts.values.map((p) => p.end), 60);
      d.recognition(
        swipe: result,
        zooming: swipe.zooming,
        consumed: swipe.consumed,
      );
      expect(d.centroidDelta, const Offset(100, 0));
      expect(d.verdict, 'Swipe Right / E');
      d.move(1, const Offset(80, 200));
      d.move(2, const Offset(80, 300));
      d.recognition(zooming: false, consumed: true);
      expect(d.verdict, 'Swipe Right / E');
      d.cancel();
      expect(d.phase, 'Cancelled');
      expect(d.contacts.length, 2);
      d.down(3, Offset.zero);
      d.down(4, const Offset(0, 100));
      d.recognition(zooming: true, consumed: false);
      expect(d.verdict, 'Pinch / rotation');
    },
  );
  test('screen cardinal directions and OS trackpad centroid are explicit', () {
    expect(screenCardinal(const Offset(0, -80)), 'Up / N');
    expect(screenCardinal(const Offset(0, 80)), 'Down / S');
    expect(screenCardinal(const Offset(-80, 2)), 'Left / W');
    expect(screenCardinal(Offset.zero), 'None');
    final d = GestureDebug();
    addTearDown(d.dispose);
    d.down(7, const Offset(100, 100), nativeTrackpad: true, kind: 'trackpad');
    d.move(7, const Offset(100, 20));
    d.end(7);
    expect(d.centroidDelta, const Offset(0, -80));
    expect(d.multi, isTrue);
    d.scrollEvent(0, const Offset(20, 30), const Offset(0, 45));
    expect(d.phase, 'Scroll');
    expect(d.contacts.values.single.delta, const Offset(0, 45));
    expect(d.scroll, isTrue);
    expect(d.multi, isFalse);
  });
  test('gesture toggle defaults off and survives settings round trips', () {
    final s = ProtoplaneSettings();
    expect(s.showGestureDebug, isFalse);
    s.showGestureDebug = true;
    final loaded = ProtoplaneSettings()..load(s.toJson());
    expect(loaded.showGestureDebug, isTrue);
    final legacy = s.toJson()..remove('showGestureDebug');
    loaded.load(legacy);
    expect(loaded.showGestureDebug, isFalse);
  });
}
