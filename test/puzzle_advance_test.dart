import 'dart:io';

import 'package:flatmates/gridcraft/blueprint.dart';
import 'package:flatmates/gridcraft/level_io.dart';
import 'package:flatmates/gridcraft/puzzle_advance.dart';
import 'package:flatmates/gridcraft/rules.dart';
import 'package:flatmates/gridcraft/twin_ls.dart';
import 'package:flatmates/screens/grid_puzzle_view.dart';
import 'package:flatmates/ui/fm_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  test('screen right is +X until the sheet rolls', () {
    expect(screenRight(0), const Offset(1, 0));
    expect(screenRight(1.5707963267948966).dx, closeTo(0, 1e-9));
    expect(screenRight(1.5707963267948966).dy, closeTo(-1, 1e-9));
  });

  test('the next puzzle starts offscreen to the right of the pieces', () {
    final shift = placeNextPuzzle(
      occupied: const [Offset.zero, Offset(4, 0), Offset(4, 3), Offset(0, 3)],
      nextPaper: const Rect.fromLTWH(0, 0, 2, 2),
      lookAt: const Offset(2, 1.5),
      right: screenRight(0),
      halfWidth: 5,
      padding: 2,
    );
    expect(shift, const Offset(9, 0));

    final pastTheScreen = placeNextPuzzle(
      occupied: const [Offset.zero, Offset(20, 1)],
      nextPaper: const Rect.fromLTWH(0, 0, 2, 2),
      lookAt: Offset.zero,
      right: screenRight(0),
      halfWidth: 5,
      padding: 2,
    );
    expect(pastTheScreen.dx, 22);
  });

  test('landing subtracts the slide so the puzzle is back at its origin', () {
    final step = GridStep(
      id: 'level',
      label: 'Level',
      polygons: const [
        [Offset(1, 1), Offset(3, 1), Offset(3, 2)],
      ],
      rules: const GridRules(forbidden: [Offset(2, 1)]),
    );
    const shift = Offset(40, -3);
    final parked = shiftStep(step, shift);
    expect(parked.polygons.first.first, const Offset(41, -2));
    expect(parked.rules.forbidden.single, const Offset(42, -2));
    expect(parked.paper.center, step.paper.center + shift);

    final destination = step.paper.center + shift;
    expect(destination - shift, step.paper.center);
    expect(shiftStep(parked, -shift).polygons, step.polygons);
  });

  testWidgets('collection and puzzle buttons open the library', (tester) async {
    final directory = Directory.systemTemp.createTempSync('play-library');
    addTearDown(() => directory.deleteSync(recursive: true));
    final store = LevelStore(directory: directory);
    final first = GridBlueprint(
      id: 'first',
      name: 'First',
      steps: twinLsBlueprint().steps,
    );
    final second = GridBlueprint(
      id: 'second',
      name: 'Second',
      steps: twinLsBlueprint().steps,
    );
    final house = await tester.runAsync(
      () => store.savePuzzle(
        collectionName: 'House',
        puzzle: first,
        fromCollectionId: null,
      ),
    );
    await tester.runAsync(
      () => store.savePuzzle(
        collectionName: 'House',
        puzzle: second,
        fromCollectionId: house!.id,
      ),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => FmThemeData(),
        child: MaterialApp(
          home: GridPuzzleView(store: store, initial: first),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('First'), findsOneWidget);
    expect(find.text('House'), findsOneWidget);
    await tester.tap(find.byKey(const Key('grid-puzzle-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('grid-library')), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);

    await tester.tap(find.byKey(const Key('grid-puzzle-item-second')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('grid-library')), findsNothing);
    expect(find.text('Second'), findsOneWidget);
  });
}
