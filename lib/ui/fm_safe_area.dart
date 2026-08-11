import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Fallback inset used on edges where the OS reports no intrusion (desktop,
/// web, pre-notch phones) so chrome never sits flush against the screen edge.
const EdgeInsets kFmScreenInset = EdgeInsets.all(12);

/// Insets that keep content clear of system chrome: the iOS status bar, notch,
/// Dynamic Island and home indicator, and their Android equivalents.
///
/// Values come from the platform (on iOS, `UIView.safeAreaInsets`), so they are
/// device- and orientation-specific and must never be hardcoded. `viewPadding`
/// is used rather than `padding` so the insets stay constant while the software
/// keyboard is open; it is still reduced by any enclosing [SafeArea] or
/// [FmSafeArea], so nesting never double-counts an edge.
EdgeInsets fmSafeInsets(
  BuildContext context, {
  EdgeInsets minimum = EdgeInsets.zero,
  bool left = true,
  bool top = true,
  bool right = true,
  bool bottom = true,
}) {
  final view = MediaQuery.viewPaddingOf(context);
  return EdgeInsets.fromLTRB(
    left ? math.max(view.left, minimum.left) : minimum.left,
    top ? math.max(view.top, minimum.top) : minimum.top,
    right ? math.max(view.right, minimum.right) : minimum.right,
    bottom ? math.max(view.bottom, minimum.bottom) : minimum.bottom,
  );
}

/// Insets [child] by [fmSafeInsets] and hides those insets from descendants.
///
/// Prefer this over [SafeArea] for interactive or text content: it honours a
/// [minimum] inset and ignores the keyboard, so overlays do not jump when a
/// text field is focused.
class FmSafeArea extends StatelessWidget {
  const FmSafeArea({
    super.key,
    required this.child,
    this.minimum = EdgeInsets.zero,
    this.left = true,
    this.top = true,
    this.right = true,
    this.bottom = true,
  });

  final Widget child;
  final EdgeInsets minimum;
  final bool left;
  final bool top;
  final bool right;
  final bool bottom;

  @override
  Widget build(BuildContext context) {
    final insets = fmSafeInsets(
      context,
      minimum: minimum,
      left: left,
      top: top,
      right: right,
      bottom: bottom,
    );
    return Padding(
      padding: insets,
      child: MediaQuery.removePadding(
        context: context,
        removeLeft: left,
        removeTop: top,
        removeRight: right,
        removeBottom: bottom,
        child: child,
      ),
    );
  }
}

/// A [Positioned] whose offsets are measured from the safe area rather than the
/// raw screen edge, for HUD elements layered over a full-bleed [Stack].
///
/// Each supplied offset is shifted by the platform inset for that edge, so
/// `FmSafePositioned(top: 12, ...)` sits 12 logical pixels below the status bar
/// on every device. Offsets left null behave exactly as in [Positioned].
class FmSafePositioned extends StatelessWidget {
  const FmSafePositioned({
    super.key,
    required this.child,
    this.left,
    this.top,
    this.right,
    this.bottom,
    this.width,
    this.height,
    this.minimum = EdgeInsets.zero,
  });

  final Widget child;
  final double? left;
  final double? top;
  final double? right;
  final double? bottom;
  final double? width;
  final double? height;
  final EdgeInsets minimum;

  @override
  Widget build(BuildContext context) {
    final insets = fmSafeInsets(context, minimum: minimum);
    return Positioned(
      left: left == null ? null : left! + insets.left,
      top: top == null ? null : top! + insets.top,
      right: right == null ? null : right! + insets.right,
      bottom: bottom == null ? null : bottom! + insets.bottom,
      width: width,
      height: height,
      child: child,
    );
  }
}
