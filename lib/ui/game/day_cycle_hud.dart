import 'package:flutter/material.dart';

/// Top-center day counter plus the sun/moon phase button.
class DayCycleHud extends StatelessWidget {
  const DayCycleHud({
    super.key,
    required this.dayNumber,
    required this.isNight,
    required this.onEndPhase,
    this.busy = false,
  });

  final int dayNumber;
  final bool isNight;
  final VoidCallback onEndPhase;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white24),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Day $dayNumber',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: isNight ? 'End night' : 'End day',
                child: InkWell(
                  onTap: busy ? null : onEndPhase,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      isNight ? Icons.dark_mode : Icons.wb_sunny,
                      size: 18,
                      color: busy
                          ? Colors.white38
                          : isNight
                              ? const Color(0xFFC8D0F8)
                              : const Color(0xFFFFE08A),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
