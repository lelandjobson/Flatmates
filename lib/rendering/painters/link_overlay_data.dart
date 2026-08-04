import 'package:flutter/material.dart';

class RenderedLine {
  const RenderedLine({
    required this.start,
    required this.end,
    required this.color,
  });

  final Offset start;
  final Offset end;
  final Color color;
}

class PrefabBubble {
  const PrefabBubble({required this.position, required this.colors});

  final Offset position;
  final List<Color> colors;
}

class LinkOverlayData {
  const LinkOverlayData({required this.lines, required this.bubbles});

  final List<RenderedLine> lines;
  final List<PrefabBubble> bubbles;
}

