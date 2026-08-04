import 'package:flutter/foundation.dart';

/// How material icons are drawn on the map (tiles, dropped items, carried).
/// Simplified uses colored circles for performance; emoji uses text emoji.
enum MaterialIconStyle {
  simplified,
  emoji,
}

/// Game settings that control visual and gameplay options.
/// Uses ChangeNotifier for reactive UI updates.
class GameSettings extends ChangeNotifier {
  // ===== Visual Settings =====

  /// Whether to show material emojis on tiles
  bool _showMaterialEmojis = true;
  bool get showMaterialEmojis => _showMaterialEmojis;
  set showMaterialEmojis(bool value) {
    if (_showMaterialEmojis != value) {
      _showMaterialEmojis = value;
      notifyListeners();
    }
  }

  /// How to draw material icons: simplified (colored circles) or emoji.
  /// Simplified is faster and avoids TextPainter/saveLayer per tile.
  MaterialIconStyle _materialIconStyle = MaterialIconStyle.simplified;
  MaterialIconStyle get materialIconStyle => _materialIconStyle;
  set materialIconStyle(MaterialIconStyle value) {
    if (_materialIconStyle != value) {
      _materialIconStyle = value;
      notifyListeners();
    }
  }

  /// Opacity of material emojis (0.0 to 1.0)
  double _materialEmojiOpacity = 0.6;
  double get materialEmojiOpacity => _materialEmojiOpacity;
  set materialEmojiOpacity(double value) {
    if (_materialEmojiOpacity != value) {
      _materialEmojiOpacity = value.clamp(0.0, 1.0);
      notifyListeners();
    }
  }

  /// Opacity of tile fill color (0.0 to 1.0). Default 50%.
  double _tileFillOpacity = 0.5;
  double get tileFillOpacity => _tileFillOpacity;
  set tileFillOpacity(double value) {
    if (_tileFillOpacity != value) {
      _tileFillOpacity = value.clamp(0.0, 1.0);
      notifyListeners();
    }
  }

  /// Opacity of tile material icons (0.0 to 1.0). Default 100%.
  double _tileIconOpacity = 1.0;
  double get tileIconOpacity => _tileIconOpacity;
  set tileIconOpacity(double value) {
    if (_tileIconOpacity != value) {
      _tileIconOpacity = value.clamp(0.0, 1.0);
      notifyListeners();
    }
  }

  /// Whether to show dropped item indicators on tiles
  bool _showDroppedItems = true;
  bool get showDroppedItems => _showDroppedItems;
  set showDroppedItems(bool value) {
    if (_showDroppedItems != value) {
      _showDroppedItems = value;
      notifyListeners();
    }
  }

  /// Whether to show the turn clock widget
  bool _showTurnClock = false;
  bool get showTurnClock => _showTurnClock;
  set showTurnClock(bool value) {
    if (_showTurnClock != value) {
      _showTurnClock = value;
      notifyListeners();
    }
  }

  /// Whether to show gather progress indicators above friends
  bool _showGatherProgress = true;
  bool get showGatherProgress => _showGatherProgress;
  set showGatherProgress(bool value) {
    if (_showGatherProgress != value) {
      _showGatherProgress = value;
      notifyListeners();
    }
  }

  // ===== Fog Settings (2.5D view) =====

  /// Maximum fog overlay opacity (0.0 = no fog, 1.0 = matches hidden tiles).
  double _fogMaxOpacity = 1.0;
  double get fogMaxOpacity => _fogMaxOpacity;
  set fogMaxOpacity(double value) {
    final v = value.clamp(0.0, 1.0);
    if (_fogMaxOpacity != v) {
      _fogMaxOpacity = v;
      notifyListeners();
    }
  }

  // ===== Hatch Settings (2.5D view) =====

  double _hatchOpacity = 1.0;
  double get hatchOpacity => _hatchOpacity;
  set hatchOpacity(double value) {
    final v = value.clamp(0.0, 1.0);
    if (_hatchOpacity != v) {
      _hatchOpacity = v;
      notifyListeners();
    }
  }

  double _hatchBrightness = 0.0;
  double get hatchBrightness => _hatchBrightness;
  set hatchBrightness(double value) {
    final v = value.clamp(0.0, 1.0);
    if (_hatchBrightness != v) {
      _hatchBrightness = v;
      notifyListeners();
    }
  }

  double _hatchScale = 1.0;
  double get hatchScale => _hatchScale;
  set hatchScale(double value) {
    final v = value.clamp(0.1, 5.0);
    if (_hatchScale != v) {
      _hatchScale = v;
      notifyListeners();
    }
  }

  /// Multiplier on base stroke widths (0.5 = halved from original defaults).
  double _hatchStrokeMultiplier = 0.5;
  double get hatchStrokeMultiplier => _hatchStrokeMultiplier;
  set hatchStrokeMultiplier(double value) {
    final v = value.clamp(0.1, 2.0);
    if (_hatchStrokeMultiplier != v) {
      _hatchStrokeMultiplier = v;
      notifyListeners();
    }
  }

  /// Rasterization resolution multiplier for hatch tiles.
  double _hatchPixelRatio = 2.0;
  double get hatchPixelRatio => _hatchPixelRatio;
  set hatchPixelRatio(double value) {
    final v = value.clamp(1.0, 8.0);
    if (_hatchPixelRatio != v) {
      _hatchPixelRatio = v;
      notifyListeners();
    }
  }

  // ===== Terrain Height (2.5D view) =====

  bool _terrainHeightEnabled = false;
  bool get terrainHeightEnabled => _terrainHeightEnabled;
  set terrainHeightEnabled(bool value) {
    if (_terrainHeightEnabled != value) {
      _terrainHeightEnabled = value;
      notifyListeners();
    }
  }

  /// Max pixel displacement at zoom 1.0 (0 = flat, 32 = full height level).
  double _terrainAmplitude = 8.0;
  double get terrainAmplitude => _terrainAmplitude;
  set terrainAmplitude(double value) {
    final v = value.clamp(0.0, 32.0);
    if (_terrainAmplitude != v) {
      _terrainAmplitude = v;
      notifyListeners();
    }
  }

  /// Noise frequency. Lower = larger rolling hills, higher = more rugged.
  double _terrainFrequency = 0.04;
  double get terrainFrequency => _terrainFrequency;
  set terrainFrequency(double value) {
    final v = value.clamp(0.01, 0.2);
    if (_terrainFrequency != v) {
      _terrainFrequency = v;
      notifyListeners();
    }
  }

  // ===== Tilt-Shift Effect (2.5D view) =====

  bool _tiltShiftEnabled = false;
  bool get tiltShiftEnabled => _tiltShiftEnabled;
  set tiltShiftEnabled(bool value) {
    if (_tiltShiftEnabled != value) {
      _tiltShiftEnabled = value;
      notifyListeners();
    }
  }

  double _tiltShiftIntensity = 0.5;
  double get tiltShiftIntensity => _tiltShiftIntensity;
  set tiltShiftIntensity(double value) {
    final v = value.clamp(0.0, 1.0);
    if (_tiltShiftIntensity != v) {
      _tiltShiftIntensity = v;
      notifyListeners();
    }
  }

  double _tiltShiftFocalCenter = 0.5;
  double get tiltShiftFocalCenter => _tiltShiftFocalCenter;
  set tiltShiftFocalCenter(double value) {
    final v = value.clamp(0.0, 1.0);
    if (_tiltShiftFocalCenter != v) {
      _tiltShiftFocalCenter = v;
      notifyListeners();
    }
  }

  double _tiltShiftFocalDepth = 0.35;
  double get tiltShiftFocalDepth => _tiltShiftFocalDepth;
  set tiltShiftFocalDepth(double value) {
    final v = value.clamp(0.0, 1.0);
    if (_tiltShiftFocalDepth != v) {
      _tiltShiftFocalDepth = v;
      notifyListeners();
    }
  }

  double _tiltShiftFeather = 0.3;
  double get tiltShiftFeather => _tiltShiftFeather;
  set tiltShiftFeather(double value) {
    final v = value.clamp(0.0, 1.0);
    if (_tiltShiftFeather != v) {
      _tiltShiftFeather = v;
      notifyListeners();
    }
  }

  // ===== Debug Settings =====

  /// Whether to show debug hit boxes
  bool _showHitBoxes = false;
  bool get showHitBoxes => _showHitBoxes;
  set showHitBoxes(bool value) {
    if (_showHitBoxes != value) {
      _showHitBoxes = value;
      notifyListeners();
    }
  }

  /// Whether to show tile coordinates
  bool _showTileCoordinates = false;
  bool get showTileCoordinates => _showTileCoordinates;
  set showTileCoordinates(bool value) {
    if (_showTileCoordinates != value) {
      _showTileCoordinates = value;
      notifyListeners();
    }
  }

  /// Whether to show friend paths
  bool _showFriendPaths = true;

  /// Whether to show off-screen friend waypoint bubbles
  bool _showFriendWaypoints = true;
  bool get showFriendWaypoints => _showFriendWaypoints;
  set showFriendWaypoints(bool value) {
    if (_showFriendWaypoints != value) {
      _showFriendWaypoints = value;
      notifyListeners();
    }
  }
  bool get showFriendPaths => _showFriendPaths;
  set showFriendPaths(bool value) {
    if (_showFriendPaths != value) {
      _showFriendPaths = value;
      notifyListeners();
    }
  }

  /// When true, friends are tinted with their assigned color at all times
  /// instead of only when selected. Selection no longer forces full opacity.
  bool _showPersistentFriendColors = false;
  bool get showPersistentFriendColors => _showPersistentFriendColors;
  set showPersistentFriendColors(bool value) {
    if (_showPersistentFriendColors != value) {
      _showPersistentFriendColors = value;
      notifyListeners();
    }
  }

  // ===== Camera Follow Settings =====

  /// Whether the camera automatically follows the selected friend.
  bool _followCameraEnabled = true;
  bool get followCameraEnabled => _followCameraEnabled;
  set followCameraEnabled(bool value) {
    if (_followCameraEnabled != value) {
      _followCameraEnabled = value;
      notifyListeners();
    }
  }

  /// Normalized inertia amount (0.0 = tight/responsive, 1.0 = loose/floaty).
  double _followCameraInertia = 0.5;
  double get followCameraInertia => _followCameraInertia;
  set followCameraInertia(double value) {
    final v = value.clamp(0.0, 1.0);
    if (_followCameraInertia != v) {
      _followCameraInertia = v;
      notifyListeners();
    }
  }

  /// Snap-back acceleration (px/s^2) when returning to the follow target
  /// after a rubber-band pan.
  double _followCameraSnapBackAccel = 5000.0;
  double get followCameraSnapBackAccel => _followCameraSnapBackAccel;
  set followCameraSnapBackAccel(double value) {
    final v = value.clamp(1000.0, 20000.0);
    if (_followCameraSnapBackAccel != v) {
      _followCameraSnapBackAccel = v;
      notifyListeners();
    }
  }

  /// Snap-back ease exponent (0.5 = subtle, 1.0 = dramatic, 1.5 = very steep).
  double _followCameraSnapBackEase = 1.0;
  double get followCameraSnapBackEase => _followCameraSnapBackEase;
  set followCameraSnapBackEase(double value) {
    final v = value.clamp(0.5, 1.5);
    if (_followCameraSnapBackEase != v) {
      _followCameraSnapBackEase = v;
      notifyListeners();
    }
  }

  /// Maximum distance (in tiles) the camera can be panned away from the
  /// follow target before rubber-banding stops further movement.
  double _followCameraMaxPanTiles = 3.0;
  double get followCameraMaxPanTiles => _followCameraMaxPanTiles;
  set followCameraMaxPanTiles(double value) {
    final v = value.clamp(1.0, 10.0);
    if (_followCameraMaxPanTiles != v) {
      _followCameraMaxPanTiles = v;
      notifyListeners();
    }
  }

  // ===== Movement Settings =====

  /// Time in seconds for friends to accelerate to (or decelerate from)
  /// full speed at the start/end of a path. Range 0.0–0.3 s.
  double _accelTime = 0.06;
  double get accelTime => _accelTime;
  set accelTime(double value) {
    final v = value.clamp(0.0, 0.3);
    if (_accelTime != v) {
      _accelTime = v;
      notifyListeners();
    }
  }

  // ===== Gameplay Settings =====

  /// Turn duration in seconds
  double _turnDuration = 0.5;
  double get turnDuration => _turnDuration;
  set turnDuration(double value) {
    if (_turnDuration != value) {
      _turnDuration = value.clamp(0.1, 5.0);
      notifyListeners();
    }
  }

  /// Default gather turns (how long to extract materials)
  int _defaultGatherTurns = 3;
  int get defaultGatherTurns => _defaultGatherTurns;
  set defaultGatherTurns(int value) {
    if (_defaultGatherTurns != value) {
      _defaultGatherTurns = value.clamp(1, 10);
      notifyListeners();
    }
  }

  /// Maximum dropped items per tile
  int _maxDroppedItemsPerTile = 100;
  int get maxDroppedItemsPerTile => _maxDroppedItemsPerTile;
  set maxDroppedItemsPerTile(int value) {
    if (_maxDroppedItemsPerTile != value) {
      _maxDroppedItemsPerTile = value.clamp(1, 100);
      notifyListeners();
    }
  }

  // ===== Turn Clock Settings =====

  /// Turns per rotation of the turn clock
  int _turnsPerClockRotation = 4;
  int get turnsPerClockRotation => _turnsPerClockRotation;
  set turnsPerClockRotation(int value) {
    if (_turnsPerClockRotation != value) {
      _turnsPerClockRotation = value.clamp(1, 12);
      notifyListeners();
    }
  }

  /// Whether turn clock uses ticking motion
  bool _turnClockTicking = true;
  bool get turnClockTicking => _turnClockTicking;
  set turnClockTicking(bool value) {
    if (_turnClockTicking != value) {
      _turnClockTicking = value;
      notifyListeners();
    }
  }

  /// Reset all settings to defaults
  void resetToDefaults() {
    _showMaterialEmojis = true;
    _materialIconStyle = MaterialIconStyle.simplified;
    _materialEmojiOpacity = 0.6;
    _tileFillOpacity = 0.5;
    _tileIconOpacity = 1.0;
    _showDroppedItems = true;
    _showTurnClock = false;
    _showGatherProgress = true;
    _fogMaxOpacity = 1.0;
    _hatchOpacity = 1.0;
    _hatchBrightness = 0.0;
    _hatchScale = 1.0;
    _hatchStrokeMultiplier = 0.5;
    _hatchPixelRatio = 2.0;
    _terrainHeightEnabled = false;
    _terrainAmplitude = 8.0;
    _terrainFrequency = 0.04;
    _tiltShiftEnabled = false;
    _tiltShiftIntensity = 0.5;
    _tiltShiftFocalCenter = 0.5;
    _tiltShiftFocalDepth = 0.35;
    _tiltShiftFeather = 0.3;
    _showHitBoxes = false;
    _showTileCoordinates = false;
    _showFriendPaths = true;
    _showFriendWaypoints = true;
    _showPersistentFriendColors = false;
    _followCameraEnabled = true;
    _followCameraInertia = 0.5;
    _followCameraSnapBackAccel = 5000.0;
    _followCameraSnapBackEase = 1.0;
    _followCameraMaxPanTiles = 3.0;
    _accelTime = 0.06;
    _turnDuration = 0.5;
    _defaultGatherTurns = 3;
    _maxDroppedItemsPerTile = 100;
    _turnsPerClockRotation = 4;
    _turnClockTicking = true;
    notifyListeners();
  }

  /// Convert settings to a map (for persistence)
  Map<String, dynamic> toMap() {
    return {
      'showMaterialEmojis': _showMaterialEmojis,
      'materialIconStyle': _materialIconStyle.name,
      'materialEmojiOpacity': _materialEmojiOpacity,
      'tileFillOpacity': _tileFillOpacity,
      'tileIconOpacity': _tileIconOpacity,
      'showDroppedItems': _showDroppedItems,
      'showTurnClock': _showTurnClock,
      'showGatherProgress': _showGatherProgress,
      'fogMaxOpacity': _fogMaxOpacity,
      'hatchOpacity': _hatchOpacity,
      'hatchBrightness': _hatchBrightness,
      'hatchScale': _hatchScale,
      'hatchStrokeMultiplier': _hatchStrokeMultiplier,
      'hatchPixelRatio': _hatchPixelRatio,
      'terrainHeightEnabled': _terrainHeightEnabled,
      'terrainAmplitude': _terrainAmplitude,
      'terrainFrequency': _terrainFrequency,
      'tiltShiftEnabled': _tiltShiftEnabled,
      'tiltShiftIntensity': _tiltShiftIntensity,
      'tiltShiftFocalCenter': _tiltShiftFocalCenter,
      'tiltShiftFocalDepth': _tiltShiftFocalDepth,
      'tiltShiftFeather': _tiltShiftFeather,
      'showHitBoxes': _showHitBoxes,
      'showTileCoordinates': _showTileCoordinates,
      'showFriendPaths': _showFriendPaths,
      'showFriendWaypoints': _showFriendWaypoints,
      'showPersistentFriendColors': _showPersistentFriendColors,
      'followCameraEnabled': _followCameraEnabled,
      'followCameraInertia': _followCameraInertia,
      'followCameraSnapBackAccel': _followCameraSnapBackAccel,
      'followCameraSnapBackEase': _followCameraSnapBackEase,
      'followCameraMaxPanTiles': _followCameraMaxPanTiles,
      'accelTime': _accelTime,
      'turnDuration': _turnDuration,
      'defaultGatherTurns': _defaultGatherTurns,
      'maxDroppedItemsPerTile': _maxDroppedItemsPerTile,
      'turnsPerClockRotation': _turnsPerClockRotation,
      'turnClockTicking': _turnClockTicking,
    };
  }

  /// Load settings from a map
  void loadFromMap(Map<String, dynamic> map) {
    _showMaterialEmojis = map['showMaterialEmojis'] ?? true;
    final styleName = map['materialIconStyle'] as String?;
    _materialIconStyle = styleName == 'emoji'
        ? MaterialIconStyle.emoji
        : MaterialIconStyle.simplified;
    _materialEmojiOpacity = (map['materialEmojiOpacity'] ?? 0.6).toDouble();
    _tileFillOpacity = (map['tileFillOpacity'] ?? 0.5).toDouble();
    _tileIconOpacity = (map['tileIconOpacity'] ?? 1.0).toDouble();
    _showDroppedItems = map['showDroppedItems'] ?? true;
    _showTurnClock = map['showTurnClock'] ?? false;
    _showGatherProgress = map['showGatherProgress'] ?? true;
    _fogMaxOpacity =
        (map['fogMaxOpacity'] ?? 1.0).toDouble().clamp(0.0, 1.0);
    _hatchOpacity = (map['hatchOpacity'] ?? 1.0).toDouble().clamp(0.0, 1.0);
    _hatchBrightness =
        (map['hatchBrightness'] ?? 0.0).toDouble().clamp(0.0, 1.0);
    _hatchScale = (map['hatchScale'] ?? 1.0).toDouble().clamp(0.1, 5.0);
    _hatchStrokeMultiplier =
        (map['hatchStrokeMultiplier'] ?? 0.5).toDouble().clamp(0.1, 2.0);
    _hatchPixelRatio =
        (map['hatchPixelRatio'] ?? 2.0).toDouble().clamp(1.0, 8.0);
    _terrainHeightEnabled = map['terrainHeightEnabled'] ?? false;
    _terrainAmplitude =
        (map['terrainAmplitude'] ?? 8.0).toDouble().clamp(0.0, 32.0);
    _terrainFrequency =
        (map['terrainFrequency'] ?? 0.04).toDouble().clamp(0.01, 0.2);
    _tiltShiftEnabled = map['tiltShiftEnabled'] ?? false;
    _tiltShiftIntensity = (map['tiltShiftIntensity'] ?? 0.5).toDouble();
    _tiltShiftFocalCenter = (map['tiltShiftFocalCenter'] ?? 0.5).toDouble();
    _tiltShiftFocalDepth = (map['tiltShiftFocalDepth'] ?? 0.35).toDouble();
    _tiltShiftFeather = (map['tiltShiftFeather'] ?? 0.3).toDouble();
    _showHitBoxes = map['showHitBoxes'] ?? false;
    _showTileCoordinates = map['showTileCoordinates'] ?? false;
    _showFriendPaths = map['showFriendPaths'] ?? true;
    _showFriendWaypoints = map['showFriendWaypoints'] ?? true;
    _showPersistentFriendColors = map['showPersistentFriendColors'] ?? false;
    _followCameraEnabled = map['followCameraEnabled'] ?? true;
    _followCameraInertia =
        (map['followCameraInertia'] ?? 0.5).toDouble().clamp(0.0, 1.0);
    _followCameraSnapBackAccel =
        (map['followCameraSnapBackAccel'] ?? 5000.0).toDouble().clamp(1000.0, 20000.0);
    _followCameraSnapBackEase =
        (map['followCameraSnapBackEase'] ?? 1.0).toDouble().clamp(0.5, 1.5);
    _followCameraMaxPanTiles =
        (map['followCameraMaxPanTiles'] ?? 3.0).toDouble().clamp(1.0, 10.0);
    _accelTime = (map['accelTime'] ?? 0.06).toDouble().clamp(0.0, 0.3);
    _turnDuration = (map['turnDuration'] ?? 0.5).toDouble();
    _defaultGatherTurns = map['defaultGatherTurns'] ?? 3;
    _maxDroppedItemsPerTile = map['maxDroppedItemsPerTile'] ?? 100;
    _turnsPerClockRotation = map['turnsPerClockRotation'] ?? 4;
    _turnClockTicking = map['turnClockTicking'] ?? true;
    notifyListeners();
  }
}
