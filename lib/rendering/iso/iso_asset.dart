import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../geometry/obj_parser.dart';
import '../../geometry/prefabs/prefab_factory.dart';
import '../../geometry/geometry.dart';
import '../../tiles/tiles.dart';
import '../../rendering/mesh.dart';
import '../../rendering/scene/scene.dart';
import '../../rendering/scene/camera.dart' as scene_camera;
import '../../rendering/lights.dart';
import 'facing_sprite_ring.dart';
import 'expression_painter_2d.dart';
import 'friend_expression.dart';
import 'iso_camera.dart';
import '../../data/asset_database.dart' show AssetCategory;
import 'iso_coordinate.dart';
import 'iso_projection.dart';
import 'iso_sprite.dart';
import 'iso_vector_generator.dart';
import '../../geometry/geometry_slicer.dart' show kSpriteGridSize;

/// An asset with 4 precomputed sprite views for axonometric rendering,
/// and optionally facing sprite rings for smooth rotation animation.
class IsoAsset {
  const IsoAsset({
    required this.id,
    required this.sprites,
    this.viewSprites,
    this.facingSprites,
    this.expressionFacingSprites,
    this.expressionViewSprites,
    this.anchorOffset = Offset.zero,
    this.scale = 1.0,
  }) : assert(
         sprites.length == 4,
         'Must have exactly 4 sprites (NW, SW, SE, NE)',
       );

  final String id;

  /// Sprites for 4 cardinal views: [NW (0), SW (1), SE (2), NE (3)]
  final List<IsoSprite> sprites;

  /// Optional view sprites (one per camera angle, no mesh rotation).
  ///
  /// When present, [getSpriteForView] uses this for accurate intermediate-
  /// angle rendering of structures and other non-rotating assets.
  /// Length matches the world view count used during generation.
  ///
  /// When null, [getSpriteForView] falls back to [sprites] via
  /// [nearestCardinalIndex].
  final List<IsoSprite>? viewSprites;

  /// Optional facing sprite rings, indexed by world view.
  ///
  /// `facingSprites[worldViewIndex].getNearest(facingAngleDeg)` returns the
  /// best sprite for a given camera angle and facing direction.
  /// Length matches the world view count used during generation.
  ///
  /// When null, rendering falls back to [viewSprites] or cardinal [sprites].
  final List<FacingSpriteRing>? facingSprites;

  // -- Expression (eyes) sprites, rendered separately for independent opacity --

  /// Expression-only facing sprite rings (one per world view).
  /// Null when the asset has no expression.
  final List<FacingSpriteRing>? expressionFacingSprites;

  /// Expression-only view sprites (one per camera angle, no rotation).
  /// Null when the asset has no expression.
  final List<IsoSprite>? expressionViewSprites;

  /// Offset within tile bounding box (normalized 0-1)
  final Offset anchorOffset;

  /// Scale factor for rendering
  final double scale;

  /// Compute the sprite top-left so that the projected ground-contact
  /// point of the 3D geometry (bottom-face centroid) sits exactly at
  /// [tileCenter].  The [sprite]'s per-view [IsoSprite.groundPoint] is
  /// used when available; otherwise falls back to centre-alignment.
  /// Wrap [asset] for map-tile craft placement: same OBJ view sprites as
  /// structures in [TileFriendDisplayView], but drawn smaller as a tile prop.
  factory IsoAsset.forCraftPlacement(IsoAsset asset) {
    return IsoAsset(
      id: '${asset.id}@craft',
      sprites: asset.sprites,
      viewSprites: asset.viewSprites,
      scale: asset.scale * IsoProjection.craftMapDisplayScale,
      anchorOffset: asset.anchorOffset,
    );
  }

  static Offset anchoredTopLeft(
    Offset tileCenter,
    double spriteWidth,
    double spriteHeight,
    IsoSprite sprite,
  ) {
    final gp = sprite.groundPoint;
    if (gp == null) {
      return Offset(
        tileCenter.dx - spriteWidth / 2,
        tileCenter.dy - spriteHeight / 2,
      );
    }
    final scaleX = spriteWidth / sprite.size.width;
    final scaleY = spriteHeight / sprite.size.height;
    return Offset(
      tileCenter.dx - gp.dx * scaleX,
      tileCenter.dy - gp.dy * scaleY,
    );
  }

  /// Whether this asset has facing sprite rings for rotation animation.
  bool get hasFacingSprites => facingSprites != null;

  /// Whether this asset has view sprites for intermediate angles.
  bool get hasViewSprites => viewSprites != null;

  /// Whether this asset has separate expression sprites.
  bool get hasExpressionSprites => expressionFacingSprites != null;

  /// Get sprite for current camera view (no facing direction).
  ///
  /// Priority:
  /// 1. [viewSprites] — uses the world view index for exact intermediate
  ///    rendering (for structures at all view directions).
  /// 2. [sprites] — falls back to nearest cardinal via [nearestCardinalIndex].
  ///
  /// [rotationOffset] adds 90-degree increments (0-3) to the selection.
  IsoSprite getSpriteForView(IsoViewDirection view, {int rotationOffset = 0}) {
    if (viewSprites != null) {
      final viewCount = viewSprites!.length;
      // Map from enum index to view sprite index proportionally
      final viewIdx = view.index * viewCount ~/ IsoViewDirection.values.length;
      // rotationOffset is in 90-degree increments; each 90° = viewCount/4 steps
      final rotStep = viewCount ~/ 4;
      final rotatedIndex = (viewIdx + rotationOffset * rotStep) % viewCount;
      return viewSprites![rotatedIndex];
    }
    final cardinalIndex = view.nearestCardinalIndex;
    final rotatedIndex = (cardinalIndex + rotationOffset) % 4;
    return sprites[rotatedIndex];
  }

  /// Get sprite by world view index and continuous facing angle in degrees.
  ///
  /// If [facingSprites] is available, looks up the nearest facing sprite
  /// from the [FacingSpriteRing] for that world view. Otherwise falls back
  /// to [viewSprites] or the nearest cardinal sprite.
  IsoSprite getSpriteForFacing(int worldViewIndex, double facingAngleDeg) {
    if (facingSprites != null) {
      final ring = facingSprites![worldViewIndex % facingSprites!.length];
      return ring.getNearest(facingAngleDeg);
    }
    if (viewSprites != null) {
      return viewSprites![worldViewIndex % viewSprites!.length];
    }
    // Fallback: nearest cardinal sprite
    final viewCount = IsoViewDirection.values.length;
    final cardIdx = ((worldViewIndex * 4 + viewCount ~/ 2) ~/ viewCount) % 4;
    return sprites[cardIdx];
  }

  /// Get the sprite for rendering this asset instance. Used when drawing
  /// selection wireframes, hit testing, and edge extraction. Respects
  /// [instance.facingAngleDeg] when the asset has facing sprites, so the
  /// selection geometry matches the friend's current orientation (e.g.
  /// diagonal movement).
  IsoSprite getSpriteForInstance(IsoAssetInstance instance, IsoCamera camera) {
    if (instance.facingAngleDeg != null && hasFacingSprites) {
      return getSpriteForFacing(
        camera.worldViewIndex,
        instance.facingAngleDeg!,
      );
    }
    return getSpriteForView(
      camera.view,
      rotationOffset: instance.rotationOffset,
    );
  }

  /// Get the expression-only sprite for a world view and facing angle.
  /// Returns null if this asset has no expression sprites.
  IsoSprite? getExpressionSpriteForFacing(
    int worldViewIndex,
    double facingAngleDeg,
  ) {
    if (expressionFacingSprites == null) return null;
    final ring =
        expressionFacingSprites![worldViewIndex %
            expressionFacingSprites!.length];
    return ring.getNearest(facingAngleDeg);
  }

  /// Draw asset at tile position
  void draw(
    Canvas canvas,
    IsoCoordinate coord,
    IsoCamera camera,
    Size viewport, {
    Paint? paint,
    int rotationOffset = 0,
    double customRotation = 0.0,
    double? facingAngleDeg,
    SpriteLayer layer = SpriteLayer.combined,
  }) {
    drawAtFractional(
      canvas,
      coord.x.toDouble(),
      coord.y.toDouble(),
      coord.h,
      camera,
      viewport,
      paint: paint,
      rotationOffset: rotationOffset,
      customRotation: customRotation,
      facingAngleDeg: facingAngleDeg,
      layer: layer,
    );
  }

  /// Draw asset at fractional coordinates (for smooth animation).
  ///
  /// When [facingAngleDeg] is non-null, the facing sprite ring system is
  /// used. The world view index is derived from [camera.worldViewIndex].
  void drawAtFractional(
    Canvas canvas,
    double x,
    double y,
    int h,
    IsoCamera camera,
    Size viewport, {
    Paint? paint,
    int rotationOffset = 0,
    double customRotation = 0.0,
    double? facingAngleDeg,
    SpriteLayer layer = SpriteLayer.combined,
  }) {
    final IsoSprite sprite;
    if (facingAngleDeg != null) {
      sprite = getSpriteForFacing(camera.worldViewIndex, facingAngleDeg);
    } else {
      sprite = getSpriteForView(camera.view, rotationOffset: rotationOffset);
    }

    // Get screen position using fractional coordinates
    final isoPos = IsoProjection.isoToScreen(
      x,
      y,
      viewIndex: camera.view.index,
    );

    // Apply height offset
    final heightOffset = h * IsoProjection.heightPerLevel;
    final worldPos = Offset(isoPos.dx, isoPos.dy - heightOffset);

    // Transform through camera
    final tileCenter = camera.worldToScreen(worldPos, viewport);

    // Calculate sprite dimensions
    final spriteWidth = sprite.size.width * scale * camera.zoom;
    final spriteHeight = sprite.size.height * scale * camera.zoom;

    final topLeft = IsoAsset.anchoredTopLeft(
        tileCenter, spriteWidth, spriteHeight, sprite);
    final dstRect =
        Rect.fromLTWH(topLeft.dx, topLeft.dy, spriteWidth, spriteHeight);

    // Apply custom rotation if specified
    if (customRotation != 0.0) {
      canvas.save();
      canvas.translate(tileCenter.dx, tileCenter.dy);
      canvas.rotate(customRotation);
      canvas.translate(-tileCenter.dx, -tileCenter.dy);
      _drawSpriteLayer(sprite, canvas, dstRect, paint, layer,
          camera.view.index);
      canvas.restore();
    } else {
      _drawSpriteLayer(sprite, canvas, dstRect, paint, layer,
          camera.view.index);
    }
  }

  static void _drawSpriteLayer(
      IsoSprite sprite, Canvas canvas, Rect dst, Paint? paint,
      SpriteLayer layer, int viewIndex) {
    switch (layer) {
      case SpriteLayer.combined:
        sprite.draw(canvas, dst, paint);
      case SpriteLayer.background:
        sprite.drawBackground(canvas, dst, paint, viewIndex: viewIndex);
      case SpriteLayer.foreground:
        sprite.drawForeground(canvas, dst, paint, viewIndex: viewIndex);
    }
  }

  /// Draw the structure with grid cells interleaved with friends by depth.
  ///
  /// Sets up the same canvas transforms as [drawAtFractional] then delegates
  /// to [IsoSprite.drawInterleaved]. [friends] must be pre-sorted ascending
  /// by depth.
  void drawInterleaved(
    Canvas canvas,
    double x,
    double y,
    int h,
    IsoCamera camera,
    Size viewport,
    List<(double, VoidCallback)> friends, {
    Paint? paint,
    int rotationOffset = 0,
  }) {
    final sprite = getSpriteForView(camera.view, rotationOffset: rotationOffset);
    final isoPos = IsoProjection.isoToScreen(x, y, viewIndex: camera.view.index);
    final heightOffset = h * IsoProjection.heightPerLevel;
    final worldPos = Offset(isoPos.dx, isoPos.dy - heightOffset);
    final tileCenter = camera.worldToScreen(worldPos, viewport);
    final spriteWidth = sprite.size.width * scale * camera.zoom;
    final spriteHeight = sprite.size.height * scale * camera.zoom;
    final topLeft = IsoAsset.anchoredTopLeft(
        tileCenter, spriteWidth, spriteHeight, sprite);
    final dstRect =
        Rect.fromLTWH(topLeft.dx, topLeft.dy, spriteWidth, spriteHeight);
    sprite.drawInterleaved(canvas, dstRect, paint, friends,
        viewIndex: camera.view.index);
  }
}

/// Instance of an asset placed at a specific coordinate
class IsoAssetInstance {
  const IsoAssetInstance({
    required this.asset,
    required this.coordinate,
    this.tint,
    this.viewRadius = 1,
    this.rotationOffset = 0,
    this.opacity = 1.0,
    this.expressionOpacity = 1.0,
    this.fractionalX,
    this.fractionalY,
    this.customRotation = 0.0,
    this.facingAngleDeg,
    this.tag,
    this.carriedMaterial,
    this.gatherProgress = 0.0,
    this.milkyFillOpacity = 0.0,
    this.expressionConfig,
    this.expressionState,
    this.verticalOffset = 0.0,
    this.expressionRotationFlipped = false,
    this.skipHitTest = false,
    this.category,
  });

  final IsoAsset asset;
  final IsoCoordinate coordinate;
  final Color? tint;
  final int viewRadius;

  /// Optional stable identifier for tracking this instance across frames
  /// (e.g., a friend ID so the selection wireframe follows during movement).
  final String? tag;

  /// Material ID currently carried by this entity (from crafts.json).
  final String? carriedMaterial;

  /// Gathering progress (0.0 = not gathering, 1.0 = fully gathered).
  /// Used by the painter to draw the captured emoji with appropriate opacity.
  final double gatherProgress;

  /// Opacity for the milky fill behind the carried material icon.
  /// Only used when carrying (post-gather); fades in over ~200ms after gather completes.
  final double milkyFillOpacity;

  /// Rotation offset in 90-degree increments (0-3)
  /// Added to camera view index when selecting sprite
  final int rotationOffset;

  /// Opacity for the base geometry sprite (0.0-1.0)
  final double opacity;

  /// Opacity for the expression (eyes) sprite layer (0.0-1.0).
  /// Independent of [opacity] so expressions can be fully opaque on a
  /// translucent body.
  final double expressionOpacity;

  /// When non-null with [expressionState], eyes are drawn in a runtime
  /// vector pass instead of the baked expression sprite.
  final FriendExpressionConfig? expressionConfig;

  /// Runtime expression state (blink, type). When non-null with
  /// [expressionConfig], [ExpressionPainter2D] is used for the eyes.
  final FriendExpressionState? expressionState;

  /// Vertical offset in world units (e.g. for hop). Positive = up.
  /// Applied in both 2D (screen Y) and when used by 3D (position.y).
  final double verticalOffset;

  /// When true, expression (eyes) rotation is negated so it matches the body.
  /// Used for cone geometry where 2.5D sprite rotation is opposite to expression.
  final bool expressionRotationFlipped;

  /// Optional fractional X coordinate for smooth animation (overrides coordinate.x for rendering)
  final double? fractionalX;

  /// Optional fractional Y coordinate for smooth animation (overrides coordinate.y for rendering)
  final double? fractionalY;

  /// Custom rotation in radians for smooth animation (e.g., gather animation)
  /// Applied in addition to rotationOffset
  final double customRotation;

  /// When non-null, selects the sprite from the facing sprite ring system.
  /// Continuous angle in degrees: 0 = north, 90 = east, 180 = south, 270 = west.
  final double? facingAngleDeg;

  /// When true, hit testing skips this instance (e.g. ingredient decorations).
  final bool skipHitTest;

  /// Optional asset category for category-specific behavior (e.g. bounding-box
  /// hit testing for foliage).
  final AssetCategory? category;

  /// Get depth for rendering order (view-independent, use with getDepthForView)
  /// Assets render slightly above tiles at the same coordinate
  double get depth => coordinate.depth + 0.0001;

  /// Get depth for rendering order based on camera view
  /// Assets render slightly above tiles at the same coordinate
  double getDepthForView(IsoViewDirection view) {
    return coordinate.getDepthForView(view) + 0.0001;
  }

  /// Convert to screen position, using fractional coords when present
  /// (so selection follows friends during movement).
  Offset toScreen(IsoCamera camera, Size viewport) {
    final x = fractionalX ?? coordinate.x.toDouble();
    final y = fractionalY ?? coordinate.y.toDouble();
    final isoPos = IsoProjection.isoToScreen(
      x,
      y,
      viewIndex: camera.view.index,
    );
    final heightOffset = coordinate.h * IsoProjection.heightPerLevel;
    final worldPos = Offset(isoPos.dx, isoPos.dy - heightOffset);
    return camera.worldToScreen(worldPos, viewport);
  }

  /// Creates a copy with modified opacity
  IsoAssetInstance withOpacity(double newOpacity) {
    return IsoAssetInstance(
      asset: asset,
      coordinate: coordinate,
      tint: tint,
      viewRadius: viewRadius,
      rotationOffset: rotationOffset,
      opacity: newOpacity,
      fractionalX: fractionalX,
      fractionalY: fractionalY,
      customRotation: customRotation,
      facingAngleDeg: facingAngleDeg,
      tag: tag,
      carriedMaterial: carriedMaterial,
      expressionConfig: expressionConfig,
      expressionState: expressionState,
      verticalOffset: verticalOffset,
      expressionRotationFlipped: expressionRotationFlipped,
    );
  }

  /// Creates a copy with modified custom rotation
  IsoAssetInstance withCustomRotation(double newRotation) {
    return IsoAssetInstance(
      asset: asset,
      coordinate: coordinate,
      tint: tint,
      viewRadius: viewRadius,
      rotationOffset: rotationOffset,
      opacity: opacity,
      fractionalX: fractionalX,
      fractionalY: fractionalY,
      customRotation: newRotation,
      facingAngleDeg: facingAngleDeg,
      tag: tag,
      carriedMaterial: carriedMaterial,
      expressionConfig: expressionConfig,
      expressionState: expressionState,
      verticalOffset: verticalOffset,
      expressionRotationFlipped: expressionRotationFlipped,
    );
  }

  // Shared paint for expression layer to avoid per-frame allocations.
  static final Paint _exprPaint = Paint();

  /// Draw this instance, including a separate expression layer if available.
  ///
  /// When [layer] is [SpriteLayer.background] or [SpriteLayer.foreground],
  /// only the corresponding depth layer of the geometry is drawn (expression
  /// sprites are skipped).
  void draw(Canvas canvas, IsoCamera camera, Size viewport,
      {SpriteLayer layer = SpriteLayer.combined}) {
    final applyVertical = verticalOffset != 0.0;
    if (applyVertical) {
      canvas.save();
      canvas.translate(
        0,
        -verticalOffset * IsoProjection.heightPerLevel * camera.zoom,
      );
    }

    Paint paint = Paint();

    // Apply tint if specified
    if (tint != null) {
      paint.colorFilter = ColorFilter.mode(tint!, BlendMode.modulate);
    }

    // Apply opacity
    if (opacity < 1.0) {
      paint.color = paint.color.withOpacity(opacity);
    }

    final hasPaint = tint != null || opacity < 1.0;

    // Draw the base geometry sprite
    final x = fractionalX ?? coordinate.x.toDouble();
    final y = fractionalY ?? coordinate.y.toDouble();
    final useFractional = fractionalX != null || fractionalY != null;

    if (useFractional) {
      asset.drawAtFractional(
        canvas,
        x,
        y,
        coordinate.h,
        camera,
        viewport,
        paint: hasPaint ? paint : null,
        rotationOffset: rotationOffset,
        customRotation: customRotation,
        facingAngleDeg: facingAngleDeg,
        layer: layer,
      );
    } else {
      asset.draw(
        canvas,
        coordinate,
        camera,
        viewport,
        paint: hasPaint ? paint : null,
        rotationOffset: rotationOffset,
        customRotation: customRotation,
        facingAngleDeg: facingAngleDeg,
        layer: layer,
      );
    }

    // Skip expression drawing for depth layer passes (bg/fg only draw geometry)
    if (layer != SpriteLayer.combined) {
      if (applyVertical) canvas.restore();
      return;
    }

    // Draw expression: runtime vector pass or baked expression sprite
    final facing = facingAngleDeg;
    if (facing == null) {
      if (applyVertical) canvas.restore();
      return;
    }

    final isoPos = useFractional
        ? IsoProjection.axonToScreen(x, y, angleRad: camera.angleRad)
        : IsoProjection.isoToScreen(
            coordinate.x.toDouble(),
            coordinate.y.toDouble(),
            viewIndex: camera.view.index,
          );
    final heightOffset = coordinate.h * IsoProjection.heightPerLevel;
    final worldPos = Offset(isoPos.dx, isoPos.dy - heightOffset);
    final tileCenter = camera.worldToScreen(worldPos, viewport);
    final zoom = camera.zoom;

    if (expressionConfig != null && expressionState != null) {
      // Runtime expression: draw eyes with vector geometry (same rect as body)
      final bodySprite = asset.getSpriteForFacing(
        camera.worldViewIndex,
        facing,
      );
      final spriteWidth = bodySprite.size.width * asset.scale * zoom;
      final spriteHeight = bodySprite.size.height * asset.scale * zoom;
      final topLeft = IsoAsset.anchoredTopLeft(
          tileCenter, spriteWidth, spriteHeight, bodySprite);
      final spriteCenter = Offset(
          topLeft.dx + spriteWidth / 2, topLeft.dy + spriteHeight / 2);
      final screenSize = Size(spriteWidth, spriteHeight);
      if (customRotation != 0.0) {
        canvas.save();
        canvas.translate(spriteCenter.dx, spriteCenter.dy);
        canvas.rotate(customRotation);
        canvas.translate(-spriteCenter.dx, -spriteCenter.dy);
      }
      final cameraAngleRad = ExpressionPainter2D.worldViewAngleDeg(
        camera.worldViewIndex,
        IsoProjection.viewCount,
      ) * (math.pi / 180);
      var meshRotationRad = facing * (math.pi / 180);
      if (expressionRotationFlipped) meshRotationRad = -meshRotationRad;
      ExpressionPainter2D.draw(
        canvas,
        expressionConfig!,
        expressionState!,
        cameraAngleRad: cameraAngleRad,
        meshRotationRad: meshRotationRad,
        screenCenter: customRotation != 0.0 ? Offset.zero : spriteCenter,
        screenSize: screenSize,
        opacity: expressionOpacity,
      );
      if (customRotation != 0.0) canvas.restore();
      if (applyVertical) canvas.restore();
      return;
    }

    // Baked expression sprite (fallback)
    if (asset.hasExpressionSprites) {
      final exprSprite = asset.getExpressionSpriteForFacing(
        camera.worldViewIndex,
        facing,
      );
      if (exprSprite != null) {
        final spriteWidth = exprSprite.size.width * asset.scale * zoom;
        final spriteHeight = exprSprite.size.height * asset.scale * zoom;
        final exprTopLeft = IsoAsset.anchoredTopLeft(
            tileCenter, spriteWidth, spriteHeight, exprSprite);
        final exprCenter = Offset(
            exprTopLeft.dx + spriteWidth / 2,
            exprTopLeft.dy + spriteHeight / 2);
        final dstRect = Rect.fromCenter(
          center: exprCenter,
          width: spriteWidth,
          height: spriteHeight,
        );
        if (expressionOpacity < 1.0) {
          _exprPaint.color = Color.fromRGBO(0, 0, 0, expressionOpacity);
          _exprPaint.colorFilter = null;
        } else {
          _exprPaint.color = const Color.fromRGBO(0, 0, 0, 1.0);
          _exprPaint.colorFilter = null;
        }
        if (customRotation != 0.0) {
          canvas.save();
          canvas.translate(exprCenter.dx, exprCenter.dy);
          canvas.rotate(customRotation);
          canvas.translate(-exprCenter.dx, -exprCenter.dy);
          exprSprite.draw(
            canvas,
            dstRect,
            expressionOpacity < 1.0 ? _exprPaint : null,
          );
          canvas.restore();
        } else {
          exprSprite.draw(
            canvas,
            dstRect,
            expressionOpacity < 1.0 ? _exprPaint : null,
          );
        }
      }
    }

    if (applyVertical) {
      canvas.restore();
    }
  }

  /// Compute a friend's depth on a structure's tile in grid-cell-offset space.
  ///
  /// The result is directly comparable to the per-cell depths precomputed in
  /// [IsoSpriteGrid], enabling the painter to interleave friend draws among
  /// structure grid cells.
  static double friendDepthOnTile(
    double friendFracX,
    double friendFracY,
    int structTileX,
    int structTileY,
    double viewAngle,
  ) {
    final dx = (friendFracX - structTileX) * kSpriteGridSize;
    final dy = (friendFracY - structTileY) * kSpriteGridSize;
    return IsoProjection.depthForAngle(dx, dy, viewAngle);
  }

  /// Draw this structure instance with grid cells interleaved around friends.
  ///
  /// [friends] is a pre-sorted (ascending depth) list of draw callbacks.
  /// Applies vertical offset, tint, and opacity the same way [draw] does.
  void drawInterleaved(
    Canvas canvas,
    IsoCamera camera,
    Size viewport,
    List<(double, VoidCallback)> friends,
  ) {
    final applyVertical = verticalOffset != 0.0;
    if (applyVertical) {
      canvas.save();
      canvas.translate(
        0,
        -verticalOffset * IsoProjection.heightPerLevel * camera.zoom,
      );
    }

    Paint? paint;
    if (tint != null || opacity < 1.0) {
      paint = Paint();
      if (tint != null) {
        paint.colorFilter = ColorFilter.mode(tint!, BlendMode.modulate);
      }
      if (opacity < 1.0) {
        paint.color = paint.color.withOpacity(opacity);
      }
    }

    final x = fractionalX ?? coordinate.x.toDouble();
    final y = fractionalY ?? coordinate.y.toDouble();

    asset.drawInterleaved(
      canvas, x, y, coordinate.h, camera, viewport, friends,
      paint: paint,
      rotationOffset: rotationOffset,
    );

    if (applyVertical) {
      canvas.restore();
    }
  }
}

/// Loader for creating IsoAssets from various sources
class IsoAssetLoader {
  IsoAssetLoader();

  final Map<String, IsoAsset> _cache = {};
  final Map<String, Completer<IsoAsset?>> _pending = {};
  final IsoVectorGenerator _vectorGenerator = IsoVectorGenerator();

  /// Load an asset from cache or create it
  Future<IsoAsset?> loadAsset(String assetId) async {
    // Check cache first
    if (_cache.containsKey(assetId)) {
      return _cache[assetId];
    }

    // Check if already loading
    if (_pending.containsKey(assetId)) {
      return _pending[assetId]!.future;
    }

    // Start loading
    final completer = Completer<IsoAsset?>();
    _pending[assetId] = completer;

    try {
      // Try to load from asset bundle first
      final asset = await _loadFromBundle(assetId);
      if (asset != null) {
        _cache[assetId] = asset;
        completer.complete(asset);
        _pending.remove(assetId);
        return asset;
      }

      // If not found in bundle, return null
      completer.complete(null);
      _pending.remove(assetId);
      return null;
    } catch (e) {
      completer.completeError(e);
      _pending.remove(assetId);
      return null;
    }
  }

  /// Generate sprites from 3D geometry (for prototyping)
  Future<IsoAsset> generateFromGeometry(
    String id,
    GeometryPrefabs geometryType, {
    Color color = Colors.white,
    double scale = 1.0,
  }) async {
    if (_cache.containsKey(id)) {
      return _cache[id]!;
    }

    final sprites = await _generateSpritesFrom3D(geometryType, color);
    final asset = IsoAsset(id: id, sprites: sprites, scale: scale);

    _cache[id] = asset;
    return asset;
  }

  /// Generate vector sprites from 3D geometry
  /// These sprites are resolution-independent and will remain crisp when zoomed
  Future<IsoAsset> generateVectorFromGeometry(
    String id,
    GeometryPrefabs geometryType, {
    Color color = Colors.white,
    double scale = 1.0,
  }) async {
    if (_cache.containsKey(id)) {
      return _cache[id]!;
    }

    // Use vector generator to create VectorIsoSprites with anchor offset
    final result = await _vectorGenerator.generateVectorSpritesWithOffset(
      geometryType,
      color,
      scale: 1.0, // Scale is handled by IsoAsset.scale
    );

    final asset = IsoAsset(
      id: id,
      sprites: result.sprites,
      scale: scale,
      anchorOffset: result.anchorOffset,
    );

    _cache[id] = asset;
    return asset;
  }

  /// Generate vector sprites with 16-angle view sprites (no mesh rotation).
  ///
  /// This produces sprites for all 16 camera view angles, suitable for
  /// structures and other non-rotating assets that need correct intermediate
  /// angle rendering without the full 256-sprite rotation grid.
  Future<IsoAsset> generateVectorFromGeometryWithAllViews(
    String id,
    GeometryPrefabs geometryType, {
    Color color = Colors.white,
    double scale = 1.0,
  }) async {
    if (_cache.containsKey(id)) {
      return _cache[id]!;
    }

    final result = await _vectorGenerator.generateAllViewSprites(
      geometryType,
      color,
      scale: 1.0,
    );

    final asset = IsoAsset(
      id: id,
      sprites: result.cardinalSprites,
      viewSprites: result.allSprites,
      scale: scale,
      anchorOffset: result.anchorOffset,
    );

    _cache[id] = asset;
    return asset;
  }

  /// Generate vector sprites with facing sprite rings for rotation animation.
  ///
  /// Produces one [FacingSpriteRing] per world view angle, each containing
  /// [facingSpriteCount] facing sprites. Includes eyes when [expression] is
  /// provided.
  Future<IsoAsset> generateVectorFromGeometryWithAnimViews(
    String id,
    GeometryPrefabs geometryType, {
    Color color = Colors.white,
    double scale = 1.0,
    FriendExpressionConfig? expression,
    int facingSpriteCount = 16,
    double meshRotationOffsetDeg = 0.0,
  }) async {
    if (_cache.containsKey(id)) {
      return _cache[id]!;
    }

    final result = await _vectorGenerator.generateFullRotationSprites(
      geometryType,
      color,
      scale: 1.0,
      expression: expression,
      facingSpriteCount: facingSpriteCount,
      meshRotationOffsetRad: meshRotationOffsetDeg * 3.14159265358979 / 180.0,
    );

    final asset = IsoAsset(
      id: id,
      sprites: result.cardinalSprites,
      facingSprites: result.facingSprites,
      expressionFacingSprites: result.expressionFacingSprites,
      scale: scale,
      anchorOffset: result.anchorOffset,
    );

    _cache[id] = asset;
    return asset;
  }

  /// Load a Wavefront OBJ file from the asset bundle and generate iso sprites.
  ///
  /// The OBJ is parsed via [ObjParser], then rendered using the fixed
  /// [IsoProjection.worldUnitsPerTile] ortho scale so that model units map
  /// predictably to tile sizes.
  Future<IsoAsset> generateFromObj(
    String id,
    String objAssetPath, {
    Color color = Colors.white,
    double scale = 1.0,
    bool generateAllViews = false,
  }) async {
    if (_cache.containsKey(id)) {
      return _cache[id]!;
    }

    final source = await rootBundle.loadString(objAssetPath);
    final geometry = ObjParser.parse(
      id: id,
      name: id,
      source: source,
    );

    final IsoAsset asset;

    if (generateAllViews) {
      final result = await _vectorGenerator.generateAllViewSpritesFromGeometry(
        geometry,
        color,
        scale: scale,
      );
      asset = IsoAsset(
        id: id,
        sprites: result.cardinalSprites,
        viewSprites: result.allSprites,
        scale: scale,
        anchorOffset: result.anchorOffset,
      );
    } else {
      final result = await _vectorGenerator.generateSpritesFromGeometry(
        geometry,
        color,
        scale: scale,
      );
      asset = IsoAsset(
        id: id,
        sprites: result.sprites,
        scale: scale,
        anchorOffset: result.anchorOffset,
      );
    }

    _cache[id] = asset;
    return asset;
  }

  /// Generate placeholder colored sprites sized to match tile bounding box
  Future<IsoAsset> generatePlaceholder(
    String id, {
    Color color = Colors.grey,
  }) async {
    if (_cache.containsKey(id)) {
      return _cache[id]!;
    }

    final sprites = await _generatePlaceholderSprites(color);
    final asset = IsoAsset(id: id, sprites: sprites);

    _cache[id] = asset;
    return asset;
  }

  Future<IsoAsset?> _loadFromBundle(String assetId) async {
    // Try to load 4 sprite images from assets
    // Expected paths: assets/iso/$assetId/nw.png, sw.png, se.png, ne.png
    final sprites = <IsoSprite>[];

    try {
      for (final direction in ['nw', 'sw', 'se', 'ne']) {
        final path = 'assets/iso/$assetId/$direction.png';
        final data = await rootBundle.load(path);
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        final frame = await codec.getNextFrame();
        // Create sprite with alpha mask for accurate hit testing
        final sprite = await _createRasterSpriteWithAlphaMask(frame.image);
        sprites.add(sprite);
      }

      return IsoAsset(id: assetId, sprites: sprites);
    } catch (e) {
      // Asset not found in bundle
      return null;
    }
  }

  Future<List<IsoSprite>> _generateSpritesFrom3D(
    GeometryPrefabs geometryType,
    Color color,
  ) async {
    const size = 256;
    const scale = 120.0;

    final sprites = <IsoSprite>[];

    // Generate sprites from 4 angles
    final angles = [45.0, 135.0, 225.0, 315.0]; // NW, SW, SE, NE

    for (final angle in angles) {
      final image = await _render3DToSprite(
        geometryType,
        color,
        angle,
        size,
        scale,
      );
      // Create sprite with alpha mask for accurate hit testing
      final sprite = await _createRasterSpriteWithAlphaMask(image);
      sprites.add(sprite);
    }

    return sprites;
  }

  Future<ui.Image> _render3DToSprite(
    GeometryPrefabs geometryType,
    Color color,
    double angle,
    int size,
    double scale,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Create a mini 3D scene
    final geometry = buildGeometry(
      GeometryFeature(id: 'sprite', geometry: geometryType, color: color),
    );

    // Set up camera
    final angleRad = angle * 3.14159 / 180;
    final distance = scale * 2;
    final cameraPos = Vector3(
      distance * math.cos(angleRad),
      distance * 0.6, // Idk why this is 0.6, but it works
      distance * math.sin(angleRad),
    );

    final camera = scene_camera.Camera(
      name: 'sprite-camera',
      position: cameraPos,
      target: Vector3.zero(),
      projection: scene_camera.ProjectionType.orthographic,
      orthographicScale: scale,
      near: 0.1,
      far: 1000,
    );

    // Create scene
    final scene = Scene(globalIllumination: 0.6);
    scene.camera = camera;
    scene.addLight(
      DirectionalLight(
        color: Colors.white,
        intensity: 0.9,
        direction: Vector3(-0.7, -1.0, -0.4),
      ),
    );

    final mesh = Mesh(
      id: 'sprite-mesh',
      name: 'Sprite',
      geometry: geometry,
      material: MaterialModel(color: color, doubleSided: true),
    );

    scene.setMeshes([mesh]);

    // Render to canvas
    _renderSceneToCanvas(canvas, scene, Size(size.toDouble(), size.toDouble()));

    final picture = recorder.endRecording();
    return picture.toImage(size, size);
  }

  void _renderSceneToCanvas(Canvas canvas, Scene scene, Size size) {
    final camera = scene.camera;
    if (camera == null) return;

    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.transparent);

    // Note: viewProjection would be used for proper 3D rendering
    // Currently using simplified placeholder rendering
    // final aspect = size.width / size.height;
    // final projection = camera.projectionMatrix(aspect);
    // final view = camera.viewMatrix;
    // final viewProjection = projection * view;

    // Simple rendering - just draw geometry as solid color
    // (This is a simplified version for sprite generation)
    for (final mesh in scene.meshes) {
      final paint = Paint()
        ..color = mesh.material.color
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(size.width / 2, size.height / 2), 30, paint);
    }
  }

  Future<List<IsoSprite>> _generatePlaceholderSprites(Color color) async {
    final sprites = <IsoSprite>[];

    // Size sprite to match tile bounding box dimensions
    // Tile bounding box is the rectangle that encloses the diamond
    final width = IsoProjection.tileWidth; // 128.0
    final height = IsoProjection.tileHeight; // 64.0

    for (var i = 0; i < 4; i++) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Fill background with semi-transparent color
      canvas.drawRect(
        Rect.fromLTWH(0, 0, width, height),
        Paint()..color = color.withOpacity(0.6),
      );

      // Draw a 2px border around the entire rectangle
      canvas.drawRect(
        Rect.fromLTWH(0, 0, width, height),
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );

      // Add a thicker inner border to make it more visible
      canvas.drawRect(
        Rect.fromLTWH(4, 4, width - 8, height - 8),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );

      // Draw view direction label
      final directions = ['NW', 'SW', 'SE', 'NE'];
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${directions[i]}\n${width.toInt()}×${height.toInt()}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(
          (width - textPainter.width) / 2,
          (height - textPainter.height) / 2,
        ),
      );

      final picture = recorder.endRecording();
      final image = await picture.toImage(width.toInt(), height.toInt());
      // Create sprite with alpha mask for accurate hit testing
      final sprite = await _createRasterSpriteWithAlphaMask(image);
      sprites.add(sprite);
    }

    return sprites;
  }

  /// Clear all cached assets
  void clearCache() {
    _cache.clear();
  }

  /// Get cache size
  int get cacheSize => _cache.length;

  /// Create a RasterIsoSprite with pre-computed alpha mask for hit testing.
  Future<RasterIsoSprite> _createRasterSpriteWithAlphaMask(
    ui.Image image, {
    int maxMaskSize = 64,
  }) async {
    final alphaMaskData = await _computeAlphaMask(
      image,
      maxMaskSize: maxMaskSize,
    );

    if (alphaMaskData != null) {
      return RasterIsoSprite(
        image,
        alphaMask: alphaMaskData.$1,
        alphaMaskWidth: alphaMaskData.$2,
        alphaMaskHeight: alphaMaskData.$3,
      );
    }

    // Fallback without alpha mask
    return RasterIsoSprite(image);
  }

  /// Compute a downscaled alpha mask from an image.
  /// Returns (mask, width, height) or null on failure.
  Future<(Uint8List, int, int)?> _computeAlphaMask(
    ui.Image image, {
    int maxMaskSize = 64,
  }) async {
    try {
      // Get image byte data in RGBA format
      final byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) return null;

      final pixels = byteData.buffer.asUint8List();
      final imgWidth = image.width;
      final imgHeight = image.height;

      // Calculate downscaled mask size while preserving aspect ratio
      int maskWidth, maskHeight;
      if (imgWidth > imgHeight) {
        maskWidth = maxMaskSize;
        maskHeight = (maxMaskSize * imgHeight / imgWidth).round().clamp(
          1,
          maxMaskSize,
        );
      } else {
        maskHeight = maxMaskSize;
        maskWidth = (maxMaskSize * imgWidth / imgHeight).round().clamp(
          1,
          maxMaskSize,
        );
      }

      // Create downscaled alpha mask
      final mask = Uint8List(maskWidth * maskHeight);

      for (var my = 0; my < maskHeight; my++) {
        for (var mx = 0; mx < maskWidth; mx++) {
          // Map mask coordinates to image coordinates
          final imgX = (mx * imgWidth / maskWidth).round().clamp(
            0,
            imgWidth - 1,
          );
          final imgY = (my * imgHeight / maskHeight).round().clamp(
            0,
            imgHeight - 1,
          );

          // Get alpha value (4th byte in RGBA)
          final pixelIndex = (imgY * imgWidth + imgX) * 4;
          final alpha = pixels[pixelIndex + 3];

          // Store in mask
          mask[my * maskWidth + mx] = alpha;
        }
      }

      return (mask, maskWidth, maskHeight);
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to compute alpha mask: $e');
      return null;
    }
  }
}
