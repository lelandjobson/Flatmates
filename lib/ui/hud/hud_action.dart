import 'package:flutter/material.dart';

/// A single action available in a HUD overlay (radial or line).
class HudAction {
  const HudAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.onActivated,
    this.enabled = true,
    this.customIcon,
  });

  final String id;
  final String label;
  final IconData icon;
  final VoidCallback onActivated;
  final bool enabled;

  /// When non-null, used instead of [icon] for the button display (e.g. friend sprite).
  final Widget? customIcon;
}
