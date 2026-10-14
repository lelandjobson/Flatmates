import 'package:flatmates/linepuzzle/line_puzzle_models.dart';
import 'package:flatmates/linepuzzle/line_puzzle_puzzles.dart';
import 'package:flatmates/linepuzzle/line_puzzle_rules.dart';
import 'package:flatmates/screens/line_puzzle_view.dart';
import 'package:flatmates/ui/fm_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  group('Line puzzle rules', () {
    test('a dot can be crossed only once', () {
      final start = LineSession.start(_loop());
      var session = _walk(start, const [
        LinePoint(-2, 0),
        LinePoint(-1, 0),
        LinePoint(0, 0),
        LinePoint(0, 1),
      ]);
      final again = step(session, const LinePoint(0, 0));
      expect(identical(again, session), isTrue);
      expect(lineVisits(session, const LinePoint(0, 0)), 1);
    });

    test('a double dot allows a second crossing and then stops', () {
      final start = LineSession.start(_loop(doubles: {const LinePoint(0, 1)}));
      var session = _walk(start, const [
        LinePoint(-2, 1),
        LinePoint(-1, 1),
        LinePoint(0, 1),
        LinePoint(0, 2),
        LinePoint(0, 1),
      ]);
      expect(lineVisits(session, const LinePoint(0, 1)), 2);
      expect(session.phase, LinePhase.drawing);

      session = _walkOn(session, const [LinePoint(1, 1)]);
      final third = step(session, const LinePoint(0, 1));
      expect(identical(third, session), isTrue);
    });

    test('a missing dot is not on the graph', () {
      final start = LineSession.start(_loop(missing: {const LinePoint(1, -1)}));
      final session = _walk(start, const [
        LinePoint(-2, -1),
        LinePoint(-1, -1),
        LinePoint(0, -1),
      ]);
      final blocked = step(session, const LinePoint(1, -1));
      expect(identical(blocked, session), isTrue);
      expect(session.puzzle.hasDot(const LinePoint(1, -1)), isFalse);
    });

    test('a tool use starts on a paper-edge dot', () {
      final start = LineSession.start(_loop());
      expect(
        identical(beginStroke(start, const LinePoint(1, 1)), start),
        isTrue,
      );
      final drawing = beginStroke(start, const LinePoint(-2, 0));
      expect(drawing.phase, LinePhase.drawing);
      expect(drawing.head, const LinePoint(-2, 0));
      expect(identical(setTool(drawing, LineTool.fold), drawing), isTrue);
    });

    test('dragging off the paper pauses so the tool can change', () {
      final start = LineSession.start(_loop());
      var session = _walk(start, const [
        LinePoint(-2, 0),
        LinePoint(-2, -1),
        LinePoint(-3, -1),
      ]);
      expect(session.phase, LinePhase.paused);
      expect(session.strokes.single.points.last, const LinePoint(-2, -1));
      expect(session.strokes.single.tool, LineTool.cut);

      session = setTool(session, LineTool.fold);
      expect(session.tool, LineTool.fold);
      session = beginStroke(session, const LinePoint(4, 0));
      expect(session.phase, LinePhase.drawing);
      expect(session.strokes.last.tool, LineTool.fold);
      expect(session.strokes.last.points, const [LinePoint(4, 0)]);
    });

    test('numbers have to be entered in order', () {
      final start = LineSession.start(_orders());
      final failed = _walk(start, const [
        LinePoint(8, 1),
        LinePoint(7, 1),
        LinePoint(6, 1),
      ]);
      expect(failed.phase, LinePhase.failed);
      expect(failed.failure?.kind, LineFailureKind.order);
      expect(failed.failure?.regionIndex, 1);

      final solved = _walk(LineSession.start(_orders()), const [
        LinePoint(-2, 1),
        LinePoint(-1, 1),
        LinePoint(0, 1),
        LinePoint(0, 2),
        LinePoint(1, 2),
        LinePoint(2, 2),
        LinePoint(3, 2),
        LinePoint(4, 2),
      ]);
      expect(solved.phase, LinePhase.solved);
      expect(solved.visited, containsAll([0, 1]));
    });

    test('the wrong paper color fails on the closing edge', () {
      final failed = _traceColor(null);
      expect(failed.phase, LinePhase.failed);
      expect(failed.failure?.kind, LineFailureKind.color);
      expect(failed.failure?.regionIndex, 0);
      expect(failed.paperColor, isNull);
      expect(failed.solvedBorders, isEmpty);

      final wrong = _traceColor(1);
      expect(wrong.phase, LinePhase.failed);
      expect(wrong.failure?.kind, LineFailureKind.color);
      expect(wrong.paperColor, 1);
    });

    test('the matching paper color solves the region on the closing edge', () {
      final solved = _traceColor(0);
      expect(solved.phase, LinePhase.solved);
      expect(solved.paperColor, 0);
      expect(solved.solvedBorders, {0});
    });

    test('two Ls is solved by tracing both outlines and switching tools', () {
      var session = LineSession.start(twoLsLinePuzzle);
      session = _walk(session, const [
        LinePoint(-2, 0),
        LinePoint(-1, 0),
        LinePoint(0, 0),
        LinePoint(1, 0),
        LinePoint(2, 0),
        LinePoint(3, 0),
        LinePoint(3, 1),
        LinePoint(2, 1),
        LinePoint(1, 1),
        LinePoint(1, 2),
        LinePoint(0, 2),
        LinePoint(0, 1),
        LinePoint(0, 0),
        LinePoint(0, -1),
        LinePoint(0, -2),
        LinePoint(0, -3),
      ]);
      expect(session.phase, LinePhase.paused);
      expect(session.solvedBorders, {0});
      expect(session.strokes.single.tool, LineTool.cut);

      session = setTool(session, LineTool.fold);
      session = _walk(session, const [
        LinePoint(4, -2),
        LinePoint(4, -1),
        LinePoint(4, 0),
        LinePoint(5, 0),
        LinePoint(6, 0),
        LinePoint(7, 0),
        LinePoint(7, 1),
        LinePoint(6, 1),
        LinePoint(5, 1),
        LinePoint(5, 2),
        LinePoint(4, 2),
        LinePoint(4, 1),
        LinePoint(4, 0),
      ]);
      expect(session.phase, LinePhase.solved);
      expect(session.solvedBorders, {0, 1});
      expect(session.strokes.last.tool, LineTool.fold);
    });

    test('the peg slides along a groove and does not skip ahead', () {
      final start = beginStroke(
        LineSession.start(_loop()),
        const LinePoint(-2, 0),
      );
      final peg = LinePeg(anchors: start.strokes.last.points);
      final moved = movePeg(start, peg, const Offset(0.5, 0.05));
      expect(moved.session.head, const LinePoint(-2, 0));
      expect(moved.peg.toward, const LinePoint(-1, 0));
      expect(moved.peg.t, closeTo(0.5, 0.02));
      expect(releasePeg(moved.peg).atAnchor, isTrue);
    });

    test('a sideways drag mid-groove stays in the groove', () {
      final start = beginStroke(
        LineSession.start(_loop()),
        const LinePoint(-2, 0),
      );
      final entered = movePeg(
        start,
        LinePeg(anchors: start.strokes.last.points),
        const Offset(0.55, 0),
      );
      final shoved = movePeg(entered.session, entered.peg, const Offset(0, 1));
      expect(shoved.peg.toward, const LinePoint(-1, 0));
      expect(shoved.peg.t, closeTo(entered.peg.t, 0.02));
      expect(shoved.session.head, const LinePoint(-2, 0));
    });

    test('near a dot, a sideways drag turns onto the crossing track', () {
      final start = beginStroke(
        LineSession.start(_loop()),
        const LinePoint(-2, 0),
      );
      final near = movePeg(
        start,
        LinePeg(anchors: start.strokes.last.points),
        const Offset(0.9, 0),
      );
      expect(near.peg.toward, const LinePoint(-1, 0));
      expect(near.peg.t, greaterThan(1 - kLineJunction));
      final turned = movePeg(near.session, near.peg, const Offset(0, 0.4));
      expect(turned.session.head, const LinePoint(-1, 0));
      expect(turned.peg.toward, const LinePoint(-1, 1));
    });

    test('backtracking lifts the line and undoes a color flip', () {
      final puzzle = LinePuzzle(
        id: 'untint',
        title: 'Untint',
        blurb: '',
        regions: [LineRegion(ring: lineRect(0, 0, 2, 2), color: 0)],
        doubles: {const LinePoint(0, 0)},
        flippers: const [LineFlipper(at: LinePoint(-1, 0), color: 0)],
      );
      final start = beginStroke(
        LineSession.start(puzzle),
        const LinePoint(-2, 0),
      );
      final crossed = movePeg(
        start,
        LinePeg(anchors: start.strokes.last.points),
        const Offset(1, 0),
      );
      expect(crossed.session.head, const LinePoint(-1, 0));
      expect(crossed.session.paperColor, 0);

      final erased = movePeg(crossed.session, crossed.peg, const Offset(-1, 0));
      expect(erased.session.phase, LinePhase.drawing);
      expect(erased.session.head, const LinePoint(-2, 0));
      expect(erased.session.paperColor, isNull);
      expect(lineVisits(erased.session, const LinePoint(-1, 0)), 0);
    });

    test('a spent dot blocks the groove', () {
      final start = beginStroke(
        LineSession.start(_loop()),
        const LinePoint(-2, 1),
      );
      var cursor = PegMove(
        start,
        LinePeg(anchors: start.strokes.last.points),
        Offset.zero,
      );
      const hop = Offset(1, 0);
      cursor = movePeg(cursor.session, cursor.peg, hop);
      cursor = movePeg(cursor.session, cursor.peg, const Offset(0, -1));
      cursor = movePeg(cursor.session, cursor.peg, hop);
      cursor = movePeg(cursor.session, cursor.peg, const Offset(0, 1));
      expect(cursor.session.head, const LinePoint(0, 1));
      final back = movePeg(cursor.session, cursor.peg, const Offset(-1, 0));
      expect(back.session.head, const LinePoint(0, 1));
      expect(
        back.peg.atAnchor || back.peg.toward != const LinePoint(-1, 1),
        isTrue,
      );
      expect(lineVisits(back.session, const LinePoint(-1, 1)), 1);
    });

    test('order and color puzzles have a clearing path', () {
      final ordered = _walk(LineSession.start(orderLinePuzzle), const [
        LinePoint(-2, 1),
        LinePoint(-1, 1),
        LinePoint(0, 1),
        LinePoint(1, 1),
        LinePoint(2, 1),
        LinePoint(3, 1),
        LinePoint(4, 1),
        LinePoint(5, 1),
        LinePoint(6, 1),
      ]);
      expect(ordered.phase, LinePhase.solved);

      final colored = _walk(LineSession.start(colorLinePuzzle), const [
        LinePoint(-2, 0),
        LinePoint(-1, 0),
        LinePoint(0, 0),
        LinePoint(1, 0),
        LinePoint(2, 0),
        LinePoint(3, 0),
        LinePoint(3, 1),
        LinePoint(3, 2),
        LinePoint(2, 2),
        LinePoint(1, 2),
        LinePoint(0, 2),
        LinePoint(0, 1),
        LinePoint(0, 0),
        LinePoint(0, -1),
        LinePoint(1, -1),
        LinePoint(2, -1),
        LinePoint(3, -1),
        LinePoint(4, -1),
        LinePoint(5, -1),
        LinePoint(5, 0),
        LinePoint(6, 0),
        LinePoint(7, 0),
        LinePoint(8, 0),
        LinePoint(8, 1),
        LinePoint(8, 2),
        LinePoint(7, 2),
        LinePoint(6, 2),
        LinePoint(5, 2),
        LinePoint(5, 1),
        LinePoint(5, 0),
      ]);
      expect(colored.phase, LinePhase.solved);
      expect(colored.paperColor, 1);
      expect(colored.solvedBorders, {0, 1});
    });
  });

  testWidgets('line puzzle shows its three boards', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => FmThemeData(),
        child: const MaterialApp(home: LinePuzzleView()),
      ),
    );
    await tester.pump();

    expect(find.text('Two Ls'), findsOneWidget);
    expect(find.text('Drag from an edge dot to start a Cut'), findsOneWidget);
    await tester.tap(find.text('Order'));
    await tester.pump();
    expect(find.text('Pass through the numbers in order.'), findsOneWidget);
    await tester.tap(find.text('Color'));
    await tester.pump();
    expect(
      find.text('Cross a color square, then trace the matching piece.'),
      findsOneWidget,
    );
  });
}

LinePuzzle _loop({
  Set<LinePoint> doubles = const {},
  Set<LinePoint> missing = const {},
}) {
  return LinePuzzle(
    id: 'loop',
    title: 'Loop',
    blurb: '',
    regions: [LineRegion(ring: lineRect(0, 0, 2, 2), coverBorder: true)],
    doubles: doubles,
    missing: missing,
  );
}

LinePuzzle _orders() {
  return LinePuzzle(
    id: 'orders',
    title: 'Orders',
    blurb: '',
    regions: [
      LineRegion(ring: lineRect(0, 0, 2, 2), order: 1),
      LineRegion(ring: lineRect(4, 0, 6, 2), order: 2),
    ],
  );
}

LineSession _traceColor(int? flipColor) {
  final puzzle = LinePuzzle(
    id: 'tint',
    title: 'Tint',
    blurb: '',
    regions: [LineRegion(ring: lineRect(0, 0, 2, 2), color: 0)],
    doubles: {const LinePoint(0, 0)},
    flippers: [
      if (flipColor != null)
        LineFlipper(at: const LinePoint(-1, 0), color: flipColor),
    ],
  );
  return _walk(LineSession.start(puzzle), const [
    LinePoint(-2, 0),
    LinePoint(-1, 0),
    LinePoint(0, 0),
    LinePoint(1, 0),
    LinePoint(2, 0),
    LinePoint(2, 1),
    LinePoint(2, 2),
    LinePoint(1, 2),
    LinePoint(0, 2),
    LinePoint(0, 1),
    LinePoint(0, 0),
  ]);
}

LineSession _walk(LineSession session, List<LinePoint> points) {
  expect(points, isNotEmpty);
  final started = beginStroke(session, points.first);
  expect(started.phase, LinePhase.drawing, reason: 'begin ${points.first}');
  return _walkOn(started, points.skip(1).toList());
}

LineSession _walkOn(LineSession session, List<LinePoint> points) {
  var current = session;
  for (final point in points) {
    final next = step(current, point);
    expect(
      identical(next, current),
      isFalse,
      reason: 'stuck at ${current.head} -> $point',
    );
    current = next;
    if (current.phase != LinePhase.drawing) break;
  }
  return current;
}
