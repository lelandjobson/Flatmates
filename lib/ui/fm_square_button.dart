import 'dart:ui';

import 'fm_button_base.dart';

class FmSquareButton extends FmButtonBase {
  const FmSquareButton({
    super.key,
    super.icon,
    super.child,
    super.size,
    super.strokeOffset,
    super.tooltip,
    super.metadata,
    super.onPressed,
    super.enabled,
  });

  @override
  void paintShape(Canvas canvas, Size size, Paint paint) {
    final rect = Rect.fromLTWH(
      paint.strokeWidth / 2,
      paint.strokeWidth / 2,
      size.width - paint.strokeWidth,
      size.height - paint.strokeWidth,
    );
    canvas.drawRect(rect, paint);
  }
}
