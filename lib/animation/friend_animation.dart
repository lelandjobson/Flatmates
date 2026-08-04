import 'dart:math' as math;

import 'package:flutter/animation.dart';

import '../rendering/iso/friend_expression.dart';

/// Pose output of a friend animation at a given progress (0..1).
///
/// Used by both 2.5D and 3D renderers to apply body rotation, facing,
/// vertical offset (hop), and expression state.
class FriendAnimationPose {
  const FriendAnimationPose({
    this.customRotationRad = 0.0,
    this.facingAngleDeg = 0.0,
    this.hopOffsetY = 0.0,
    this.expressionState = FriendExpressionState.neutral,
  });

  /// Body rotation in radians (e.g. for spin or shake).
  final double customRotationRad;

  /// Facing angle in degrees (0 = north, 90 = east). Drives sprite selection.
  final double facingAngleDeg;

  /// Vertical offset in world units (e.g. for hop).
  final double hopOffsetY;

  /// Runtime expression (blink, type) for the eyes.
  final FriendExpressionState expressionState;

  FriendAnimationPose copyWith({
    double? customRotationRad,
    double? facingAngleDeg,
    double? hopOffsetY,
    FriendExpressionState? expressionState,
  }) {
    return FriendAnimationPose(
      customRotationRad: customRotationRad ?? this.customRotationRad,
      facingAngleDeg: facingAngleDeg ?? this.facingAngleDeg,
      hopOffsetY: hopOffsetY ?? this.hopOffsetY,
      expressionState: expressionState ?? this.expressionState,
    );
  }
}

/// A named animation clip for friends with a fixed duration.
///
/// [getPose] maps progress t in [0, 1] to the current pose.
/// Tracks can be combined; for the first version one clip at a time is used.
class FriendAnimation {
  const FriendAnimation({
    required this.name,
    required this.durationSeconds,
    required this.getPose,
  });

  final String name;
  final double durationSeconds;

  /// Returns the pose at progress [t] in [0, 1].
  final FriendAnimationPose Function(double t) getPose;

  /// Progress t in [0, 1] from elapsed time (handles looping).
  double progressFromElapsed(double elapsedSeconds, {bool repeat = false}) {
    if (durationSeconds <= 0) return 0.0;
    final raw = elapsedSeconds / durationSeconds;
    if (repeat) {
      final frac = raw - raw.floor();
      return frac.clamp(0.0, 1.0);
    }
    return raw.clamp(0.0, 1.0);
  }
}

/// Plays a [FriendAnimation] and exposes the current pose.
///
/// Used by map view (gather spin) and by the animation preview view.
class FriendAnimationPlayer {
  FriendAnimationPlayer();

  FriendAnimation? _animation;
  double _elapsedSeconds = 0.0;
  bool _playing = false;

  /// Currently playing animation, if any.
  FriendAnimation? get animation => _animation;

  /// Elapsed time within the current clip.
  double get elapsedSeconds => _elapsedSeconds;

  /// When true, the animation loops; otherwise it plays once.
  bool repeat = false;

  /// Whether the player is advancing time (play has been called).
  bool get isPlaying => _playing;

  /// Whether the current clip has finished (when not repeating).
  bool get isFinished {
    if (_animation == null || repeat) return false;
    return _elapsedSeconds >= _animation!.durationSeconds;
  }

  /// Current pose from the current animation at current progress.
  /// When the animation has finished (play once), returns the default/neutral
  /// pose so the character always ends in the starting state.
  FriendAnimationPose get currentPose {
    final anim = _animation;
    if (anim == null) return const FriendAnimationPose();
    if (isFinished) return const FriendAnimationPose();
    final t = anim.progressFromElapsed(_elapsedSeconds, repeat: repeat);
    return anim.getPose(t);
  }

  /// Progress in [0, 1] for the current clip.
  double get progress {
    final anim = _animation;
    if (anim == null) return 0.0;
    return anim.progressFromElapsed(_elapsedSeconds, repeat: repeat);
  }

  /// Start or replace the current animation. Resets elapsed time.
  void play(FriendAnimation? animation, {bool resetElapsed = true}) {
    _animation = animation;
    if (resetElapsed) _elapsedSeconds = 0.0;
    _playing = true;
  }

  /// Pause (stop advancing time).
  void pause() {
    _playing = false;
  }

  /// Resume advancing time.
  void resume() {
    _playing = true;
  }

  /// Stop and clear the current animation.
  void stop() {
    _animation = null;
    _elapsedSeconds = 0.0;
    _playing = false;
  }

  /// Advance time by [dt] seconds. Call every frame when [isPlaying].
  void update(double dt) {
    if (!_playing || _animation == null) return;
    _elapsedSeconds += dt;
    if (!repeat && _elapsedSeconds >= _animation!.durationSeconds) {
      _elapsedSeconds = _animation!.durationSeconds;
      _playing = false;
    }
  }
}

// ---------------------------------------------------------------------------
// Built-in animations
// ---------------------------------------------------------------------------

/// Rotate: facing spins 0 -> 360 over duration.
FriendAnimation friendAnimationRotate({double durationSeconds = 2.0}) {
  return FriendAnimation(
    name: 'rotate',
    durationSeconds: durationSeconds,
    getPose: (t) => FriendAnimationPose(
      facingAngleDeg: t * 360.0,
      expressionState: FriendExpressionState.neutral,
    ),
  );
}

/// Shake: facing oscillates left-right (e.g. -20 to +20 deg).
FriendAnimation friendAnimationShake({double durationSeconds = 1.0}) {
  return FriendAnimation(
    name: 'shake',
    durationSeconds: durationSeconds,
    getPose: (t) {
      final angle = 20.0 * math.sin(t * math.pi * 4);
      return FriendAnimationPose(
        facingAngleDeg: angle,
        expressionState: FriendExpressionState.neutral,
      );
    },
  );
}

/// Gaze: eyes shift left-right without body rotation -- looking around curiously.
FriendAnimation friendAnimationGaze({double durationSeconds = 2.5}) {
  return FriendAnimation(
    name: 'gaze',
    durationSeconds: durationSeconds,
    getPose: (t) {
      final offset = math.sin(t * math.pi * 2);
      return FriendAnimationPose(
        expressionState: FriendExpressionState(gazeOffset: offset),
      );
    },
  );
}

/// Approximate friend sprite height in the same units as [hopOffsetY].
/// Used so hop peak is at most 1.75x friend height.
const double _friendHeightUnits = 2.0;

/// Max hop amplitude = 1.75x friend height, then scaled down 3x for subtler motion.
const double _hopPeakMax = 1.75 * _friendHeightUnits / 3.0;

/// Hop: vertical bounce like a ball — fast up, slow at top, fall with acceleration, small ground bounces.
/// Peak height is at most 1.75x the friend sprite height.
FriendAnimation friendAnimationHop({double durationSeconds = 0.7}) {
  return FriendAnimation(
    name: 'hop',
    durationSeconds: durationSeconds,
    getPose: (t) {
      double y;
      if (t < 0.35) {
        // Rise: fast leave ground, slow at apex (easeOut)
        final u = t / 0.35;
        y = _hopPeakMax * Curves.easeOut.transform(u);
      } else if (t < 0.70) {
        // Fall: slow at top, gain speed (easeIn)
        final u = (t - 0.35) / 0.35;
        y = _hopPeakMax * (1.0 - Curves.easeIn.transform(u));
      } else if (t < 0.85) {
        // First small bounce
        final u = (t - 0.70) / 0.15;
        y = _hopPeakMax * 0.34 * math.sin(u * math.pi);
      } else {
        // Second tiny bounce
        final u = (t - 0.85) / 0.15;
        y = _hopPeakMax * 0.11 * math.sin(u * math.pi);
      }
      return FriendAnimationPose(
        hopOffsetY: y,
        expressionState: FriendExpressionState.neutral,
      );
    },
  );
}

/// Gather spin: facing spins at ~90 deg/sec for gathering. One full rotation.
FriendAnimation friendAnimationGatherSpin({double durationSeconds = 4.0}) {
  return FriendAnimation(
    name: 'gather_spin',
    durationSeconds: durationSeconds,
    getPose: (t) => FriendAnimationPose(
      facingAngleDeg: t * 360.0,
      expressionState: FriendExpressionState.neutral,
    ),
  );
}

/// Blink: quick close and open of eyes.
FriendAnimation friendAnimationBlink({double durationSeconds = 0.2}) {
  return FriendAnimation(
    name: 'blink',
    durationSeconds: durationSeconds,
    getPose: (t) {
      final open = t < 0.5
          ? Curves.easeIn.transform(t * 2)
          : Curves.easeOut.transform((t - 0.5) * 2);
      return FriendAnimationPose(
        expressionState: FriendExpressionState(blinkOpen: 1.0 - open),
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Registry
// ---------------------------------------------------------------------------

/// Registry of named friend animations for use by map view and preview view.
class FriendAnimationRegistry {
  FriendAnimationRegistry._();

  static final Map<String, FriendAnimation> _entries = {};

  static List<String> get names => _entries.keys.toList()..sort();

  static void register(FriendAnimation animation) {
    _entries[animation.name] = animation;
  }

  static FriendAnimation? get(String name) => _entries[name];

  static bool contains(String name) => _entries.containsKey(name);

  static void registerDefaults() {
    register(friendAnimationRotate());
    register(friendAnimationShake());
    register(friendAnimationHop());
    register(friendAnimationGatherSpin());
    register(friendAnimationBlink());
    register(friendAnimationGaze());
  }

  static void clear() => _entries.clear();
}
