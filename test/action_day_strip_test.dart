import 'package:flatmates/gameplay/flatmates/day_action.dart';
import 'package:flatmates/gameplay/flatmates/day_action_store.dart';
import 'package:flatmates/ui/game/action_day_strip.dart';
import 'package:flatmates/ui/game/game_tool_carousel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('play sits outside a yellow-to-blue frame of white icons',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActionDayStrip(
            plan: FlatmateDayPlan(
              friendId: 'f',
              slots: [
                const DayActionSlot(kind: DayActionKind.collect, tile: (1, 1)),
                const DayActionSlot(),
                lockedSleepSlot((0, 0)),
              ],
            ),
            playing: false,
            selectedSlot: 0,
            onPlay: () {},
            onSlotTap: (_) {},
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
    expect(find.byIcon(Icons.bed_outlined), findsOneWidget);
    expect(find.byType(HudToolButton), findsNWidgets(4));
    expect(find.byType(AnimatedScale), findsNWidgets(4));
    final selected = tester.widget<AnimatedScale>(
      find.descendant(
        of: find.byType(HudToolButton).at(1),
        matching: find.byType(AnimatedScale),
      ),
    );
    expect(selected.scale, kGameToolCarouselScale);
    expect(selected.duration, kGameToolCarouselDuration);

    expect(
      tester.widget<Icon>(find.byIcon(Icons.inventory_2_outlined)).color,
      Colors.white,
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.play_arrow)).color,
      Colors.white70,
    );

    final frames = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
    expect(
      frames.any((box) {
        final decoration = box.decoration;
        return decoration is BoxDecoration &&
            decoration.gradient is LinearGradient &&
            (decoration.gradient as LinearGradient).colors.first ==
                kDayStartYellow &&
            (decoration.gradient as LinearGradient).colors.last ==
                kDayEndMidnight;
      }),
      isTrue,
    );
  });
}
