import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../gridcraft/blueprint.dart';
import '../../gridcraft/model_painter.dart' show kBlueprintInk;
import '../../papercut/paper.dart';

/// Right-hand column of paper pieces to lay on a model face. Tap a piece to
/// pick it, or drag it sideways out of the column; the drag carries the
/// piece id.
class PieceInventory extends StatelessWidget {
  const PieceInventory({
    super.key,
    required this.pieces,
    required this.step,
    required this.onPick,
    this.selectedId,
    this.previewing,
  });

  final List<PapercutPiece> pieces;

  /// Blueprint ink drawn on each thumbnail, clipped to the paper.
  final GridStep step;
  final ValueChanged<String> onPick;
  final String? selectedId;

  /// True while the dragged piece is drawn on the model instead, so the
  /// thumbnail under the finger hides.
  final ValueListenable<bool>? previewing;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xF01A1A1A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SizedBox(
        width: 92,
        child: pieces.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'No paper',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              )
            : ListView.separated(
                key: const Key('grid-piece-inventory'),
                padding: const EdgeInsets.all(8),
                shrinkWrap: true,
                itemCount: pieces.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final piece = pieces[index];
                  final selected = piece.id == selectedId;
                  final thumbnail = CustomPaint(
                    painter: _ThumbnailPainter(piece: piece, step: step),
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
  _ThumbnailPainter({required this.piece, required this.step});

  final PapercutPiece piece;
  final GridStep step;

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
      !identical(oldDelegate.step, step);
}
