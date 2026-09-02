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

/// Strength ladder for gameplay place / delete. [faint] is the delete ceiling
/// except for very large removals.
enum FmHapticLevel { faint, light, medium, heavy }

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

FmHapticStyle fmHapticStyleForLevel(FmHapticLevel level) => switch (level) {
      FmHapticLevel.faint => FmHapticStyle.selectionClick,
      FmHapticLevel.light => FmHapticStyle.lightImpact,
      FmHapticLevel.medium => FmHapticStyle.mediumImpact,
      FmHapticLevel.heavy => FmHapticStyle.heavyImpact,
    };

/// Place strength from object size (tiles / cells / segments).
FmHapticLevel fmHapticPlaceLevel(int size) {
  if (size <= 1) return FmHapticLevel.light;
  if (size <= 3) return FmHapticLevel.medium;
  return FmHapticLevel.heavy;
}

/// Delete stays weak even for a large mass.
FmHapticLevel fmHapticDeleteLevel(int size) {
  if (size >= 8) return FmHapticLevel.light;
  return FmHapticLevel.faint;
}

Future<void> fmHapticLevel(FmHapticLevel level) =>
    fmHaptic(fmHapticStyleForLevel(level));

Future<void> fmHapticPlace(int size) => fmHapticLevel(fmHapticPlaceLevel(size));

Future<void> fmHapticDelete(int size) =>
    fmHapticLevel(fmHapticDeleteLevel(size));

Future<void> fmHapticSmallClick() => fmHaptic(kFmHapticSmallClick);

Future<void> fmHapticBigClick() => fmHaptic(kFmHapticBigClick);
