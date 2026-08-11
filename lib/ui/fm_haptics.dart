import 'package:flutter/services.dart';

/// Feel presets for [fmHaptic]. Change [kFmHapticSmallClick] /
/// [kFmHapticBigClick] to retune all call sites at once.
enum FmHapticStyle {
  /// Soft tick — good for per-cell / selection-style feedback.
  selectionClick,

  /// Light impact.
  lightImpact,

  /// Medium impact.
  mediumImpact,

  /// Strong impact — good for completions.
  heavyImpact,

  /// Platform vibrate (coarser than impact APIs).
  vibrate,
}

/// Universal small-click feel (paint cells, tool actions, etc.).
const FmHapticStyle kFmHapticSmallClick = FmHapticStyle.selectionClick;

/// Universal big-click feel (blueprint / craft completion).
const FmHapticStyle kFmHapticBigClick = FmHapticStyle.heavyImpact;

Future<void> fmHaptic(FmHapticStyle style) {
  switch (style) {
    case FmHapticStyle.selectionClick:
      return HapticFeedback.selectionClick();
    case FmHapticStyle.lightImpact:
      return HapticFeedback.lightImpact();
    case FmHapticStyle.mediumImpact:
      return HapticFeedback.mediumImpact();
    case FmHapticStyle.heavyImpact:
      return HapticFeedback.heavyImpact();
    case FmHapticStyle.vibrate:
      return HapticFeedback.vibrate();
  }
}

Future<void> fmHapticSmallClick() => fmHaptic(kFmHapticSmallClick);

Future<void> fmHapticBigClick() => fmHaptic(kFmHapticBigClick);
