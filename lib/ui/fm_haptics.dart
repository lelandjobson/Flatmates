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

/// How many selection taps a single moment will play. The last step is a
/// heavy thump.
const int kFmSelectionTapCap = 4;

/// Seconds of gathering a selection before its taps start.
const double kFmSelectionMoment = 0.07;

/// Seconds between the taps of one selection crescendo.
const double kFmSelectionTapGap = 0.046;

/// Seconds between the light ticks of an exacto buzz.
const double kFmExactoBuzzGap = 0.034;

/// Seconds between the stronger pulses of a straight cut or a snip.
const double kFmCutPulseGap = 0.09;

/// What a cut in progress should feel like.
enum FmCutFeel { none, exacto, pulse }

const List<FmHapticStyle> _kSelectionLadder = [
  FmHapticStyle.selectionClick,
  FmHapticStyle.lightImpact,
  FmHapticStyle.mediumImpact,
  FmHapticStyle.heavyImpact,
];

/// Taps for [count] objects selected in one moment. One object is a light
/// tick. Each further object adds a stronger tap, up to a heavy thump.
List<FmHapticStyle> fmSelectionTaps(int count) {
  if (count <= 0) return const [];
  final n = count < kFmSelectionTapCap ? count : kFmSelectionTapCap;
  return [for (var i = 0; i < n; i++) _kSelectionLadder[i]];
}

/// Gathers a selection into moments, then plays a crescendo. Also ticks
/// while a cut is moving. [take] is the clock: pass the same seconds the
/// view advances, and play everything it returns.
class FmHapticPlayer {
  int _added = 0;
  bool _moment = false;
  double _momentEnd = 0;

  List<FmHapticStyle> _queue = const [];
  int _at = 0;
  double _nextTap = 0;
  double _buzzAt = 0;

  /// [count] objects just became selected.
  void noteSelected(int count, double now) {
    if (count <= 0) return;
    _added += count;
    if (_queue.isNotEmpty || _moment) return;
    _moment = true;
    _momentEnd = now + kFmSelectionMoment;
  }

  /// Feels due at [now]. A cut buzz or pulse only runs while [cutting] says
  /// the blade is moving, and stops as soon as it is not.
  List<FmHapticStyle> take(double now, {FmCutFeel cutting = FmCutFeel.none}) {
    final out = <FmHapticStyle>[];
    if (_moment && _queue.isEmpty && now >= _momentEnd) {
      _queue = fmSelectionTaps(_added);
      _added = 0;
      _moment = false;
      _at = 0;
      _nextTap = now;
    }
    if (_queue.isNotEmpty && now >= _nextTap) {
      out.add(_queue[_at]);
      _at++;
      if (_at >= _queue.length) {
        _queue = const [];
        if (_added > 0) {
          _moment = true;
          _momentEnd = now;
        }
      } else {
        _nextTap = now + kFmSelectionTapGap;
      }
    }
    if (cutting == FmCutFeel.none) {
      _buzzAt = now + kFmExactoBuzzGap;
    } else if (now >= _buzzAt) {
      out.add(
        cutting == FmCutFeel.exacto
            ? FmHapticStyle.selectionClick
            : FmHapticStyle.lightImpact,
      );
      _buzzAt =
          now +
          (cutting == FmCutFeel.exacto ? kFmExactoBuzzGap : kFmCutPulseGap);
    }
    return out;
  }
}
