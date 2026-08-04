import 'iso_visibility.dart';

/// Tracks per-tile fog overlay opacity and animates transitions.
///
/// Each tile has an overlay opacity between 0.0 (fully visible, no overlay)
/// and [maxFogOpacity] (in fog). When a tile's visibility changes between
/// [TileVisibility.visible] and [TileVisibility.fog], the opacity animates
/// over [fadeDuration].
///
/// Hidden tiles are not tracked — they are simply not rendered.
class FogAnimator {
  FogAnimator({
    this.fadeDuration = const Duration(milliseconds: 400),
    double maxFogOpacity = 0.60,
  }) : _maxFogOpacity = maxFogOpacity;

  /// How long the fade in/out takes.
  final Duration fadeDuration;

  /// Maximum overlay opacity when a tile is in fog.
  /// At 1.0 fog tiles are fully covered and match the hidden-tile background.
  double _maxFogOpacity;
  double get maxFogOpacity => _maxFogOpacity;
  set maxFogOpacity(double value) {
    if (_maxFogOpacity == value) return;
    _maxFogOpacity = value;
    for (final key in _targetOpacity.keys) {
      if (_targetOpacity[key]! > 0) {
        _targetOpacity[key] = value;
      }
    }
  }

  /// Per-tile current opacity (0.0 = visible, maxFogOpacity = full fog).
  final Map<String, double> _currentOpacity = {};

  /// Per-tile target opacity.
  final Map<String, double> _targetOpacity = {};

  /// Previous visibility snapshot so we can detect changes.
  Map<String, TileVisibility> _previousVisibility = {};

  /// Update targets when a new visibility map arrives.
  /// Call this whenever [IsoVisibilityManager.calculateVisibility] produces
  /// a new map.
  void updateVisibility(Map<String, TileVisibility> newVisibility) {
    // Detect tiles whose visibility changed
    final allKeys = <String>{
      ..._previousVisibility.keys,
      ...newVisibility.keys,
    };

    for (final key in allKeys) {
      final oldVis = _previousVisibility[key] ?? TileVisibility.hidden;
      final newVis = newVisibility[key] ?? TileVisibility.hidden;

      if (newVis == TileVisibility.hidden) {
        // Remove tracking for hidden tiles
        _currentOpacity.remove(key);
        _targetOpacity.remove(key);
        continue;
      }

      final target = newVis == TileVisibility.fog ? maxFogOpacity : 0.0;
      _targetOpacity[key] = target;

      // If the tile just appeared (was hidden), snap to target immediately
      if (oldVis == TileVisibility.hidden) {
        _currentOpacity[key] = target;
      } else {
        // Ensure there's a current value to animate from
        _currentOpacity.putIfAbsent(key, () => target);
      }
    }

    _previousVisibility = Map.of(newVisibility);
  }

  /// Advance all animations by [dt] (in seconds).
  /// Returns true if any tile is still animating (caller should keep ticking).
  bool tick(double dt) {
    if (_currentOpacity.isEmpty) return false;

    final fadeSec = fadeDuration.inMilliseconds / 1000.0;
    if (fadeSec <= 0) return false;

    final step = dt / fadeSec; // 0..1 fraction of a full fade per tick
    bool anyAnimating = false;

    for (final key in _currentOpacity.keys.toList()) {
      final target = _targetOpacity[key];
      if (target == null) continue;

      final current = _currentOpacity[key]!;
      if ((current - target).abs() < 0.001) {
        _currentOpacity[key] = target;
        continue;
      }

      anyAnimating = true;
      if (current < target) {
        _currentOpacity[key] = (current + step * maxFogOpacity).clamp(
          0.0,
          target,
        );
      } else {
        _currentOpacity[key] = (current - step * maxFogOpacity).clamp(
          target,
          maxFogOpacity,
        );
      }
    }

    return anyAnimating;
  }

  /// Get the fog overlay opacity for a tile. Returns 0.0 if not tracked.
  double getOpacity(String tileKey) {
    return _currentOpacity[tileKey] ?? 0.0;
  }

  /// Get the full map of current opacities (for passing to the painter).
  Map<String, double> get opacities => _currentOpacity;

  /// Clear all state.
  void clear() {
    _currentOpacity.clear();
    _targetOpacity.clear();
    _previousVisibility.clear();
  }
}
