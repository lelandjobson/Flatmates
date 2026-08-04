import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'fm_theme.dart';
import 'fm_tooltip.dart';

class FmColumnBox extends StatelessWidget {
  final List<Widget> children;
  final MainAxisAlignment mainAxisAlignment;
  final CrossAxisAlignment crossAxisAlignment;
  final EdgeInsets padding;
  final String? tooltip;
  final Map<String, dynamic>? metadata;

  const FmColumnBox({
    super.key,
    required this.children,
    this.mainAxisAlignment = MainAxisAlignment.start,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.padding = const EdgeInsets.all(8),
    this.tooltip,
    this.metadata,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<FmThemeData>();

    final box = CustomPaint(
      painter: _BoxPainter(
        strokeColor: theme.strokeColor,
        fillColor: theme.fillColor,
        strokeWidth: theme.strokeWidth,
      ),
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: mainAxisAlignment,
          crossAxisAlignment: crossAxisAlignment,
          children: children,
        ),
      ),
    );

    return FmTooltip(message: tooltip, child: box);
  }
}

class _BoxPainter extends CustomPainter {
  final Color strokeColor;
  final Color fillColor;
  final double strokeWidth;

  _BoxPainter({
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

    if (fillColor.a > 0) {
      final fillPaint = Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill;
      canvas.drawRect(rect, fillPaint);
    }

    final strokePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawRect(rect, strokePaint);
  }

  @override
  bool shouldRepaint(_BoxPainter oldDelegate) =>
      strokeColor != oldDelegate.strokeColor ||
      fillColor != oldDelegate.fillColor ||
      strokeWidth != oldDelegate.strokeWidth;
}
