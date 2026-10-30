import 'dart:math' as math;
import 'dart:ui';

/// Degrees the paper turns between neighboring pips.
const double kAsmrDialPipDegrees = 10;

/// Share of the whole bar at each end where, with cruise on, holding the
/// knob keeps the paper turning.
const double kAsmrDialEndShare = 0.1;

/// Radians per second the paper turns while the knob is held in an end.
const double kAsmrDialCruiseSpeed = math.pi / 2;

/// Screen pixels around the bar that still take hold of the knob.
const double kAsmrDialGrab = 26;

/// The scissors' turn dial: a level bar below the blade. Its circle is the
/// reticle's circle, drawn by the scissors. A full drag from the middle
/// to either end turns the paper 90 degrees about [pivot]. Pips mark
/// equal ten-degree steps along that range.
class AsmrTurnDial {
  const AsmrTurnDial({
    required this.center,
    required this.halfLength,
    required this.pivot,
  });

  /// The middle of the bar, where the knob rests.
  final Offset center;
  final double halfLength;

  /// Where the paper turns about, above the bar.
  final Offset pivot;

  /// How far the bar sits below the pivot.
  double get depth => math.max(center.dy - pivot.dy, 1);

  /// Knob offsets closer to the middle than this follow the finger one to
  /// one: 80% of the bar.
  double get freeReach => halfLength * (1 - 2 * kAsmrDialEndShare);

  /// The knob's offset for a finger [travel] along the bar: one to one
  /// through the full bar. Cruise mode adds resistance near the ends.
  double knobFor(double travel, {bool cruise = false}) {
    if (!cruise) return travel.clamp(-halfLength, halfLength);
    final free = freeReach;
    final distance = travel.abs();
    if (distance <= free) return travel;
    final give = halfLength - free;
    if (give <= 0) return travel.sign * free;
    return travel.sign *
        (free + give * (1 - math.exp(-(distance - free) / give)));
  }

  /// Dial angle: the center is pi/2, with a quarter turn to either end.
  double angleAt(double x) =>
      math.pi / 2 -
      (halfLength <= 0 ? 0 : (x / halfLength).clamp(-1.0, 1.0)) * math.pi / 2;

  /// Whether a knob at [x] is in an end of the bar.
  bool inEnd(double x) => x.abs() > freeReach + 1e-9;

  /// Which way a knob held at [x] keeps the paper turning: the way dragging
  /// it there turned it.
  double cruiseSign(double x) => x > 0 ? -1 : 1;

  /// Bar offsets of the pips, the middle one first.
  List<double> get pips {
    final out = <double>[0];
    for (var k = 1; ; k++) {
      final angle = k * kAsmrDialPipDegrees * math.pi / 180;
      if (angle > math.pi / 2) break;
      final x = halfLength * angle / (math.pi / 2);
      if (x > halfLength) break;
      out
        ..add(x)
        ..add(-x);
    }
    return out;
  }

  /// Whether [point] is on the circle, which rests [knob] pixels from the
  /// middle. The bar itself is not a handle.
  bool grabs(Offset point, {double knob = 0}) =>
      (point - (center + Offset(knob, 0))).distance <= kAsmrDialGrab;

  /// Draws the bar and its pips. The circle is the reticle's, drawn by the
  /// caller, so cutting and turning share one circle. With [cruise] the ends
  /// of the bar are drawn heavier.
  void paint(Canvas canvas, {required Color ink, bool cruise = false}) {
    final bar = Paint()
      ..color = ink.withValues(alpha: ink.a * 0.35)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    final left = center - Offset(halfLength, 0);
    final right = center + Offset(halfLength, 0);
    canvas.drawLine(left, right, bar);
    if (cruise) {
      final end = Paint()
        ..color = ink.withValues(alpha: ink.a * 0.55)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(left, center - Offset(freeReach, 0), end);
      canvas.drawLine(center + Offset(freeReach, 0), right, end);
    }
    for (final x in pips) {
      final lean = math.cos(math.atan(x.abs() / depth));
      final half = 1 + 2.5 * lean;
      canvas.drawLine(
        center + Offset(x, -half),
        center + Offset(x, half),
        Paint()
          ..color = ink.withValues(alpha: ink.a * (0.2 + 0.5 * lean))
          ..strokeWidth = 1,
      );
    }
  }
}
