import 'dart:async';
import 'package:flutter/material.dart';
import '../geometry/prefabs/prefab_factory.dart';
import '../rendering/iso/path_geometry.dart';
import 'placed_asset_database.dart' show AssetTypeId;

/// Category of asset for rendering order and behavior
enum AssetCategory {
  /// Structure (houses, buildings, etc.)
  structure,

  /// Decorative element
  decoration,

  /// Path-affecting asset (renders after paths but before regular assets)
  pathAsset,

  /// Decoration tied to a tile's material (e.g. trees on lumber tiles).
  /// Opacity is governed by zoom-domain render guidelines.
  ingredientDecoration,

  /// Foliage placed independently of tiles (trees, bushes, etc.).
  /// Hit-tested using bounding box rather than outline polygon.
  foliage,
}

/// Asset definition - describes HOW to create an asset
class AssetDefinition {
  AssetDefinition({
    required this.typeId,
    required this.name,
    required this.sourceType,
    this.category = AssetCategory.structure,
    this.prefab,
    this.imagePath,
    this.objAssetPath,
    this.color,
    this.scale = 1.0,
    this.customPathGeometry,
    this.metadata = const {},
    this.generateAnimationViews = false,
    this.generateAllViews = false,
    this.facingSpriteCount = 16,
    this.meshRotationOffsetDeg = 0.0,
  });

  /// Unique type identifier (UUID)
  final AssetTypeId typeId;

  /// Human-readable name
  final String name;

  /// How to create this asset
  final AssetSourceType sourceType;

  /// Category for rendering order
  final AssetCategory category;

  /// For geometry-based assets
  final GeometryPrefabs? prefab;

  /// For image-based assets
  final String? imagePath;

  /// For OBJ model assets (e.g. "assets/models/house_foo/steps/1.obj")
  final String? objAssetPath;

  /// Optional color override
  final Color? color;

  /// Scale factor for rendering (1.0 = normal size, 0.5 = half size)
  final double scale;

  /// Custom path geometry for path assets
  final PathSegmentGeometry? customPathGeometry;

  /// Additional metadata
  final Map<String, dynamic> metadata;

  /// When true, the asset cache generates 16-angle animation sprites
  /// (with eyes if the geometry has an expression config).
  final bool generateAnimationViews;

  /// When true, the asset cache generates 16-angle view sprites for all
  /// camera directions. Use for structures that need correct intermediate-
  /// angle rendering without the full 256-sprite rotation grid.
  final bool generateAllViews;

  /// Number of facing direction sprites to generate when
  /// [generateAnimationViews] is true. Must be a multiple of 4.
  /// Default is 16 (22.5-degree increments).
  final int facingSpriteCount;

  /// Constant Y-axis rotation offset (degrees) baked into every facing sprite.
  /// Prevents flat-on views for planar geometries like trees.
  final double meshRotationOffsetDeg;
}

/// How an asset should be created
enum AssetSourceType {
  /// Generated from 3D geometry
  geometry,

  /// Loaded from image file
  image,

  /// Generated placeholder
  placeholder,

  /// Loaded from a Wavefront OBJ model file
  obj,
}

/// Database of asset type definitions
///
/// Maps typeId → asset definition (HOW to create it)
/// Does NOT store instances or positions
class AssetDatabase {
  AssetDatabase();

  /// Asset type definitions
  final Map<AssetTypeId, AssetDefinition> _definitions = {};

  /// Get asset count
  int get count => _definitions.length;

  /// Get all type IDs
  Iterable<AssetTypeId> get typeIds => _definitions.keys;

  /// Register a new asset type
  Future<void> registerAssetType(AssetDefinition definition) async {
    await Future.delayed(Duration.zero);
    _definitions[definition.typeId] = definition;
  }

  /// Get asset definition by type ID
  Future<AssetDefinition?> getAssetDefinition(AssetTypeId typeId) async {
    await Future.delayed(Duration.zero);
    return _definitions[typeId];
  }

  /// Synchronous variant of [getAssetDefinition] for use in tight loops
  /// where the definitions are known to be pre-loaded.
  AssetDefinition? getAssetDefinitionSync(AssetTypeId typeId) {
    return _definitions[typeId];
  }

  /// Check if asset type exists
  bool hasAssetType(AssetTypeId typeId) {
    return _definitions.containsKey(typeId);
  }

  /// Remove asset type
  Future<bool> removeAssetType(AssetTypeId typeId) async {
    await Future.delayed(Duration.zero);
    return _definitions.remove(typeId) != null;
  }

  /// Get all definitions
  Future<List<AssetDefinition>> getAllDefinitions() async {
    await Future.delayed(Duration.zero);
    return _definitions.values.toList();
  }

  /// Clear all definitions
  Future<void> clear() async {
    await Future.delayed(Duration.zero);
    _definitions.clear();
  }
}
