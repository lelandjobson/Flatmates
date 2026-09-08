import 'package:flatmates/ui/game/paper_cost_hover.dart';
import 'package:flatmates/ui/game/paper_fly_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fly stays on the pointer until the tile moves on screen', () {
    const cursor = Offset(100, 80);
    const tile = Offset(90, 120);
    expect(
      paperFlyScreenAnchor(
        cursor: cursor,
        originWorldScreen: tile,
        currentWorldScreen: tile,
      ),
      cursor,
    );
    expect(
      paperFlyScreenAnchor(
        cursor: cursor,
        originWorldScreen: tile,
        currentWorldScreen: const Offset(130, 100),
      ),
      const Offset(140, 60),
    );
  });

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

  testWidgets('fly overlay keeps its ticker when a hover chip appears', (
    tester,
  ) async {
    final gone = <int>[];
    final events = [
      PaperFlyEvent(id: 1, delta: -2, cursor: const Offset(50, 50)),
    ];

    Widget stack({required bool hover}) {
      return MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              if (hover)
                const PaperCostHover(
                  cursor: Offset(50, 50),
                  delta: 2,
                  canAfford: true,
                ),
              PaperFlyOverlay(
                key: const ValueKey('paperFlyOverlay'),
                events: events,
                onExpired: gone.add,
              ),
            ],
          ),
        ),
      );
    }

    await tester.pumpWidget(stack(hover: false));
    await tester.pump();
    final state = tester.state(find.byType(PaperFlyOverlay));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(stack(hover: true));
    await tester.pump();
    expect(tester.state(find.byType(PaperFlyOverlay)), same(state));
    expect(gone, isEmpty);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump();
    expect(gone, contains(1));
  });
}
