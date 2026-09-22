import 'package:flatmates/ui/game/game_tool_carousel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('primary modes wrap around the row', () {
    expect(GameMode.select.stepped(1), GameMode.create);
    expect(GameMode.create.stepped(1), GameMode.edit);
    expect(GameMode.edit.stepped(1), GameMode.action);
    expect(GameMode.action.stepped(1), GameMode.select);
    expect(GameMode.select.stepped(-1), GameMode.action);
  });

  test('edit tools wrap around the row', () {
    expect(GameEditTool.transform.stepped(1), GameEditTool.paint);
    expect(GameEditTool.paint.stepped(1), GameEditTool.delete);
    expect(GameEditTool.delete.stepped(1), GameEditTool.transform);
    expect(GameEditTool.transform.stepped(-1), GameEditTool.delete);
  });

  test('create tools wrap around the scalable list', () {
    expect(GameCreateTool.volume.stepped(1), GameCreateTool.path);
    expect(GameCreateTool.path.stepped(1), GameCreateTool.playground);
    expect(GameCreateTool.playground.stepped(1), GameCreateTool.volume);
    expect(GameCreateTool.playground.stepped(-1), GameCreateTool.path);
    expect(GameCreateTool.playground.icon, Icons.grid_on);
    expect(GameCreateTool.playground.label, 'Playgrounds');
  });

  test('create and edit lists stay independently listed', () {
    expect(kGameModeItems, hasLength(3));
    expect(kGameEditToolItems.map((i) => i.value), GameEditTool.values);
    expect(kGameCreateToolItems.map((i) => i.value), GameCreateTool.values);
  });

  test('modes are black, gold-tinted, and blue-tinted', () {
    expect(GameMode.select.fill, kHudSelectFill);
    expect(gameModeFill(GameMode.edit).r, greaterThan(gameModeFill(GameMode.create).r));
    expect(gameModeFill(GameMode.create).b, greaterThan(gameModeFill(GameMode.edit).b));
    expect(
      gameModeFill(GameMode.action).r,
      greaterThan(hudTintedBlack(kHudSunset, amount: 0.28).r),
    );
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

  testWidgets('tapping an icon selects it; a fling does not', (tester) async {
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
      const Offset(-80, 0),
      500,
    );
    await tester.pumpAndSettle();
    expect(selected, GameMode.edit);

    await tester.tap(find.byIcon(Icons.ads_click));
    await tester.pumpAndSettle();
    expect(selected, GameMode.select);
  });

  testWidgets('changing selection keeps each icon in its slot', (tester) async {
    var selected = GameMode.select;
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

    final before = {
      Icons.ads_click: tester.getCenter(find.byIcon(Icons.ads_click)).dx,
      Icons.add: tester.getCenter(find.byIcon(Icons.add)).dx,
      Icons.tune: tester.getCenter(find.byIcon(Icons.tune)).dx,
    };

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    expect(selected, GameMode.edit);

    expect(
      (tester.getCenter(find.byIcon(Icons.ads_click)).dx - before[Icons.ads_click]!)
          .abs(),
      lessThan(2),
    );
    expect(
      (tester.getCenter(find.byIcon(Icons.add)).dx - before[Icons.add]!).abs(),
      lessThan(2),
    );
    expect(
      (tester.getCenter(find.byIcon(Icons.tune)).dx - before[Icons.tune]!).abs(),
      lessThan(2),
    );
  });

  testWidgets('the tool group stays centered in the bar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HudToolCarousel<GameMode>(
            items: kGameModeItems,
            selected: GameMode.edit,
            onSelect: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final barCenter = tester.getCenter(find.byType(HudToolCarousel<GameMode>)).dx;
    final first = tester.getCenter(find.byIcon(Icons.ads_click)).dx;
    final last = tester.getCenter(find.byIcon(Icons.tune)).dx;
    expect(((first + last) / 2 - barCenter).abs(), lessThan(2));
  });

  testWidgets('adding Actions recenters the group and keeps order',
      (tester) async {
    var showAction = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return HudToolCarousel<GameMode>(
                items: gameModeItems(showAction: showAction),
                selected: GameMode.select,
                onSelect: (_) {},
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    var barCenter = tester.getCenter(find.byType(HudToolCarousel<GameMode>)).dx;
    expect(
      ((tester.getCenter(find.byIcon(Icons.ads_click)).dx +
                  tester.getCenter(find.byIcon(Icons.tune)).dx) /
              2 -
          barCenter)
          .abs(),
      lessThan(2),
    );

    showAction = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return HudToolCarousel<GameMode>(
                items: gameModeItems(showAction: showAction),
                selected: GameMode.select,
                onSelect: (_) {},
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final xs = [
      tester.getCenter(find.byIcon(Icons.ads_click)).dx,
      tester.getCenter(find.byIcon(Icons.add)).dx,
      tester.getCenter(find.byIcon(Icons.tune)).dx,
      tester.getCenter(find.byIcon(Icons.route)).dx,
    ];
    expect(xs, orderedEquals(List<double>.from(xs)..sort()));

    barCenter = tester.getCenter(find.byType(HudToolCarousel<GameMode>)).dx;
    expect(((xs.first + xs.last) / 2 - barCenter).abs(), lessThan(2));
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
