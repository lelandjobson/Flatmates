import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'fm_safe_area.dart';

/// Base layout for every routed screen.
///
/// The screen fills the display edge to edge — [background] paints under the
/// status bar and home indicator — while [content] is inset by
/// [fmSafeInsets] so text and controls never sit under system chrome.
/// [overlays] are raw [Stack] children for HUD elements that position
/// themselves, typically with [FmSafePositioned].
class FmScreen extends StatelessWidget {
  const FmScreen({
    super.key,
    this.background,
    this.content,
    this.overlays = const <Widget>[],
    this.backgroundColor = const Color(0xFF000000),
    this.minimum = kFmScreenInset,
    this.appBar,
  });

  /// Painted full-bleed behind [content]: 3D canvases, artwork, tap catchers.
  final Widget? background;

  /// Interactive and text content, inset to the safe area.
  final Widget? content;

  /// Self-positioning HUD layers stacked above [content].
  final List<Widget> overlays;

  final Color backgroundColor;

  /// Inset applied on edges where the platform reports no system chrome.
  final EdgeInsets minimum;

  final PreferredSizeWidget? appBar;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          ThemeData.estimateBrightnessForColor(backgroundColor) ==
              Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: appBar,
        body: Stack(
          fit: StackFit.expand,
          children: [
            ?background,
            if (content != null) FmSafeArea(minimum: minimum, child: content!),
            ...overlays,
          ],
        ),
      ),
    );
  }
}
