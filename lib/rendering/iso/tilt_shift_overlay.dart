import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Screen-space tilt-shift overlay that blurs the top and bottom of the
/// viewport while keeping the center sharp, creating a miniature-world effect.
///
/// Uses horizontally-banded [BackdropFilter] widgets, each clipped to its
/// strip and with sigma proportional to distance from the focal center.
/// This avoids the ShaderMask+BackdropFilter compositing issue where
/// ShaderMask's saveLayer isolates BackdropFilter from the real backdrop.
class TiltShiftOverlay extends StatelessWidget {
  const TiltShiftOverlay({
    super.key,
    required this.intensity,
    required this.focalCenter,
    required this.focalDepth,
    required this.feather,
  });

  final double intensity;
  final double focalCenter;
  final double focalDepth;
  final double feather;

  static const double _maxSigma = 20.0;
  static const int _bandCount = 12;

  @override
  Widget build(BuildContext context) {
    final maxSigma = intensity * _maxSigma;
    if (maxSigma < 0.5) return const SizedBox.shrink();

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          if (height <= 0) return const SizedBox.shrink();

          final bandHeight = height / _bandCount;
          final c = focalCenter.clamp(0.0, 1.0);
          final halfDepth = focalDepth.clamp(0.0, 1.0) / 2;
          final f = feather.clamp(0.01, 1.0);

          final bands = <Widget>[];
          for (int i = 0; i < _bandCount; i++) {
            final bandCenterNorm = (i + 0.5) / _bandCount;
            final distFromFocal = (bandCenterNorm - c).abs();
            final blurFrac =
                ((distFromFocal - halfDepth) / f).clamp(0.0, 1.0);
            final sigma = blurFrac * maxSigma;
            if (sigma < 0.5) continue;

            bands.add(
              Positioned(
                top: i * bandHeight,
                left: 0,
                right: 0,
                height: bandHeight + 1,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            );
          }

          if (bands.isEmpty) return const SizedBox.shrink();
          return Stack(children: bands);
        },
      ),
    );
  }
}
