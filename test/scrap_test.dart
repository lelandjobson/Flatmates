import 'package:flatmates/gridcraft/scrap.dart';
import 'package:flatmates/papercut/paper.dart';
import 'package:flatmates/papercut/split.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const color = Color(0xFFFFF3B0);
  const sheetRing = [Offset(0, 0), Offset(6, 0), Offset(6, 4), Offset(0, 4)];
  const leftShape = [Offset(0, 0), Offset(2, 0), Offset(2, 4), Offset(0, 4)];
  const rightShape = [Offset(4, 0), Offset(6, 0), Offset(6, 4), Offset(4, 4)];

  PapercutSheet sheet() => PapercutSheet(
    pieces: const [
      PapercutPiece(id: 'paper', color: color, vertices: sheetRing),
    ],
  );

  test('one carrier is kept and the empty offcut is scrap', () {
    final cut = applyPapercutCut(sheet(), const [Offset(5, -1), Offset(5, 5)])!;
    final verdict = classifyFreshPieces(
      before: sheet(),
      after: cut,
      closedRings: const [leftShape],
    );
    expect(verdict.discardsBlueprint, isFalse);
    expect(verdict.carriers, hasLength(1));
    expect(verdict.scraps, hasLength(1));
    expect(verdict.carriers.single.vertices.first.dx, lessThan(5));
    expect(verdict.smallest!.vertices.length, 4);
  });

  test('two carriers discard a blueprint piece', () {
    final cut = applyPapercutCut(sheet(), const [Offset(3, -1), Offset(3, 5)])!;
    final verdict = classifyFreshPieces(
      before: sheet(),
      after: cut,
      closedRings: const [leftShape, rightShape],
    );
    expect(verdict.discardsBlueprint, isTrue);
    expect(verdict.carriers, hasLength(2));
    expect(verdict.scraps, isEmpty);
    expect(verdict.smallest, isNotNull);
  });

  test('an exact cut-out is freed and the rest still carries', () {
    final cut = applyPapercutCut(sheet(), const [Offset(2, -1), Offset(2, 5)])!;
    final verdict = classifyFreshPieces(
      before: sheet(),
      after: cut,
      closedRings: const [leftShape, rightShape],
    );
    expect(verdict.discardsBlueprint, isFalse);
    expect(verdict.freed, hasLength(1));
    expect(verdict.carriers, hasLength(1));
    expect(verdict.scraps, isEmpty);
    expect(verdict.freed.single.id, isNot(verdict.carriers.single.id));
  });

  test('a cut through a blueprint piece still fails', () {
    final cut = applyPapercutCut(sheet(), const [
      Offset(1.5, -1),
      Offset(1.5, 5),
    ])!;
    const ring = [Offset(0, 0), Offset(3, 0), Offset(3, 4), Offset(0, 4)];
    final verdict = classifyFreshPieces(
      before: sheet(),
      after: cut,
      closedRings: const [ring],
    );
    expect(verdict.discardsBlueprint, isTrue);
    expect(verdict.carriers, hasLength(2));
    expect(verdict.scraps, isEmpty);
  });

  test('paper that only shares a blueprint edge is scrap', () {
    // A concave ring whose center falls in the notch. The notch paper
    // meets the ring only along its outline.
    const ring = [
      Offset(0, 0),
      Offset(4, 0),
      Offset(4, 1),
      Offset(1, 1),
      Offset(1, 3),
      Offset(4, 3),
      Offset(4, 4),
      Offset(0, 4),
    ];
    const mouth = [Offset(1, 1), Offset(4, 1), Offset(4, 3), Offset(1, 3)];
    final before = sheet();
    final after = PapercutSheet(
      pieces: const [
        PapercutPiece(id: 'body', color: color, vertices: ring),
        PapercutPiece(id: 'mouth', color: color, vertices: mouth),
      ],
    );
    final verdict = classifyFreshPieces(
      before: before,
      after: after,
      closedRings: const [ring],
    );
    expect(verdict.discardsBlueprint, isFalse);
    expect(verdict.freed, isEmpty);
    expect(verdict.carriers.map((piece) => piece.id), ['body']);
    expect(verdict.scraps.map((piece) => piece.id), ['mouth']);
  });

  test('leftover cells run from the top-left and finish at 3 seconds', () {
    const piece = PapercutPiece(
      id: 'margin',
      color: color,
      vertices: [Offset(0, 0), Offset(2, 0), Offset(2, 2), Offset(0, 2)],
    );
    final cells = leftoverCells(
      pieces: const [piece],
      freedIds: const {},
      spacing: 1,
    );
    expect(cells, const [
      Offset(0.5, 1.5),
      Offset(1.5, 1.5),
      Offset(0.5, 0.5),
      Offset(1.5, 0.5),
    ]);
    final windows = tallySchedule(cells.length);
    expect(windows.last.end, closeTo(3, 1e-9));
    expect(tallyFinished(windows, 0), 0);
    expect(tallyFinished(windows, 3), 4);
    expect(tallyFinished(windows, windows.first.end), 1);
  });

  test('a freed blueprint piece is left out of the tally', () {
    const freed = PapercutPiece(
      id: 'shape',
      color: color,
      vertices: [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)],
    );
    const margin = PapercutPiece(
      id: 'margin',
      color: color,
      vertices: [Offset(1, 0), Offset(2, 0), Offset(2, 1), Offset(1, 1)],
    );
    final cells = leftoverCells(
      pieces: const [freed, margin],
      freedIds: const {'shape'},
      spacing: 1,
    );
    expect(cells, const [Offset(1.5, 0.5)]);
  });
}
