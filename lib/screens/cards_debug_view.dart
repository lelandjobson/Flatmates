import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/fm_dev_back_button.dart';
import '../crafting/blueprint_set.dart';

class CardsDebugView extends StatefulWidget {
  const CardsDebugView({super.key});

  @override
  State<CardsDebugView> createState() => _CardsDebugViewState();
}

class _CardsDebugViewState extends State<CardsDebugView> {
  int _stepCount = 3;
  int _currentStepIndex = 0;
  bool _stepTransitioning = false;

  final _focusNode = FocusNode();

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
    if (_currentStepIndex > 0) {
      setState(() {
        _stepTransitioning = true;
      });
      Future.delayed(const Duration(milliseconds: 50), () {
        if (!mounted) return;
        setState(() {
          _currentStepIndex--;
          _stepTransitioning = false;
        });
      });
    }
  }

  void _goRight() {
    if (_currentStepIndex < _stepCount - 1) {
      setState(() {
        _stepTransitioning = true;
      });
      Future.delayed(const Duration(milliseconds: 50), () {
        if (!mounted) return;
        setState(() {
          _currentStepIndex++;
          _stepTransitioning = false;
        });
      });
    }
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
      child: Scaffold(
        backgroundColor: const Color(0xFF111111),
        body: Stack(
          children: [
            Column(
              children: [
                const SizedBox(height: 24),
                // Step cards centered at top
                Center(child: _buildStepCards()),
                const Spacer(),
                // Controls at bottom
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: _removeCard,
                        icon: const Icon(Icons.remove_circle_outline),
                        color: _stepCount > 1 ? Colors.white : Colors.white24,
                        iconSize: 32,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '$_stepCount cards',
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        onPressed: _addCard,
                        icon: const Icon(Icons.add_circle_outline),
                        color: Colors.white,
                        iconSize: 32,
                      ),
                      const SizedBox(width: 32),
                      IconButton(
                        onPressed: _currentStepIndex > 0 ? _goLeft : null,
                        icon: const Icon(Icons.arrow_back),
                        color: Colors.white,
                        disabledColor: Colors.white24,
                        iconSize: 32,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_currentStepIndex + 1} / $_stepCount',
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _currentStepIndex < _stepCount - 1 ? _goRight : null,
                        icon: const Icon(Icons.arrow_forward),
                        color: Colors.white,
                        disabledColor: Colors.white24,
                        iconSize: 32,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const FmDevBackButton(),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Step cards (same logic as crafting workstation)
  // -------------------------------------------------------------------------

  Widget _buildStepCards() {
    final viewportHeight = MediaQuery.of(context).size.height;
    final baseCardHeight = viewportHeight / 10;
    final activeCardHeight = baseCardHeight * 1.15;
    final baseCardWidth = baseCardHeight * 1.4;
    final activeCardWidth = activeCardHeight * 1.4;
    final overlapOffset = baseCardWidth * 0.35;

    final steps = _steps;
    final completedCount = _currentStepIndex;
    final futureCount = steps.length - _currentStepIndex - 1;

    final completedWidth = completedCount > 0
        ? completedCount * baseCardWidth + (completedCount - 1) * 6
        : 0.0;
    final futureWidth = futureCount > 0
        ? baseCardWidth + (futureCount - 1) * overlapOffset
        : 0.0;
    const gap = 12.0;
    final totalWidth = completedWidth +
        (completedCount > 0 ? gap : 0) +
        activeCardWidth +
        (futureCount > 0 ? gap : 0) +
        futureWidth;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      height: activeCardHeight + 8,
      width: totalWidth,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.centerLeft,
        children: [
          // Completed cards (left, spaced out)
          for (int i = 0; i < completedCount; i++)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              left: i * (baseCardWidth + 6),
              top: (activeCardHeight - baseCardHeight) / 2 + 4,
              child: _buildStepCardWidget(
                index: i,
                steps: steps,
                width: baseCardWidth,
                height: baseCardHeight,
              ),
            ),

          // Current (active) card
          AnimatedPositioned(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            left: completedWidth + (completedCount > 0 ? gap : 0),
            top: 4,
            child: _buildStepCardWidget(
              index: _currentStepIndex,
              steps: steps,
              width: activeCardWidth,
              height: activeCardHeight,
            ),
          ),

          // Future cards (right, stacked/overlapping)
          for (int i = 0; i < futureCount; i++)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              left: completedWidth +
                  (completedCount > 0 ? gap : 0) +
                  activeCardWidth +
                  gap +
                  i * overlapOffset,
              top: (activeCardHeight - baseCardHeight) / 2 + 4,
              child: _buildStepCardWidget(
                index: _currentStepIndex + 1 + i,
                steps: steps,
                width: baseCardWidth,
                height: baseCardHeight,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStepCardWidget({
    required int index,
    required List<BlueprintStep> steps,
    required double width,
    required double height,
  }) {
    final step = steps[index];
    final isCurrent = index == _currentStepIndex;
    final isCompleted = index < _currentStepIndex;
    final iconSize = height * 0.4;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: _stepTransitioning && isCurrent ? 0.5 : 1.0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        width: width,
        height: height,
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
        child: Center(
          child: isCompleted
              ? Icon(Icons.check, color: const Color(0xFF66FF66), size: iconSize)
              : Icon(
                  IconData(step.iconCodePoint, fontFamily: 'MaterialIcons'),
                  color: isCurrent
                      ? const Color(0xFFAA66FF)
                      : Colors.white38,
                  size: iconSize,
                ),
        ),
      ),
    );
  }
}
