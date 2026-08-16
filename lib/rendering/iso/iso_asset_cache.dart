import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'friend_expression.dart';
import 'iso_asset.dart';
import '../../data/asset_database.dart';
import '../../data/placed_asset_database.dart' show AssetTypeId;

/// Cache for converted isometric assets
///
/// Memoizes the conversion from AssetDefinition → IsoAsset
/// to avoid regenerating sprites for the same asset type
class IsoAssetCache {
  IsoAssetCache({
    required IsoAssetLoader assetLoader,
    required AssetDatabase assetDatabase,
  }) : _assetLoader = assetLoader,
       _assetDatabase = assetDatabase;

  final IsoAssetLoader _assetLoader;
  final AssetDatabase _assetDatabase;

  /// Cache: typeId → converted IsoAsset
  final Map<AssetTypeId, IsoAsset> _cache = {};

  /// Pending conversions to avoid duplicate work
  final Map<AssetTypeId, Completer<IsoAsset?>> _pending = {};

  /// Get cached asset count
  int get cacheSize => _cache.length;

  /// Check if asset is cached
  bool isCached(AssetTypeId typeId) {
    return _cache.containsKey(typeId);
  }

  /// Get or create an IsoAsset from its type ID
  ///
  /// Flow:
  /// 1. Check cache - return if exists
  /// 2. Check if already converting - wait for that
  /// 3. Fetch definition from AssetDatabase
  /// 4. Convert to IsoAsset using IsoAssetLoader
  /// 5. Cache and return
  Future<IsoAsset?> getOrCreateAsset(AssetTypeId typeId) async {
    // Check cache first
    if (_cache.containsKey(typeId)) {
      return _cache[typeId];
    }

    // Check if already pending
    if (_pending.containsKey(typeId)) {
      return await _pending[typeId]!.future;
    }

    // Start conversion
    final completer = Completer<IsoAsset?>();
    _pending[typeId] = completer;

    try {
      // Get asset definition
      final definition = await _assetDatabase.getAssetDefinition(typeId);
      if (definition == null) {
        if (kDebugMode) debugPrint('Asset type not found: $typeId');
        completer.complete(null);
        return null;
      }

      // Convert based on source type
      final asset = await _convertDefinitionToAsset(definition);

      if (asset != null) {
        // Cache the result
        _cache[typeId] = asset;
        completer.complete(asset);
        return asset;
      } else {
        if (kDebugMode) debugPrint('Failed to convert asset: ${definition.name}');
        completer.complete(null);
        return null;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Error creating asset $typeId: $e');
      completer.completeError(e);
      return null;
    } finally {
      _pending.remove(typeId);
    }
  }

  /// Convert an AssetDefinition to an IsoAsset
  Future<IsoAsset?> _convertDefinitionToAsset(
    AssetDefinition definition,
  ) async {
    switch (definition.sourceType) {
      case AssetSourceType.geometry:
        if (definition.prefab == null) {
          return null;
        }
        if (definition.generateAnimationViews) {
          final expression = FriendExpressionConfig.forGeometry(
            definition.prefab!,
          );
          return await _assetLoader.generateVectorFromGeometryWithAnimViews(
            definition.name,
            definition.prefab!,
            color: definition.color ?? Colors.white,
            scale: definition.scale,
            expression: expression,
            facingSpriteCount: definition.facingSpriteCount,
            meshRotationOffsetDeg: definition.meshRotationOffsetDeg,
          );
        }
        if (definition.generateAllViews) {
          return await _assetLoader.generateVectorFromGeometryWithAllViews(
            definition.name,
            definition.prefab!,
            color: definition.color ?? Colors.white,
            scale: definition.scale,
          );
        }
        return await _assetLoader.generateVectorFromGeometry(
          definition.name,
          definition.prefab!,
          color: definition.color ?? Colors.white,
          scale: definition.scale,
        );

      case AssetSourceType.image:
        if (kDebugMode) {
          debugPrint(
            'Image loading not yet implemented for: ${definition.imagePath}',
          );
        }
        return null;

      case AssetSourceType.placeholder:
        return await _assetLoader.generatePlaceholder(
          definition.name,
          color: definition.color ?? Colors.blue,
        );

      case AssetSourceType.obj:
        if (definition.objAssetPath == null) {
          if (kDebugMode) {
            debugPrint('OBJ asset path is null for: ${definition.name}');
          }
          return null;
        }
        return await _assetLoader.generateFromObj(
          definition.name,
          definition.objAssetPath!,
          color: definition.color ?? Colors.white,
          scale: definition.scale,
          generateAllViews: definition.generateAllViews,
        );
    }
  }

  /// Get or create a rotatable variant of a structure asset with facing sprite
  /// rings (16 facing directions x 8 camera views = 128 sprites by default).
  ///
  /// Cached under a separate key (`typeId_rot<count>`) so it doesn't evict
  /// the normal structure asset.
  Future<IsoAsset?> getOrCreateRotatableAsset(
    AssetTypeId typeId, {
    int facingSpriteCount = 16,
  }) async {
    final rotKey = '${typeId}_rot$facingSpriteCount';

    if (_cache.containsKey(rotKey)) {
      return _cache[rotKey];
    }

    if (_pending.containsKey(rotKey)) {
      return await _pending[rotKey]!.future;
    }

    final completer = Completer<IsoAsset?>();
    _pending[rotKey] = completer;

    try {
      final definition = await _assetDatabase.getAssetDefinition(typeId);
      if (definition == null || definition.prefab == null) {
        completer.complete(null);
        return null;
      }

      final asset =
          await _assetLoader.generateVectorFromGeometryWithAnimViews(
        '${definition.name}_rot$facingSpriteCount',
        definition.prefab!,
        color: definition.color ?? Colors.white,
        scale: definition.scale,
        facingSpriteCount: facingSpriteCount,
      );

      _cache[rotKey] = asset;
      completer.complete(asset);
      return asset;
    } catch (e) {
      if (kDebugMode) debugPrint('Error creating rotatable asset $typeId: $e');
      completer.completeError(e);
      return null;
    } finally {
      _pending.remove(rotKey);
    }
  }

  /// Synchronously retrieve a previously cached asset (returns null if not yet loaded).
  IsoAsset? getCachedAsset(AssetTypeId typeId) => _cache[typeId];

  /// Preload multiple assets
  Future<void> preloadAssets(List<AssetTypeId> typeIds) async {
    await Future.wait(typeIds.map((typeId) => getOrCreateAsset(typeId)));
  }

  /// Clear a specific asset from cache
  void evict(AssetTypeId typeId) {
    _cache.remove(typeId);
    // TODO: Dispose asset resources if needed
  }

  /// Clear entire cache
  void clear() {
    // TODO: Dispose asset resources if needed
    _cache.clear();
    _pending.clear();
  }

  /// Get cache statistics
  CacheStats get stats {
    return CacheStats(cached: _cache.length, pending: _pending.length);
  }
}

/// Cache statistics
class CacheStats {
  const CacheStats({required this.cached, required this.pending});

  final int cached;
  final int pending;

  @override
  String toString() => 'CacheStats(cached: $cached, pending: $pending)';
}
