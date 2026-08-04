import 'dart:math' as math;
import 'dart:ui';

import 'fm_button_base.dart';

class FmHexagonalButton extends FmButtonBase {
  const FmHexagonalButton({
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

    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = (math.pi / 3) * i - math.pi / 2;
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    canvas.drawPath(path, paint);
  }
}
