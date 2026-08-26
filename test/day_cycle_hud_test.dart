import 'package:flatmates/ui/game/day_advance_overlay.dart';
import 'package:flatmates/ui/game/day_cycle_hud.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('day hud shows the counter and a sun while it is day', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DayCycleHud(
            dayNumber: 3,
            isNight: false,
            onEndPhase: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('Day 3'), findsOneWidget);
    expect(find.byIcon(Icons.wb_sunny), findsOneWidget);
    await tester.tap(find.byIcon(Icons.wb_sunny));
    expect(tapped, isTrue);
  });

  testWidgets('night hud shows a moon and ignores taps while busy', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DayCycleHud(
            dayNumber: 1,
            isNight: true,
            busy: true,
            onEndPhase: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.dark_mode), findsOneWidget);
    await tester.tap(find.byIcon(Icons.dark_mode));
    expect(tapped, isFalse);
  });

  testWidgets('day advance overlay snaps lighting then finishes the dummy bar',
      (tester) async {
    var ready = false;
    var finished = false;
    await tester.pumpWidget(
      MaterialApp(
        home: DayAdvanceOverlay(
          nextDay: 4,
          fadeDuration: const Duration(milliseconds: 100),
          barDuration: const Duration(milliseconds: 400),
          onReadyForDay: () => ready = true,
          onFinished: () => finished = true,
        ),
      ),
    );

    expect(find.text('Day 4'), findsOneWidget);
    expect(ready, isFalse);
    await tester.pumpAndSettle();
    expect(ready, isTrue);
    expect(finished, isTrue);
  });
}
