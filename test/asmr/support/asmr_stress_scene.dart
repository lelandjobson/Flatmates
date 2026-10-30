import 'dart:ui';

import 'package:flatmates/asmr/asmr_piece.dart';
import 'package:flatmates/asmr/asmr_paper.dart';

/// Real grid splits plus valid, short unfinished Exacto strokes. Kept
/// deterministic so crash regressions and benchmarks use identical geometry.
List<AsmrPiece> asmrStressScene({
  required int side,
  required int scoresPerPiece,
}) {
  var pieces = [
    AsmrPiece.sheet(
      id: 'stress',
      paper: kAsmrCraftPaper,
      at: Offset.zero,
    ).affixedTo(0),
  ];
  for (var i = 1; i < side; i++) {
    final x = -80 + 160 * i / side;
    pieces = cutPieces(pieces, [
      Offset(x, -120),
      Offset(x, 120),
    ], exact: true)!.pieces;
  }
  for (var i = 1; i < side; i++) {
    final y = -110 + 220 * i / side;
    pieces = cutPieces(pieces, [
      Offset(-90, y),
      Offset(90, y),
    ], exact: true)!.pieces;
  }
  return [
    for (final p in pieces)
      () {
        final box = p.localPath.getBounds();
        return p.copyWith(
          scores: [
            for (var line = 0; line < scoresPerPiece; line++)
              [
                for (var sample = 0; sample < 12; sample++)
                  Offset(
                    box.left + box.width * (0.2 + 0.6 * sample / 11),
                    box.top +
                        box.height *
                            (0.2 + 0.6 * (line + 1) / (scoresPerPiece + 1)),
                  ),
              ],
          ],
        );
      }(),
  ];
}
