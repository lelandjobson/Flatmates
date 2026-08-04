import 'package:flutter/material.dart';
import 'hud_action.dart';
import 'hud_layout.dart';

/// Horizontal action bar shown over the center of a path after a long drag.
/// Presents context-dependent actions (Move Here, Gather, Create Path, etc.).
class LineDragHud extends HudLayout {
  const LineDragHud({
    super.key,
    required super.anchor,
    required super.camera,
    required super.viewport,
    required this.actions,
    this.showCancelButton = true,
    this.onDismiss,
  });

  final List<HudAction> actions;

  /// When false, no Cancel button is shown (e.g. friend move/gather prompt).
  final bool showCancelButton;

  final VoidCallback? onDismiss;

  static const double _buttonHeight = 44.0;
  static const double _buttonSpacing = 10.0;

  @override
  Widget buildOverlay(BuildContext context, Offset center) {
    if (actions.isEmpty) return const SizedBox.shrink();

    final totalWidth = actions.length * 130.0 +
        (actions.length - 1) * _buttonSpacing +
        16.0; // padding

    return Positioned(
      left: (center.dx - totalWidth / 2).clamp(8.0, viewport.width - totalWidth - 8.0),
      top: (center.dy - _buttonHeight / 2 - 40).clamp(8.0, viewport.height - _buttonHeight - 8.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < actions.length; i++) ...[
              if (i > 0) SizedBox(width: _buttonSpacing),
              _LineHudButton(action: actions[i]),
            ],
            if (showCancelButton) ...[
              SizedBox(width: _buttonSpacing),
              _LineHudButton(
                action: HudAction(
                  id: '_dismiss',
                  label: 'Cancel',
                  icon: Icons.close,
                  onActivated: onDismiss ?? () {},
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LineHudButton extends StatelessWidget {
  const _LineHudButton({required this.action});

  final HudAction action;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: action.enabled ? action.onActivated : null,
      child: Container(
        height: LineDragHud._buttonHeight,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: action.enabled
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: action.enabled ? Colors.white38 : Colors.white12,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              action.icon,
              color: action.enabled ? Colors.white : Colors.grey,
              size: 20,
            ),
            const SizedBox(width: 6),
            Text(
              action.label,
              style: TextStyle(
                color: action.enabled ? Colors.white : Colors.grey,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
