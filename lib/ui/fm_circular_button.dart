import 'dart:ui';

import 'fm_button_base.dart';

class FmCircularButton extends FmButtonBase {
  const FmCircularButton({
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
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - paint.strokeWidth) / 2;
    canvas.drawCircle(center, radius, paint);
  }
}
