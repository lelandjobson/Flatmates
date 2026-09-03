import 'package:flutter/material.dart';

/// Paper cost of the pending place / remove, parked just above the cursor.
class PaperCostHover extends StatelessWidget {
  const PaperCostHover({
    super.key,
    required this.cursor,
    required this.delta,
    required this.canAfford,
  });

  final Offset cursor;
  final int delta;
  final bool canAfford;

  static const double _above = 22;

  @override
  Widget build(BuildContext context) {
    final spend = delta > 0;
    final color = !canAfford
        ? const Color(0xFFE53935)
        : spend
            ? const Color(0xFFF4EFE6)
            : const Color(0xFF66BB6A);
    final label = delta > 0 ? '-$delta' : '+${-delta}';
    return Positioned(
      left: cursor.dx - 28,
      top: cursor.dy - _above - 16,
      width: 56,
      child: IgnorePointer(
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: canAfford ? Colors.white24 : const Color(0xFFE53935),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
