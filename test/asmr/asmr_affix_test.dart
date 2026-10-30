import 'dart:math' as math;

import 'package:flatmates/asmr/asmr_paper.dart';
import 'package:flatmates/asmr/asmr_piece.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'the print travels with a rotated sheet while judging uses placement coordinates',
    () {
      final original = AsmrPiece.sheet(
        id: 'a',
        paper: kAsmrCraftPaper,
        at: const Offset(10, 20),
      ).copyWith(angle: 0.3).affixedTo(1);
      final stamp = original.blueprints.single;
      const target = Offset(5, 8);
      final local = stamp.toPaper(target);
      expect(original.toDesk(local), offsetMoreOrLessEquals(target));
      final moved = original.copyWith(
        position: const Offset(100, 200),
        angle: math.pi / 2,
      );
      expect(moved.toDesk(local), isNot(offsetMoreOrLessEquals(target)));
      expect(
        moved.inBlueprintSpace(1).toDesk(local),
        offsetMoreOrLessEquals(target),
      );
      final cut = cutPieces(
        [moved],
        [
          moved.toDesk(const Offset(-100, 0)),
          moved.toDesk(const Offset(100, 0)),
        ],
        exact: true,
      )!;
      expect(cut.pieces, hasLength(2));
      for (final part in cut.pieces) {
        expect(part.blueprints.single, same(stamp));
        expect(
          part.inBlueprintSpace(1).position,
          offsetMoreOrLessEquals(original.position),
        );
      }
    },
  );

  test('the palette uses distinct grounds with brighter companion inks', () {
    expect(kAsmrCraftPalette, hasLength(5));
    expect(kAsmrCraftPalette.map((p) => p.color).toSet(), hasLength(5));
    for (final paper in kAsmrCraftPalette) {
      expect(
        paper.markingColor.computeLuminance(),
        greaterThan(paper.color.computeLuminance()),
      );
      expect(asmrPaperById(paper.id), same(paper));
      expect(asmrPaletteForColor(paper.color), same(paper));
    }
  });
}
