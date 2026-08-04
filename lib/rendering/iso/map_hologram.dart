import 'package:flutter/material.dart';

import 'iso_coordinate.dart';

/// A single temporary, non-selectable overlay drawn on the map.
///
/// Holograms have a colour and a duration. When [durationSeconds] is > 0 the
/// hologram fades out over the last 30 % of its lifetime and is automatically
/// pruned by the owning [MapHologramManager]. When [durationSeconds] is 0 the
/// hologram is permanent and stays at full opacity until explicitly removed.
class MapHologram {
  MapHologram({
    required this.tile,
    required this.color,
    required this.durationSeconds,
  });

  /// The tile this hologram is drawn on.
  final IsoCoordinate tile;

  /// Base colour (alpha channel is overridden by the fade curve).
  final Color color;

  /// Total lifetime in seconds. 0 = permanent (never expires).
  final double durationSeconds;

  /// Seconds elapsed since the hologram was created.
  double elapsed = 0;

  /// Tile key for efficient lookup ("x:y").
  String get tileKey => '${tile.x}:${tile.y}';

  /// Current opacity (1.0 -> 0.0 over the last 30 % of the duration).
  double get opacity {
    if (durationSeconds <= 0) return 1.0;
    final t = (elapsed / durationSeconds).clamp(0.0, 1.0);
    // Fade-out starts at 70 % of the lifetime.
    if (t < 0.7) return 1.0;
    return 1.0 - ((t - 0.7) / 0.3).clamp(0.0, 1.0);
  }

  /// Whether this hologram has expired.
  bool get isExpired => durationSeconds > 0 && elapsed >= durationSeconds;
}

/// Manages a set of [MapHologram] instances.
///
/// Call [tick] once per frame from the game loop. Expired entries are
/// automatically removed. The [activeOverlays] getter returns a map suitable
/// for passing directly to the painter — tile key -> `Color` with the current
/// fade-out opacity baked into the alpha channel.
class MapHologramManager {
  final Map<String, MapHologram> _holograms = {};

  /// Number of active holograms.
  int get length => _holograms.length;

  /// Whether there are no active holograms.
  bool get isEmpty => _holograms.isEmpty;

  // ---------------------------------------------------------------------------
  // Mutation
  // ---------------------------------------------------------------------------

  /// Add (or replace) a hologram on [tile].
  ///
  /// [color] is the base colour. [duration] is the lifetime in seconds (0 =
  /// permanent).
  void add(IsoCoordinate tile, Color color, {double duration = 3.0}) {
    final h = MapHologram(tile: tile, color: color, durationSeconds: duration);
    _holograms[h.tileKey] = h;
  }

  /// Remove the hologram on [tile], if any.
  void remove(IsoCoordinate tile) {
    _holograms.remove('${tile.x}:${tile.y}');
  }

  /// Remove all holograms.
  void clear() {
    _holograms.clear();
  }

  // ---------------------------------------------------------------------------
  // Game-loop tick
  // ---------------------------------------------------------------------------

  /// Advance all hologram timers by [dt] seconds and prune expired entries.
  void tick(double dt) {
    final expired = <String>[];
    for (final entry in _holograms.entries) {
      entry.value.elapsed += dt;
      if (entry.value.isExpired) {
        expired.add(entry.key);
      }
    }
    for (final key in expired) {
      _holograms.remove(key);
    }
  }

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  /// Returns a map of tile key -> `Color` (with current fade-out opacity
  /// baked into the alpha channel) for all active holograms.
  ///
  /// Pass this directly as the `tileOverlays` parameter of `IsoPainter`.
  Map<String, Color> get activeOverlays {
    if (_holograms.isEmpty) return const {};
    final result = <String, Color>{};
    for (final entry in _holograms.entries) {
      final h = entry.value;
      final a = (h.color.a * h.opacity).clamp(0.0, 1.0);
      result[entry.key] = h.color.withValues(alpha: a);
    }
    return result;
  }
}
