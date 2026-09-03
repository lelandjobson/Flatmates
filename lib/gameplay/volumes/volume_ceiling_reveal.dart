import 'package:flutter/scheduler.dart';
import 'package:vector_math/vector_math_64.dart';

import '../outlines/outline_edges.dart';
import '../viewers/world_plane.dart';
import 'volume.dart';
import 'volume_content_loader.dart';
import 'volume_store.dart';

/// Hide the focused part's ceiling once closer than this.
const double kVolumeCeilingRevealDistance = 28.5;

/// Restore ceilings once farther than this. Between the two, hold.
const double kVolumeCeilingRestoreDistance = 30;

const Duration kVolumeCeilingFadeDuration = Duration(milliseconds: 320);

/// Tools, picks, and overlays treat a faded face as gone at or below this.
const double kVolumeFeatureHiddenOpacity = 0.15;

/// Distance hysteresis: reveal below 28.5, restore above 30, hold in between.
bool volumeCeilingWantsReveal({
  required double distance,
  required bool currentlyRevealing,
}) {
  if (distance < kVolumeCeilingRevealDistance) return true;
  if (distance > kVolumeCeilingRestoreDistance) return false;
  return currentlyRevealing;
}

class _FadeState {
  double current = 1;
  double target = 1;
}

/// Per-part ceiling opacity driven by zoom, look-at, and content load.
class VolumeCeilingReveal {
  VolumeCeilingReveal({
    required this.loader,
    TickerProvider? vsync,
    this.onChanged,
    this.fadeDuration = kVolumeCeilingFadeDuration,
  }) {
    if (vsync != null && fadeDuration > Duration.zero) {
      _ticker = vsync.createTicker(_onTick);
    }
    loader.addListener(_onLoaderChanged);
  }

  final VolumeContentLoader loader;
  final VoidCallback? onChanged;
  final Duration fadeDuration;

  Ticker? _ticker;
  Duration? _lastElapsed;
  VolumeStore? _volumes;
  Vector3? _lookAt;
  double _distance = 0;
  bool _enabled = true;
  bool _wantsReveal = false;
  VolumePartId? _focus;
  final Map<VolumePartId, _FadeState> _states = {};

  bool get wantsReveal => _wantsReveal;
  VolumePartId? get focus => _focus;

  /// Current ceiling opacities that are not fully opaque.
  Map<VolumePartId, double> get opacities => {
        for (final entry in _states.entries)
          if (entry.value.current < 0.999) entry.key: _renderOpacity(entry.value.current),
      };

  double opacityFor(VolumePartId part) {
    final state = _states[part];
    if (state == null) return 1;
    return _renderOpacity(state.current);
  }

  /// Visibility of a volume face that contextual zoom can hide.
  ///
  /// Roofs follow the ceiling fade. Floors appear only once the interior is
  /// opening. Walls stay fully visible.
  double featureOpacityForFace(int tx, int ty, VolumeFace face) {
    final ceiling = opacityFor(VolumePartId(tx, ty));
    return switch (face) {
      VolumeFace.posY => ceiling,
      VolumeFace.negY => ceiling >= 0.999 ? 0.0 : 1.0,
      VolumeFace.posX ||
      VolumeFace.negX ||
      VolumeFace.posZ ||
      VolumeFace.negZ =>
        1.0,
    };
  }

  /// Visibility of a transform handle. Height follows the ceiling; others stay.
  double featureOpacityForHandle(int tx, int ty, VolumeHandle handle) {
    if (handle == VolumeHandle.posY) {
      return opacityFor(VolumePartId(tx, ty));
    }
    return 1;
  }

  bool hidesFace(int tx, int ty, VolumeFace face) =>
      featureOpacityForFace(tx, ty, face) <= kVolumeFeatureHiddenOpacity;

  bool hidesHandle(int tx, int ty, VolumeHandle handle) =>
      featureOpacityForHandle(tx, ty, handle) <= kVolumeFeatureHiddenOpacity;

  /// Roof-only outline edges fade with that part's ceiling. Wall/roof rims stay.
  double outlineOpacityFor(OutlineEdge edge, VolumeGrid grid) {
    if (edge.faces.isEmpty) return 1;
    if (!edge.faces.every((face) => face.normal.y > 0.85)) return 1;
    final mid = Vector3(
      (edge.a.x + edge.b.x) * 0.5,
      (edge.a.y + edge.b.y) * 0.5,
      (edge.a.z + edge.b.z) * 0.5,
    );
    final tile = grid.tileAtWorld(mid);
    if (tile == null) return 1;
    return opacityFor(VolumePartId(tile.$1, tile.$2));
  }

  void update({
    required VolumeStore volumes,
    required Vector3 lookAt,
    required double distance,
    required bool enabled,
  }) {
    _volumes = volumes;
    _lookAt = lookAt;
    _distance = distance;
    _enabled = enabled;
    _recompute();
  }

  void dispose() {
    loader.removeListener(_onLoaderChanged);
    _ticker?.dispose();
    _ticker = null;
  }

  void _onLoaderChanged() => _recompute();

  void _recompute() {
    final volumes = _volumes;
    final lookAt = _lookAt;
    if (volumes == null || lookAt == null) return;

    final enabled = _enabled;
    _focus = enabled ? VolumePartId.atLookAt(volumes, lookAt) : null;
    _wantsReveal = enabled &&
        volumeCeilingWantsReveal(
          distance: _distance,
          currentlyRevealing: _wantsReveal,
        );

    final focus = _focus;
    final neighbors = focus == null
        ? const <VolumePartId>[]
        : adjacentVolumeParts(
            volumes: volumes,
            origin: focus,
            cursor: lookAt,
          );
    if (_wantsReveal && focus != null) {
      loader.request(focus: focus, neighbors: neighbors);
    }

    final revealable = <VolumePartId>{
      if (_wantsReveal && focus != null) focus,
      if (_wantsReveal) ...neighbors,
    };

    final live = <VolumePartId>{
      for (final volume in volumes.visibleVolumes)
        for (final cell in volume.cells)
          VolumePartId(cell.tx, cell.ty),
    };
    _states.removeWhere((id, _) => !live.contains(id));

    for (final id in live) {
      final target =
          revealable.contains(id) && loader.isLoaded(id) ? 0.0 : 1.0;
      final existing = _states[id];
      if (target >= 0.999 &&
          (existing == null || existing.current >= 0.999)) {
        _states.remove(id);
        continue;
      }
      final state = existing ?? _FadeState();
      state.target = target;
      _states[id] = state;
    }

    if (fadeDuration <= Duration.zero || _ticker == null) {
      var changed = false;
      for (final state in _states.values) {
        if (state.current != state.target) {
          state.current = state.target;
          changed = true;
        }
      }
      _states.removeWhere(
        (id, state) => state.current >= 0.999 && state.target >= 0.999,
      );
      if (changed) onChanged?.call();
      return;
    }

    _ensureTicker();
  }

  void _ensureTicker() {
    final ticker = _ticker;
    if (ticker == null) return;
    final busy = _states.values.any(
      (state) => (state.current - state.target).abs() > 1e-4,
    );
    if (busy && !ticker.isActive) {
      _lastElapsed = null;
      ticker.start();
    } else if (!busy && ticker.isActive) {
      ticker.stop();
      _lastElapsed = null;
    }
  }

  void _onTick(Duration elapsed) {
    final last = _lastElapsed ?? elapsed;
    _lastElapsed = elapsed;
    final dt = (elapsed - last).inMicroseconds / 1e6;
    if (dt <= 0) return;
    final seconds = fadeDuration.inMicroseconds / 1e6;
    final step = seconds <= 0 ? 1.0 : dt / seconds;
    var changed = false;
    for (final state in _states.values) {
      final next = _moveToward(state.current, state.target, step);
      if (next != state.current) {
        state.current = next;
        changed = true;
      }
    }
    _states.removeWhere(
      (id, state) => state.current >= 0.999 && state.target >= 0.999,
    );
    if (changed) onChanged?.call();
    _ensureTicker();
  }
}

double _renderOpacity(double current) {
  if (current <= 0.02) return 0;
  if (current >= 0.98) return 1;
  return current;
}

double _moveToward(double current, double target, double step) {
  if ((target - current).abs() <= step) return target;
  return current + step * (target > current ? 1 : -1);
}
