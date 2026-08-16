import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/fm_dev_back_button.dart';
import '../ui/fm_screen.dart';
import '../ui/fm_step_cards.dart';
import '../crafting/blueprint_set.dart';
import '../crafting/crafting_blueprint.dart';

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

  List<BlueprintStep> get _steps => List.generate(
    _stepCount,
    (i) => BlueprintStep(
      craft: 'Step${i + 1}',
      stepIndex: i,
      logicalIndex: i + 1,
      kind: BlueprintStepKind.parts,
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
    Future.delayed(FmStepCards.promoteDuration, () {
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
            FmStepCards(
              steps: _steps,
              currentIndex: _currentStepIndex,
              promotingIndex: _promotingIndex,
            ),
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
}
