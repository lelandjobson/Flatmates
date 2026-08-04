import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'fm_theme.dart';

class FmDevBackButton extends StatefulWidget {
  const FmDevBackButton({super.key});

  @override
  State<FmDevBackButton> createState() => _FmDevBackButtonState();
}

class _FmDevBackButtonState extends State<FmDevBackButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<FmThemeData>();

    return Positioned(
      top: 12,
      left: 12,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => context.goNamed('dev_routes'),
          child: CustomPaint(
            painter: _BackButtonPainter(
              strokeColor: theme.strokeColor,
              fillColor: _hovered ? theme.hoverColor : theme.fillColor,
              strokeWidth: theme.strokeWidth,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                '← Dev',
                style: TextStyle(
                  color: theme.textColor,
                  fontSize: 12,
                  decoration: TextDecoration.none,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BackButtonPainter extends CustomPainter {
  final Color strokeColor;
  final Color fillColor;
  final double strokeWidth;

  _BackButtonPainter({
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
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));

    if (fillColor.a > 0) {
      canvas.drawRRect(rrect, Paint()..color = fillColor);
    }

    canvas.drawRRect(
      rrect,
      Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
  }

  @override
  bool shouldRepaint(_BackButtonPainter oldDelegate) =>
      strokeColor != oldDelegate.strokeColor ||
      fillColor != oldDelegate.fillColor ||
      strokeWidth != oldDelegate.strokeWidth;
}
