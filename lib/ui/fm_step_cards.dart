import 'package:flutter/material.dart';

import '../crafting/blueprint_set.dart';

/// Step-progress cards: active centered in a 1/4-width zone, completed on the
/// left, upcoming on the right. Side cards sit on a fixed 5-slot quadratic rail;
/// overflow stacks fully behind the outermost slot in a straight row.
///
/// Pass [promotingIndex] when a side card is growing into center so that card
/// animates 25% faster; dismissed/side reshuffles use the base duration.
class FmStepCards extends StatelessWidget {
  const FmStepCards({
    super.key,
    required this.steps,
    required this.currentIndex,
    this.promotingIndex,
  });

  final List<BlueprintStep> steps;
  final int currentIndex;

  /// Index of the card currently growing into center (faster animation).
  final int? promotingIndex;

  static const double goldenRatio = 1.6180339887;
  static const int maxVisibleSide = 5;
  static const Duration baseDuration = Duration(milliseconds: 400);
  static const Duration promoteDuration = Duration(milliseconds: 320);

  static double sideProgress(int slot) {
    if (maxVisibleSide <= 1) return 0;
    final t = slot / (maxVisibleSide - 1);
    return 1 - (1 - t) * (1 - t);
  }

  static double sideCardLeft({
    required int slot,
    required double zoneStart,
    required double zoneEnd,
    required double cardWidth,
    required bool outerIsLeft,
  }) {
    final zoneCenter = (zoneStart + zoneEnd) / 2;
    final nearestLeft = zoneCenter - cardWidth / 2;
    final outerLeft = outerIsLeft ? zoneStart : zoneEnd - cardWidth;
    final p = sideProgress(slot);
    return nearestLeft + (outerLeft - nearestLeft) * p;
  }

  Duration _durationFor(int index) =>
      index == promotingIndex ? promoteDuration : baseDuration;

  @override
  Widget build(BuildContext context) {
    if (steps.length <= 1) return const SizedBox.shrink();

    final viewportHeight = MediaQuery.sizeOf(context).height;
    final baseCardHeight = viewportHeight / 10;
    final activeCardHeight = baseCardHeight * 1.15;
    final baseCardWidth = baseCardHeight / goldenRatio;
    final activeCardWidth = activeCardHeight / goldenRatio;
    final sideTop = (activeCardHeight - baseCardHeight) / 2 + 4;

    return SizedBox(
      height: activeCardHeight + 8,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final centerZoneW = w / 4;
          final sideZoneW = (w - centerZoneW) / 2;
          final leftZoneStart = 0.0;
          final leftZoneEnd = sideZoneW;
          final rightZoneStart = sideZoneW + centerZoneW;
          final rightZoneEnd = w;
          final centerX = w / 2;

          final layouts = <_FmStepCardLayout>[];

          void addSideCards({
            required int totalOnSide,
            required int Function(int slot) stepIndexForSlot,
            required Iterable<int> extraIndices,
            required double zoneStart,
            required double zoneEnd,
            required bool outerIsLeft,
          }) {
            final visible = totalOnSide.clamp(0, maxVisibleSide);
            if (visible == 0) return;

            for (int slot = 0; slot < visible; slot++) {
              final left = sideCardLeft(
                slot: slot,
                zoneStart: zoneStart,
                zoneEnd: zoneEnd,
                cardWidth: baseCardWidth,
                outerIsLeft: outerIsLeft,
              );

              if (slot == visible - 1 && totalOnSide > maxVisibleSide) {
                var depth = extraIndices.length;
                for (final extraIndex in extraIndices) {
                  layouts.add(
                    _FmStepCardLayout(
                      index: extraIndex,
                      left: left,
                      top: sideTop,
                      width: baseCardWidth,
                      height: baseCardHeight,
                      z: -100 - depth,
                      isActive: false,
                    ),
                  );
                  depth--;
                }
              }

              layouts.add(
                _FmStepCardLayout(
                  index: stepIndexForSlot(slot),
                  left: left,
                  top: sideTop,
                  width: baseCardWidth,
                  height: baseCardHeight,
                  z: 50 - slot,
                  isActive: false,
                ),
              );
            }
          }

          final completedCount = currentIndex;
          addSideCards(
            totalOnSide: completedCount,
            stepIndexForSlot: (s) => completedCount - 1 - s,
            extraIndices: [
              for (int i = 0; i < completedCount - maxVisibleSide; i++) i,
            ],
            zoneStart: leftZoneStart,
            zoneEnd: leftZoneEnd,
            outerIsLeft: true,
          );

          final futureCount = steps.length - currentIndex - 1;
          addSideCards(
            totalOnSide: futureCount,
            stepIndexForSlot: (s) => currentIndex + 1 + s,
            extraIndices: [
              for (
                int i = steps.length - 1;
                i >= currentIndex + 1 + maxVisibleSide;
                i--
              )
                i,
            ],
            zoneStart: rightZoneStart,
            zoneEnd: rightZoneEnd,
            outerIsLeft: false,
          );

          layouts.add(
            _FmStepCardLayout(
              index: currentIndex,
              left: centerX - activeCardWidth / 2,
              top: 4,
              width: activeCardWidth,
              height: activeCardHeight,
              z: 1000,
              isActive: true,
            ),
          );

          layouts.sort((a, b) => a.z.compareTo(b.z));

          return Stack(
            clipBehavior: Clip.none,
            children: [
              for (final layout in layouts)
                AnimatedPositioned(
                  key: ValueKey<int>(layout.index),
                  duration: _durationFor(layout.index),
                  curve: Curves.easeOutCubic,
                  left: layout.left,
                  top: layout.top,
                  width: layout.width,
                  height: layout.height,
                  child: _FmStepCardFace(
                    step: steps[layout.index],
                    isCurrent: layout.isActive,
                    isCompleted: layout.index < currentIndex,
                    duration: _durationFor(layout.index),
                    opacity: layout.isActive ? 0.75 : 0.5,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _FmStepCardLayout {
  const _FmStepCardLayout({
    required this.index,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.z,
    required this.isActive,
  });

  final int index;
  final double left;
  final double top;
  final double width;
  final double height;
  final int z;
  final bool isActive;
}

class _FmStepCardFace extends StatelessWidget {
  const _FmStepCardFace({
    required this.step,
    required this.isCurrent,
    required this.isCompleted,
    required this.duration,
    required this.opacity,
  });

  final BlueprintStep step;
  final bool isCurrent;
  final bool isCompleted;
  final Duration duration;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: duration,
      opacity: opacity,
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isCurrent
                ? const Color(0xFFAA66FF)
                : isCompleted
                ? const Color(0xFF66FF66)
                : const Color(0xFF7733CC).withValues(alpha: 0.4),
            width: isCurrent ? 2.0 : 1.5,
          ),
          color: isCompleted
              ? const Color(0xFF66FF66).withValues(alpha: 0.1)
              : isCurrent
              ? const Color(0xFFAA66FF).withValues(alpha: 0.05)
              : const Color(0xFF1A1A2E).withValues(alpha: 0.8),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final iconSize = constraints.maxHeight * 0.4;
            return Center(
              child: isCompleted
                  ? Icon(
                      Icons.check,
                      color: const Color(0xFF66FF66),
                      size: iconSize,
                    )
                  : Icon(
                      _iconForCodePoint(step.iconCodePoint),
                      color: isCurrent
                          ? const Color(0xFFAA66FF)
                          : Colors.white38,
                      size: iconSize,
                    ),
            );
          },
        ),
      ),
    );
  }
}

/// Maps JSON/debug code points to compile-time [Icons] constants so release
/// builds can tree-shake the Material Icons font.
IconData _iconForCodePoint(int codePoint) {
  switch (codePoint) {
    case 0xe3c9:
      return Icons.edit;
    case 0xe87e:
      return Icons.build;
    case 0xe8b8:
      return Icons.settings;
    case 0xe55b:
      return Icons.place;
    case 0xe145:
      return Icons.add;
    default:
      return Icons.build;
  }
}
