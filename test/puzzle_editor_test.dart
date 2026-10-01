import 'dart:io';

import 'package:flatmates/geometry/polygon_union.dart';
import 'package:flatmates/gridcraft/blueprint.dart';
import 'package:flatmates/gridcraft/edit.dart';
import 'package:flatmates/gridcraft/level_io.dart';
import 'package:flatmates/gridcraft/rules.dart';
import 'package:flatmates/gridcraft/twin_ls.dart';
import 'package:flatmates/screens/puzzle_editor_view.dart';
import 'package:flatmates/ui/fm_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  const paper = Rect.fromLTRB(0, 0, 4, 4);

  test('a snapped ring closes and a crossing draft is refused', () {
    var draft = <Offset>[];
    for (final point in const [Offset(0, 0), Offset(2, 0), Offset(2, 2)]) {
      final click = applyDraftClick(draft, point);
      expect(click.closed, isNull);
      draft = click.draft;
    }
    final closed = applyDraftClick(draft, Offset.zero);
    expect(closed.draft, isEmpty);
    expect(closed.open, isNull);
    expect(closed.closed, [
      const Offset(0, 0),
      const Offset(2, 0),
      const Offset(2, 2),
    ]);

    draft = const [];
    for (final point in const [Offset(0, 0), Offset(3, 0), Offset(3, 1)]) {
      final click = applyDraftClick(draft, point);
      expect(click.open, isNull);
      draft = click.draft;
    }
    final finished = applyDraftClick(draft, const Offset(3, 1));
    expect(finished.draft, isEmpty);
    expect(finished.closed, isNull);
    expect(finished.open, [
      const Offset(0, 0),
      const Offset(3, 0),
      const Offset(3, 1),
    ]);
    final next = applyDraftClick(finished.draft, const Offset(1, 1));
    expect(next.draft, [const Offset(1, 1)]);

    draft = const [];
    for (final point in const [Offset(0, 0), Offset(1, 1), Offset(0, 1)]) {
      draft = applyDraftClick(draft, point).draft;
    }
    final crossed = applyDraftClick(draft, const Offset(1, 0));
    expect(crossed.closed, isNull);
    expect(crossed.draft, draft);
  });

  test('selected shapes move on the grid and merge into one', () {
    final moved = translatePolygons(
      const [
        [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)],
      ],
      {0},
      const Offset(2, 0),
    );
    expect(moved.single.first, const Offset(2, 0));
    expect(moved.single[1], const Offset(3, 0));

    final merged = mergeSelected(const [
      [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)],
      [Offset(1, 0), Offset(2, 0), Offset(2, 1), Offset(1, 1)],
    ]);
    expect(merged, hasLength(1));
    expect(polygonSignedArea(merged.single), closeTo(2, 1e-6));
  });

  test('rules survive json and a step without rules stays empty', () {
    const bare = GridStep(
      id: 'step',
      label: 'Step',
      polygons: [
        [Offset(0, 0), Offset(1, 0), Offset(0, 1)],
      ],
    );
    final bareJson = bare.toJson();
    expect(bareJson.containsKey('rules'), isFalse);
    expect(GridStep.fromJson(bareJson).rules.isEmpty, isTrue);

    const rules = GridRules(
      maxExits: 2,
      maxLength: 8,
      forbidden: [Offset(1, 1)],
      colors: [ColorMark(Offset(2, 0), 0)],
      numbers: [OrderMark(Offset(3, 0), 1)],
      arrows: [GridEdge(Offset(0, 0), Offset(1, 0))],
      docks: [Offset(4, 2)],
      links: [LinkMark(Offset(1, 2), 1), LinkMark(Offset(2, 2), 1)],
      seams: [GridEdge(Offset(0, 1), Offset(1, 1))],
    );
    final step = bare.copyWith(rules: rules);
    final loaded = GridStep.fromJson(step.toJson());
    expect(loaded.rules.maxExits, 2);
    expect(loaded.rules.maxLength, 8);
    expect(loaded.rules.forbidden, rules.forbidden);
    expect(loaded.rules.colors.single.color, 0);
    expect(loaded.rules.numbers.single.number, 1);
    expect(loaded.rules.arrows.single.b, const Offset(1, 0));
    expect(loaded.rules.docks, rules.docks);
    expect(loaded.rules.links, hasLength(2));
    expect(loaded.rules.seams.single.a, const Offset(0, 1));

    final puzzle = copyPuzzle(
      GridBlueprint(id: 'src', name: 'Source', steps: [step]),
      stamp: 7,
    );
    expect(puzzle.id, 'puzzle-7');
    expect(puzzle.name, 'Copy of Source');
    expect(puzzle.steps.single.rules.maxExits, 2);
    expect(blankPuzzle(stamp: 3).steps.single.polygons, isEmpty);
  });

  test('forbid, colors, numbers, exits, and length gate a segment', () {
    final open = const CutProgress();

    final forbid = const GridRules(forbidden: [Offset(1, 0)]);
    expect(
      forbid.allows(Offset.zero, const Offset(1, 0), open, paper: paper),
      isFalse,
    );
    expect(
      forbid.allows(Offset.zero, const Offset(0, 1), open, paper: paper),
      isTrue,
    );

    const colors = GridRules(
      colors: [
        ColorMark(Offset(1, 0), 0),
        ColorMark(Offset(3, 0), 0),
        ColorMark(Offset(2, 0), 1),
      ],
    );
    final firstRed = colors.consider(
      Offset.zero,
      const Offset(1, 0),
      open,
      paper: paper,
    );
    expect(firstRed.allowed, isTrue);
    expect(firstRed.failed, isFalse);
    expect(firstRed.progress.openColor, 0);
    final alternate = colors.consider(
      const Offset(1, 0),
      const Offset(3, 0),
      firstRed.progress,
      paper: paper,
    );
    expect(alternate.allowed, isTrue);
    expect(alternate.failed, isTrue);
    expect(alternate.cause?.kind, FailureKind.color);
    expect(alternate.cause?.index, 2);

    const gate = GridRules(colors: [ColorMark(Offset.zero, 0)]);
    final entered = gate.consider(
      Offset.zero,
      const Offset(1, 0),
      open,
      paper: paper,
    );
    expect(entered.allowed, isTrue);
    expect(entered.progress.collectedColors, {0});
    final inward = gate.consider(
      Offset.zero,
      const Offset(1, 1),
      open,
      paper: paper,
    );
    expect(inward.allowed, isTrue);
    expect(inward.progress.collectedColors, {0});
    expect(gemsRemain(gate, inward.progress), isFalse);
    final edgeEntry = gate.consider(
      const Offset(0, 2),
      const Offset(1, 2),
      open,
      paper: paper,
    );
    expect(edgeEntry.allowed, isTrue);
    expect(edgeEntry.progress.collectedColors, isEmpty);
    expect(entryGemsRemain(gate, open), isFalse);

    const numberGate = GridRules(numbers: [OrderMark(Offset.zero, 1)]);
    expect(entryGemsRemain(numberGate, open), isTrue);
    final blockedEntry = numberGate.consider(
      const Offset(0, 2),
      const Offset(1, 2),
      open,
      paper: paper,
    );
    expect(blockedEntry.allowed, isFalse);

    const numbers = GridRules(
      numbers: [OrderMark(Offset(1, 0), 2), OrderMark(Offset(2, 0), 1)],
    );
    final early = numbers.consider(
      Offset.zero,
      const Offset(2, 0),
      open,
      paper: paper,
    );
    expect(early.allowed, isTrue);
    expect(early.failed, isTrue);
    expect(early.cause?.kind, FailureKind.number);
    expect(early.cause?.index, 0);
    const ordered = GridRules(
      numbers: [OrderMark(Offset(1, 0), 1), OrderMark(Offset(2, 0), 2)],
    );
    final counted = ordered.consider(
      Offset.zero,
      const Offset(2, 0),
      open,
      paper: paper,
    );
    expect(counted.allowed, isTrue);
    expect(counted.progress.nextNumber, 3);

    const exits = GridRules(maxExits: 1);
    final left = exits.consider(
      const Offset(2, 2),
      const Offset(0, 2),
      open,
      paper: paper,
    );
    expect(left.allowed, isTrue);
    expect(left.progress.exitsUsed, 1);
    expect(
      exits.allows(
        const Offset(2, 2),
        const Offset(4, 2),
        left.progress,
        paper: paper,
      ),
      isFalse,
    );
    expect(
      exits.allows(
        const Offset(1, 1),
        const Offset(2, 2),
        left.progress,
        paper: paper,
      ),
      isTrue,
    );

    const length = GridRules(maxLength: 2);
    final short = length.consider(
      Offset.zero,
      const Offset(1, 0),
      open,
      paper: paper,
    );
    expect(short.allowed, isTrue);
    expect(short.progress.lengthUsed, closeTo(1, 1e-6));
    expect(
      length.allows(
        Offset.zero,
        const Offset(2, 0),
        short.progress,
        paper: paper,
      ),
      isFalse,
    );
  });

  test('left drag contains and right drag also crosses', () {
    const square = [Offset(0, 0), Offset(2, 0), Offset(2, 2), Offset(0, 2)];
    const neighbor = [Offset(3, 0), Offset(5, 0), Offset(5, 2), Offset(3, 2)];
    final around = Rect.fromLTRB(-0.5, -0.5, 2.5, 2.5);
    expect(marqueePick(Offset.zero, const Offset(10, 4)), MarqueePick.contain);
    expect(marqueePick(const Offset(10, 4), Offset.zero), MarqueePick.cross);
    expect(polygonInMarquee(square, around, MarqueePick.contain), isTrue);
    expect(polygonInMarquee(neighbor, around, MarqueePick.contain), isFalse);

    final slice = Rect.fromLTRB(0.5, -1, 1.5, 3);
    expect(polygonInMarquee(square, slice, MarqueePick.contain), isFalse);
    expect(polygonInMarquee(square, slice, MarqueePick.cross), isTrue);
    expect(
      edgeInMarquee(
        const Offset(0, 1),
        const Offset(4, 1),
        slice,
        MarqueePick.cross,
      ),
      isTrue,
    );
    expect(
      edgeInMarquee(
        const Offset(0, 1),
        const Offset(4, 1),
        slice,
        MarqueePick.contain,
      ),
      isFalse,
    );
  });

  test('a marquee selects marks and a move carries them with the shape', () {
    const square = [Offset(0, 0), Offset(2, 0), Offset(2, 2), Offset(0, 2)];
    const rules = GridRules(
      forbidden: [Offset(1, 1), Offset(8, 8)],
      arrows: [GridEdge(Offset(0, 2), Offset(2, 2))],
    );
    final step = GridStep(
      id: 'step',
      label: 'Step',
      polygons: const [square],
      rules: rules,
    );
    final hits = marqueeHits(
      step,
      Rect.fromLTRB(-1, -1, 3, 3),
      MarqueePick.contain,
    );
    expect(hits.polygons, {0});
    expect(hits.marks, {
      const RulePick(RuleKind.forbidden, 0),
      const RulePick(RuleKind.arrow, 0),
    });

    const shift = Offset(2, 0);
    final movedPolygons = translatePolygons(
      step.polygons,
      hits.polygons,
      shift,
    );
    final movedRules = translateRules(rules, hits.marks, shift);
    expect(movedPolygons.single.first, const Offset(2, 0));
    expect(movedRules.forbidden, [const Offset(3, 1), const Offset(8, 8)]);
    expect(movedRules.arrows.single.a, const Offset(2, 2));
    expect(movedRules.arrows.single.b, const Offset(4, 2));
  });

  test('the sheet stays two units outside the shapes as they move', () {
    const step = GridStep(
      id: 'step',
      label: 'Step',
      polygons: [
        [Offset(0, 0), Offset(2, 0), Offset(2, 2), Offset(0, 2)],
      ],
      rules: GridRules(forbidden: [Offset(10, 1)]),
    );
    expect(step.paperMargin, 2);
    expect(step.paper, const Rect.fromLTRB(-2, -2, 12, 4));
    final moved = step.copyWith(
      polygons: translatePolygons(step.polygons, {0}, const Offset(3, 1)),
    );
    expect(moved.paper, const Rect.fromLTRB(1, -1, 12, 5));
  });

  testWidgets('help explains the tool in the submenu', (tester) async {
    final directory = Directory.systemTemp.createTempSync('puzzle-help');
    addTearDown(() => directory.deleteSync(recursive: true));
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => FmThemeData(),
        child: MaterialApp(
          home: PuzzleEditorView(store: LevelStore(directory: directory)),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('puzzle-tool-help')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('puzzle-tool-help-title')), findsOneWidget);
    expect(find.text('Shapes'), findsOneWidget);
    expect(find.textContaining('left to right'), findsOneWidget);

    await tester.tap(find.byKey(const Key('puzzle-tool-help-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('puzzle-tool-help-dialog')), findsNothing);

    await tester.tap(find.byTooltip('Forbid'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('puzzle-tool-help')));
    await tester.pumpAndSettle();
    expect(find.text('Forbid'), findsOneWidget);
    expect(find.textContaining('cannot travel through'), findsOneWidget);
  });

  testWidgets('editor menus fit beside help on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final directory = Directory.systemTemp.createTempSync('puzzle-narrow');
    addTearDown(() => directory.deleteSync(recursive: true));
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => FmThemeData(),
        child: MaterialApp(
          home: PuzzleEditorView(store: LevelStore(directory: directory)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Level'));
    await tester.pumpAndSettle();
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Mirror X'), findsOneWidget);
    await tester.tap(find.byTooltip('Color gems'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('level attachments, permutations, and tool filter round-trip', () {
    const step = GridStep(
      id: 'level',
      label: 'Level',
      polygons: [
        [Offset.zero, Offset(2, 0), Offset(2, 2), Offset(0, 2)],
      ],
      edgeStyles: [
        [
          EdgeStyle.penned,
          EdgeStyle.penciled,
          EdgeStyle.penned,
          EdgeStyle.penned,
        ],
      ],
      collisions: [1],
      tools: ToolFilter({CraftTool.scissors: 6, CraftTool.folder: null}),
      attachment: ScissorAttachment(flashlightThrow: 4, thickCut: 0.25),
      permutation: LevelPermutation(darkness: true, mirrorX: true),
      allowSeparation: true,
    );
    final loaded = GridStep.fromJson(step.toJson());
    expect(loaded.edgeStyleOf(0)[1], EdgeStyle.penciled);
    expect(loaded.collisionOf(0), 1);
    expect(loaded.tools!.allows(CraftTool.scissors), isTrue);
    expect(loaded.tools!.budget(CraftTool.scissors), 6);
    expect(loaded.tools!.allows(CraftTool.holePunch), isFalse);
    expect(loaded.attachment.flashlightThrow, 4);
    expect(loaded.attachment.thickCut, 0.25);
    expect(loaded.permutation.darkness, isTrue);
    expect(loaded.permutation.mirrorX, isTrue);
    expect(loaded.allowSeparation, isTrue);
    expect(
      GridStep.fromJson(
        loaded.copyWith(allowSeparation: false).toJson(),
      ).allowSeparation,
      isFalse,
    );
    expect(loaded.scissorLengthBudget, 6);
    expect(loaded.toJson().containsKey('edgeStyles'), isTrue);
  });

  test('a loose save reloads spacing, margin, and polygons', () async {
    final directory = Directory.systemTemp.createTempSync('puzzle-play-save');
    addTearDown(() => directory.deleteSync(recursive: true));
    final store = LevelStore(directory: directory);
    final level = twinLsBlueprint();
    await store.save(level);
    final loaded = await store.loadAll();
    expect(loaded, hasLength(1));
    final step = loaded.single.steps.single;
    expect(step.gridSpacing, level.steps.single.gridSpacing);
    expect(step.paperMargin, level.steps.single.paperMargin);
    expect(step.polygons, level.steps.single.polygons);
    await store.save(loaded.single);
    expect(File('${directory.path}/twin-ls.json').existsSync(), isTrue);
  });

  test(
    'save writes a collection folder and rename deletes the old puzzle',
    () async {
      final directory = Directory.systemTemp.createTempSync('puzzle-folders');
      addTearDown(() => directory.deleteSync(recursive: true));
      final store = LevelStore(directory: directory);
      final house = await store.savePuzzle(
        collectionName: 'Front Door',
        puzzle: _storedPuzzle('door', 'Door'),
        fromCollectionId: null,
      );
      expect(house.name, 'Front Door');
      expect(house.id, 'front-door');
      final manifest = File('${directory.path}/front-door/collection.json');
      expect(manifest.readAsStringSync(), contains('Front Door'));
      expect(
        File('${directory.path}/front-door/door.json').existsSync(),
        isTrue,
      );

      await store.savePuzzle(
        collectionName: 'Front Door',
        puzzle: _storedPuzzle('window', 'Window'),
        fromCollectionId: house.id,
      );
      await store.savePuzzle(
        collectionName: 'Front Door',
        puzzle: _storedPuzzle('door', 'Gate'),
        fromCollectionId: house.id,
      );
      expect(
        File('${directory.path}/front-door/door.json').existsSync(),
        isFalse,
      );
      expect(
        File('${directory.path}/front-door/gate.json').existsSync(),
        isTrue,
      );
      expect(
        File('${directory.path}/front-door/window.json').existsSync(),
        isTrue,
      );

      await store.savePuzzle(
        collectionName: 'Estate',
        puzzle: _storedPuzzle('door', 'Gate'),
        fromCollectionId: house.id,
      );
      expect(Directory('${directory.path}/front-door').existsSync(), isFalse);
      expect(File('${directory.path}/estate/gate.json').existsSync(), isTrue);
      expect(File('${directory.path}/estate/window.json').existsSync(), isTrue);
      final loaded = await store.loadAll();
      expect(loaded.map((puzzle) => puzzle.name), ['Gate', 'Window']);
    },
  );

  test('a taken name leaves the existing puzzle file in place', () async {
    final directory = Directory.systemTemp.createTempSync('puzzle-taken');
    addTearDown(() => directory.deleteSync(recursive: true));
    final store = LevelStore(directory: directory);
    final house = await store.savePuzzle(
      collectionName: 'House',
      puzzle: _storedPuzzle('door', 'Door'),
      fromCollectionId: null,
    );
    await store.savePuzzle(
      collectionName: 'House',
      puzzle: _storedPuzzle('window', 'Window'),
      fromCollectionId: house.id,
    );
    await expectLater(
      store.savePuzzle(
        collectionName: 'House',
        puzzle: _storedPuzzle('window', 'Door'),
        fromCollectionId: house.id,
      ),
      throwsA(
        isA<LevelSaveException>().having(
          (error) => error.failure,
          'failure',
          LevelSaveFailure.puzzleTaken,
        ),
      ),
    );
    expect(File('${directory.path}/house/door.json').existsSync(), isTrue);
    expect(File('${directory.path}/house/window.json').existsSync(), isTrue);
  });

  test(
    'loose puzzle files load as Puzzles and move into a folder on save',
    () async {
      final directory = Directory.systemTemp.createTempSync('puzzle-loose');
      addTearDown(() => directory.deleteSync(recursive: true));
      final store = LevelStore(directory: directory);
      await store.save(_storedPuzzle('one', 'Attic'));
      await store.save(_storedPuzzle('two', 'Cellar'));
      final loose = await store.loadCollections();
      expect(loose.single.name, 'Puzzles');
      expect(loose.single.loose, isTrue);
      expect(File('${directory.path}/one.json').existsSync(), isTrue);

      await store.savePuzzle(
        collectionName: 'Puzzles',
        puzzle: _storedPuzzle('one', 'Attic'),
        fromCollectionId: loose.single.id,
      );
      expect(File('${directory.path}/one.json').existsSync(), isFalse);
      expect(File('${directory.path}/two.json').existsSync(), isFalse);
      expect(File('${directory.path}/puzzles/attic.json').existsSync(), isTrue);
      expect(File('${directory.path}/puzzles/two.json').existsSync(), isTrue);
      expect(
        File('${directory.path}/puzzles/collection.json').readAsStringSync(),
        contains('Puzzles'),
      );
      final flat = await store.loadAll();
      expect(flat, hasLength(2));
    },
  );

  testWidgets('save names both, and unsaved edits ask before switching', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('puzzle-save-ui');
    addTearDown(() => directory.deleteSync(recursive: true));
    final store = LevelStore(directory: directory);
    await store.savePuzzle(
      collectionName: 'House',
      puzzle: _storedPuzzle('door', 'Door'),
      fromCollectionId: null,
    );
    await _pumpEditor(tester, store);
    await _pumpDialog(tester);

    await tester.tap(find.byKey(const Key('puzzle-save')));
    await _pumpDialog(tester);
    expect(find.byKey(const Key('puzzle-save-dialog')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('puzzle-collection-name')),
      'Shed',
    );
    await tester.enterText(find.byKey(const Key('puzzle-name')), 'Floor');
    await tester.tap(find.byKey(const Key('puzzle-save-confirm')));
    await _pumpDialog(tester);
    expect(find.byKey(const Key('puzzle-save-dialog')), findsNothing);
    expect(File('${directory.path}/shed/floor.json').existsSync(), isTrue);
    expect(File('${directory.path}/shed/collection.json').existsSync(), isTrue);
    expect(find.text('Floor'), findsWidgets);
    expect(find.text('Shed'), findsWidgets);

    await tester.tap(find.byKey(const Key('puzzle-puzzle-button')));
    await _pumpDialog(tester);
    expect(find.byKey(const Key('puzzle-save-prompt')), findsNothing);
    await tester.tap(find.byKey(const Key('puzzle-collection-item-house')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('puzzle-item-door')));
    await _pumpDialog(tester);
    expect(find.byKey(const Key('puzzle-library')), findsNothing);
    expect(find.text('Door'), findsWidgets);

    await tester.tap(find.byTooltip('Forbid'));
    await _pumpDialog(tester);
    await tester.tap(find.byKey(const Key('puzzle-editor-canvas')));
    await _pumpDialog(tester);

    await tester.tap(find.byKey(const Key('puzzle-puzzle-button')));
    await _pumpDialog(tester);
    await tester.tap(find.byKey(const Key('puzzle-collection-item-shed')));
    await tester.pump();
    await tester.tap(find.text('Floor'));
    await _pumpDialog(tester);
    expect(find.byKey(const Key('puzzle-save-prompt')), findsOneWidget);
    await tester.tap(find.byKey(const Key('puzzle-save-discard')));
    await _pumpDialog(tester);
    expect(find.byKey(const Key('puzzle-library')), findsNothing);
    expect(find.text('Floor'), findsWidgets);
  });

  testWidgets('search hides collections and puzzles that do not match', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('puzzle-search');
    addTearDown(() => directory.deleteSync(recursive: true));
    final store = LevelStore(directory: directory);
    await store.savePuzzle(
      collectionName: 'House',
      puzzle: _storedPuzzle('door', 'Door'),
      fromCollectionId: null,
    );
    await store.savePuzzle(
      collectionName: 'Garden',
      puzzle: _storedPuzzle('tree', 'Tree'),
      fromCollectionId: null,
    );
    await _pumpEditor(tester, store);
    await _pumpDialog(tester);
    await tester.tap(find.byKey(const Key('puzzle-collection-button')));
    await _pumpDialog(tester);
    expect(
      find.byKey(const Key('puzzle-collection-item-garden')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('puzzle-collection-item-garden')));
    await tester.pump();
    expect(find.byKey(const Key('puzzle-item-tree')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('puzzle-library-search')),
      'Door',
    );
    await tester.pump();
    expect(
      find.byKey(const Key('puzzle-collection-item-garden')),
      findsNothing,
    );
    expect(find.byKey(const Key('puzzle-item-tree')), findsNothing);
    expect(find.byKey(const Key('puzzle-item-door')), findsOneWidget);
  });
}

GridBlueprint _storedPuzzle(String id, String name) {
  return GridBlueprint(
    id: id,
    name: name,
    steps: const [GridStep(id: 'level', label: 'Level', polygons: [])],
  );
}

Future<void> _pumpEditor(WidgetTester tester, LevelStore store) {
  return tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => FmThemeData(),
      child: MaterialApp(home: PuzzleEditorView(store: store)),
    ),
  );
}

/// Advances dialog routes without waiting out a focused text cursor.
Future<void> _pumpDialog(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 400));
}
