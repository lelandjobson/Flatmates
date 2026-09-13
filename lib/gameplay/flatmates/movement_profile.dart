/// Tunable friend walk: stride, right-lane offset, jank, smoothness, bend speed.
class MovementProfile {
  const MovementProfile({
    required this.id,
    required this.name,
    this.movementTileRatio = 1,
    this.offset = 0,
    this.jank = 0,
    this.jankIntensity = 0.15,
    this.smoothness = 0.65,
    this.bendSlowdown = 0.55,
    this.hopHeight = 0.85,
    this.tileSpeed = 2.5,
    this.startBackup = 0.12,
    this.startSeconds = 0.28,
    this.startTilt = 0.22,
    this.stopSlide = 0.18,
    this.stopSeconds = 0.36,
    this.stopTilt = 0.18,
  });

  /// Hop gait on every tile, slight right lane, light meander.
  static const hop = MovementProfile(
    id: 'hop',
    name: 'Hop',
    offset: 0.35,
    jank: 0.15,
    jankIntensity: 0.2,
    smoothness: 0.7,
    bendSlowdown: 0.55,
    hopHeight: 0.85,
  );

  /// Ground slide, same lane and bend rules, no hop.
  static const slide = MovementProfile(
    id: 'slide',
    name: 'Slide',
    offset: 0.35,
    jank: 0.15,
    jankIntensity: 0.2,
    smoothness: 0.7,
    bendSlowdown: 0.55,
    hopHeight: 0,
  );

  static const List<MovementProfile> presets = [hop, slide];

  final String id;
  final String name;

  /// Stride in tiles. `1` samples every tile; `2` every two tiles; `0.5` twice.
  final double movementTileRatio;

  /// `0` path center, `1` right edge facing forward.
  final double offset;

  /// Chance `0..1` that a knot is laterally perturbed.
  final double jank;

  /// How far jank can move a knot, as a fraction of remaining half-width.
  final double jankIntensity;

  /// `0` polyline through knots, `1` fullest fillets / interpolation.
  final double smoothness;

  /// `0` constant speed, `1` crawl at 90° corners.
  final double bendSlowdown;

  /// Peak hop as a fraction of body size. `0` is a ground slide.
  final double hopHeight;

  /// Travel speed in tiles per second on a straight.
  final double tileSpeed;

  /// How far the body rocks back before launch, in tiles.
  final double startBackup;

  /// Wind-up duration in seconds.
  final double startSeconds;

  /// Forward lean at launch, in radians.
  final double startTilt;

  /// How far the body slides past the stop tile, in tiles.
  final double stopSlide;

  /// Brake-slide duration in seconds.
  final double stopSeconds;

  /// Backward lean while braking, in radians.
  final double stopTilt;

  static MovementProfile byId(String id) {
    for (final preset in presets) {
      if (preset.id == id) return preset;
    }
    return hop;
  }

  MovementProfile copyWith({
    String? id,
    String? name,
    double? movementTileRatio,
    double? offset,
    double? jank,
    double? jankIntensity,
    double? smoothness,
    double? bendSlowdown,
    double? hopHeight,
    double? tileSpeed,
    double? startBackup,
    double? startSeconds,
    double? startTilt,
    double? stopSlide,
    double? stopSeconds,
    double? stopTilt,
  }) {
    return MovementProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      movementTileRatio: movementTileRatio ?? this.movementTileRatio,
      offset: offset ?? this.offset,
      jank: jank ?? this.jank,
      jankIntensity: jankIntensity ?? this.jankIntensity,
      smoothness: smoothness ?? this.smoothness,
      bendSlowdown: bendSlowdown ?? this.bendSlowdown,
      hopHeight: hopHeight ?? this.hopHeight,
      tileSpeed: tileSpeed ?? this.tileSpeed,
      startBackup: startBackup ?? this.startBackup,
      startSeconds: startSeconds ?? this.startSeconds,
      startTilt: startTilt ?? this.startTilt,
      stopSlide: stopSlide ?? this.stopSlide,
      stopSeconds: stopSeconds ?? this.stopSeconds,
      stopTilt: stopTilt ?? this.stopTilt,
    );
  }

  MovementProfile clamped() {
    return MovementProfile(
      id: id,
      name: name,
      movementTileRatio: movementTileRatio.clamp(0.25, 3),
      offset: offset.clamp(0, 1),
      jank: jank.clamp(0, 1),
      jankIntensity: jankIntensity.clamp(0, 1),
      smoothness: smoothness.clamp(0, 1),
      bendSlowdown: bendSlowdown.clamp(0, 1),
      hopHeight: hopHeight.clamp(0, 1),
      tileSpeed: tileSpeed.clamp(0.5, 6),
      startBackup: startBackup.clamp(0, 0.5),
      startSeconds: startSeconds.clamp(0.05, 0.8),
      startTilt: startTilt.clamp(0, 0.45),
      stopSlide: stopSlide.clamp(0, 0.6),
      stopSeconds: stopSeconds.clamp(0.05, 1),
      stopTilt: stopTilt.clamp(0, 0.45),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'movementTileRatio': movementTileRatio,
        'offset': offset,
        'jank': jank,
        'jankIntensity': jankIntensity,
        'smoothness': smoothness,
        'bendSlowdown': bendSlowdown,
        'hopHeight': hopHeight,
        'tileSpeed': tileSpeed,
        'startBackup': startBackup,
        'startSeconds': startSeconds,
        'startTilt': startTilt,
        'stopSlide': stopSlide,
        'stopSeconds': stopSeconds,
        'stopTilt': stopTilt,
      };

  factory MovementProfile.fromJson(Map<String, dynamic> json) {
    double read(String key, double fallback) {
      final value = json[key];
      if (value is num) return value.toDouble();
      return fallback;
    }

    return MovementProfile(
      id: json['id'] as String? ?? 'custom',
      name: json['name'] as String? ?? 'Custom',
      movementTileRatio: read('movementTileRatio', 1),
      offset: read('offset', 0),
      jank: read('jank', 0),
      jankIntensity: read('jankIntensity', 0.15),
      smoothness: read('smoothness', 0.65),
      bendSlowdown: read('bendSlowdown', 0.55),
      hopHeight: read('hopHeight', 0.85),
      tileSpeed: read('tileSpeed', 2.5),
      startBackup: read('startBackup', 0.12),
      startSeconds: read('startSeconds', 0.28),
      startTilt: read('startTilt', 0.22),
      stopSlide: read('stopSlide', 0.18),
      stopSeconds: read('stopSeconds', 0.36),
      stopTilt: read('stopTilt', 0.18),
    ).clamped();
  }

  @override
  bool operator ==(Object other) =>
      other is MovementProfile &&
      other.id == id &&
      other.name == name &&
      other.movementTileRatio == movementTileRatio &&
      other.offset == offset &&
      other.jank == jank &&
      other.jankIntensity == jankIntensity &&
      other.smoothness == smoothness &&
      other.bendSlowdown == bendSlowdown &&
      other.hopHeight == hopHeight &&
      other.tileSpeed == tileSpeed &&
      other.startBackup == startBackup &&
      other.startSeconds == startSeconds &&
      other.startTilt == startTilt &&
      other.stopSlide == stopSlide &&
      other.stopSeconds == stopSeconds &&
      other.stopTilt == stopTilt;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        movementTileRatio,
        offset,
        jank,
        jankIntensity,
        smoothness,
        bendSlowdown,
        hopHeight,
        tileSpeed,
        startBackup,
        startSeconds,
        startTilt,
        stopSlide,
        stopSeconds,
        stopTilt,
      );
}

/// File-safe id from a display name.
String movementProfileSlug(String name) {
  final slug = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'profile' : slug;
}
