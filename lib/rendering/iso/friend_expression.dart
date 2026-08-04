import 'dart:convert';

import 'package:flutter/material.dart';
import '../../geometry/prefabs/prefab_factory.dart';

/// 3D eye mesh style for scene rendering and crafting preview.
///
/// Does not affect [IsoVectorGenerator] sprite expression (2D ellipses) unless
/// extended later.
enum FriendEyeGeometry3d {
  sphere,
  cylinder;

  static FriendEyeGeometry3d fromJson(Object? value) {
    if (value is! String) return FriendEyeGeometry3d.sphere;
    switch (value) {
      case 'cylinder':
        return FriendEyeGeometry3d.cylinder;
      case 'sphere':
        return FriendEyeGeometry3d.sphere;
      default:
        return FriendEyeGeometry3d.sphere;
    }
  }

  String toJsonValue() => switch (this) {
        FriendEyeGeometry3d.sphere => 'sphere',
        FriendEyeGeometry3d.cylinder => 'cylinder',
      };
}

/// Configuration for friend "expression" overlays (eyes) rendered into sprites.
///
/// Eye positions are defined in 3D world units relative to the geometry centre.
/// During sprite generation the positions are projected through the same MVP
/// matrix as the geometry, so they rotate naturally with the camera angle.
class FriendExpressionConfig {
  const FriendExpressionConfig({
    required this.eyeHeight,
    required this.eyeSpacing,
    required this.eyeRadiusX,
    required this.eyeRadiusY,
    this.eyeColor = Colors.white,
    this.eyeForwardOffset = 0.0,
    this.eyeGeometry3d = FriendEyeGeometry3d.sphere,
  });

  /// Y offset from geometry centre (world units) – higher = eyes further up.
  final double eyeHeight;

  /// Lateral distance between eye centres (world units).
  final double eyeSpacing;

  /// Horizontal radius of each eye ellipse (world units).
  final double eyeRadiusX;

  /// Vertical radius of each eye ellipse (world units).
  final double eyeRadiusY;

  /// Colour of the eyes (default: white).
  final Color eyeColor;

  /// Forward offset toward camera (world units). Keeps eyes on the front face
  /// and prevents z-fighting / occlusion by the geometry.
  final double eyeForwardOffset;

  /// Mesh style for 3D views (sphere ellipsoid vs capped cylinder along local +Z).
  final FriendEyeGeometry3d eyeGeometry3d;

  // -------------------------------------------------------------------------
  // JSON serialization
  // -------------------------------------------------------------------------

  /// Create a config from a JSON map.
  factory FriendExpressionConfig.fromJson(Map<String, dynamic> json) {
    return FriendExpressionConfig(
      eyeHeight: (json['eyeHeight'] as num).toDouble(),
      eyeSpacing: (json['eyeSpacing'] as num).toDouble(),
      eyeRadiusX: (json['eyeRadiusX'] as num).toDouble(),
      eyeRadiusY: (json['eyeRadiusY'] as num).toDouble(),
      eyeForwardOffset: (json['eyeForwardOffset'] as num?)?.toDouble() ?? 0.0,
      eyeColor: json['eyeColor'] != null
          ? Color(json['eyeColor'] as int)
          : Colors.white,
      eyeGeometry3d: FriendEyeGeometry3d.fromJson(json['eyeGeometry3d']),
    );
  }

  /// Create a config from a JSON string.
  factory FriendExpressionConfig.fromJsonString(String jsonString) {
    return FriendExpressionConfig.fromJson(
      jsonDecode(jsonString) as Map<String, dynamic>,
    );
  }

  /// Serialize to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
    'eyeHeight': eyeHeight,
    'eyeSpacing': eyeSpacing,
    'eyeRadiusX': eyeRadiusX,
    'eyeRadiusY': eyeRadiusY,
    'eyeForwardOffset': eyeForwardOffset,
    'eyeColor': eyeColor.value,
    'eyeGeometry3d': eyeGeometry3d.toJsonValue(),
  };

  /// Serialize to a formatted JSON string.
  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  FriendExpressionConfig copyWith({
    double? eyeHeight,
    double? eyeSpacing,
    double? eyeRadiusX,
    double? eyeRadiusY,
    Color? eyeColor,
    double? eyeForwardOffset,
    FriendEyeGeometry3d? eyeGeometry3d,
  }) {
    return FriendExpressionConfig(
      eyeHeight: eyeHeight ?? this.eyeHeight,
      eyeSpacing: eyeSpacing ?? this.eyeSpacing,
      eyeRadiusX: eyeRadiusX ?? this.eyeRadiusX,
      eyeRadiusY: eyeRadiusY ?? this.eyeRadiusY,
      eyeColor: eyeColor ?? this.eyeColor,
      eyeForwardOffset: eyeForwardOffset ?? this.eyeForwardOffset,
      eyeGeometry3d: eyeGeometry3d ?? this.eyeGeometry3d,
    );
  }

  // -------------------------------------------------------------------------
  // Per-geometry-type defaults
  // -------------------------------------------------------------------------

  static const FriendExpressionConfig cube = FriendExpressionConfig(
    eyeHeight: 35,
    eyeSpacing: 30,
    eyeRadiusX: 8,
    eyeRadiusY: 10,
    eyeForwardOffset: 62,
  );

  static const FriendExpressionConfig frog = FriendExpressionConfig(
    eyeHeight: 100,
    eyeSpacing: 40,
    eyeRadiusX: 10,
    eyeRadiusY: 12,
    eyeForwardOffset: 82,
  );

  static const FriendExpressionConfig cone = FriendExpressionConfig(
    eyeHeight: 80,
    eyeSpacing: 28,
    eyeRadiusX: 7,
    eyeRadiusY: 9,
    eyeForwardOffset: 50,
  );

  /// Defaults keyed by geometry type.
  static const Map<GeometryPrefabs, FriendExpressionConfig> defaults = {
    GeometryPrefabs.cube: cube,
    GeometryPrefabs.frog: frog,
    GeometryPrefabs.cone: cone,
  };

  /// Look up the default config for a geometry type. Returns `null` for
  /// geometry types that have no expression (e.g. house).
  static FriendExpressionConfig? forGeometry(GeometryPrefabs type) =>
      defaults[type];
}

// ---------------------------------------------------------------------------
// Expression state (runtime: type + blink) — shared by 2.5D and 3D
// ---------------------------------------------------------------------------

/// Emotion/expression type for friend faces (eyes, future eyebrows/mouth).
enum ExpressionType {
  neutral,
  smile,
  anger,
  indifference,
  sadness,
  perplexed,
  wow,
}

/// Runtime expression state used by both 2.5D and 3D renderers.
///
/// Layout (eye position, size) comes from [FriendExpressionConfig]; this
/// holds the time-varying state: emotion type and blink openness.
class FriendExpressionState {
  const FriendExpressionState({
    this.expressionType = ExpressionType.neutral,
    this.blinkOpen = 1.0,
    this.gazeOffset = 0.0,
  });

  /// Emotion type (neutral, smile, anger, indifference).
  final ExpressionType expressionType;

  /// Blink openness: 0 = fully closed, 1 = fully open.
  final double blinkOpen;

  /// Horizontal eye gaze: -1 = look left, 0 = center, 1 = look right.
  /// Shifts both eye positions laterally along the mesh's right axis.
  final double gazeOffset;

  FriendExpressionState copyWith({
    ExpressionType? expressionType,
    double? blinkOpen,
    double? gazeOffset,
  }) {
    return FriendExpressionState(
      expressionType: expressionType ?? this.expressionType,
      blinkOpen: blinkOpen ?? this.blinkOpen,
      gazeOffset: gazeOffset ?? this.gazeOffset,
    );
  }

  /// Default state: neutral, eyes open.
  static const FriendExpressionState neutral =
      FriendExpressionState(expressionType: ExpressionType.neutral, blinkOpen: 1.0);
}

/// Squint multipliers (horizontal, vertical) for 3D eye ellipsoids by expression.
/// Used by 2D painter and 3D views so eye shape matches across modes.
(double, double) squintMultipliersForExpression(ExpressionType type) {
  switch (type) {
    case ExpressionType.anger:
      return (1.0, 0.85);
    case ExpressionType.sadness:
      return (1.0, 0.9);
    case ExpressionType.perplexed:
      return (0.7, 0.7);
    case ExpressionType.wow:
      return (0.5, 0.95);
    case ExpressionType.smile:
    case ExpressionType.indifference:
    case ExpressionType.neutral:
      return (1.0, 1.0);
  }
}

// ---------------------------------------------------------------------------
// Expression Registry — globally accessible named collection
// ---------------------------------------------------------------------------

/// A globally accessible registry of named [FriendExpressionConfig] instances.
///
/// Usage:
/// ```dart
/// // Register built-in defaults (called once at startup)
/// ExpressionRegistry.registerDefaults();
///
/// // Register a custom expression from editor-tuned JSON
/// ExpressionRegistry.register('sleepy_cube', FriendExpressionConfig.fromJson({
///   "eyeHeight": 30, "eyeSpacing": 25,
///   "eyeRadiusX": 10, "eyeRadiusY": 5,
///   "eyeForwardOffset": 62
/// }));
///
/// // Look up by name when instantiating a friend
/// final expr = ExpressionRegistry.get('sleepy_cube');
/// ```
class ExpressionRegistry {
  ExpressionRegistry._();

  static final Map<String, FriendExpressionConfig> _entries = {};

  /// All registered expression names (sorted alphabetically).
  static List<String> get names => _entries.keys.toList()..sort();

  /// All registered entries as an unmodifiable map.
  static Map<String, FriendExpressionConfig> get all =>
      Map.unmodifiable(_entries);

  /// Register a named expression config.
  /// Overwrites any existing entry with the same [name].
  static void register(String name, FriendExpressionConfig config) {
    _entries[name] = config;
  }

  /// Remove a named expression. Returns true if it existed.
  static bool remove(String name) => _entries.remove(name) != null;

  /// Look up an expression by name. Returns `null` if not found.
  static FriendExpressionConfig? get(String name) => _entries[name];

  /// Whether a name is already registered.
  static bool contains(String name) => _entries.containsKey(name);

  /// Register all built-in geometry-type defaults under their type name
  /// (e.g. "cube", "frog", "cone").
  static void registerDefaults() {
    for (final entry in FriendExpressionConfig.defaults.entries) {
      _entries[entry.key.name] = entry.value;
    }
  }

  /// Bulk-load expressions from a JSON map of `{ "name": { ...config } }`.
  static void loadFromJsonMap(Map<String, dynamic> map) {
    for (final entry in map.entries) {
      _entries[entry.key] = FriendExpressionConfig.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }
  }

  /// Bulk-load expressions from a JSON string representing a map.
  static void loadFromJsonString(String jsonString) {
    loadFromJsonMap(jsonDecode(jsonString) as Map<String, dynamic>);
  }

  /// Export all registered expressions as a JSON-compatible map.
  static Map<String, dynamic> toJsonMap() => {
    for (final entry in _entries.entries) entry.key: entry.value.toJson(),
  };

  /// Export all registered expressions as a formatted JSON string.
  static String toJsonString() =>
      const JsonEncoder.withIndent('  ').convert(toJsonMap());

  /// Clear all entries.
  static void clear() => _entries.clear();
}
