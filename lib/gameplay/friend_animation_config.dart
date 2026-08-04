import 'dart:math' as math;
import 'package:flutter/animation.dart';

/// Curve for segment movement: accelerate to max speed over the first half of
/// the segment distance, then decelerate over the second half. Maps normalized
/// time t (0..1) to normalized position (0..1) so that velocity is 0 at start
/// and end, and peaks at the midpoint. Works for any segment length (including
/// 1 tile) and generalizes to diagonal movement (distance-based).
class HalfDistanceAccelDecelCurve extends Curve {
  const HalfDistanceAccelDecelCurve();

  @override
  double transformInternal(double t) {
    final clamped = t.clamp(0.0, 1.0);
    if (clamped <= 0.5) {
      // First half of time → first half of distance (ease-in: 0 velocity at start)
      return 0.5 * Curves.easeInQuad.transform(clamped * 2);
    } else {
      // Second half of time → second half of distance (ease-out: 0 velocity at end)
      return 0.5 +
          0.5 * Curves.easeOutQuad.transform((clamped - 0.5) * 2);
    }
  }
}

/// A custom "whoosh" curve with pause at start and end, swift movement in middle.
/// Creates a snappy, responsive feel: pause -> swift movement -> pause
/// Based on user's desired curve: 0 0 0 0.02 0.06 0.1 0.2 0.4 0.6 0.8 0.9 0.95 1 1 1
class WhooshCurve extends Curve {
  const WhooshCurve({this.pauseStart = 0.15, this.pauseEnd = 0.15});

  /// Fraction of time to pause at start (0.0 to 0.4)
  final double pauseStart;

  /// Fraction of time to pause at end (0.0 to 0.4)
  final double pauseEnd;

  @override
  double transformInternal(double t) {
    // Pause at start
    if (t < pauseStart) return 0.0;
    // Pause at end
    if (t > (1.0 - pauseEnd)) return 1.0;

    // Map the middle portion (pauseStart to 1-pauseEnd) to 0-1
    final middleRange = 1.0 - pauseStart - pauseEnd;
    final adjusted = (t - pauseStart) / middleRange;

    // Apply a steep ease curve for the swift movement
    // Using easeInOutQuart for dramatic acceleration/deceleration
    return Curves.easeInOutQuart.transform(adjusted);
  }
}

/// Configuration for friend-specific animations
/// Each friend type can have custom animation curves and properties
class FriendAnimationConfig {
  const FriendAnimationConfig({
    required this.movementCurve,
    required this.gatherCurve,
    required this.gatherRotation,
    this.gatherAnimationDurationMs = 300,
  });

  /// Curve for movement animation between tiles
  final Curve movementCurve;

  /// Curve for gathering animation (rotation, etc.)
  final Curve gatherCurve;

  /// Rotation angle for gathering animation (in radians)
  final double gatherRotation;

  /// Duration of gather animation per turn (in milliseconds)
  final int gatherAnimationDurationMs;

  /// "Whoosh" movement curve - pause, swift move, pause
  static const WhooshCurve whooshCurve = WhooshCurve();

  /// Half-distance accel/decel: reach max speed in first half of segment, slow to stop in second half
  static const HalfDistanceAccelDecelCurve halfDistanceAccelDecelCurve =
      HalfDistanceAccelDecelCurve();

  /// Default configuration for cube friends
  static const FriendAnimationConfig cube = FriendAnimationConfig(
    movementCurve: halfDistanceAccelDecelCurve,
    gatherCurve: Curves.easeInOutCubic,
    gatherRotation: math.pi / 2, // 90 degrees
    gatherAnimationDurationMs: 400,
  );

  /// Default configuration for frogman friends
  static const FriendAnimationConfig frogman = FriendAnimationConfig(
    movementCurve: halfDistanceAccelDecelCurve,
    gatherCurve: Curves.easeInOutBack, // Slight bounce
    gatherRotation: math.pi / 4, // 45 degrees (frog crouch)
    gatherAnimationDurationMs: 350,
  );

  /// Default configuration for cone friends
  static const FriendAnimationConfig cone = FriendAnimationConfig(
    movementCurve: halfDistanceAccelDecelCurve,
    gatherCurve: Curves.easeInOutQuad,
    gatherRotation: math.pi / 3, // 60 degrees
    gatherAnimationDurationMs: 380,
  );

  /// Default configuration (fallback)
  static const FriendAnimationConfig defaultConfig = cube;

  /// Get animation config for a friend type
  static FriendAnimationConfig forFriendType(String friendType) {
    return switch (friendType.toLowerCase()) {
      'cube' => cube,
      'frogman' => frogman,
      'cone' => cone,
      _ => defaultConfig,
    };
  }

  /// Apply movement curve to a progress value (0.0 to 1.0)
  double applyMovementCurve(double t) {
    return movementCurve.transform(t.clamp(0.0, 1.0));
  }

  /// Apply gather curve to a progress value (0.0 to 1.0)
  double applyGatherCurve(double t) {
    return gatherCurve.transform(t.clamp(0.0, 1.0));
  }

  /// Get current rotation for gathering animation
  /// [turnProgress] is 0.0 to 1.0 within a single turn
  double getGatherRotation(double turnProgress) {
    // Oscillate back and forth during gathering
    // Goes from 0 -> rotation -> 0 over one turn
    final curvedProgress = applyGatherCurve(turnProgress);
    if (turnProgress < 0.5) {
      // First half: rotate forward
      return gatherRotation * (curvedProgress * 2);
    } else {
      // Second half: rotate back
      return gatherRotation * (2 - curvedProgress * 2);
    }
  }
}
