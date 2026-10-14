import 'package:flatmates/flatgram/flatgram_models.dart';
import 'package:flatmates/screens/tilewalk_view.dart';
import 'package:flatmates/tilewalk/tilewalk_models.dart';
import 'package:flatmates/tilewalk/tilewalk_painter.dart';
import 'package:flatmates/tilewalk/tilewalk_projector.dart';
import 'package:flatmates/tilewalk/tilewalk_puzzles.dart';
import 'package:flatmates/tilewalk/tilewalk_rules.dart';
import 'package:flatmates/ui/fm_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  group('Tilewalk rules', () {
    test('a swipe onto empty floor does not move the cube', () {
      final start = TilewalkSession.start(easyTilewalkPuzzle());
      final stepped = stepCube(start, TilewalkStep.down);
      expect(identical(stepped, start), isTrue);
      expect(stepped.cube, const GridPoint(0, 0));
    });

    test('the piece under the cube cannot be moved or turned', () {
      final start = TilewalkSession.start(easyTilewalkPuzzle());
      expect(canMoveTile(start, 'easy_start'), isFalse);
      expect(canMoveTile(start, 'easy_l'), isTrue);
      final turned = rotateTile(start, 'easy_start');
      expect(identical(turned, start), isTrue);
      final moved = placeTile(start, 'easy_start', const GridPoint(0, 1));
      expect(identical(moved, start), isTrue);
    });

    test('stepping on a mark collects that piece into the tray', () {
      final start = TilewalkSession.start(easyTilewalkPuzzle());
      expect(showDoor(start), isFalse);
      final stepped = stepCube(start, TilewalkStep.right);
      expect(stepped.cube, const GridPoint(1, 0));
      expect(stepped.tray, contains('easy_dot'));
      expect(stepped.pickups, isEmpty);
      expect(stepped.won, isFalse);
    });

    test('the door stays hidden until every cell is covered', () {
      final easy = easyTilewalkPuzzle();
      final beforeExit = _play(easy, easy.solution.length - 1);
      expect(isBoardComplete(beforeExit), isTrue);
      expect(showDoor(beforeExit), isTrue);
      expect(beforeExit.won, isFalse);
      expect(beforeExit.cube, isNot(easy.exitCell));

      final won = applyTilewalkCommand(beforeExit, easy.solution.last);
      expect(won.won, isTrue);
      expect(won.cube, easy.exitCell);
    });

    test('medium gap blocks the mark until the bridge is turned', () {
      final start = TilewalkSession.start(mediumTilewalkPuzzle());
      final blocked = stepCube(start, TilewalkStep.right);
      expect(identical(blocked, start), isTrue);

      final unturned = placeTile(start, 'med_l', const GridPoint(2, 0));
      expect(identical(unturned, start), isTrue);

      final turned = rotateTile(start, 'med_l');
      expect(turned.orientation('med_l'), 1);
      final bridged = placeTile(turned, 'med_l', const GridPoint(2, 0));
      expect(bridged.placed.map((p) => p.pieceId), contains('med_l'));
      expect(bridged.tray, isNot(contains('med_l')));
    });

    test('hard marks are collected in path order', () {
      final hard = hardTilewalkPuzzle();
      final start = TilewalkSession.start(hard);
      expect(canMoveTile(start, 'hard_start'), isFalse);

      final atFirst = _play(hard, 2);
      expect(atFirst.cube, const GridPoint(2, 0));
      expect(atFirst.tray, ['hard_l']);
      expect(atFirst.pickups.map((p) => p.pieceId), ['hard_d']);

      final jump = stepCube(atFirst, TilewalkStep.down);
      expect(identical(jump, atFirst), isTrue);
    });
  });

  group('Tilewalk camera', () {
    test('pitch lifts the cube and keeps grid right and down', () {
      const projector = TilewalkProjector(
        origin: Offset(200, 400),
        scale: 48,
        focusX: 1,
        focusY: 1,
      );
      final ground = projector.project(1, 1, 0);
      final above = projector.project(1, 1, 1);
      final east = projector.project(2, 1, 0);
      final south = projector.project(1, 2, 0);

      expect(above.dy, lessThan(ground.dy));
      expect(east.dx, greaterThan(ground.dx));
      expect(south.dy, greaterThan(ground.dy));
      expect(projector.depth(1, 1, 0), greaterThan(projector.depth(1, 2, 0)));
    });

    test('a pickup badge stays clear of the tile icon on a phone-sized board', () {
      final session = TilewalkSession.start(mediumTilewalkPuzzle());
      final projector = TilewalkProjector.fit(
        const Size(390, 700),
        session.puzzle.bounds,
      );
      final marks = tilewalkIconMarks(projector: projector, session: session);
      final pickup = marks.firstWhere((mark) => mark.pickup);
      final island = marks.firstWhere((mark) => mark.pieceId == 'med_island');
      expect(TilewalkIconMark.radius * 2, greaterThanOrEqualTo(36));
      expect((pickup.center - island.center).distance, greaterThanOrEqualTo(40));
    });
  });

  group('Tilewalk puzzles', () {
    for (final puzzle in kTilewalkPuzzles) {
      test('${puzzle.difficulty} solution fills the floor and exits', () {
        expect(puzzle.cells, contains(puzzle.startCell));
        expect(puzzle.cells, contains(puzzle.exitCell));
        for (final pickup in puzzle.pickups) {
          expect(puzzle.cells, contains(pickup.cell));
          expect(puzzle.byId.containsKey(pickup.pieceId), isTrue);
        }

        final won = _play(puzzle, puzzle.solution.length);
        expect(won.won, isTrue);
        expect(showDoor(won), isTrue);
        expect(isBoardComplete(won), isTrue);
        expect(won.pickups, isEmpty);
        expect(won.tray, isEmpty);
      });
    }
  });

  testWidgets('tilewalk lays out easy, medium, and hard on a phone', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final size in const [Size(390, 844), Size(320, 568)]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => FmThemeData(),
          child: const MaterialApp(home: TilewalkView()),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Easy'));
      await tester.pump();
      expect(find.text('First Steps'), findsOneWidget);
      await tester.tap(find.text('Medium'));
      await tester.pump();
      expect(find.text('The Gap'), findsOneWidget);
      await tester.tap(find.text('Hard'));
      await tester.pump();
      expect(find.text('Two Marks'), findsOneWidget);
    }
  });
}

TilewalkSession _play(TilewalkPuzzle puzzle, int commandCount) {
  var session = TilewalkSession.start(puzzle);
  for (final command in puzzle.solution.take(commandCount)) {
    final next = applyTilewalkCommand(session, command);
    expect(
      identical(next, session),
      isFalse,
      reason: '$command did not change ${puzzle.id}',
    );
    session = next;
  }
  return session;
}
