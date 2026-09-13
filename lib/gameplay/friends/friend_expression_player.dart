import 'dart:math' as math;

import 'friend_expression_pose.dart';

const double kExpressionFadeSeconds = 0.15;

/// Idle face director: fade when stopped, then blink / glance / cute cuts.
class FriendExpressionPlayer {
  FriendExpressionPlayer({
    required this.seed,
    this.presenting = false,
    double? firstHold,
  }) : _rng = math.Random(seed.hashCode) {
    _hold = firstHold ?? _restHold();
  }

  final String seed;
  bool presenting;
  final math.Random _rng;

  double opacity = 0;
  FriendExpressionPose from = FriendExpressionPose.rest;
  FriendExpressionPose to = FriendExpressionPose.rest;
  FriendExpressionPose current = FriendExpressionPose.rest;
  double blendT = 1;
  double blendSeconds = 0.18;
  double _hold = 0;

  bool get isBlending => blendT < 1;

  void tick(double dt, {required bool moving}) {
    final show = presenting || !moving;
    final target = show ? 1.0 : 0.0;
    if (dt > 0) {
      final step = dt / kExpressionFadeSeconds;
      if (opacity < target) {
        opacity = (opacity + step).clamp(0.0, 1.0);
      } else if (opacity > target) {
        opacity = (opacity - step).clamp(0.0, 1.0);
      }
    }

    if (!show) {
      if (to.id != FriendExpressionId.rest) {
        _go(FriendExpressionPose.rest, 0.12);
      }
      _advanceBlend(dt);
      return;
    }

    _advanceBlend(dt);
    if (isBlending) return;
    _hold -= dt;
    if (_hold > 0) return;

    if (to.id != FriendExpressionId.rest) {
      _go(FriendExpressionPose.rest, to.id == FriendExpressionId.blink ? 0.08 : 0.18);
      return;
    }
    _pickAction();
  }

  /// Test helper: start a blend to [id] immediately.
  void play(FriendExpressionId id, {double duration = 0.12, double gaze = 1}) {
    _go(FriendExpressionPose.byId(id, gaze: gaze), duration);
  }

  void _advanceBlend(double dt) {
    if (!isBlending || blendSeconds <= 1e-9) {
      current = to;
      blendT = 1;
      return;
    }
    blendT = (blendT + dt / blendSeconds).clamp(0.0, 1.0);
    final u = blendT * blendT * (3 - 2 * blendT);
    current = FriendExpressionPose.lerp(from, to, u);
  }

  void _pickAction() {
    final roll = _rng.nextDouble();
    if (roll < 0.4) {
      _go(FriendExpressionPose.blink, 0.08);
      _hold = 0.04;
    } else if (roll < 0.72) {
      final gaze = _rng.nextBool() ? 1.0 : -1.0;
      _go(FriendExpressionPose.glance(gaze), 0.18);
      _hold = 0.4 + _rng.nextDouble() * 0.8;
    } else {
      final cuts = [
        FriendExpressionPose.happy,
        FriendExpressionPose.sad,
        FriendExpressionPose.wow,
        FriendExpressionPose.sleepy,
        FriendExpressionPose.inquisitive,
      ];
      _go(cuts[_rng.nextInt(cuts.length)], 0.2);
      _hold = 0.6 + _rng.nextDouble() * 0.9;
    }
  }

  void _go(FriendExpressionPose next, double seconds) {
    from = current;
    to = next;
    blendT = 0;
    blendSeconds = seconds;
    if (next.id == FriendExpressionId.rest) {
      _hold = _restHold();
    }
  }

  double _restHold() => 1.5 + _rng.nextDouble() * 2.5;
}
