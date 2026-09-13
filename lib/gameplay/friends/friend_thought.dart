import 'dart:math' as math;

import 'friend_desire.dart';
import 'friend_feeling.dart';

const double kFeelingInViewMin = 1.0;
const double kFeelingInViewMax = 2.0;
const double kFeelingDelayMin = 1.0;
const double kFeelingDelayMax = 3.0;
const double kFeelingShowSeconds = 5.0;
const double kDesireAssignChance = 0.7;

/// Current feeling / desire plus the auto-show director.
class FriendThought {
  FriendThought({
    required this.seed,
    bool assignDemo = true,
    math.Random? rng,
  }) : _rng = rng ?? math.Random(seed.hashCode) {
    _rollGates();
    if (assignDemo) assignDemoThoughts();
  }

  final String seed;
  final math.Random _rng;

  Feeling? feeling;
  Desire? desire;

  double percolateTime = 0;
  bool hovered = false;

  double _inViewElapsed = 0;
  double _delayElapsed = 0;
  double _showElapsed = 0;
  double _inViewNeed = kFeelingInViewMin;
  double _delayNeed = kFeelingDelayMin;
  bool _armed = false;
  bool _autoShow = false;

  bool get percolating => desire != null;
  bool get showFeelingCard => feeling != null && (_autoShow || hovered);
  bool get showDesireCloud => desire != null && hovered;
  bool get isAutoShowingFeeling => _autoShow;
  bool get isWaitingToShowFeeling => feeling != null && _armed && !_autoShow;
  bool get isWatchingInView =>
      feeling != null && !_armed && !_autoShow && _inViewElapsed > 0;

  void assignDemoThoughts() {
    feeling = kFeelings[_rng.nextInt(kFeelings.length)];
    desire = _rng.nextDouble() < kDesireAssignChance
        ? kDesires[_rng.nextInt(kDesires.length)]
        : null;
    _resetFeelingCycle();
  }

  void setFeeling(Feeling? next) {
    feeling = next;
    _resetFeelingCycle();
  }

  void setDesire(Desire? next) {
    desire = next;
  }

  void showFeelingNow() {
    if (feeling == null) return;
    _autoShow = true;
    _showElapsed = 0;
    _armed = false;
  }

  void copyFrom(FriendThought other) {
    feeling = other.feeling;
    desire = other.desire;
  }

  /// Test hook for deterministic in-view / delay gates.
  void debugSetGates({required double inViewNeed, required double delayNeed}) {
    _inViewNeed = inViewNeed;
    _delayNeed = delayNeed;
  }

  void tick(
    double dt, {
    required bool inView,
    required bool hovered,
  }) {
    this.hovered = hovered;
    if (dt > 0) percolateTime += dt;

    if (feeling == null) {
      _resetFeelingCycle();
      return;
    }

    if (!inView) {
      _inViewElapsed = 0;
      _delayElapsed = 0;
      _armed = false;
      if (!hovered) {
        _autoShow = false;
        _showElapsed = 0;
      }
      return;
    }

    if (_autoShow) {
      if (!hovered) {
        _showElapsed += dt;
        if (_showElapsed >= kFeelingShowSeconds) {
          _autoShow = false;
          _showElapsed = 0;
          _rearm();
        }
      }
      return;
    }

    if (!_armed) {
      _inViewElapsed += dt;
      if (_inViewElapsed >= _inViewNeed) {
        _armed = true;
        _delayElapsed = 0;
      }
      return;
    }

    _delayElapsed += dt;
    if (_delayElapsed >= _delayNeed) {
      _autoShow = true;
      _showElapsed = 0;
    }
  }

  void _rearm() {
    _inViewElapsed = 0;
    _delayElapsed = 0;
    _armed = false;
    _rollGates();
  }

  void _resetFeelingCycle() {
    _inViewElapsed = 0;
    _delayElapsed = 0;
    _showElapsed = 0;
    _armed = false;
    _autoShow = false;
    _rollGates();
  }

  void _rollGates() {
    _inViewNeed =
        kFeelingInViewMin + _rng.nextDouble() * (kFeelingInViewMax - kFeelingInViewMin);
    _delayNeed =
        kFeelingDelayMin + _rng.nextDouble() * (kFeelingDelayMax - kFeelingDelayMin);
  }
}
