import 'dart:math' as math;
import 'dart:ui';

/// The central rectangle left by the four UI bands, in viewport coordinates.
/// Empty bands contribute only the platform inset. The gap keeps drawn geometry
/// clear of control borders and shadows without adding a second zoom margin.
Rect craftingSafeZone(
  Size viewport, {
  Rect? header,
  Rect? left,
  Rect? right,
  Rect? footer,
  double insetLeft = 0,
  double insetTop = 0,
  double insetRight = 0,
  double insetBottom = 0,
  double gap = 8,
}) {
  final l = math.max(insetLeft, left?.right ?? 0.0) + gap;
  final t = math.max(insetTop, header?.bottom ?? 0.0) + gap;
  final r =
      math.min(viewport.width - insetRight, right?.left ?? viewport.width) -
      gap;
  final b =
      math.min(viewport.height - insetBottom, footer?.top ?? viewport.height) -
      gap;
  // Extremely constrained layouts still need a finite projection rectangle.
  final x = l.clamp(0.0, math.max(0.0, viewport.width - 1)).toDouble();
  final y = t.clamp(0.0, math.max(0.0, viewport.height - 1)).toDouble();
  return Rect.fromLTRB(x, y, math.max(x + 1, r), math.max(y + 1, b));
}
