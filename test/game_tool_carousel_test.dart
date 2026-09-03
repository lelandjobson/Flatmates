import 'package:flatmates/ui/game/game_tool_carousel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('primary modes wrap around the row', () {
    expect(GameMode.select.stepped(1), GameMode.create);
    expect(GameMode.create.stepped(1), GameMode.edit);
    expect(GameMode.edit.stepped(1), GameMode.select);
    expect(GameMode.select.stepped(-1), GameMode.edit);
  });

  test('edit tools wrap around the row', () {
    expect(GameEditTool.transform.stepped(1), GameEditTool.paint);
    expect(GameEditTool.paint.stepped(1), GameEditTool.delete);
    expect(GameEditTool.delete.stepped(1), GameEditTool.transform);
    expect(GameEditTool.transform.stepped(-1), GameEditTool.delete);
  });

  test('create tools wrap around the scalable list', () {
    expect(GameCreateTool.volume.stepped(1), GameCreateTool.path);
    expect(GameCreateTool.path.stepped(1), GameCreateTool.wall);
    expect(GameCreateTool.wall.stepped(1), GameCreateTool.volume);
    expect(GameCreateTool.wall.stepped(-1), GameCreateTool.path);
  });

  test('create and edit lists stay independently swipeable', () {
    expect(kGameModeItems, hasLength(3));
    expect(kGameEditToolItems.map((i) => i.value), GameEditTool.values);
    expect(kGameCreateToolItems.map((i) => i.value), GameCreateTool.values);
  });

  test('modes are black, gold-tinted, and blue-tinted', () {
    expect(GameMode.select.fill, kHudSelectFill);
    expect(gameModeFill(GameMode.edit).r, greaterThan(gameModeFill(GameMode.create).r));
    expect(gameModeFill(GameMode.create).b, greaterThan(gameModeFill(GameMode.edit).b));
  });

  test('carousel duration is 300ms', () {
    expect(kGameToolCarouselDuration, const Duration(milliseconds: 300));
  });

  test('focus target wraps last to first in one adjacent step', () {
    expect(carouselFocusTarget(current: 1, index: 0, length: 3), 0);
    expect(carouselFocusTarget(current: 0, index: 1, length: 3), 1);
    expect(carouselFocusTarget(current: 1, index: 2, length: 3), 2);
    expect(carouselFocusTarget(current: 2, index: 0, length: 3), 3);
    expect(carouselFocusTarget(current: 0, index: 2, length: 3), -1);
    expect(carouselWrapIndex(-1, 3), 2);
    expect(carouselWrapIndex(3, 3), 0);
  });

  test('item slots sit on the replica nearest the focus', () {
    expect(carouselItemSlot(0, 2, 3), 3);
    expect(carouselItemSlot(2, 0, 3), -1);
    expect(carouselItemSlot(1, 1, 3), 1);
    expect(carouselItemSlot(0, 0, 3), 0);
  });

  testWidgets('a swipe moves to the next item, including onto the first',
      (tester) async {
    var selected = GameMode.edit;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return HudToolCarousel<GameMode>(
                items: kGameModeItems,
                selected: selected,
                onSelect: (mode) => setState(() => selected = mode),
              );
            },
          ),
        ),
      ),
    );
    await tester.fling(
      find.byType(HudToolCarousel<GameMode>),
      const Offset(-60, 0),
      400,
    );
    await tester.pumpAndSettle();
    expect(selected, GameMode.select);
  });

  testWidgets('wrap from last to first slides the next icon in', (tester) async {
    var selected = GameMode.edit;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return HudToolCarousel<GameMode>(
                items: kGameModeItems,
                selected: selected,
                onSelect: (mode) => setState(() => selected = mode),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final center = tester.getCenter(find.byType(HudToolCarousel<GameMode>)).dx;
    expect(
      (tester.getCenter(find.byIcon(Icons.tune)).dx - center).abs(),
      lessThan(8),
    );

    await tester.fling(
      find.byType(HudToolCarousel<GameMode>),
      const Offset(-80, 0),
      500,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(selected, GameMode.select);
    expect(
      (tester.getCenter(find.byIcon(Icons.ads_click)).dx - center).abs(),
      greaterThan(12),
    );

    await tester.pumpAndSettle();
    expect(
      (tester.getCenter(find.byIcon(Icons.ads_click)).dx - center).abs(),
      lessThan(8),
    );
  });

  test('submenus share the parent hue and are 10% less black', () {
    final edit = gameModeFill(GameMode.edit);
    final editSub = gameModeFill(GameMode.edit, submenu: true);
    final create = gameModeFill(GameMode.create);
    final createSub = gameModeFill(GameMode.create, submenu: true);
    expect(editSub.computeLuminance(), greaterThan(edit.computeLuminance()));
    expect(createSub.computeLuminance(), greaterThan(create.computeLuminance()));
    expect(kGameEditToolItems.map((i) => i.fill).toSet(), {editSub});
    expect(kGameCreateToolItems.map((i) => i.fill).toSet(), {createSub});
  });
}
