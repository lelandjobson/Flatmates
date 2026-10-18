import 'dart:ui';

import 'package:flatmates/screens/asmr_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('cut a face out over the hologram and see it on the cube', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<void> frames(int ms) async {
      for (var t = 0; t < ms; t += 16) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    await tester.pumpWidget(const MaterialApp(home: AsmrView()));
    await frames(300);
    expect(find.text('Faces filled  0 / 6'), findsOneWidget);
    expect(find.byTooltip('Orbit'), findsOneWidget);

    await tester.tap(find.byTooltip('Select'));
    await frames(50);
    final pick = await tester.startGesture(
      const Offset(400, 300),
      kind: PointerDeviceKind.mouse,
    );
    await pick.up();
    await frames(100);

    await tester.tap(find.byIcon(Icons.view_in_ar));
    await frames(700);

    await tester.tap(find.byTooltip('Mint dots'));
    await frames(100);

    const center = Offset(400, 300);
    const scale = 600 / 260;
    Offset screen(double x, double y) => center + Offset(x, y) * scale;
    final gesture = await tester.startGesture(
      screen(-35, -35),
      kind: PointerDeviceKind.mouse,
    );
    final corners = [
      screen(35, -35),
      screen(35, 35),
      screen(-35, 35),
      screen(-35, -33),
    ];
    var at = screen(-35, -35);
    for (final corner in corners) {
      final delta = corner - at;
      const steps = 30;
      for (var i = 1; i <= steps; i++) {
        await gesture.moveTo(at + delta * (i / steps));
        await tester.pump(const Duration(milliseconds: 8));
      }
      at = corner;
    }
    await gesture.up();
    await frames(100);
    expect(find.text('Faces filled  1 / 6'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.view_in_ar));
    await frames(700);
    expect(tester.takeException(), isNull);

    final orbit = await tester.startGesture(const Offset(400, 300));
    for (var i = 0; i < 20; i++) {
      await orbit.moveBy(const Offset(12, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await orbit.up();
    await frames(300);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('straight cut drags a segment across the paper', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<void> frames(int ms) async {
      for (var t = 0; t < ms; t += 16) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    await tester.pumpWidget(const MaterialApp(home: AsmrView()));
    await frames(300);
    await tester.tap(find.byIcon(Icons.view_in_ar));
    await frames(700);

    await tester.tap(find.byTooltip('Straight cut'));
    await frames(50);
    expect(
      find.text(
        'Drag a straight line. Every piece it crosses is cut along that line.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Mint dots'));
    await frames(50);

    const center = Offset(400, 300);
    final gesture = await tester.startGesture(
      center + const Offset(-220, 0),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveTo(center + const Offset(220, 0));
    await tester.pump();
    await gesture.up();
    await frames(100);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
