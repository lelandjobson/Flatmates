import 'tiles.dart';

/// State of a single tile's cooldown after being gathered from.
class TileCooldownState {
  TileCooldownState({
    required this.materialId,
    required this.cooldownDuration,
  });

  /// The material ID that was gathered (from crafts.json).
  final String materialId;

  /// Total cooldown time in seconds.
  final double cooldownDuration;

  /// Elapsed time since the cooldown started.
  double elapsed = 0.0;

  /// Whether the 100 ms restoration flash has played.
  bool flashPlayed = false;

  /// Normalised progress (0.0 = just gathered, 1.0 = fully restored).
  double get progress => cooldownDuration > 0
      ? (elapsed / cooldownDuration).clamp(0.0, 1.0)
      : 1.0;

  /// True when the cooldown has fully elapsed.
  bool get isComplete => progress >= 1.0;
}

/// Manages per-tile cooldowns after gathering.
///
/// Each tile is keyed by `'$x:$y'` (matching the fog-key pattern used
/// elsewhere). Call [tick] every frame to advance all active cooldowns,
/// and [startCooldown] when a friend finishes gathering from a tile.
class TileCooldownManager {
  TileCooldownManager();

  final Map<String, TileCooldownState> _cooldowns = <String, TileCooldownState>{};

  /// Default cooldown in seconds, used when no material-specific override
  /// exists.
  static const double defaultCooldown = 5.0;

  /// Material-specific cooldown durations (seconds).
  /// Overrides [defaultCooldown] for listed material IDs.
  static final Map<String, double> materialCooldowns = {
    // All materials default to 5 s; add overrides here as needed.
  };

  /// Start a cooldown for the tile at ([x], [y]).
  void startCooldown(int x, int y, String materialId) {
    final key = '$x:$y';
    final duration = materialCooldowns[materialId] ?? defaultCooldown;
    _cooldowns[key] = TileCooldownState(
      materialId: materialId,
      cooldownDuration: duration,
    );
  }

  /// Advance every active cooldown by [dt] seconds.
  ///
  /// Completed cooldowns are removed automatically.
  void tick(double dt) {
    final toRemove = <String>[];
    for (final entry in _cooldowns.entries) {
      entry.value.elapsed += dt;
      if (entry.value.isComplete && entry.value.flashPlayed) {
        toRemove.add(entry.key);
      }
    }
    for (final key in toRemove) {
      _cooldowns.remove(key);
    }
  }

  /// Returns the cooldown state for tile at ([x], [y]), or null if no
  /// active cooldown.
  TileCooldownState? getCooldown(int x, int y) {
    return _cooldowns['$x:$y'];
  }

  /// Whether the tile at ([x], [y]) is currently on cooldown (not
  /// gatherable).
  bool isOnCooldown(int x, int y) {
    final state = _cooldowns['$x:$y'];
    if (state == null) return false;
    return !state.isComplete;
  }

  /// All active cooldown entries, keyed by `'$x:$y'`.
  Map<String, TileCooldownState> get cooldowns =>
      Map.unmodifiable(_cooldowns);

  /// Mark the flash as played for a specific tile.
  void markFlashPlayed(int x, int y) {
    final state = _cooldowns['$x:$y'];
    if (state != null) state.flashPlayed = true;
  }
}
