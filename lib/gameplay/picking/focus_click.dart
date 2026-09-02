import 'dart:math' as math;
import 'dart:ui';

import 'selectable.dart';

/// Fraction of screen width used as the focus-click radius.
const double kFocusClickRadiusFraction = 0.10;

/// Hard cap on the focus-click radius, in logical pixels.
const double kFocusClickRadiusMax = 200;

/// Max time between two taps that counts as a double-click into focus.
const Duration kFocusDoubleTap = Duration(milliseconds: 400);

double focusClickRadius(double screenWidth) =>
    math.min(kFocusClickRadiusMax, screenWidth * kFocusClickRadiusFraction);

/// True when [local] is inside the crosshair focus disc.
bool isFocusClick(Offset local, Size viewport) {
  if (viewport.width <= 0 || viewport.height <= 0) return false;
  final center = Offset(viewport.width / 2, viewport.height / 2);
  return (local - center).distance <= focusClickRadius(viewport.width);
}

/// Created objects (including paths and regions) can enter a viewer.
bool canFocusHit(SelectableHit hit) => hit.isCreatedObject;

/// A second center click on the current selection, or a double-tap, focuses.
bool shouldEnterFocus({
  required bool alreadySelected,
  required bool nearCenter,
  required bool doubleTap,
  required bool focusable,
}) {
  if (!focusable) return false;
  if (doubleTap) return true;
  return alreadySelected && nearCenter;
}
