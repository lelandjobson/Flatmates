import 'package:flutter/material.dart';

class GraphViewTheme {
  const GraphViewTheme({
    this.canvasBackground = const Color(0xFF0F1116),
    this.surfaceColor = const Color(0xFF171A21),
    this.nodeExpandableBody = const Color(0xFF1B2230),
    this.nodeLeafBody = const Color(0xFF2A2D33),
    this.nodeLeafBorder = const Color(0xFF2A2D33),
    this.nodeDefaultBorder = const Color(0xFF4A5060),
    this.selectedBorder = Colors.cyanAccent,
    this.selectedBorderWidth = 2.2,
    this.defaultBorderWidth = 1.0,
    this.dimmedOpacity = 0.4,
    this.textPrimary = Colors.white,
    this.textSecondary = Colors.white70,
    this.textMuted = Colors.white54,
    this.edgeFallbackColor = const Color(0xFF95A1B4),
    this.menuBackground = const Color(0xFF1E2230),
    this.menuBorder = Colors.white24,
    this.nodeShadowColor = const Color(0x42000000),
    this.nodeWidth = 220,
    this.nodeHeight = 86,
    this.horizontalGap = 320,
    this.verticalGap = 130,
    this.canvasPadding = 140,
    this.minScale = 0.55,
    this.borderRadius = 12.0,
    this.menuButtonSize = 32.0,
  });

  final Color canvasBackground;
  final Color surfaceColor;
  final Color nodeExpandableBody;
  final Color nodeLeafBody;
  final Color nodeLeafBorder;
  final Color nodeDefaultBorder;
  final Color selectedBorder;
  final double selectedBorderWidth;
  final double defaultBorderWidth;
  final double dimmedOpacity;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color edgeFallbackColor;
  final Color menuBackground;
  final Color menuBorder;
  final Color nodeShadowColor;

  final double nodeWidth;
  final double nodeHeight;
  final double horizontalGap;
  final double verticalGap;
  final double canvasPadding;
  final double minScale;
  final double borderRadius;
  final double menuButtonSize;

  static const GraphViewTheme dark = GraphViewTheme();
}
