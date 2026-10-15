import 'dart:ui';

import 'package:flatmates/gridcraft/cube_blueprint.dart';
import 'package:flatmates/papercut/paper.dart';
import 'package:flatmates/papercut/split.dart';
import 'package:flutter_test/flutter_test.dart';

PapercutSheet _sheet(Rect paper) => PapercutSheet(
  pieces: [
    PapercutPiece(
      id: 'paper',
      color: const Color(0xFFFFF3B0),
      vertices: [
        paper.topLeft,
        paper.topRight,
        paper.bottomRight,
        paper.bottomLeft,
      ],
    ),
  ],
);

void main() {
  test('a piece that wraps a notch of its neighbor is not its hole', () {
    final paper = cubeBlueprint().steps.single.paper;
    final cut = applyPapercutCut(_sheet(paper), [
      Offset(10, paper.bottom),
      const Offset(10, 10),
      const Offset(20, 10),
      const Offset(20, 5),
      const Offset(10, 5),
      Offset(10, paper.top),
    ])!;
    expect(cut.pieces, hasLength(2));
    for (final piece in cut.pieces) {
      expect(piece.holes, isEmpty, reason: piece.id);
    }
  });

  test('a closed loop inside the paper still becomes a hole', () {
    final cut = applyPapercutCut(
      _sheet(const Rect.fromLTRB(0, 0, 10, 10)),
      const [
        Offset(3, 3),
        Offset(6, 3),
        Offset(6, 6),
        Offset(3, 6),
        Offset(3, 3),
      ],
    )!;
    expect(cut.pieces, hasLength(2));
    final holes = [for (final piece in cut.pieces) piece.holes.length];
    expect(holes..sort(), [0, 1]);
  });
}
