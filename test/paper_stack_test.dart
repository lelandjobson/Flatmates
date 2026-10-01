import 'package:flatmates/geometry/polygon_union.dart';
import 'package:flatmates/gridcraft/fold.dart';
import 'package:flatmates/gridcraft/paper_stack.dart';
import 'package:flatmates/papercut/paper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PapercutPiece box(
    String id,
    List<Offset> ring, {
    Offset separation = Offset.zero,
  }) {
    return PapercutPiece(
      id: id,
      color: const Color(0xFFFFF3B0),
      vertices: ring,
      separation: separation,
    );
  }

  const square = [Offset(0, 0), Offset(2, 0), Offset(2, 2), Offset(0, 2)];
  const shifted = [Offset(4, 0), Offset(6, 0), Offset(6, 2), Offset(4, 2)];
  const aside = [Offset(10, 0), Offset(12, 0), Offset(12, 2), Offset(10, 2)];

  PapercutSheet pile(List<PapercutPiece> pieces) {
    return PapercutSheet(pieces: pieces);
  }

  test('a stroke through stacked paper cuts both sheets', () {
    final sheet = pile([
      box('bottom', square),
      box('top', shifted, separation: const Offset(-4, 0)),
    ]);
    final cut = cutThroughFolds(sheet, const [Offset(0, 1), Offset(2, 1)])!;
    expect(
      _idAt(cut, const Offset(1, 0.5)),
      isNot(equals(_idAt(cut, const Offset(1, 1.5)))),
    );
    expect(
      _idAt(cut, const Offset(5, 0.5)),
      isNot(equals(_idAt(cut, const Offset(5, 1.5)))),
    );
    expect(_idAt(cut, const Offset(1, 0.5)).startsWith('bottom'), isTrue);
    expect(_idAt(cut, const Offset(5, 0.5)).startsWith('top'), isTrue);
  });

  test('covered blueprint ink is one over the sheet count solid', () {
    expect(pageOpacity(1), 1);
    expect(pageCounts(pile([box('only', square)])), [1]);

    final pair = pile([box('a', square), box('b', square)]);
    expect(pageCounts(pair), [2, 2]);
    expect(pageOpacity(2), 0.5);

    final triple = pile([box('a', square), box('b', square), box('c', square)]);
    expect(pageCounts(triple), [3, 3, 3]);
    expect(pageOpacity(3), closeTo(1 / 3, 1e-9));

    final withAside = pile([
      box('a', square),
      box('b', shifted, separation: const Offset(-4, 0)),
      box('c', aside),
    ]);
    expect(pageCounts(withAside), [2, 2, 1]);
    expect(pageOpacity(1), 1);
  });

  test('a folded sheet counts both layers as pages', () {
    final folded = foldSheet(
      sheet: pile([
        box('paper', const [
          Offset(0, 0),
          Offset(4, 0),
          Offset(4, 4),
          Offset(0, 4),
        ]),
      ]),
      spanA: const Offset(2, 0),
      spanB: const Offset(2, 4),
      flapPoint: const Offset(3, 2),
      facing: FoldFacing.toward,
    )!;
    expect(pageCounts(folded), [2, 2]);
  });

  test('a fold shows the pink back and the blueprint through the paper', () {
    final folded = foldSheet(
      sheet: pile([
        box('paper', const [
          Offset(0, 0),
          Offset(4, 0),
          Offset(4, 4),
          Offset(0, 4),
        ]),
      ]),
      spanA: const Offset(3, 0),
      spanB: const Offset(3, 4),
      flapPoint: const Offset(3.5, 2),
      facing: FoldFacing.toward,
    )!;
    final base = folded.pieces.indexWhere(
      (piece) => polygonCentroid(piece.vertices).dx < 3,
    );
    final flap = folded.pieces.indexWhere(
      (piece) => polygonCentroid(piece.vertices).dx > 3,
    );
    expect(base, isNonNegative);
    expect(flap, isNonNegative);

    expect(showingBack(const Offset(1, 2), folded.folds), isFalse);
    expect(showingBack(const Offset(3.5, 2), folded.folds), isTrue);
    expect(
      blueprintInkCover(
        pieceIndex: base,
        local: const Offset(1, 2),
        sheet: folded,
      ),
      0,
    );
    expect(
      blueprintInkCover(
        pieceIndex: base,
        local: const Offset(2.5, 2),
        sheet: folded,
      ),
      1,
    );
    expect(
      blueprintInkCover(
        pieceIndex: flap,
        local: const Offset(3.5, 2),
        sheet: folded,
      ),
      1,
    );
    expect(pageOpacity(2), 0.5);

    final bend = folded.folds.length - 1;
    expect(
      showingBack(const Offset(3.5, 2), folded.folds, bend: bend, bendT: 0.25),
      isFalse,
    );
    expect(
      showingBack(const Offset(3.5, 2), folded.folds, bend: bend, bendT: 0.75),
      isTrue,
    );
    expect(
      paperSideColor(folded.pieces[flap], back: true),
      const Color(0xFFFFB3BA),
    );
    expect(
      paperSideColor(folded.pieces[flap], back: false),
      folded.pieces[flap].color,
    );
  });

  test('clicks walk down a stack and a drag keeps the last sheet', () {
    final sheet = pile([
      box('bottom', square),
      box('middle', square),
      box('top', square),
    ]);
    const point = Offset(1, 1);
    expect(piecesUnder(point, sheet), [2, 1, 0]);

    final pick = PaperStackPick();
    final start = DateTime(2026);
    expect(pick.tap(point, sheet, start), 2);
    expect(
      pick.tap(point, sheet, start.add(const Duration(milliseconds: 80))),
      1,
    );
    expect(
      pick.tap(point, sheet, start.add(const Duration(milliseconds: 160))),
      0,
    );
    expect(pick.press(point, sheet), 0);
    expect(
      pick.tap(point, sheet, start.add(const Duration(milliseconds: 240))),
      2,
    );

    final two = pile([box('bottom', square), box('top', square)]);
    final buried = PaperStackPick();
    expect(buried.tap(point, two, start), 1);
    expect(
      buried.tap(point, two, start.add(const Duration(milliseconds: 50))),
      0,
    );
    expect(buried.press(point, two), 0);
    expect(
      buried.tap(point, two, start.add(const Duration(milliseconds: 100))),
      1,
    );

    final other = pile([box('right', aside), box('left', square)]);
    expect(buried.press(const Offset(11, 1), other), 0);
  });
}

String _idAt(PapercutSheet sheet, Offset point) {
  for (final piece in sheet.pieces) {
    if (piece.vertices.length < 3 || !isInsidePolygon(point, piece.vertices)) {
      continue;
    }
    return piece.id;
  }
  fail('no piece at $point');
}
