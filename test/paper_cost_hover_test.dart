import 'package:flatmates/ui/game/paper_cost_hover.dart';
import 'package:flatmates/ui/game/paper_fly_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('hover chip shows a spend above the cursor', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              PaperCostHover(
                cursor: Offset(100, 80),
                delta: 20,
                canAfford: true,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('-20'), findsOneWidget);
  });

  testWidgets('hover chip shows a refund', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              PaperCostHover(
                cursor: Offset(40, 40),
                delta: -1,
                canAfford: true,
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('+1'), findsOneWidget);
  });

  testWidgets('fly overlay paints spend and refund then expires', (tester) async {
    final gone = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaperFlyOverlay(
            events: [
              PaperFlyEvent(
                id: 1,
                delta: -20,
                cursor: const Offset(50, 50),
              ),
              PaperFlyEvent(
                id: 2,
                delta: 3,
                cursor: const Offset(50, 50),
              ),
            ],
            onExpired: gone.add,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(gone, isEmpty);
    await tester.pump(kPaperFlyDuration);
    await tester.pump();
    expect(gone, containsAll([1, 2]));
  });
}
