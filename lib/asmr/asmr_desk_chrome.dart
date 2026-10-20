import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../gridcraft/edit.dart' show MarqueePick, marqueePick;
import 'asmr_paper.dart';
import 'asmr_piece.dart';

const Size kAsmrSwatchSize = Size(56, 72);

/// An undo or redo icon with no disc behind it.
class AsmrHistoryButton extends StatelessWidget {
  const AsmrHistoryButton({
    super.key,
    required this.buttonKey,
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.gap,
    required this.onTap,
  });

  final Key buttonKey;
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final EdgeInsets gap;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: buttonKey,
      padding: gap,
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(
              icon,
              size: 24,
              color: enabled ? Colors.white : Colors.white24,
            ),
          ),
        ),
      ),
    );
  }
}

/// The desk's papers, and the pieces stowed in it.
class AsmrPaperDrawer extends StatelessWidget {
  const AsmrPaperDrawer({
    super.key,
    required this.tiles,
    required this.onTap,
    required this.stowed,
    required this.onUnstow,
    required this.accepting,
  });

  final AsmrPaperTiles tiles;
  final ValueChanged<AsmrPaper> onTap;
  final List<AsmrPiece> stowed;
  final ValueChanged<AsmrPiece> onUnstow;
  final bool accepting;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('asmr-drawer'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: accepting ? 0.55 : 0.35),
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(18)),
        border: Border.all(
          color: Colors.white.withValues(alpha: accepting ? 0.75 : 0.12),
          width: accepting ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final paper in kAsmrPapers)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Draggable<AsmrPaper>(
                data: paper,
                feedback: _Swatch(paper: paper, tiles: tiles, lifted: true),
                childWhenDragging: Opacity(
                  opacity: 0.5,
                  child: _Swatch(paper: paper, tiles: tiles),
                ),
                child: Tooltip(
                  message: paper.name,
                  child: GestureDetector(
                    onTap: () => onTap(paper),
                    child: _Swatch(paper: paper, tiles: tiles),
                  ),
                ),
              ),
            ),
          for (final piece in stowed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Tooltip(
                message: 'Lay ${piece.paper.name} back down',
                child: GestureDetector(
                  key: ValueKey('asmr-stowed-${piece.id}'),
                  onTap: () => onUnstow(piece),
                  child: _StowedSwatch(piece: piece, tiles: tiles),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The trash under the paper drawer. A plain icon; it fills in while a
/// selection is dragged onto it.
class AsmrTrashButton extends StatelessWidget {
  const AsmrTrashButton({super.key, required this.hot});

  final bool hot;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Trash',
      child: SizedBox(
        width: 48,
        height: 48,
        child: Icon(
          Icons.delete_outline,
          size: hot ? 32 : 26,
          color: hot ? const Color(0xFFE57373) : Colors.white,
        ),
      ),
    );
  }
}

class _StowedSwatch extends StatelessWidget {
  const _StowedSwatch({required this.piece, required this.tiles});

  final AsmrPiece piece;
  final AsmrPaperTiles tiles;

  @override
  Widget build(BuildContext context) {
    return SizedBox.fromSize(
      size: kAsmrSwatchSize,
      child: CustomPaint(
        painter: _StowedPainter(piece: piece, tiles: tiles),
      ),
    );
  }
}

class _StowedPainter extends CustomPainter {
  const _StowedPainter({required this.piece, required this.tiles});

  final AsmrPiece piece;
  final AsmrPaperTiles tiles;

  @override
  void paint(Canvas canvas, Size size) {
    final ring = piece.ring;
    if (ring.length < 3) return;
    var minX = ring.first.dx;
    var maxX = minX;
    var minY = ring.first.dy;
    var maxY = minY;
    for (final point in ring) {
      minX = math.min(minX, point.dx);
      maxX = math.max(maxX, point.dx);
      minY = math.min(minY, point.dy);
      maxY = math.max(maxY, point.dy);
    }
    final width = math.max(maxX - minX, 1e-6);
    final height = math.max(maxY - minY, 1e-6);
    final scale = math.min(
      (size.width - 8) / width,
      (size.height - 8) / height,
    );
    final path = Path()..addPolygon(ring, true);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-(minX + maxX) / 2, -(minY + maxY) / 2);
    canvas.drawPath(path, tiles.paint(piece.paper));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 / scale
        ..color = Colors.white.withValues(alpha: 0.7),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _StowedPainter old) => old.piece != piece;
}

/// The select tool's box. Dragging right contains, in green; dragging left
/// also crosses, in blue. Same reading as the puzzle editor's marquee.
class AsmrMarqueePainter extends CustomPainter {
  const AsmrMarqueePainter({required this.start, required this.end});

  final Offset start;
  final Offset end;

  @override
  void paint(Canvas canvas, Size size) {
    if ((end - start).distance < 2) return;
    final box = Rect.fromPoints(start, end);
    final cross = marqueePick(start, end) == MarqueePick.cross;
    final color = cross ? const Color(0xFF42A5F5) : const Color(0xFF66BB6A);
    canvas.drawRect(
      box,
      Paint()
        ..color = color.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRect(
      box,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant AsmrMarqueePainter old) =>
      old.start != start || old.end != end;
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.paper,
    required this.tiles,
    this.lifted = false,
  });

  final AsmrPaper paper;
  final AsmrPaperTiles tiles;
  final bool lifted;

  @override
  Widget build(BuildContext context) {
    return SizedBox.fromSize(
      size: kAsmrSwatchSize,
      child: CustomPaint(
        painter: _SwatchPainter(paper: paper, tiles: tiles, lifted: lifted),
      ),
    );
  }
}

class _SwatchPainter extends CustomPainter {
  const _SwatchPainter({
    required this.paper,
    required this.tiles,
    required this.lifted,
  });

  final AsmrPaper paper;
  final AsmrPaperTiles tiles;
  final bool lifted;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(4),
    );
    canvas.drawRRect(
      rect.shift(Offset(0, lifted ? 6 : 2)),
      Paint()
        ..color = Colors.black.withValues(alpha: lifted ? 0.45 : 0.3)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, lifted ? 8 : 3),
    );
    canvas.save();
    canvas.clipRRect(rect);
    canvas.scale(1.6);
    canvas.drawRect(Offset.zero & (size / 1.6), tiles.paint(paper));
    canvas.restore();
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.white.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(covariant _SwatchPainter old) =>
      old.paper != paper || old.lifted != lifted;
}

class AsmrRoundButton extends StatelessWidget {
  const AsmrRoundButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.35),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: Colors.white70, size: 22),
          ),
        ),
      ),
    );
  }
}

class AsmrTextLink extends StatelessWidget {
  const AsmrTextLink({
    super.key,
    required this.label,
    required this.buttonKey,
    required this.onTap,
  });

  final String label;
  final Key buttonKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        key: buttonKey,
        onTap: onTap,
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
