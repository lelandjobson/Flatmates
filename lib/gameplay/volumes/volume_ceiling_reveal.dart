import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:vector_math/vector_math_64.dart';

import '../outlines/outline_edges.dart';
import '../viewers/world_plane.dart';
import 'volume.dart';
import 'volume_content_loader.dart';
import 'volume_datum.dart';
import 'volume_solid.dart';
import 'volume_store.dart';
import 'volume_wall_cutaway.dart';

/// Hide the focused part's ceiling once closer than this.
const double kVolumeCeilingRevealDistance = 28;

/// Restore ceilings once farther than this. Between the two, hold.
const double kVolumeCeilingRestoreDistance = 32;

/// Click / look-inside zoom: just closer than [kVolumeCeilingRevealDistance].
const double kVolumeLookInsideDistance = 26;

const Duration kVolumeCeilingFadeDuration = Duration(milliseconds: 320);

/// Tools, picks, and overlays treat a faded face as gone at or below this.
const double kVolumeFeatureHiddenOpacity = 0.15;

/// Distance hysteresis: reveal below 28, restore above 32, hold in between.
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
  Vector3? _cameraPosition;
  double _distance = 0;
  bool _enabled = true;
  int _currentDatum = 0;
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
  /// opening. Camera-facing walls fade only on the current datum.
  double featureOpacityForFace(int tx, int ty, VolumeFace face) {
    final ceiling = opacityFor(VolumePartId(tx, ty));
    return switch (face) {
      VolumeFace.posY => ceiling,
      VolumeFace.negY => ceiling >= 0.999 ? 0.0 : 1.0,
      VolumeFace.posX ||
      VolumeFace.negX ||
      VolumeFace.posZ ||
      VolumeFace.negZ =>
        _wallOpacity(tx, ty, face, ceiling),
    };
  }

  /// Visibility of a transform handle. Height follows the ceiling; walls
  /// follow the same cutaway as their face on the current datum.
  double featureOpacityForHandle(int tx, int ty, VolumeHandle handle) {
    if (handle == VolumeHandle.posY) {
      return opacityFor(VolumePartId(tx, ty));
    }
    return featureOpacityForFace(tx, ty, faceForHandle(handle));
  }

  /// True once this tile's roof has started opening (floor becomes visible).
  bool revealsInterior(int tx, int ty) =>
      opacityFor(VolumePartId(tx, ty)) < 0.999;

  bool hidesFace(int tx, int ty, VolumeFace face) =>
      featureOpacityForFace(tx, ty, face) <= kVolumeFeatureHiddenOpacity;

  bool hidesHandle(int tx, int ty, VolumeHandle handle) =>
      featureOpacityForHandle(tx, ty, handle) <= kVolumeFeatureHiddenOpacity;

  /// Roof edges fade with the ceiling. Looking into a tile also hides its
  /// outer wall silhouette, including perimeter edges that sit on the tile
  /// boundary (those would otherwise resolve to the empty neighbor).
  double outlineOpacityFor(OutlineEdge edge, VolumeGrid grid) {
    if (edge.faces.isEmpty) return 1;
    final mid = Vector3(
      (edge.a.x + edge.b.x) * 0.5,
      (edge.a.y + edge.b.y) * 0.5,
      (edge.a.z + edge.b.z) * 0.5,
    );
    var opacity = 1.0;
    var anyVolume = false;
    for (final tile in _outlineTiles(edge, mid, grid)) {
      if (_volumes?.volumeAt(tile.$1, tile.$2) == null) continue;
      anyVolume = true;
      final ceiling = opacityFor(VolumePartId(tile.$1, tile.$2));
      if (ceiling < opacity) opacity = ceiling;
    }
    return anyVolume ? opacity : 1;
  }

  /// Tiles that own [edge]. Perimeter samples are pushed inward so a wall on
  /// x = tileMax still counts as the occupied cell, not the neighbor. Corner
  /// edges combine both face normals so they do not slide onto a diagonal.
  Set<(int, int)> _outlineTiles(
    OutlineEdge edge,
    Vector3 mid,
    VolumeGrid grid,
  ) {
    const inset = 0.25;
    final tiles = <(int, int)>{};
    void add(Vector3 point) {
      final tile = grid.tileAtWorld(point);
      if (tile != null) tiles.add(tile);
    }

    add(mid);
    var ix = 0.0;
    var iy = 0.0;
    var iz = 0.0;
    for (final face in edge.faces) {
      add(face.center);
      add(
        Vector3(
          mid.x - face.normal.x * inset,
          mid.y - face.normal.y * inset,
          mid.z - face.normal.z * inset,
        ),
      );
      ix -= face.normal.x;
      iy -= face.normal.y;
      iz -= face.normal.z;
    }
    final len = math.sqrt(ix * ix + iy * iy + iz * iz);
    if (len > 1e-8) {
      add(
        Vector3(
          mid.x + ix / len * inset,
          mid.y + iy / len * inset,
          mid.z + iz / len * inset,
        ),
      );
    }
    return tiles;
  }

  void update({
    required VolumeStore volumes,
    required Vector3 lookAt,
    required double distance,
    required bool enabled,
    Vector3? cameraPosition,
    int currentDatum = 0,
  }) {
    final cameraMoved = cameraPosition != null &&
        (_cameraPosition == null ||
            _cameraPosition!.distanceToSquared(cameraPosition) > 1e-6);
    _volumes = volumes;
    _lookAt = lookAt;
    _distance = distance;
    _enabled = enabled;
    _cameraPosition = cameraPosition;
    _currentDatum = currentDatum;
    _recompute();
    if (cameraMoved && _states.isNotEmpty) onChanged?.call();
  }

  double _wallOpacity(
    int tx,
    int ty,
    VolumeFace face,
    double ceiling,
  ) {
    final volume = _volumes?.volumeAt(tx, ty);
    if (volume == null ||
        !volumeAtCurrentDatum(
          volumeDatum: volume.datum,
          currentDatum: _currentDatum,
        )) {
      return 1;
    }
    final camera = _cameraPosition;
    final grid = _volumes?.grid;
    if (camera == null || grid == null || ceiling >= 0.999) return 1;
    return wallOpacityForFace(
      face: face,
      camera: camera,
      cellCenter: grid.tileCenter(tx, ty),
      ceilingOpacity: ceiling,
    );
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
      final volume = volumes.volumeAt(id.tx, id.ty);
      final atDatum = volume != null &&
          volumeAtCurrentDatum(
            volumeDatum: volume.datum,
            currentDatum: _currentDatum,
          );
      final target = atDatum &&
              revealable.contains(id) &&
              loader.isLoaded(id)
          ? 0.0
          : 1.0;
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
