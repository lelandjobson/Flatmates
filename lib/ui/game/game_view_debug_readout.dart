import 'package:flutter/material.dart';

/// Hide the camera dump on compact windows so it does not crowd HUD chrome.
const kGameViewDebugReadoutMinWidth = 720.0;
const kGameViewDebugReadoutMinHeight = 520.0;

/// Sit above the 48px left rotate control (`bottom: 12`).
const kGameViewDebugReadoutBottom = 68.0;
const kGameViewDebugReadoutLeft = 12.0;

bool gameViewDebugReadoutFits(Size size) {
  return size.width >= kGameViewDebugReadoutMinWidth &&
      size.height >= kGameViewDebugReadoutMinHeight;
}

/// Pass-through, left-aligned debug lines for GameView.
class GameViewDebugReadout extends StatelessWidget {
  const GameViewDebugReadout({
    super.key,
    required this.lines,
    this.isError = false,
    this.busy = false,
  });

  final List<String> lines;
  final bool isError;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) return const SizedBox.shrink();
    final color = isError
        ? Colors.redAccent
        : busy
            ? Colors.amberAccent
            : Colors.white70;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xE6101010),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white10),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: DefaultTextStyle(
            style: TextStyle(
              color: color,
              fontSize: 11,
              height: 1.35,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final line in lines) Text(line),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
