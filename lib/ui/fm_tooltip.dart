import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'fm_theme.dart';

class FmTooltip extends StatefulWidget {
  final Widget child;
  final String? message;
  final Duration showDelay;
  final Duration hideDelay;

  const FmTooltip({
    super.key,
    required this.child,
    this.message,
    this.showDelay = const Duration(milliseconds: 500),
    this.hideDelay = const Duration(milliseconds: 200),
  });

  @override
  State<FmTooltip> createState() => _FmTooltipState();
}

class _FmTooltipState extends State<FmTooltip> {
  OverlayEntry? _overlayEntry;
  bool _isHovered = false;

  void _showTooltip() {
    if (widget.message == null || widget.message!.isEmpty) return;
    _removeTooltip();

    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => _FmTooltipOverlay(
        message: widget.message!,
        targetOffset: offset,
        targetSize: size,
        theme: context.read<FmThemeData>(),
      ),
    );

    overlay.insert(_overlayEntry!);
  }

  void _removeTooltip() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _handleMouseEnter(PointerEvent _) {
    _isHovered = true;
    Future.delayed(widget.showDelay, () {
      if (_isHovered && mounted) _showTooltip();
    });
  }

  void _handleMouseExit(PointerEvent _) {
    _isHovered = false;
    Future.delayed(widget.hideDelay, () {
      if (!_isHovered && mounted) _removeTooltip();
    });
  }

  @override
  void dispose() {
    _removeTooltip();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.message == null || widget.message!.isEmpty) {
      return widget.child;
    }

    return MouseRegion(
      onEnter: _handleMouseEnter,
      onExit: _handleMouseExit,
      child: widget.child,
    );
  }
}

class _FmTooltipOverlay extends StatelessWidget {
  final String message;
  final Offset targetOffset;
  final Size targetSize;
  final FmThemeData theme;

  const _FmTooltipOverlay({
    required this.message,
    required this.targetOffset,
    required this.targetSize,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    const double padding = 8;
    const double arrowHeight = 6;
    final top = targetOffset.dy - arrowHeight - padding * 2 - theme.tooltipFontSize - 4;
    final left = targetOffset.dx + targetSize.width / 2;

    return Positioned(
      top: top,
      left: left,
      child: FractionalTranslation(
        translation: const Offset(-0.5, 0),
        child: CustomPaint(
          painter: _TooltipPainter(
            backgroundColor: const Color(0xEE222222),
            borderColor: theme.strokeColor,
            strokeWidth: theme.strokeWidth,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: padding, vertical: 4),
            child: Text(
              message,
              style: TextStyle(
                color: theme.textColor,
                fontSize: theme.tooltipFontSize,
                decoration: TextDecoration.none,
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TooltipPainter extends CustomPainter {
  final Color backgroundColor;
  final Color borderColor;
  final double strokeWidth;

  _TooltipPainter({
    required this.backgroundColor,
    required this.borderColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));

    final fillPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawRRect(rrect, fillPaint);
    canvas.drawRRect(rrect, strokePaint);
  }

  @override
  bool shouldRepaint(_TooltipPainter oldDelegate) =>
      backgroundColor != oldDelegate.backgroundColor ||
      borderColor != oldDelegate.borderColor ||
      strokeWidth != oldDelegate.strokeWidth;
}
