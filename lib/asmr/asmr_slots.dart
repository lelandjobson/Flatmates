import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'asmr_piece.dart';

/// How many leftover pieces the desk can put away.
const int kAsmrSlots = 3;

/// Side of one slot, in screen pixels.
const double kAsmrSlotSize = 52;

/// The scrap slots beside the desk: each holds one leftover piece, drawn
/// small. Drop a held piece on a slot to put it away; tap a full slot to lay
/// it back down. Empty slots show only while [open].
class AsmrScrapSlots extends StatelessWidget {
  const AsmrScrapSlots({
    super.key,
    required this.slots,
    required this.slotKeys,
    required this.onTap,
    this.hot,
    this.open = false,
  });

  final List<AsmrPiece?> slots;

  /// One key per slot, for finding where a dragged piece was let go.
  final List<GlobalKey> slotKeys;
  final ValueChanged<int> onTap;

  /// The slot a held piece is over.
  final int? hot;
  final bool open;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < slots.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: slots[i] == null && !open
                ? const SizedBox(width: kAsmrSlotSize, height: kAsmrSlotSize)
                : _Slot(
                    key: slotKeys[i],
                    index: i,
                    piece: slots[i],
                    hot: hot == i,
                    onTap: () => onTap(i),
                  ),
          ),
      ],
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({
    super.key,
    required this.index,
    required this.piece,
    required this.hot,
    required this.onTap,
  });

  final int index;
  final AsmrPiece? piece;
  final bool hot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final held = piece;
    return Tooltip(
      message: held == null ? 'Scrap slot' : 'Lay the scrap back down',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: held == null ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: kAsmrSlotSize,
          height: kAsmrSlotSize,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: hot ? 0.55 : 0.3),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.white.withValues(alpha: hot ? 0.8 : 0.2),
              width: hot ? 2 : 1,
            ),
          ),
          child: held == null
              ? null
              : CustomPaint(
                  key: ValueKey('asmr-slot-$index'),
                  painter: _ScrapPainter(held),
                ),
        ),
      ),
    );
  }
}

class _ScrapPainter extends CustomPainter {
  const _ScrapPainter(this.piece);

  final AsmrPiece piece;

  @override
  void paint(Canvas canvas, Size size) {
    final ring = piece.ring;
    if (ring.length < 3) return;
    var box = Rect.fromPoints(ring.first, ring.first);
    for (final p in ring) {
      box = box.expandToInclude(Rect.fromPoints(p, p));
    }
    final scale = math.min(
      (size.width - 12) / math.max(box.width, 1e-6),
      (size.height - 12) / math.max(box.height, 1e-6),
    );
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-box.center.dx, -box.center.dy);
    final path = piece.localPath;
    canvas.drawPath(path, Paint()..color = piece.paper.color);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 / scale
        ..color = Colors.white.withValues(alpha: 0.8),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ScrapPainter old) =>
      !identical(old.piece, piece);
}
