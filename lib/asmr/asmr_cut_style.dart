import 'package:flutter/painting.dart';

import 'asmr_piece.dart';

/// Cut boundaries belong to the paper, with a colored core and a pale halo.
void paintAsmrCutEdges(Canvas canvas, AsmrPiece piece, double px) {
  if (piece.cutEdges.isEmpty || piece.edgeTone == null) return;
  final path = piece.cutEdgePath;
  final color = piece.paper.cutEdgeColor(piece.edgeTone!);
  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4 * px
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Color.lerp(
        color,
        const Color(0xFFFFFFFF),
        0.6,
      )!.withValues(alpha: 0.38)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * px),
  );
  // The two touching pieces each own the inside half of their boundary ink.
  canvas.save();
  canvas.clipPath(piece.localPath);
  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * px
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color,
  );
  canvas.restore();
}
