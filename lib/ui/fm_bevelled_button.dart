import 'dart:ui';

import 'fm_button_base.dart';

class FmBevelledButton extends FmButtonBase {
  final double bevelSize;

  const FmBevelledButton({
    super.key,
    super.icon,
    super.child,
    super.size,
    super.strokeOffset,
    super.tooltip,
    super.metadata,
    super.onPressed,
    super.enabled,
    this.bevelSize = 8,
  });

  @override
  void paintShape(Canvas canvas, Size size, Paint paint) {
    final sw = paint.strokeWidth / 2;
    final b = bevelSize;
    final w = size.width - sw * 2;
    final h = size.height - sw * 2;

    final path = Path()
      ..moveTo(sw + b, sw)
      ..lineTo(sw + w - b, sw)
      ..lineTo(sw + w, sw + b)
      ..lineTo(sw + w, sw + h - b)
      ..lineTo(sw + w - b, sw + h)
      ..lineTo(sw + b, sw + h)
      ..lineTo(sw, sw + h - b)
      ..lineTo(sw, sw + b)
      ..close();

    canvas.drawPath(path, paint);
  }
}
