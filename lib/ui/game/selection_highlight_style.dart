import 'package:flutter/material.dart';

/// Fill + outline used when hovering or selecting a map entity.
class SelectionHighlightStyle {
  const SelectionHighlightStyle({
    this.fill = const Color(0x33FFFFFF),
    this.outline = const Color(0xE6FFFFFF),
    this.outlineWidth = 3.5,
    this.fadeDuration = const Duration(milliseconds: 160),
  });

  static const SelectionHighlightStyle standard = SelectionHighlightStyle();

  final Color fill;
  final Color outline;
  final double outlineWidth;
  final Duration fadeDuration;
}
