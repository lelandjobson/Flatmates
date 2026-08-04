import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'fm_theme.dart';
import 'fm_tooltip.dart';

class FmSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;
  final double width;
  final double height;
  final String? tooltip;
  final Map<String, dynamic>? metadata;
  final bool enabled;

  const FmSlider({
    super.key,
    required this.value,
    this.min = 0.0,
    this.max = 1.0,
    this.onChanged,
    this.width = 200,
    this.height = 32,
    this.tooltip,
    this.metadata,
    this.enabled = true,
  });

  @override
  State<FmSlider> createState() => _FmSliderState();
}

class _FmSliderState extends State<FmSlider> {
  bool _isDragging = false;
  bool _isHovered = false;

  double get _normalizedValue =>
      ((widget.value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);

  void _updateValue(Offset localPosition) {
    if (!widget.enabled || widget.onChanged == null) return;
    final fraction = (localPosition.dx / widget.width).clamp(0.0, 1.0);
    final value = widget.min + fraction * (widget.max - widget.min);
    widget.onChanged!(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<FmThemeData>();

    final slider = MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onHorizontalDragStart: (details) {
          _isDragging = true;
          _updateValue(details.localPosition);
        },
        onHorizontalDragUpdate: (details) {
          _updateValue(details.localPosition);
        },
        onHorizontalDragEnd: (_) {
          _isDragging = false;
        },
        onTapDown: (details) {
          _updateValue(details.localPosition);
        },
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: CustomPaint(
            painter: _SliderPainter(
              normalizedValue: _normalizedValue,
              strokeColor: widget.enabled
                  ? theme.strokeColor
                  : theme.strokeColor.withValues(alpha: 0.3),
              fillColor: widget.enabled
                  ? theme.strokeColor
                  : theme.disabledColor,
              trackColor: widget.enabled
                  ? theme.fillColor
                  : theme.disabledColor,
              strokeWidth: theme.strokeWidth,
              isHovered: _isHovered,
              isDragging: _isDragging,
              hoverColor: theme.hoverColor,
            ),
          ),
        ),
      ),
    );

    return FmTooltip(
      message: widget.tooltip,
      child: slider,
    );
  }
}

class _SliderPainter extends CustomPainter {
  final double normalizedValue;
  final Color strokeColor;
  final Color fillColor;
  final Color trackColor;
  final double strokeWidth;
  final bool isHovered;
  final bool isDragging;
  final Color hoverColor;

  _SliderPainter({
    required this.normalizedValue,
    required this.strokeColor,
    required this.fillColor,
    required this.trackColor,
    required this.strokeWidth,
    required this.isHovered,
    required this.isDragging,
    required this.hoverColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final trackHeight = 4.0;
    final trackY = size.height / 2;
    final thumbRadius = isDragging ? 8.0 : (isHovered ? 7.0 : 6.0);

    // Track background
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width / 2, trackY),
        width: size.width,
        height: trackHeight,
      ),
      const Radius.circular(2),
    );

    final trackPaint = Paint()
      ..color = trackColor == const Color(0x00000000)
          ? strokeColor.withValues(alpha: 0.2)
          : trackColor
      ..style = PaintingStyle.fill;
    canvas.drawRRect(trackRect, trackPaint);

    // Active portion
    final activeWidth = size.width * normalizedValue;
    if (activeWidth > 0) {
      final activeRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, trackY - trackHeight / 2, activeWidth, trackHeight),
        const Radius.circular(2),
      );
      final activePaint = Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill;
      canvas.drawRRect(activeRect, activePaint);
    }

    // Track stroke
    final trackStrokePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawRRect(trackRect, trackStrokePaint);

    // Thumb
    final thumbX = size.width * normalizedValue;
    final thumbCenter = Offset(thumbX.clamp(thumbRadius, size.width - thumbRadius), trackY);

    final thumbFillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(thumbCenter, thumbRadius, thumbFillPaint);

    final thumbStrokePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(thumbCenter, thumbRadius, thumbStrokePaint);
  }

  @override
  bool shouldRepaint(_SliderPainter oldDelegate) =>
      normalizedValue != oldDelegate.normalizedValue ||
      strokeColor != oldDelegate.strokeColor ||
      fillColor != oldDelegate.fillColor ||
      isHovered != oldDelegate.isHovered ||
      isDragging != oldDelegate.isDragging;
}
