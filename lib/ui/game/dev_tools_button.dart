import 'package:flutter/material.dart';

/// Small faded text toggle for the GameView DevTools panel.
class DevToolsButton extends StatelessWidget {
  const DevToolsButton({
    super.key,
    required this.active,
    required this.onPressed,
  });

  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          'devtools',
          style: TextStyle(
            fontSize: 11,
            letterSpacing: 0.5,
            color: Colors.white.withValues(alpha: active ? 0.85 : 0.5),
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
