import 'package:flutter/material.dart';

/// Bottom-right lock that disables pan and restores touch tool controls.
class ViewLockButton extends StatelessWidget {
  const ViewLockButton({
    super.key,
    required this.locked,
    required this.onPressed,
  });

  final bool locked;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: locked ? 'Unlock view' : 'Lock view',
      child: Material(
        color: Colors.black.withValues(alpha: 0.7),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(
              locked ? Icons.lock : Icons.lock_open,
              color: locked ? Colors.white : Colors.white70,
              size: 26,
            ),
          ),
        ),
      ),
    );
  }
}
