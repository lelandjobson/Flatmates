import 'package:flutter/material.dart';

import 'link_overlay_data.dart';

class LinkPainter extends CustomPainter {
  const LinkPainter(this.lines);

  final List<RenderedLine> lines;

  @override
  void paint(Canvas canvas, Size size) {
    for (final line in lines) {
      final paint = Paint()
        ..color = line.color.withOpacity(0.8)
        ..strokeWidth = 3.5
        ..style = PaintingStyle.stroke;
      canvas.drawLine(line.start, line.end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant LinkPainter oldDelegate) {
    if (oldDelegate.lines.length != lines.length) {
      return true;
    }
    for (var i = 0; i < lines.length; i++) {
      final a = lines[i];
      final b = oldDelegate.lines[i];
      if (a.start != b.start || a.end != b.end || a.color != b.color) {
        return true;
      }
    }
    return false;
  }
}

