import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'fm_theme.dart';
import 'fm_tooltip.dart';

enum FmButtonState { idle, hovered, pressed, disabled }

abstract class FmButtonBase extends StatefulWidget {
  final IconData? icon;
  final Widget? child;
  final double size;
  final double strokeOffset;
  final String? tooltip;
  final Map<String, dynamic>? metadata;
  final VoidCallback? onPressed;
  final bool enabled;

  const FmButtonBase({
    super.key,
    this.icon,
    this.child,
    this.size = 48,
    this.strokeOffset = 6,
    this.tooltip,
    this.metadata,
    this.onPressed,
    this.enabled = true,
  }) : assert(icon != null || child != null);

  @override
  State<FmButtonBase> createState() => FmButtonBaseState();

  void paintShape(Canvas canvas, Size size, Paint paint);
}

class FmButtonBaseState extends State<FmButtonBase> {
  FmButtonState _state = FmButtonState.idle;

  FmButtonState get state => widget.enabled ? _state : FmButtonState.disabled;

  void _handleTapDown(TapDownDetails _) {
    if (!widget.enabled) return;
    setState(() => _state = FmButtonState.pressed);
  }

  void _handleTapUp(TapUpDetails _) {
    if (!widget.enabled) return;
    setState(() => _state = FmButtonState.hovered);
    widget.onPressed?.call();
  }

  void _handleTapCancel() {
    if (!widget.enabled) return;
    setState(() => _state = FmButtonState.hovered);
  }

  void _handleMouseEnter(PointerEvent _) {
    if (!widget.enabled) return;
    setState(() => _state = FmButtonState.hovered);
  }

  void _handleMouseExit(PointerEvent _) {
    if (!widget.enabled) return;
    setState(() => _state = FmButtonState.idle);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<FmThemeData>();

    Color fillColor;
    switch (state) {
      case FmButtonState.hovered:
        fillColor = theme.hoverColor;
        break;
      case FmButtonState.pressed:
        fillColor = theme.pressedColor;
        break;
      case FmButtonState.disabled:
        fillColor = theme.disabledColor;
        break;
      case FmButtonState.idle:
        fillColor = theme.fillColor;
        break;
    }

    final strokeColor = widget.enabled
        ? theme.strokeColor
        : theme.strokeColor.withValues(alpha: 0.3);

    final iconColor = widget.enabled
        ? theme.textColor
        : theme.textColor.withValues(alpha: 0.3);

    final buttonWidget = MouseRegion(
      onEnter: _handleMouseEnter,
      onExit: _handleMouseExit,
      cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown: _handleTapDown,
        onTapUp: _handleTapUp,
        onTapCancel: _handleTapCancel,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(
            painter: _ButtonPainter(
              paintShape: widget.paintShape,
              strokeColor: strokeColor,
              fillColor: fillColor,
              strokeWidth: theme.strokeWidth,
            ),
            child: Center(
              child: widget.child ??
                  Icon(
                    widget.icon!,
                    size: widget.size - widget.strokeOffset * 2 - theme.strokeWidth * 2,
                    color: iconColor,
                  ),
            ),
          ),
        ),
      ),
    );

    return FmTooltip(
      message: widget.tooltip,
      child: buttonWidget,
    );
  }
}

class _ButtonPainter extends CustomPainter {
  final void Function(Canvas canvas, Size size, Paint paint) paintShape;
  final Color strokeColor;
  final Color fillColor;
  final double strokeWidth;

  _ButtonPainter({
    required this.paintShape,
    required this.strokeColor,
    required this.fillColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    paintShape(canvas, size, fillPaint);

    final strokePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    paintShape(canvas, size, strokePaint);
  }

  @override
  bool shouldRepaint(_ButtonPainter oldDelegate) =>
      strokeColor != oldDelegate.strokeColor ||
      fillColor != oldDelegate.fillColor ||
      strokeWidth != oldDelegate.strokeWidth;
}

class Icon extends StatelessWidget {
  final IconData icon;
  final double? size;
  final Color? color;

  const Icon(this.icon, {super.key, this.size, this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size ?? 24,
      height: size ?? 24,
      child: Center(
        child: Text(
          String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            fontSize: size ?? 24,
            color: color ?? const Color(0xFFFFFFFF),
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}
