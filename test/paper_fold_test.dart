import 'dart:math' as math;

import 'package:flatmates/geometry/polygon_union.dart';
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

  test('a cut across a folded sheet hits the flap and the paper under it', () {
    final folded = foldSheet(
      sheet: sheet(),
      spanA: const Offset(2, 0),
      spanB: const Offset(2, 4),
      flapPoint: const Offset(3, 2),
      facing: FoldFacing.toward,
    )!;
    final cut = cutThroughFolds(folded, const [Offset(0, 2), Offset(2, 2)]);
    expect(cut, isNotNull);
    expect(
      _pieceAt(cut!, const Offset(1, 1))!.id,
      isNot(equals(_pieceAt(cut, const Offset(1, 3))!.id)),
    );
    expect(
      _pieceAt(cut, const Offset(3, 1))!.id,
      isNot(equals(_pieceAt(cut, const Offset(3, 3))!.id)),
    );
  });

  test('a semicircle through a folded edge opens into a hole', () {
    final folded = foldSheet(
      sheet: sheet(),
      spanA: const Offset(2, 0),
      spanB: const Offset(2, 4),
      flapPoint: const Offset(3, 2),
      facing: FoldFacing.toward,
    )!;
    final cut = cutThroughFolds(folded, _semicircleLeft())!;
    const sample = Offset(1.2, 2);
    for (final piece in cut.pieces) {
      if (polygonSignedArea(piece.vertices).abs() < 4) continue;
      expect(_drawnContains(piece, sample, cut.folds), isFalse);
    }
    final opened = unfoldAt(cut, const Offset(2, 0.25))!;
    final holed = opened.pieces.where((piece) => piece.holes.isNotEmpty);
    expect(holed, isNotEmpty);
    expect(
      isInsidePolygon(const Offset(2, 2), holed.first.holes.first),
      isTrue,
    );
    final scraps = opened.pieces.where(
      (piece) => polygonSignedArea(piece.vertices).abs() < 4,
    );
    expect(scraps, hasLength(2));
  });

  test('a cut through two fold directions hits every layer', () {
    final first = foldSheet(
      sheet: sheet(),
      spanA: const Offset(2, 0),
      spanB: const Offset(2, 4),
      flapPoint: const Offset(3, 2),
      facing: FoldFacing.toward,
    )!;
    final folded = foldSheet(
      sheet: first,
      spanA: const Offset(0, 2),
      spanB: const Offset(2, 2),
      flapPoint: const Offset(1, 3),
      facing: FoldFacing.toward,
    )!;
    expect(folded.pieces, hasLength(4));
    final cut = cutThroughFolds(folded, const [Offset(0, 1), Offset(2, 1)])!;
    expect(cut.pieces, hasLength(8));
    void split(Offset below, Offset above) {
      expect(_pieceAt(cut, below)!.id, isNot(equals(_pieceAt(cut, above)!.id)));
    }

    split(const Offset(1, 0.5), const Offset(1, 1.5));
    split(const Offset(3, 0.5), const Offset(3, 1.5));
    split(const Offset(1, 2.5), const Offset(1, 3.5));
    split(const Offset(3, 2.5), const Offset(3, 3.5));
  });

  test('a second fold also cuts the layer already folded over', () {
    final first = foldSheet(
      sheet: sheet(),
      spanA: const Offset(2, 0),
      spanB: const Offset(2, 4),
      flapPoint: const Offset(3, 2),
      facing: FoldFacing.toward,
    )!;
    final second = foldSheet(
      sheet: first,
      spanA: const Offset(0, 2),
      spanB: const Offset(2, 2),
      flapPoint: const Offset(1, 3),
      facing: FoldFacing.toward,
    );
    expect(second, isNotNull);
    expect(second!.pieces.length, greaterThan(first.pieces.length));
    final shown = displayPoint(const Offset(4, 4), second.folds);
    expect(shown.dx, closeTo(0, 1e-6));
    expect(shown.dy, closeTo(0, 1e-6));
  });

  test('a fold bends through the crease before it lands', () {
    final folded = foldSheet(
      sheet: sheet(),
      spanA: const Offset(2, 0),
      spanB: const Offset(2, 4),
      flapPoint: const Offset(3, 2),
      facing: FoldFacing.toward,
    )!;
    final mid = displayPoint(
      const Offset(4, 2),
      folded.folds,
      bend: 0,
      bendT: 0.5,
    );
    expect(mid.dx, closeTo(2, 1e-6));
    expect(mid.dy, closeTo(2, 1e-6));
    final landed = displayPoint(const Offset(4, 2), folded.folds);
    expect(landed.dx, closeTo(0, 1e-6));
  });

  test('the folder crease is perpendicular to the nearest edge', () {
    final left = folderGuide(const Offset(0.4, 1.4), sheet(), 1);
    expect(left, isNotNull);
    expect(left!.line.$1.dy, closeTo(left.line.$2.dy, 1e-6));
    expect(left.line.$1.dy, closeTo(1, 1e-6));
    expect(left.line.$1.dx, closeTo(0, 1e-6));
    expect(left.line.$2.dx, closeTo(4, 1e-6));
    expect(left.flap!.dy, lessThan(1));

    final top = folderGuide(const Offset(1.4, 0.4), sheet(), 1);
    expect(top, isNotNull);
    expect(top!.line.$1.dx, closeTo(top.line.$2.dx, 1e-6));
    expect(top.line.$1.dx, closeTo(1, 1e-6));
    expect(top.flap!.dx, lessThan(1));
  });

  test('a diagonal edge snaps its fold to the stronger axis', () {
    const ring = [Offset(0, 0), Offset(2, 0), Offset(0, 1)];
    final bottom = axisPerpendicular(ring[0], ring[1], ring);
    expect(bottom, const Offset(0, 1));
    final slant = axisPerpendicular(ring[1], ring[2], ring);
    expect(slant!.dx.abs() == 1 || slant.dy.abs() == 1, isTrue);
    expect(slant.dx == 0 || slant.dy == 0, isTrue);
  });
  test('the folder preview hides away from the paper', () {
    expect(folderGuide(const Offset(6, 2), sheet(), 1), isNull);
  });

  test('a fold stays on the nearest paper', () {
    PapercutPiece box(String id, double x) {
      return PapercutPiece(
        id: id,
        color: const Color(0xFFFFF3B0),
        vertices: [
          Offset(x, 0),
          Offset(x + 4, 0),
          Offset(x + 4, 4),
          Offset(x, 4),
        ],
      );
    }

    final both = PapercutSheet(pieces: [box('near', 0), box('far', 8)]);
    final guide = folderGuide(const Offset(0.4, 1.4), both, 1);
    expect(guide, isNotNull);
    expect(guide!.line.$1.dx, inInclusiveRange(0, 4));
    expect(guide.line.$2.dx, inInclusiveRange(0, 4));
    expect(guide.line.$1.dy, inInclusiveRange(0, 4));
    expect(guide.line.$2.dy, inInclusiveRange(0, 4));
  });

  test('an unfold cue sits on the drawn crease', () {
    final folded = foldSheet(
      sheet: sheet(),
      spanA: const Offset(2, 0),
      spanB: const Offset(2, 4),
      flapPoint: const Offset(3, 2),
      facing: FoldFacing.toward,
    )!;
    final cue = unfoldCue(folded, const Offset(2.2, 2));
    expect(cue, isNotNull);
    expect(cue!.$1.dx, closeTo(2, 1e-6));
    expect(cue.$2.dx, closeTo(2, 1e-6));
    expect(unfoldCue(folded, const Offset(0, 0)), isNull);
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

  test('a hole punch centers on the nearest grid point', () {
    expect(snapPunchCenter(const Offset(1.2, 1.6), 1), const Offset(1, 2));
    expect(snapPunchCenter(const Offset(0, 2), 1), const Offset(0, 2));
    expect(
      snapPunchCenter(const Offset(0.4, -0.6), 0.5),
      const Offset(0.5, -0.5),
    );
  });

  test('a thick cut removes a strip and a hole punch bites the edge', () {
    final thick = applyThickCut(sheet(), const [
      Offset(0, 2),
      Offset(4, 2),
    ], 0.25);
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
      [
        EdgeStyle.penned,
        EdgeStyle.penciled,
        EdgeStyle.penned,
        EdgeStyle.penned,
      ],
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

  test('fold dashes share one pattern measured from the world origin', () {
    bool covers(List<(Offset, Offset)> marks, double x) {
      for (final mark in marks) {
        final lo = math.min(mark.$1.dx, mark.$2.dx);
        final hi = math.max(mark.$1.dx, mark.$2.dx);
        if (x >= lo - 1e-6 && x <= hi + 1e-6) return true;
      }
      return false;
    }

    final whole = globalDashSegments(Offset.zero, const Offset(4, 0));
    final left = globalDashSegments(Offset.zero, const Offset(2, 0));
    final right = globalDashSegments(const Offset(2, 0), const Offset(4, 0));
    final mid = globalDashSegments(const Offset(0.2, 0), const Offset(1.8, 0));
    for (final x in [0.1, 0.5, 0.7, 1.1, 1.5, 2.1, 3.2]) {
      if (x < 2) expect(covers(left, x), covers(whole, x), reason: '$x');
      if (x > 2) expect(covers(right, x), covers(whole, x), reason: '$x');
      if (x > 0.2 && x < 1.8) {
        expect(covers(mid, x), covers(whole, x), reason: '$x');
      }
    }
    expect(covers(mid, 0.4), isTrue);
    expect(covers(whole, 0.8), isFalse);
    expect(covers(mid, 0.8), isFalse);

    final backward = globalDashSegments(const Offset(4, 0), Offset.zero);
    for (final x in [0.3, 0.9, 1.4, 2.5, 3.7]) {
      expect(covers(backward, x), covers(whole, x), reason: '$x');
    }

    final vertical = globalDashSegments(const Offset(3, 0), const Offset(3, 2));
    final across = globalDashSegments(Offset.zero, const Offset(3, 0));
    expect(vertical.first.$1.dy, closeTo(0, 1e-6));
    expect(across.last.$2.dx, closeTo(2 + foldDashFraction, 1e-6));
  });

  test('victory waits until every closed blueprint piece is free', () {
    const left = [Offset(0, 0), Offset(2, 0), Offset(2, 2), Offset(0, 2)];
    const right = [Offset(2, 0), Offset(4, 0), Offset(4, 2), Offset(2, 2)];
    final step = GridStep(
      id: 'level',
      label: 'Level',
      polygons: const [
        left,
        right,
        [Offset(0, 3), Offset(1, 3)],
      ],
      ringClosed: const [true, true, false],
    );
    PapercutPiece box(String id, List<Offset> ring) {
      return PapercutPiece(
        id: id,
        color: const Color(0xFFFFF3B0),
        vertices: ring,
      );
    }

    expect(liberatedPieceIndexes(step, sheet()), isEmpty);
    expect(piecesLiberated(step, {}), isFalse);

    final half = PapercutSheet(
      pieces: [
        box('left', left),
        box('rest', const [
          Offset(2, 0),
          Offset(4, 0),
          Offset(4, 4),
          Offset(2, 4),
        ]),
      ],
    );
    expect(liberatedPieceIndexes(step, half), {0});
    expect(piecesLiberated(step, {0}), isFalse);

    final both = PapercutSheet(
      pieces: [box('left', left), box('right', right)],
    );
    expect(liberatedPieceIndexes(step, both), {0, 1});
    expect(piecesLiberated(step, {0, 1}), isTrue);
  });

  test('an opened fold rejoins the paper so the crease folds again', () {
    FolderGuide crease(PapercutSheet on) {
      final guide = folderGuide(const Offset(1.6, 0.3), on, 1);
      expect(guide, isNotNull);
      expect(guide!.drawn.$1.dx, closeTo(2, 1e-6));
      return guide;
    }

    PapercutSheet fold(PapercutSheet on) {
      final guide = crease(on);
      return foldSheet(
        sheet: on,
        spanA: guide.line.$1,
        spanB: guide.line.$2,
        flapPoint: guide.flap!,
        facing: FoldFacing.toward,
      )!;
    }

    final folded = fold(sheet());
    expect(folded.pieces, hasLength(2));
    final opened = unfoldAt(folded, const Offset(2, 2))!;
    expect(opened.pieces, hasLength(1));
    expect(
      polygonSignedArea(opened.pieces.single.vertices).abs(),
      closeTo(16, 1e-6),
    );
    expect(opened.pieces.single.vertices, hasLength(4));

    final refolded = fold(opened);
    expect(refolded.folds.last.facing, FoldFacing.toward);
    final shown = displayPoint(const Offset(3.5, 2), refolded.folds);
    expect(shown.dx, lessThan(2));
    final reopened = unfoldAt(refolded, const Offset(2, 2))!;
    expect(reopened.pieces, hasLength(1));
    expect(reopened.scores, hasLength(1));
  });

  test('an opened fold leaves a real cut on its crease apart', () {
    const color = Color(0xFFFFF3B0);
    final cutOnCrease = PapercutSheet(
      pieces: const [
        PapercutPiece(
          id: 'left',
          color: color,
          vertices: [Offset(0, 0), Offset(2, 0), Offset(2, 4), Offset(0, 4)],
        ),
        PapercutPiece(
          id: 'right',
          color: color,
          vertices: [Offset(2, 0), Offset(4, 0), Offset(4, 4), Offset(2, 4)],
        ),
      ],
      cutStrokes: const [
        [Offset(2, -1), Offset(2, 5)],
      ],
      folds: [
        FoldJoint(
          a: const Offset(2, 0),
          b: const Offset(2, 4),
          side: sideOfLine(
            const Offset(3, 2),
            const Offset(2, 0),
            const Offset(2, 4),
          ),
          facing: FoldFacing.toward,
        ),
      ],
    );
    final opened = unfoldAt(cutOnCrease, const Offset(2, 2))!;
    expect(opened.pieces, hasLength(2));
  });

  test('a separated piece folds and unfolds under the drawn reticle', () {
    const shift = Offset(10, 0);
    final moved = PapercutSheet(
      pieces: [
        PapercutPiece(
          id: 'paper',
          color: const Color(0xFFFFF3B0),
          vertices: const [
            Offset(0, 0),
            Offset(8, 0),
            Offset(8, 4),
            Offset(0, 4),
          ],
          separation: shift,
        ),
      ],
    );
    final first = folderGuide(const Offset(14.6, 0.3), moved, 1);
    expect(first, isNotNull);
    expect(first!.drawn.$1.dx, closeTo(15, 1e-6));
    expect(first.drawn.$2.dx, closeTo(15, 1e-6));
    final folded = foldSheet(
      sheet: moved,
      spanA: first.line.$1,
      spanB: first.line.$2,
      flapPoint: first.flap!,
      facing: FoldFacing.toward,
    )!;

    final next = folderGuide(const Offset(11.3, 2), folded, 1);
    expect(next, isNotNull);
    expect(next!.drawn.$1.dy, closeTo(2, 1e-6));
    expect(next.drawn.$1.dx, closeTo(10, 1e-6));
    expect(next.drawn.$2.dx, closeTo(15, 1e-6));

    final cue = unfoldCue(folded, const Offset(15.1, 1));
    expect(cue, isNotNull);
    expect(cue!.$1.dx, closeTo(15, 1e-6));
    expect(unfoldAt(folded, const Offset(15.1, 1)), isNotNull);
  });
}

/// Semicircle on the left of the crease x = 2, centered at (2, 2).
List<Offset> _semicircleLeft() {
  const center = Offset(2, 2);
  const radius = 1.5;
  const steps = 16;
  return [
    for (var i = 0; i <= steps; i++)
      Offset(
        center.dx - radius * math.cos((i / steps - 0.5) * math.pi),
        center.dy + radius * math.sin((i / steps - 0.5) * math.pi),
      ),
  ];
}

PapercutPiece? _pieceAt(PapercutSheet sheet, Offset point) {
  for (final piece in sheet.pieces) {
    if (piece.vertices.length < 3 || !isInsidePolygon(point, piece.vertices)) {
      continue;
    }
    var inHole = false;
    for (final hole in piece.holes) {
      if (hole.length >= 3 && isInsidePolygon(point, hole)) inHole = true;
    }
    if (!inHole) return piece;
  }
  return null;
}

bool _drawnContains(PapercutPiece piece, Offset point, List<FoldJoint> folds) {
  final ring = shownRing(piece.vertices, piece.separation, folds);
  if (ring.length < 3 || !isInsidePolygon(point, ring)) return false;
  for (final hole in piece.holes) {
    final drawn = shownRing(hole, piece.separation, folds);
    if (drawn.length >= 3 && isInsidePolygon(point, drawn)) return false;
  }
  return true;
}
