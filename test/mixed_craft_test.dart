import 'dart:math' as math;

import 'package:flatmates/gridcraft/edit.dart';
import 'package:flatmates/gridcraft/fold.dart';
import 'package:flatmates/gridcraft/mixed_craft.dart';
import 'package:flatmates/papercut/models.dart';
import 'package:flatmates/papercut/paper.dart';
import 'package:flatmates/screens/mixed_crafting_view.dart';
import 'package:flatmates/ui/fm_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  group('mixed craft sheet', () {
    test('the opening sheet is 24 units about the origin', () {
      final piece = mixedOpeningArea().sheets.single.paper.pieces.single;
      expect(piece.vertices[1].dx - piece.vertices[0].dx, 24);
      expect(piece.vertices[2].dy - piece.vertices[1].dy, 24);
      expect(piece.vertices.first, const Offset(-12, -12));
      expect(gridCellsAcross(kMixedDefaultScale), 6);
    });

    test('plus steps finer and minus steps coarser', () {
      expect(stepGridScale(4, finer: true), 3);
      expect(stepGridScale(4, finer: false), 6);
      expect(_walk(4, finer: true), [3, 2, 1]);
      expect(_walk(4, finer: false), [6, 8, 12]);
      expect(gridCellsAcross(12), 2);
      expect(gridCellsAcross(1), 24);
      final history = MixedCraftHistory();
      stepGridScale(4, finer: true);
      expect(history.undo(mixedOpeningArea()), isNull);
    });

    test('a second sheet sits one cell clear of the first', () {
      final placed = placeSheet(mixedOpeningArea(), kPapercutGreen, 4);
      expect(placed.sheets, hasLength(2));
      final added = placed.sheets.last.paper.pieces.single;
      expect(added.color, kPapercutGreen);
      expect(added.vertices.first, const Offset(16, -12));
      expect(added.vertices[1].dx, 40);
    });
  });

  group('crafting grid fade', () {
    test('a scale step crossfades both lattices over 300ms', () {
      expect(kGridScaleFade, const Duration(milliseconds: 300));
      final fade = GridScaleCrossfade();
      expect(fade.opacities(0), {kMixedDefaultScale: 1.0});

      expect(fade.retarget(stepGridScale(4, finer: true)), isTrue);
      expect(fade.scale, 3);
      expect(fade.opacities(0), {4: 1.0});
      expect(fade.opacities(0.5)[4], closeTo(0.5, 1e-9));
      expect(fade.opacities(0.5)[3], closeTo(0.5, 1e-9));
      expect(fade.opacities(1).keys, {3});
      expect(fade.opacities(1)[3], 1);

      fade.settle();
      expect(fade.opacities(0), {3: 1.0});
      expect(fade.retarget(3), isFalse);
    });

    test('a step during the fade retargets from the current opacities', () {
      final fade = GridScaleCrossfade();
      fade.retarget(3);
      expect(fade.retarget(2, t: 0.5), isTrue);

      final held = fade.opacities(0);
      expect(held[4], closeTo(0.5, 1e-9));
      expect(held[3], closeTo(0.5, 1e-9));
      expect(held.containsKey(2), isFalse);

      final mid = fade.opacities(0.5);
      expect(mid[4], closeTo(0.25, 1e-9));
      expect(mid[3], closeTo(0.25, 1e-9));
      expect(mid[2], closeTo(0.5, 1e-9));
      expect(fade.opacities(1).keys, {2});

      final back = GridScaleCrossfade();
      back.retarget(3);
      expect(back.retarget(4, t: 0.25), isTrue);
      expect(back.opacities(0)[4], closeTo(0.75, 1e-9));
      expect(back.opacities(0)[3], closeTo(0.25, 1e-9));
      expect(back.opacities(1).keys, {4});

      final finest = GridScaleCrossfade(scale: 1);
      expect(finest.retarget(stepGridScale(1, finer: true)), isFalse);
      expect(finest.opacities(0.4), {1: 1.0});
    });
  });

  group('mixed craft select', () {
    test(
      'left to right misses a partial overlap and right to left hits it',
      () {
        final area = mixedOpeningArea();
        final rect = const Rect.fromLTRB(0, 0, 10, 10);
        expect(mixedMarqueeHits(area, rect, MarqueePick.contain), isEmpty);
        expect(mixedMarqueeHits(area, rect, MarqueePick.cross), {
          'sheet-1/paper',
        });
        expect(
          mixedMarqueeHits(
            area,
            const Rect.fromLTRB(-12, -12, 12, 12),
            MarqueePick.contain,
          ),
          {'sheet-1/paper'},
        );
      },
    );

    test('a hidden piece is neither under the reticle nor in a marquee', () {
      final area = mixedOpeningArea().copy(selected: {'sheet-1/paper'});
      final hidden = hideSelection(area)!;
      expect(pieceUnderAim(hidden, Offset.zero), isNull);
      expect(
        mixedMarqueeHits(
          hidden,
          const Rect.fromLTRB(-20, -20, 20, 20),
          MarqueePick.cross,
        ),
        isEmpty,
      );
      final shown = showPiece(hidden, 'sheet-1/paper')!;
      expect(pieceUnderAim(shown, Offset.zero), 'sheet-1/paper');
    });
  });

  group('mixed craft cut', () {
    test('an aim inside the sheet does not lock and an edge does', () {
      final area = mixedOpeningArea();
      expect(lockCut(Offset.zero, area, 4), isNull);
      final lock = lockCut(const Offset(-12, 0), area, 4);
      expect(lock, isNotNull);
      expect(lock!.point, const Offset(-12, 0));
    });

    test('a through cut splits and leaves the pieces unmoved', () {
      final area = mixedOpeningArea();
      final next = commitCut(
        area,
        'sheet-1',
        const Offset(-12, 0),
        const Offset(12, 0),
      );
      expect(next, isNotNull);
      expect(next!.sheets.single.paper.pieces.length, greaterThan(1));
      for (final piece in next.sheets.single.paper.pieces) {
        expect(piece.separation, Offset.zero);
      }
      expect(pieceUnderAim(next, const Offset(0, 6)), isNotNull);
      expect(
        pieceUnderAim(next, const Offset(0, 6)),
        isNot(pieceUnderAim(next, const Offset(0, -6))),
      );
    });

    test('a cut that stops inside the sheet does not split', () {
      final area = mixedOpeningArea();
      expect(
        commitCut(area, 'sheet-1', const Offset(-12, 0), Offset.zero),
        isNull,
      );
      expect(area.sheets.single.paper.pieces, hasLength(1));
    });

    test('an interior aim leaves through the far edge', () {
      const ring = [
        Offset(-12, -12),
        Offset(12, -12),
        Offset(12, 12),
        Offset(-12, 12),
      ];
      final end = cutSpanEnd(const Offset(-12, 0), Offset.zero, ring);
      expect(end, isNotNull);
      expect(end!.dx, closeTo(12, 1e-6));
      expect(end.dy, closeTo(0, 1e-6));
      final split = commitCut(
        mixedOpeningArea(),
        'sheet-1',
        const Offset(-12, 0),
        end,
      );
      expect(split, isNotNull);
      expect(split!.sheets.single.paper.pieces.length, greaterThan(1));
    });
  });

  group('mixed craft fold', () {
    test('a fold start inside the sheet does not lock and an edge does', () {
      final area = mixedOpeningArea();
      expect(lockFold(Offset.zero, area, 4), isNull);
      final lock = lockFold(const Offset(-12, 0), area, 4);
      expect(lock, isNotNull);
      expect(lock!.point, const Offset(-12, 0));
      expect(lock.sheetId, 'sheet-1');
      expect(lock.pieceId, 'paper');
    });

    test('a score then a fold can be unfolded', () {
      final area = mixedOpeningArea();
      const start = Offset(-12, 0);
      const end = Offset(12, 0);
      const face = Offset(0, 6);
      final scored = scoreSpan(area, 'sheet-1', start, end, face);
      expect(scored, isNotNull);
      expect(scored!.sheets.single.paper.scores, isNotEmpty);
      final folded = foldSpan(scored, 'sheet-1', start, end, face);
      expect(folded, isNotNull);
      expect(folded!.sheets.single.paper.folds, isNotEmpty);
      final sheet = folded.sheets.single;
      final piece = sheet.paper.pieces.first;
      final ring = shownRing(
        piece.vertices,
        piece.separation,
        sheet.paper.folds,
        pieceId: piece.id,
      );
      var aim = Offset.zero;
      for (final point in ring) {
        aim += point;
      }
      aim = aim / ring.length.toDouble();
      final opened = unfoldUnder(folded, aim);
      expect(opened, isNotNull);
      expect(
        opened!.sheets.single.paper.folds.single.facing,
        FoldFacing.unfolded,
      );
    });

    test('a crease nearer than the cell wins the snap', () {
      final area = mixedOpeningArea();
      expect(snapCraft(const Offset(3, 1), 4, area), const Offset(4, 0));
      final scored = scoreSpan(
        area,
        'sheet-1',
        const Offset(-12, 0),
        const Offset(12, 0),
        const Offset(0, 6),
      )!;
      expect(snapCraft(const Offset(1, 0.2), 4, scored), const Offset(1, 0));
    });
  });

  group('mixed craft history', () {
    test('undo restores a cut, a move, and a hide, and redo puts it back', () {
      final history = MixedCraftHistory();
      final area = mixedOpeningArea().copy(selected: {'sheet-1/paper'});

      history.push(area);
      final cut = commitCut(
        area,
        'sheet-1',
        const Offset(-12, 0),
        const Offset(12, 0),
      )!;
      final restoredCut = history.undo(cut)!;
      expect(restoredCut.sheets.single.paper.pieces, hasLength(1));
      final redone = history.redo(restoredCut)!;
      expect(redone.sheets.single.paper.pieces.length, greaterThan(1));

      history.push(area);
      final moved = movePieces(area, const Offset(4, 0))!;
      expect(
        moved.sheets.single.paper.pieces.single.separation,
        const Offset(4, 0),
      );
      final restoredMove = history.undo(moved)!;
      expect(
        restoredMove.sheets.single.paper.pieces.single.separation,
        Offset.zero,
      );

      history.push(area);
      final hidden = hideSelection(area)!;
      expect(hidden.hidden, contains('sheet-1/paper'));
      final restoredHide = history.undo(hidden)!;
      expect(restoredHide.hidden, isEmpty);
      final shown = history.redo(restoredHide)!;
      expect(shown.hidden, contains('sheet-1/paper'));
    });

    test('undo restores the selection and a new commit clears redo', () {
      final history = MixedCraftHistory();
      final area = mixedOpeningArea().copy(selected: {'sheet-1/paper'});
      history.push(area);
      final hidden = hideSelection(area)!;
      final back = history.undo(hidden)!;
      expect(back.selected, {'sheet-1/paper'});
      expect(history.canRedo, isTrue);
      history.push(area);
      expect(history.canRedo, isFalse);
    });

    test('a quarter turn bakes the moved sheet onto the grid', () {
      final area = mixedOpeningArea().copy(selected: {'sheet-1/paper'});
      final moved = movePieces(area, const Offset(4, 0))!;
      final turned = rotateSelection(moved)!;
      final piece = turned.sheets.single.paper.pieces.single;
      expect(piece.separation, Offset.zero);
      expect(piece.vertices.first, const Offset(16, -12));
    });
  });

  testWidgets('the crafting view keeps grid scale out of undo', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => FmThemeData(),
        child: const MaterialApp(home: MixedCraftingView()),
      ),
    );
    await tester.pump();

    expect(find.text('Yellow'), findsOneWidget);
    expect(find.text('Green'), findsOneWidget);
    expect(find.byIcon(Icons.near_me), findsOneWidget);
    expect(find.byIcon(Icons.content_cut), findsOneWidget);
    expect(find.byIcon(Icons.flip), findsOneWidget);
    expect(find.byIcon(Icons.adjust), findsOneWidget);
    expect(find.byIcon(Icons.crop_free), findsOneWidget);

    GestureDetector button(Key key) {
      return tester.widget<GestureDetector>(find.byKey(key));
    }

    expect(button(const Key('mixed-undo')).onTap, isNull);
    expect(button(const Key('mixed-redo')).onTap, isNull);

    await tester.tap(find.byKey(const Key('mixed-plus')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('mixed-minus')));
    await tester.pump();
    expect(button(const Key('mixed-undo')).onTap, isNull);

    await tester.tap(find.text('Yellow'));
    await tester.pump();
    expect(button(const Key('mixed-undo')).onTap, isNotNull);

    await tester.tap(find.byKey(const Key('mixed-undo')));
    await tester.pump();
    expect(button(const Key('mixed-undo')).onTap, isNull);
    expect(button(const Key('mixed-redo')).onTap, isNotNull);

    await tester.tap(find.text('Green'));
    await tester.pump();
    expect(button(const Key('mixed-redo')).onTap, isNull);
    expect(button(const Key('mixed-undo')).onTap, isNotNull);
  });

  testWidgets('a second tap cuts through the reticle', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => FmThemeData(),
        child: const MaterialApp(home: MixedCraftingView()),
      ),
    );
    await tester.pump();

    GestureDetector button(Key key) {
      return tester.widget<GestureDetector>(find.byKey(key));
    }

    await tester.tap(find.byIcon(Icons.content_cut));
    await tester.pump();

    final canvas = find.byKey(const Key('mixed-craft-canvas'));
    final center = tester.getCenter(canvas);
    const margin = kMixedPaperSize / 2 * 1.35;
    final aspect = 800 / 600;
    final fit = math.max(margin, margin / math.max(aspect, 0.05));
    final pixelsPerUnit = 600 / (2 * fit * 1.35);

    Future<void> pan(Offset delta) async {
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(delta);
      await gesture.up();
      await tester.pump();
    }

    await pan(Offset(12 * pixelsPerUnit, 0));
    await tester.tap(canvas);
    await tester.pump();
    expect(button(const Key('mixed-undo')).onTap, isNull);

    await pan(Offset(-24 * pixelsPerUnit, 0));
    await tester.tap(canvas);
    await tester.pump();
    expect(button(const Key('mixed-undo')).onTap, isNotNull);
    await tester.pumpAndSettle();
  });
}

List<int> _walk(int scale, {required bool finer}) {
  final steps = <int>[];
  var current = scale;
  while (true) {
    final next = stepGridScale(current, finer: finer);
    if (next == current) return steps;
    steps.add(next);
    current = next;
  }
}
