import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/fm_dev_back_button.dart';
import '../ui/fm_screen.dart';
import '../crafting/blueprint_set.dart';

class CardsDebugView extends StatefulWidget {
  const CardsDebugView({super.key});

  @override
  State<CardsDebugView> createState() => _CardsDebugViewState();
}

class _CardsDebugViewState extends State<CardsDebugView> {
  int _stepCount = 3;
  int _currentStepIndex = 0;

  /// Card growing into the center (animates 25% faster).
  int? _promotingIndex;

  final _focusNode = FocusNode();

  static const Duration _baseDuration = Duration(milliseconds: 400);
  // 25% faster than base.
  static const Duration _promoteDuration = Duration(milliseconds: 320);

  List<BlueprintStep> get _steps => List.generate(
    _stepCount,
    (i) => BlueprintStep(
      craft: 'Step${i + 1}',
      island: 0,
      label: 'Step ${i + 1}',
      iconCodePoint: [0xe3c9, 0xe87e, 0xe8b8, 0xe55b, 0xe145][i % 5],
    ),
  );

  void _goLeft() {
    if (_currentStepIndex <= 0) return;
    setState(() {
      _promotingIndex = _currentStepIndex - 1;
      _currentStepIndex--;
    });
    _clearPromoteAfterAnimation();
  }

  void _goRight() {
    if (_currentStepIndex >= _stepCount - 1) return;
    setState(() {
      _promotingIndex = _currentStepIndex + 1;
      _currentStepIndex++;
    });
    _clearPromoteAfterAnimation();
  }

  void _clearPromoteAfterAnimation() {
    final promoted = _promotingIndex;
    Future.delayed(_promoteDuration, () {
      if (!mounted) return;
      if (_promotingIndex == promoted) {
        setState(() => _promotingIndex = null);
      }
    });
  }

  void _addCard() {
    setState(() => _stepCount++);
  }

  void _removeCard() {
    if (_stepCount <= 1) return;
    setState(() {
      _stepCount--;
      if (_currentStepIndex >= _stepCount) {
        _currentStepIndex = _stepCount - 1;
      }
    });
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _goLeft();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _goRight();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: FmScreen(
        backgroundColor: const Color(0xFF111111),
        overlays: const [FmDevBackButton()],
        content: Column(
          children: [
            const SizedBox(height: 24),
            _buildStepCards(),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                runSpacing: 8,
                children: [
                  IconButton(
                    onPressed: _removeCard,
                    icon: const Icon(Icons.remove_circle_outline),
                    color: _stepCount > 1 ? Colors.white : Colors.white24,
                    iconSize: 28,
                    visualDensity: VisualDensity.compact,
                  ),
                  Text(
                    '$_stepCount cards',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  IconButton(
                    onPressed: _addCard,
                    icon: const Icon(Icons.add_circle_outline),
                    color: Colors.white,
                    iconSize: 28,
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    onPressed: _currentStepIndex > 0 ? _goLeft : null,
                    icon: const Icon(Icons.arrow_back),
                    color: Colors.white,
                    disabledColor: Colors.white24,
                    iconSize: 28,
                    visualDensity: VisualDensity.compact,
                  ),
                  Text(
                    '${_currentStepIndex + 1} / $_stepCount',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  IconButton(
                    onPressed: _currentStepIndex < _stepCount - 1
                        ? _goRight
                        : null,
                    icon: const Icon(Icons.arrow_forward),
                    color: Colors.white,
                    disabledColor: Colors.white24,
                    iconSize: 28,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Three zones: left (done) | center 1/4 (active) | right (upcoming).
  // Side cards sit on a fixed 5-slot rail (quadratic). Slot 5 is the hard max
  // sideways position — further cards stack fully behind it in a straight row.
  // -------------------------------------------------------------------------

  static const double _goldenRatio = 1.6180339887;
  static const int _maxVisibleSide = 5;

  static double _sideProgress(int slot) {
    // Always measure against the 5-slot rail so positions stay fixed as cards
    // advance; slot 4 (0-based) is the outer limit.
    if (_maxVisibleSide <= 1) return 0;
    final t = slot / (_maxVisibleSide - 1);
    return 1 - (1 - t) * (1 - t);
  }

  static double _sideCardLeft({
    required int slot,
    required double zoneStart,
    required double zoneEnd,
    required double cardWidth,
    required bool outerIsLeft,
  }) {
    final zoneCenter = (zoneStart + zoneEnd) / 2;
    final nearestLeft = zoneCenter - cardWidth / 2;
    final outerLeft = outerIsLeft ? zoneStart : zoneEnd - cardWidth;
    final p = _sideProgress(slot);
    return nearestLeft + (outerLeft - nearestLeft) * p;
  }

  Duration _durationFor(int index) =>
      index == _promotingIndex ? _promoteDuration : _baseDuration;

  Widget _buildStepCards() {
    final viewportHeight = MediaQuery.of(context).size.height;
    final baseCardHeight = viewportHeight / 10;
    final activeCardHeight = baseCardHeight * 1.15;
    final baseCardWidth = baseCardHeight / _goldenRatio;
    final activeCardWidth = activeCardHeight / _goldenRatio;
    final sideTop = (activeCardHeight - baseCardHeight) / 2 + 4;
    final steps = _steps;

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

          final layouts = <_CardLayout>[];

          void addSideCards({
            required int totalOnSide,
            required int Function(int slot) stepIndexForSlot,
            required Iterable<int> extraIndices,
            required double zoneStart,
            required double zoneEnd,
            required bool outerIsLeft,
          }) {
            final visible = totalOnSide.clamp(0, _maxVisibleSide);
            if (visible == 0) return;

            for (int slot = 0; slot < visible; slot++) {
              final left = _sideCardLeft(
                slot: slot,
                zoneStart: zoneStart,
                zoneEnd: zoneEnd,
                cardWidth: baseCardWidth,
                outerIsLeft: outerIsLeft,
              );

              // Overflow past the 5th rail slot stacks fully behind it —
              // same x/y, straight row, no further sideways travel.
              if (slot == visible - 1 && totalOnSide > _maxVisibleSide) {
                var depth = extraIndices.length;
                for (final extraIndex in extraIndices) {
                  layouts.add(
                    _CardLayout(
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
                _CardLayout(
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

          final completedCount = _currentStepIndex;
          addSideCards(
            totalOnSide: completedCount,
            stepIndexForSlot: (s) => completedCount - 1 - s,
            extraIndices: [
              for (int i = 0; i < completedCount - _maxVisibleSide; i++) i,
            ],
            zoneStart: leftZoneStart,
            zoneEnd: leftZoneEnd,
            outerIsLeft: true,
          );

          final futureCount = steps.length - _currentStepIndex - 1;
          addSideCards(
            totalOnSide: futureCount,
            stepIndexForSlot: (s) => _currentStepIndex + 1 + s,
            extraIndices: [
              for (
                int i = steps.length - 1;
                i >= _currentStepIndex + 1 + _maxVisibleSide;
                i--
              )
                i,
            ],
            zoneStart: rightZoneStart,
            zoneEnd: rightZoneEnd,
            outerIsLeft: false,
          );

          layouts.add(
            _CardLayout(
              index: _currentStepIndex,
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
                  child: _buildStepCardFace(
                    index: layout.index,
                    steps: steps,
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

  Widget _buildStepCardFace({
    required int index,
    required List<BlueprintStep> steps,
    required Duration duration,
    required double opacity,
  }) {
    final step = steps[index];
    final isCurrent = index == _currentStepIndex;
    final isCompleted = index < _currentStepIndex;

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
                      IconData(step.iconCodePoint, fontFamily: 'MaterialIcons'),
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

class _CardLayout {
  const _CardLayout({
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
