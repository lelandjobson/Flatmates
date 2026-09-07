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

  /// Flat floor / region pick — thin enough that program outlines stay readable.
  static const SelectionHighlightStyle floor = SelectionHighlightStyle(
    fill: Color(0x14FFFFFF),
    outline: Color(0x99FFFFFF),
    outlineWidth: 1.15,
  );

  static const SelectionHighlightStyle delete = SelectionHighlightStyle(
    fill: Color(0x55E53935),
    outline: Color(0xF0EF5350),
  );

  static const SelectionHighlightStyle invalid = SelectionHighlightStyle(
    fill: Color(0x33E53935),
    outline: Color(0xF0E53935),
  );

  final Color fill;
  final Color outline;
  final double outlineWidth;
  final Duration fadeDuration;
}
