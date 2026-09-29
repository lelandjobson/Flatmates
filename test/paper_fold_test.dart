import 'package:flatmates/gridcraft/blueprint.dart';
import 'package:flatmates/gridcraft/fold.dart';
import 'package:flatmates/gridcraft/scissor.dart';
import 'package:flatmates/papercut/paper.dart';
import 'package:flatmates/papercut/split.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PapercutSheet sheet() {
    return PapercutSheet(
      pieces: [
        PapercutPiece(
          id: 'paper',
          color: const Color(0xFFFFF3B0),
          vertices: const [
            Offset(0, 0),
            Offset(4, 0),
            Offset(4, 4),
            Offset(0, 4),
          ],
        ),
      ],
    );
  }

  test('a fold reflects the flap and an unfold leaves a score', () {
    final folded = foldSheet(
      sheet: sheet(),
      spanA: const Offset(2, 0),
      spanB: const Offset(2, 4),
      flapPoint: const Offset(3, 2),
      facing: FoldFacing.toward,
    );
    expect(folded, isNotNull);
    expect(folded!.folds.single.facing, FoldFacing.toward);
    final sample = folded.pieces
        .expand((piece) => piece.vertices)
        .firstWhere((point) => point.dx > 2.2);
    final shown = displayPoint(sample, folded.folds);
    expect(shown.dx, lessThan(2));

    final opened = unfoldAt(folded, const Offset(2, 2));
    expect(opened, isNotNull);
    expect(opened!.folds.single.facing, FoldFacing.unfolded);
    expect(opened.scores, hasLength(1));
  });

  test('a no-fold zone refuses a flap that meets it', () {
    final blocked = foldSheet(
      sheet: sheet(),
      spanA: const Offset(2, 0),
      spanB: const Offset(2, 4),
      flapPoint: const Offset(3, 2),
      facing: FoldFacing.away,
      noFold: const [
        [Offset(2.5, 1), Offset(3.5, 1), Offset(3.5, 3), Offset(2.5, 3)],
      ],
    );
    expect(blocked, isNull);
  });

  test('marks land on the folded face and not the concealed paper', () {
    final folded = foldSheet(
      sheet: sheet(),
      spanA: const Offset(2, 0),
      spanB: const Offset(2, 4),
      flapPoint: const Offset(3, 2),
      facing: FoldFacing.toward,
    )!;
    final marked = addPaperMark(folded, const [Offset(1.2, 2), Offset(1.5, 2)]);
    expect(marked.marks, hasLength(1));
    expect(marked.marks.single.points.first.dx, greaterThan(2));
  });

  test('a thick cut removes a strip and a hole punch bites the edge', () {
    final thick = applyThickCut(sheet(), const [Offset(0, 2), Offset(4, 2)], 0.25);
    expect(thick, isNotNull);
    expect(thick!.pieces.length, greaterThan(1));

    final punched = subtractRegion(
      sheet(),
      punchOutline(const Offset(0, 2), PunchShape.circle, 1),
    );
    expect(punched, isNotNull);
    expect(
      punchCrossesBlueprint(
        punchOutline(const Offset(1, 1), PunchShape.square, 1),
        const [
          [Offset(0, 0), Offset(2, 0), Offset(2, 2), Offset(0, 2)],
        ],
      ),
      isTrue,
    );
  });

  test('a penciled edge yields to a collinear penned neighbor', () {
    const pieces = [
      [Offset(0, 0), Offset(2, 0), Offset(2, 2), Offset(0, 2)],
      [Offset(2, 0), Offset(4, 0), Offset(4, 2), Offset(2, 2)],
    ];
    const styles = [
      [EdgeStyle.penned, EdgeStyle.penciled, EdgeStyle.penned, EdgeStyle.penned],
      [EdgeStyle.penned, EdgeStyle.penned, EdgeStyle.penned, EdgeStyle.penned],
    ];
    expect(
      penciledRidesPennedNeighbor(
        pieces,
        styles,
        const Offset(2, 0),
        const Offset(2, 2),
      ),
      isTrue,
    );
    final blocked = nextOutlineHit(
      from: const Offset(1, 1),
      direction: const Offset(1, 0),
      closed: [pieces.first],
    );
    expect(blocked!.dx, closeTo(2, 1e-6));
  });

  test('a hits piece fails when its paper leaves before the count is zero', () {
    const ring = [Offset(0, 0), Offset(2, 0), Offset(2, 2), Offset(0, 2)];
    final intact = sheet();
    final freed = PapercutSheet(
      pieces: [
        PapercutPiece(
          id: 'scrap',
          color: const Color(0xFFFFF3B0),
          vertices: ring,
        ),
      ],
    );
    expect(blueprintPieceCutOut(ring, intact), isFalse);
    expect(blueprintPieceCutOut(ring, freed), isTrue);
    expect(
      paperRemovedEarly(2, cutOut: blueprintPieceCutOut(ring, freed)),
      isTrue,
    );
    expect(
      paperRemovedEarly(0, cutOut: blueprintPieceCutOut(ring, freed)),
      isFalse,
    );
    expect(
      paperRemovedEarly(2, cutOut: blueprintPieceCutOut(ring, intact)),
      isFalse,
    );
    expect(paperRemovedEarly(null, cutOut: true), isFalse);
  });

  test('the collision anchor is the central cell and mirrors a cut', () {
    expect(
      collisionAnchor(const [
        Offset(0, 0),
        Offset(3, 0),
        Offset(3, 3),
        Offset(0, 3),
      ]),
      const Offset(1.5, 1.5),
    );
    final images = mirroredPolylines(
      const [Offset(0, 1), Offset(1, 1)],
      const Offset(2, 2),
      mirrorX: true,
      mirrorY: false,
    );
    expect(images.single.first.dx, closeTo(4, 1e-6));
    expect(images.single.first.dy, closeTo(1, 1e-6));
  });
}
