import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../gridcraft/blueprint.dart';
import '../../gridcraft/folded_model.dart' show Decal;
import '../../gridcraft/model_painter.dart' show kBlueprintInk, paintDecal;
import '../../gridcraft/pattern_paper_painter.dart' show paintPatternPaper;
import '../../gridcraft/scissor.dart' show markOwner;
import '../../papercut/paper.dart';

/// Right-hand bar of stowed paper pieces, labelled along its inner edge. Tap
/// a piece to pick it, or drag it sideways out of the bar; the drag carries
/// the piece id. Fills the height it is given.
class PieceInventory extends StatelessWidget {
  const PieceInventory({
    super.key,
    required this.pieces,
    required this.step,
    required this.onPick,
    this.selectedId,
    this.previewing,
    this.accepting = false,
    this.decals = const [],
    this.pattern,
  });

  final List<PapercutPiece> pieces;

  /// Blueprint ink drawn on each thumbnail, clipped to the paper.
  final GridStep step;

  /// Drawn on the thumbnail of the piece that holds each one.
  final List<Decal> decals;
  final ValueChanged<String> onPick;
  final String? selectedId;

  /// True while the dragged piece is drawn on the model instead, so the
  /// thumbnail under the finger hides.
  final ValueListenable<bool>? previewing;

  /// Paper is held over the bar and would be stowed on release.
  final bool accepting;

  /// Pieces are pattern paper: drawn with this pattern and no blueprint ink.
  final CutPattern? pattern;

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFFF9F43);
    return AnimatedContainer(
      key: const Key('grid-inventory'),
      duration: const Duration(milliseconds: 140),
      width: 116,
      height: double.infinity,
      decoration: BoxDecoration(
        color: accepting ? const Color(0xF0262019) : const Color(0xF01A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accepting ? accent : Colors.white10,
          width: accepting ? 2 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 18,
            offset: Offset(-4, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Center(
              child: RotatedBox(
                quarterTurns: 3,
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 140),
                  style: TextStyle(
                    color: accepting ? accent : Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                  ),
                  child: const Text(
                    'INVENTORY',
                    key: Key('grid-inventory-label'),
                    maxLines: 1,
                  ),
                ),
              ),
            ),
          ),
          Container(width: 1, color: Colors.white10),
          Expanded(
            child: pieces.isEmpty
                ? const SizedBox.expand()
                : ListView.separated(
                    key: const Key('grid-piece-inventory'),
                    padding: const EdgeInsets.all(8),
                    itemCount: pieces.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final piece = pieces[index];
                      final selected = piece.id == selectedId;
                      final thumbnail = CustomPaint(
                        painter: _ThumbnailPainter(
                          piece: piece,
                          step: step,
                          pattern: pattern,
                          decals: [
                            for (final decal in decals)
                              if (markOwner(decal.center, [piece]) != null)
                                decal,
                          ],
                        ),
                      );
                      return Draggable<String>(
                        data: piece.id,
                        affinity: Axis.horizontal,
                        dragAnchorStrategy: pointerDragAnchorStrategy,
                        feedback: _DragFeedback(
                          previewing: previewing,
                          child: thumbnail,
                        ),
                        childWhenDragging: const SizedBox(height: 76),
                        child: GestureDetector(
                          key: Key('grid-inventory-${piece.id}'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onPick(piece.id),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            height: 76,
                            decoration: BoxDecoration(
                              color: const Color(0xFF262626),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: selected
                                    ? const Color(0xFFFFD54F)
                                    : Colors.white12,
                                width: selected ? 2 : 1,
                              ),
                            ),
                            child: thumbnail,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// The thumbnail centered under the finger while dragging.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.previewing, required this.child});

  final ValueListenable<bool>? previewing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shown = Transform.translate(
      offset: const Offset(-38, -38),
      child: SizedBox(width: 76, height: 76, child: child),
    );
    final listenable = previewing;
    if (listenable == null) return Opacity(opacity: 0.85, child: shown);
    return ValueListenableBuilder<bool>(
      valueListenable: listenable,
      builder: (context, hidden, _) => AnimatedOpacity(
        opacity: hidden ? 0 : 0.85,
        duration: const Duration(milliseconds: 120),
        child: shown,
      ),
    );
  }
}

class _ThumbnailPainter extends CustomPainter {
  _ThumbnailPainter({
    required this.piece,
    required this.step,
    required this.decals,
    this.pattern,
  });

  final PapercutPiece piece;
  final GridStep step;
  final List<Decal> decals;
  final CutPattern? pattern;

  @override
  void paint(Canvas canvas, Size size) {
    if (piece.vertices.length < 3) return;
    final box = pointBounds(piece.vertices);
    if (box.width <= 0 || box.height <= 0) return;
    const pad = 8.0;
    final scale = math.min(
      (size.width - pad * 2) / box.width,
      (size.height - pad * 2) / box.height,
    );
    final middle = size.center(Offset.zero);
    Offset place(Offset point) => Offset(
      middle.dx + (point.dx - box.center.dx) * scale,
      middle.dy - (point.dy - box.center.dy) * scale,
    );
    Path ring(List<Offset> points) {
      final path = Path()
        ..moveTo(place(points.first).dx, place(points.first).dy);
      for (final point in points.skip(1)) {
        path.lineTo(place(point).dx, place(point).dy);
      }
      return path..close();
    }

    final paper = ring(piece.vertices);
    for (final hole in piece.holes) {
      if (hole.length >= 3) paper.addPath(ring(hole), Offset.zero);
    }
    paper.fillType = PathFillType.evenOdd;
    final pattern = this.pattern;
    if (pattern != null) {
      paintPatternPaper(
        canvas,
        paper: paper,
        color: piece.color,
        lines: [
          for (final (a, b) in pattern.patternLines(box)) (place(a), place(b)),
        ],
        lineWidth: 0.8,
      );
      return;
    }
    canvas.drawPath(paper, Paint()..color = piece.color);
    canvas.save();
    canvas.clipPath(paper);
    final ink = Paint()
      ..color = kBlueprintInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final pencil = Paint()
      ..color = kBlueprintInk.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (var i = 0; i < step.polygons.length; i++) {
      final points = step.polygons[i];
      final styles = step.edgeStyleOf(i);
      for (var e = 0; e < step.edgeCountOf(i); e++) {
        canvas.drawLine(
          place(points[e]),
          place(points[(e + 1) % points.length]),
          styles[e] == EdgeStyle.penciled ? pencil : ink,
        );
      }
    }
    for (final decal in decals) {
      paintDecal(canvas, decal, place);
    }
    canvas.restore();
    canvas.drawPath(
      paper,
      Paint()
        ..color = const Color(0xFF1A1A2E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant _ThumbnailPainter oldDelegate) =>
      !identical(oldDelegate.piece, piece) ||
      !identical(oldDelegate.step, step) ||
      !identical(oldDelegate.pattern, pattern) ||
      !listEquals(oldDelegate.decals, decals);
}
