import 'package:flutter/animation.dart';

import '../friend_animation_config.dart';

/// One pose sample in a [FlatmateWalkStyle] clip. [at] is 0–1 along a tile.
class FlatmateWalkKeyframe {
  const FlatmateWalkKeyframe({
    required this.at,
    this.up = 0,
    this.side = 0,
  });

  /// Normalized time along the current tile step.
  final double at;

  /// Hop height scale, 0–1 of [FlatmateWalkStyle.hopHeightFactor].
  final double up;

  /// Lateral sway scale, 0–1 of [FlatmateWalkStyle.swayWidthFactor].
  final double side;
}

/// Hop / sway offsets in world units for one sample along a tile.
class FlatmateWalkOffset {
  const FlatmateWalkOffset({this.up = 0, this.side = 0});

  final double up;
  final double side;
}

/// Programmable per-tile walk clip. Add a style with a curve + keyframes.
class FlatmateWalkStyle {
  const FlatmateWalkStyle({
    required this.id,
    required this.label,
    this.alongCurve = Curves.linear,
    this.keyframes = const [],
    this.randomizeSide = false,
    this.hopHeightFactor = 0.65,
    this.swayWidthFactor = 0.45,
  });

  final String id;
  final String label;

  /// Remaps 0–1 tile progress before lerping tile centers.
  final Curve alongCurve;

  /// Pose keys along the tile. Empty means no hop or sway.
  final List<FlatmateWalkKeyframe> keyframes;

  /// When true, [side] flips left/right per tile using a stable hash.
  final bool randomizeSide;

  /// Peak hop as a fraction of friend body size.
  final double hopHeightFactor;

  /// Peak sway as a fraction of friend body size.
  final double swayWidthFactor;

  /// Little hops with random left/right sway. Default GameView walk.
  static const hop = FlatmateWalkStyle(
    id: 'hop',
    label: 'Hop',
    randomizeSide: true,
    keyframes: [
      FlatmateWalkKeyframe(at: 0, up: 0, side: 0),
      FlatmateWalkKeyframe(at: 0.45, up: 1, side: 0.7),
      FlatmateWalkKeyframe(at: 1, up: 0, side: 0),
    ],
  );

  /// Linear slide between tile centers (legacy zip).
  static const slide = FlatmateWalkStyle(
    id: 'slide',
    label: 'Slide',
  );

  /// Pause, zip, pause on each tile.
  static const whoosh = FlatmateWalkStyle(
    id: 'whoosh',
    label: 'Whoosh',
    alongCurve: WhooshCurve(),
  );

  static const List<FlatmateWalkStyle> all = [hop, slide, whoosh];

  static FlatmateWalkStyle byId(String id) {
    for (final style in all) {
      if (style.id == id) return style;
    }
    return hop;
  }

  /// Maps raw tile progress through [alongCurve].
  double curveAlong(double t) => alongCurve.transform(t.clamp(0.0, 1.0));

  /// Stable ±1 sway sign for a tile segment.
  static double sideSign(int segmentIndex, String swaySeed) {
    final hash = Object.hash(swaySeed, segmentIndex);
    return (hash & 1) == 0 ? 1.0 : -1.0;
  }

  /// Hop and sway at tile progress [t] (0–1), scaled by [bodySize].
  FlatmateWalkOffset pose({
    required double t,
    required int segmentIndex,
    required String swaySeed,
    required double bodySize,
  }) {
    if (keyframes.isEmpty) return const FlatmateWalkOffset();
    final sampled = _lerpKeys(t.clamp(0.0, 1.0));
    final sign = randomizeSide ? sideSign(segmentIndex, swaySeed) : 1.0;
    return FlatmateWalkOffset(
      up: sampled.up * hopHeightFactor * bodySize,
      side: sampled.side * swayWidthFactor * bodySize * sign,
    );
  }

  ({double up, double side}) _lerpKeys(double t) {
    if (t <= keyframes.first.at) {
      return (up: keyframes.first.up, side: keyframes.first.side);
    }
    if (t >= keyframes.last.at) {
      return (up: keyframes.last.up, side: keyframes.last.side);
    }
    for (var i = 0; i < keyframes.length - 1; i++) {
      final a = keyframes[i];
      final b = keyframes[i + 1];
      if (t >= a.at && t <= b.at) {
        final span = b.at - a.at;
        final u = span <= 1e-9 ? 1.0 : (t - a.at) / span;
        return (
          up: a.up + (b.up - a.up) * u,
          side: a.side + (b.side - a.side) * u,
        );
      }
    }
    return (up: keyframes.last.up, side: keyframes.last.side);
  }
}
