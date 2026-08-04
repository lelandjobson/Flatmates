import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'fm_theme.dart';
import 'fm_tooltip.dart';

class FmCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final String? tooltip;
  final Map<String, dynamic>? metadata;

  const FmCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.tooltip,
    this.metadata,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<FmThemeData>();

    final card = CustomPaint(
      painter: _CardPainter(
        strokeColor: theme.strokeColor,
        fillColor: theme.fillColor,
        strokeWidth: theme.strokeWidth,
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );

    return FmTooltip(message: tooltip, child: card);
  }
}

class _CardPainter extends CustomPainter {
  final Color strokeColor;
  final Color fillColor;
  final double strokeWidth;

  _CardPainter({
    required this.strokeColor,
    required this.fillColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));

    if (fillColor.a > 0) {
      final fillPaint = Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill;
      canvas.drawRRect(rrect, fillPaint);
    }

    final strokePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawRRect(rrect, strokePaint);
  }

  @override
  bool shouldRepaint(_CardPainter oldDelegate) =>
      strokeColor != oldDelegate.strokeColor ||
      fillColor != oldDelegate.fillColor ||
      strokeWidth != oldDelegate.strokeWidth;
}
