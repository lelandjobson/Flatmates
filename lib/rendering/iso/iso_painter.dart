import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'iso_camera.dart';
import 'iso_coordinate.dart';
import 'iso_asset.dart';
import 'iso_sprite.dart';
import 'iso_sprite_grid.dart';
import 'iso_projection.dart';
import 'iso_visibility.dart';
import 'iso_hit_tester.dart';
import 'path_renderable.dart';
import 'scene_raster_cache.dart';
import '../../data/asset_database.dart' show AssetCategory;
import '../../data/game_settings.dart';
import '../../data/path_database.dart';
import '../../tiles/tiles.dart';
import '../../gameplay/dropped_item.dart';
import '../../tiles/tile_cooldown.dart';
import '../../animation/tile_restoration.dart';
import '../../ui/view_mode_filters.dart';
import 'svg_icon_cache.dart';
import '../hatch/hatch_renderer.dart';

/// Style for a drag path preview line.
enum DragPathStyle { dashed, orthogonal }

/// Preview path rendered during a HUD long-drag interaction.
/// Waypoints are tile centers in screen space, forming a polyline.
class DragPathPreview {
  const DragPathPreview({
    required this.waypoints,
    this.style = DragPathStyle.dashed,
    this.color = const Color(0xAAFFFFFF),
    this.endpointColor,
  });

  /// Path through tile centers in screen space (start to end).
  final List<Offset> waypoints;
  final DragPathStyle style;
  final Color color;

  /// Optional color for the endpoint circle. Falls back to [color].
  final Color? endpointColor;
}

/// Data for a tile to be rendered
class IsoTileData {
  const IsoTileData({
    required this.coordinate,
    required this.color,
    this.elevation = 0.0,
    this.materialId,
    this.materialAmount,
  });

  final IsoCoordinate coordinate;
  final Color color;
  final double elevation;

  /// Material ID from crafts (e.g. fm-clay) - used for icon rendering
  final String? materialId;

  /// Amount of the dominant material remaining on this tile.
  final int? materialAmount;

  double get depth => coordinate.depth;
}

/// Base class for renderable items
abstract class IsoRenderable {
  double get depth;
  double getDepthForView(IsoViewDirection view);
  void draw(Canvas canvas, IsoCamera camera, Size viewport);
}

// -- Shared Paint objects reused across frames to avoid per-tile allocation --
final Paint _tileFillPaint = Paint();
final Paint _tileOutlinePaint = Paint()
  ..color =
      const Color(0x4D000000) // black 30%
  ..style = PaintingStyle.stroke
  ..strokeWidth = 1.0;
final Paint _fogPaint = Paint();
final Paint _depthFillPaint = Paint();
final Paint _depthStrokePaint = Paint()
  ..color = const Color(0x33000000)
  ..style = PaintingStyle.stroke
  ..strokeWidth = 0.5;
final Paint _voidEdgePaint = Paint()
  ..color = const Color(0xFF757575)
  ..style = PaintingStyle.stroke
  ..strokeWidth = 3.0
  ..strokeCap = StrokeCap.round;
final Paint _emojiLayerPaint = Paint()..color = const Color(0x4DFFFFFF);
final Paint _materialIconPaint = Paint()..style = PaintingStyle.fill;

/// Darken a colour by [fraction] (0.0 = unchanged, 1.0 = black).
Color _darken(Color c, double fraction) {
  final f = 1.0 - fraction;
  return Color.fromARGB(
    c.alpha,
    (c.red * f).round(),
    (c.green * f).round(),
    (c.blue * f).round(),
  );
}

/// Tile renderable
class _TileRenderable implements IsoRenderable {
  const _TileRenderable(
    this.tile,
    this.visibility, {
    this.showMaterialEmoji = false,
    this.materialIconStyle = MaterialIconStyle.simplified,
    this.fogOverlayOpacity = 0.0,
    this.cooldownState,
    this.gatherDrain = 0.0,
    this.svgIconCache,
    this.tileFillOpacity = 0.5,
    this.tileIconOpacity = 1.0,
    this.terrainAmplitude = 0.0,
  });

  final IsoTileData tile;
  final TileVisibility visibility;
  final bool showMaterialEmoji;
  final MaterialIconStyle materialIconStyle;
  final SvgIconCache? svgIconCache;

  /// Fill color opacity (0.0 = transparent, 1.0 = fully opaque).
  final double tileFillOpacity;

  /// Material icon opacity (0.0 = invisible, 1.0 = fully opaque).
  final double tileIconOpacity;

  /// Terrain height pixel displacement at zoom 1.0.
  final double terrainAmplitude;

  /// Animated fog overlay opacity (0.0 = fully visible, up to ~0.05 = fog).
  final double fogOverlayOpacity;

  /// Non-null when this tile is on cooldown after being gathered from.
  final TileCooldownState? cooldownState;

  /// Gather drain progress (0.0 = full tile, 1.0 = fully drained).
  /// When > 0, the tile fill shrinks toward the center.
  final double gatherDrain;

  @override
  double get depth => tile.depth + tile.elevation * 0.0005;

  @override
  double getDepthForView(IsoViewDirection view) {
    return tile.coordinate.getDepthForView(view) + tile.elevation * 0.0005;
  }

  @override
  void draw(Canvas canvas, IsoCamera camera, Size viewport) {
    drawTile(canvas, camera, viewport, null);
  }

  /// Draw the tile, optionally appending outline segments to [outlineBatch]
  /// instead of drawing them individually. When [outlineBatch] is non-null
  /// the caller is responsible for stroking the accumulated path once.
  void drawTile(
    Canvas canvas,
    IsoCamera camera,
    Size viewport,
    Path? outlineBatch,
  ) {
    final points = tile.coordinate.getDiamondPoints(camera, viewport);

    // Apply terrain height displacement (negative Y = higher on screen).
    final elevDy = tile.elevation * terrainAmplitude * camera.zoom;
    if (elevDy != 0) {
      for (var i = 0; i < points.length; i++) {
        points[i] = Offset(points[i].dx, points[i].dy - elevDy);
      }
    }

    final path = Path()
      ..moveTo(points[0].dx, points[0].dy)
      ..lineTo(points[1].dx, points[1].dy)
      ..lineTo(points[2].dx, points[2].dy)
      ..lineTo(points[3].dx, points[3].dy)
      ..close();

    if (visibility == TileVisibility.hidden) {
      _tileFillPaint.color = IsoPainter._bgColor;
      canvas.drawPath(path, _tileFillPaint);
      if (outlineBatch != null) {
        outlineBatch.addPath(path, Offset.zero);
      }
      return;
    }

    final isOnCooldown = cooldownState != null && !cooldownState!.isComplete;

    if (isOnCooldown) {
      // While on cooldown, let the restoration animation paint the tile
      // instead of the normal fill. The animation draws on a transparent
      // background; the solid fill is handled inside the animation when
      // near completion to prevent any visible flash.
      final anim = (tile.materialId != null && tile.materialId!.isNotEmpty)
          ? TileRestorationAnimations.forMaterialId(tile.materialId!)
          : TileRestorationAnimations.forMaterialId(kNoMaterialId);
      anim.draw(canvas, path, points, cooldownState!.progress, tile.color);
    } else if (gatherDrain > 0.001) {
      // Being gathered: shrink the fill toward the tile center.
      final center = Offset(
        (points[0].dx + points[1].dx + points[2].dx + points[3].dx) / 4,
        (points[0].dy + points[1].dy + points[2].dy + points[3].dy) / 4,
      );
      final scale = 1.0 - gatherDrain;
      final drainPath = Path()
        ..moveTo(
          center.dx + (points[0].dx - center.dx) * scale,
          center.dy + (points[0].dy - center.dy) * scale,
        )
        ..lineTo(
          center.dx + (points[1].dx - center.dx) * scale,
          center.dy + (points[1].dy - center.dy) * scale,
        )
        ..lineTo(
          center.dx + (points[2].dx - center.dx) * scale,
          center.dy + (points[2].dy - center.dy) * scale,
        )
        ..lineTo(
          center.dx + (points[3].dx - center.dx) * scale,
          center.dy + (points[3].dy - center.dy) * scale,
        )
        ..close();
      _tileFillPaint.color = _darken(tile.color, 0.02).withValues(alpha: tileFillOpacity);
      canvas.drawPath(drainPath, _tileFillPaint);
    } else {
      // Normal tile fill (also handles post-cooldown: seamless because
      // the animation already drew the solid fill behind the grid).
      _tileFillPaint.color = _darken(tile.color, 0.02).withValues(alpha: tileFillOpacity);
      canvas.drawPath(path, _tileFillPaint);

      // If cooldown just completed, mark flash as played so the manager
      // cleans up the entry on the next tick.
      if (cooldownState != null && cooldownState!.isComplete) {
        cooldownState!.flashPlayed = true;
      }
    }

    // Outline: batch into a single path if provided, else draw individually
    if (outlineBatch != null) {
      outlineBatch.addPath(path, Offset.zero);
    } else {
      canvas.drawPath(path, _tileOutlinePaint);
    }

    if (fogOverlayOpacity > 0.001) {
      _fogPaint.color = IsoPainter._bgColor.withValues(alpha: fogOverlayOpacity);
      canvas.drawPath(path, _fogPaint);
    }

    if (showMaterialEmoji &&
        tile.materialId != null &&
        tile.materialId!.isNotEmpty &&
        visibility != TileVisibility.hidden) {
      final cooldownScale = isOnCooldown ? 0.2 : 1.0;
      final iconAlpha = tileIconOpacity * (1.0 - fogOverlayOpacity) * cooldownScale;
      if (iconAlpha > 0.005) {
        var center = tile.coordinate.toScreen(camera, viewport);
        if (elevDy != 0) {
          center = Offset(center.dx, center.dy - elevDy);
        }
        final iconSize = 12.0 * camera.zoom;
        final dst = Rect.fromCenter(
          center: center,
          width: iconSize,
          height: iconSize,
        );
        if (svgIconCache?.hasIcon(tile.materialId!) == true) {
          svgIconCache!.drawIcon(canvas, dst, tile.materialId!, alpha: iconAlpha);
        } else {
          _materialIconPaint.color = tile.color.withValues(alpha: iconAlpha);
          canvas.drawCircle(center, 6.0 * camera.zoom, _materialIconPaint);
        }
      }
    }
  }
}

/// Asset renderable
class _AssetRenderable implements IsoRenderable {
  const _AssetRenderable(this.asset);

  final IsoAssetInstance asset;

  @override
  double get depth => asset.depth;

  @override
  double getDepthForView(IsoViewDirection view) {
    return asset.getDepthForView(view);
  }

  @override
  void draw(Canvas canvas, IsoCamera camera, Size viewport) {
    asset.draw(canvas, camera, viewport);
  }

  void drawBackground(Canvas canvas, IsoCamera camera, Size viewport) {
    asset.draw(canvas, camera, viewport, layer: SpriteLayer.background);
  }

  void drawForeground(Canvas canvas, IsoCamera camera, Size viewport) {
    asset.draw(canvas, camera, viewport, layer: SpriteLayer.foreground);
  }
}

/// Custom painter for isometric view
class IsoPainter extends CustomPainter {
  IsoPainter({
    required this.camera,
    required this.tiles,
    this.paths = const [],
    this.assets = const [],
    this.sceneRasterCache,
    this.ghostPath,
    this.visibilityMap,
    this.showGrid = false,
    this.showCoordinates = false,
    this.selectedTile,
    this.passiveHighlightCoord,
    this.selectedAssets = const [],
    this.clickPosition,
    this.editingTileCoord,
    this.pathEditMode = false,
    this.editingPathId,
    this.ghostFlashOpacity,
    this.showHitBoxes = false,
    this.hitTestDebugInfo,
    this.showMaterialEmojis = false,
    this.materialIconStyle = MaterialIconStyle.simplified,
    this.droppedItems,
    this.paintedTiles,
    this.paintColor,
    this.paintOpacity = 0.75,
    this.assetDimOpacity = 1.0,
    this.fogOpacities = const {},
    this.tileCooldowns = const {},
    this.tileGatherDrains = const {},
    this.tileOverlays,
    this.viewMode,
    this.viewModeFilters,
    this.showNonBoundaryEdges = false,
    this.materialIdToColor,
    this.svgIconCache,
    this.tileFillOpacity = 0.5,
    this.tileIconOpacity = 1.0,
    this.dragPreviewPath,
    this.queuedActionCoordinates = const [],
    this.isRecording = false,
    this.productionMode = false,
    this.queuedMovePaths = const [],
    this.selectedActionPath,
    this.hatchRenderer,
    this.materialHatchMap,
    this.hatchOpacity = 1.0,
    this.hatchBrightness = 0.0,
    this.hatchScale = 1.0,
    this.terrainAmplitude = 0.0,
    this.voidTileKeys,
    this.showDrawOrder = false,
    this.cellColorTheme,
  }) : super(repaint: camera);

  final IsoCamera camera;

  /// Optional scene raster cache for compositing static structures.
  final SceneRasterCache? sceneRasterCache;

  /// Optional map for material ID -> color (from CraftsTechProvider). Used for
  /// dropped item bubbles and friend carried/gather icons.
  final Map<String, Color>? materialIdToColor;

  /// Optional cache of SVG icons for material/craft IDs. When set, material
  /// icons on tiles use SVG when available; otherwise fall back to colored circle.
  final SvgIconCache? svgIconCache;

  /// Preview path rendered during HUD long-drag interaction.
  final DragPathPreview? dragPreviewPath;

  /// Coordinates with a queued TileAction (rendered as floating "!" icon).
  final List<IsoCoordinate> queuedActionCoordinates;

  /// Whether the game is in recording mode (paused clock, tinted world).
  final bool isRecording;

  /// Whether the view is in production mode (structures at 50% opacity).
  final bool productionMode;

  /// Preview paths for queued move actions (rendered as semi-dark blue lines).
  final List<DragPathPreview> queuedMovePaths;

  /// Path of the currently selected action in the panel (rendered white).
  final DragPathPreview? selectedActionPath;

  final List<IsoTileData> tiles;
  final List<PathEntry> paths;
  final List<IsoAssetInstance> assets;
  final PathEntry? ghostPath;
  final Map<String, TileVisibility>? visibilityMap;

  /// Per-tile animated fog overlay opacities (tile key -> 0.0 .. maxFogOpacity).
  final Map<String, double> fogOpacities;
  final bool showGrid;
  final bool showCoordinates;
  final IsoTileData? selectedTile;
  /// Dim tile glow drawn under a selected entity (visual only, not a selection).
  final IsoCoordinate? passiveHighlightCoord;
  final List<IsoAssetInstance> selectedAssets;
  final Offset? clickPosition;
  final IsoCoordinate? editingTileCoord;
  final bool pathEditMode;
  final String? editingPathId;
  final double? ghostFlashOpacity;
  final bool showHitBoxes;
  final HitTestDebugInfo? hitTestDebugInfo;

  /// Whether to show material type icons on tiles
  final bool showMaterialEmojis;

  /// How to draw material icons: simplified (circle) or emoji
  final MaterialIconStyle materialIconStyle;

  /// Opacity of tile fill color (0.0 = transparent, 1.0 = opaque).
  final double tileFillOpacity;

  /// Opacity of tile material icons (0.0 = invisible, 1.0 = opaque).
  final double tileIconOpacity;

  /// Optional hatch renderer for drawing tile hatch patterns.
  final HatchRenderer? hatchRenderer;

  /// Maps materialId -> hatch patternId.  When non-null together with
  /// [hatchRenderer], tiles with a matching material get a hatch overlay.
  final Map<String, String>? materialHatchMap;

  final double hatchOpacity;
  final double hatchBrightness;
  final double hatchScale;

  /// Terrain height displacement in pixels at zoom 1.0. When 0, tiles are flat.
  final double terrainAmplitude;

  /// Tile keys ("x:y") that are void (missing). Used to detect naked edges
  /// for depth face rendering.
  final Set<String>? voidTileKeys;

  /// Debug: tint each structure cell and friend with a spectral gradient
  /// based on draw order (red=back, blue=front).
  final bool showDrawOrder;

  /// When set, structure cells are tinted per-coordinate using this
  /// [kSpriteGridSize]x[kSpriteGridSize] color grid (row, col).
  final List<List<Color>>? cellColorTheme;

  /// Dropped items to render on tiles
  final TileDroppedItems? droppedItems;

  /// Set of painted tile coordinate keys (e.g. "x:y") to highlight
  final Set<String>? paintedTiles;

  /// Colour used for the painted tile overlay
  final Color? paintColor;

  /// Opacity for the painted tile overlay (0.0–1.0)
  final double paintOpacity;

  /// Opacity multiplier for asset rendering (< 1.0 dims assets, e.g. during paint mode)
  final double assetDimOpacity;

  /// Per-tile coloured overlays (tile key "x:y" -> RGBA colour).
  ///
  /// Unlike [paintedTiles] (single colour for all tiles), this supports a
  /// different colour per tile. Alpha is respected, so fade-out opacity can
  /// be baked into the colour. Rendered after tiles, before paths.
  final Map<String, Color>? tileOverlays;

  /// Current view mode name (e.g., 'tile', 'structure', 'friend').
  final String? viewMode;

  /// Filter settings for the current view mode (primary/secondary opacity & saturation).
  final ViewModeFilters? viewModeFilters;

  /// When false (default), selection wireframes show only the outline boundary.
  /// When true, all interior (non-boundary) edges are also drawn.
  final bool showNonBoundaryEdges;

  /// Per-tile cooldown states (tile key "x:y" -> state).
  /// Tiles on cooldown are rendered with the restoration animation.
  final Map<String, TileCooldownState> tileCooldowns;

  /// Per-tile gather drain progress (tile key "x:y" -> 0.0..1.0).
  /// Tiles being gathered from shrink their fill toward the center.
  final Map<String, double> tileGatherDrains;

  // Shared paints for per-frame drawing (avoid per-frame allocation)
  static const Color _bgColor = Color(0xFF0D0B1A);
  static final Paint _bgPaint = Paint()..color = _bgColor;
  static final Paint _viewFilterPaint = Paint();
  static final Paint _fogDimPaint = Paint();

  // Reusable buffers – cleared and refilled each paint() call to avoid GC churn.
  static final List<_TileRenderable> _tileRenderBuf = [];
  static final List<(double, PathEntry)> _pathDepthBuf = [];
  static final List<_AssetRenderable> _assetRenderBuf = [];
  static final List<_AssetRenderable> _structureBuf = [];
  static final List<_AssetRenderable> _friendBuf = [];
  static final Map<String, List<_AssetRenderable>> _friendTileLookup = {};
  static final Set<_AssetRenderable> _drawnFriends = {};
  static final List<(double, VoidCallback)> _interleaveBuf = [];

  // Sort caching — avoid re-sorting when view/assets haven't changed.
  static int _cachedTileSortView = -1;
  static int _cachedTileSortLen = -1;
  static int _cachedAssetSortView = -1;
  static List<IsoAssetInstance>? _cachedAssetList;

  /// Pixel buffer beyond viewport edges before culling an asset sprite.
  static const double _cullBuffer = 120.0;

  /// Get per-element visual settings, returning defaults when no filters set.
  ElementVisualSettings _elementSettings(ElementCategory cat) {
    if (viewModeFilters == null) return ElementVisualSettings();
    return viewModeFilters![cat];
  }

  /// Create a saturation ColorFilter using a color matrix.
  /// [s] ranges from 0.0 (greyscale) to 1.0 (full colour).
  static ColorFilter _saturationFilter(double s) {
    final inv = 1.0 - s;
    final r = 0.2126 * inv;
    final g = 0.7152 * inv;
    final b = 0.0722 * inv;
    return ColorFilter.matrix(<double>[
      r + s,
      g,
      b,
      0,
      0,
      r,
      g + s,
      b,
      0,
      0,
      r,
      g,
      b + s,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ]);
  }

  /// Create a brightness ColorFilter using a color matrix.
  /// [b] ranges from 0.0 (black) to 1.0 (normal) to 2.0 (overexposed).
  static ColorFilter _brightnessFilter(double b) {
    final offset = (b - 1.0) * 255;
    return ColorFilter.matrix(<double>[
      1, 0, 0, 0, offset,
      0, 1, 0, 0, offset,
      0, 0, 1, 0, offset,
      0, 0, 0, 1, 0,
    ]);
  }

  /// Build a combined ColorFilter for saturation and brightness.
  /// Returns null if both are at their default (1.0).
  static ColorFilter? _combinedFilter(double saturation, double brightness) {
    if (saturation >= 1.0 && brightness >= 1.0) return null;
    if (brightness >= 1.0) return _saturationFilter(saturation);
    if (saturation >= 1.0) return _brightnessFilter(brightness);
    // Chain: apply saturation matrix first, then brightness offset.
    final sInv = 1.0 - saturation;
    final r = 0.2126 * sInv;
    final g = 0.7152 * sInv;
    final bk = 0.0722 * sInv;
    final offset = (brightness - 1.0) * 255;
    return ColorFilter.matrix(<double>[
      r + saturation, g, bk, 0, offset,
      r, g + saturation, bk, 0, offset,
      r, g, bk + saturation, 0, offset,
      0, 0, 0, 1, 0,
    ]);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // Clear background
    canvas.drawRect(Offset.zero & size, _bgPaint);

    // Draw grid if enabled
    if (showGrid) {
      _drawGrid(canvas, size);
    }

    // Collect renderables into reusable buffers (avoids per-frame allocation)
    _tileRenderBuf.clear();
    for (final t in tiles) {
      final visibility = visibilityMap != null
          ? _getVisibilityForTile(t)
          : TileVisibility.visible;
      final tileKey = '${t.coordinate.x}:${t.coordinate.y}';
      _tileRenderBuf.add(_TileRenderable(
        t,
        visibility,
        showMaterialEmoji: showMaterialEmojis,
        materialIconStyle: materialIconStyle,
        fogOverlayOpacity: fogOpacities[tileKey] ?? 0.0,
        cooldownState: tileCooldowns[tileKey],
        gatherDrain: tileGatherDrains[tileKey] ?? 0.0,
        svgIconCache: svgIconCache,
        tileFillOpacity: tileFillOpacity,
        tileIconOpacity: tileIconOpacity,
        terrainAmplitude: terrainAmplitude,
      ));
    }

    _pathDepthBuf.clear();
    for (final p in paths) {
      _pathDepthBuf.add((PathRenderable.getDepthForPath(p, camera.view), p));
    }
    _pathDepthBuf.sort((a, b) => a.$1.compareTo(b.$1));

    _assetRenderBuf.clear();
    for (final a in assets) {
      _assetRenderBuf.add(_AssetRenderable(a));
    }

    // Only re-sort tiles when view direction or tile count changes.
    final viewIdx = camera.view.index;
    if (viewIdx != _cachedTileSortView ||
        _tileRenderBuf.length != _cachedTileSortLen) {
      _sortByDepth(_tileRenderBuf, camera.view);
      _cachedTileSortView = viewIdx;
      _cachedTileSortLen = _tileRenderBuf.length;
    }
    // Only re-sort assets when view direction or asset list changes.
    if (viewIdx != _cachedAssetSortView || !identical(assets, _cachedAssetList)) {
      _sortByDepth(_assetRenderBuf, camera.view);
      _cachedAssetSortView = viewIdx;
      _cachedAssetList = assets;
    }

    // Compute per-element visual filter values.
    // Tile and friend opacity is applied at the per-instance level (tileFillOpacity,
    // per-friend opacity in IsoAssetInstance), so saveLayers here only handle
    // saturation/brightness. Structure opacity is applied via saveLayer.
    final tileCfg = _elementSettings(ElementCategory.tiles);
    final tileCf = _combinedFilter(tileCfg.saturation, tileCfg.brightness);

    final structCfg = _elementSettings(ElementCategory.structures);
    var structureOpacity = structCfg.opacity;
    final structCf = _combinedFilter(structCfg.saturation, structCfg.brightness);

    final friendCfg = _elementSettings(ElementCategory.friends);
    final friendCf = _combinedFilter(friendCfg.saturation, friendCfg.brightness);

    // Production mode: structures at 50% opacity for better world visibility
    if (productionMode && structureOpacity > 0.5) {
      structureOpacity = 0.5;
    }

    // Draw in fixed order: tiles -> painted overlays -> paths -> dropped items -> assets

    // --- Tiles ---
    // Opacity is baked into tileFillOpacity; saveLayer only for saturation/brightness.
    if (tileCf != null) {
      _viewFilterPaint.color = const Color.fromRGBO(255, 255, 255, 1.0);
      _viewFilterPaint.colorFilter = tileCf;
      canvas.saveLayer(Offset.zero & size, _viewFilterPaint);
    }
    final outlineBatch = Path();
    final hasVoid = voidTileKeys != null && voidTileKeys!.isNotEmpty;

    // Batch tile fills by color when tiles have no special states.
    final bool canBatch = !hasVoid && terrainAmplitude == 0;
    if (canBatch && tileCooldowns.isEmpty && tileGatherDrains.isEmpty) {
      _batchTileFills(canvas, size, outlineBatch);
    } else {
      for (final renderable in _tileRenderBuf) {
        if (hasVoid) {
          _drawTileDepthFaces(canvas, camera, size, renderable);
        }
        renderable.drawTile(canvas, camera, size, outlineBatch);
      }
    }
    canvas.drawPath(outlineBatch, _tileOutlinePaint);
    if (hasVoid) {
      final voidEdgeBatch = Path();
      _collectVoidEdges(camera, size, voidEdgeBatch);
      canvas.drawPath(voidEdgeBatch, _voidEdgePaint);
    }
    if (tileCf != null) {
      canvas.restore();
      _viewFilterPaint.colorFilter = null;
    }

    // --- Tile hatch overlays ---
    if (hatchRenderer != null && materialHatchMap != null) {
      _drawTileHatches(canvas, size);
    }

    // Draw painted tile overlays (tile painter system)
    if (paintedTiles != null &&
        paintedTiles!.isNotEmpty &&
        paintColor != null) {
      _drawPaintedTileOverlays(canvas, size);
    }

    // Draw per-tile coloured overlays (hologram system)
    if (tileOverlays != null && tileOverlays!.isNotEmpty) {
      _drawTileOverlays(canvas, size);
    }

    for (final pair in _pathDepthBuf) {
      PathRenderable.drawPath(canvas, camera, size, pair.$2);
    }

    // Draw HUD drag preview path
    if (dragPreviewPath != null) {
      _drawDragPreviewPath(canvas, dragPreviewPath!);
    }

    // Draw queued move action paths (semi-dark blue)
    for (final qp in queuedMovePaths) {
      _drawDragPreviewPath(canvas, qp);
    }

    // Draw selected action path (white highlight)
    if (selectedActionPath != null) {
      _drawDragPreviewPath(canvas, selectedActionPath!);
    }

    // --- Assets (structures and friends) ---
    // Build friend-to-tile lookup for per-cell depth interleaving.
    _structureBuf.clear();
    _friendBuf.clear();
    _friendTileLookup.clear();
    for (final r in _assetRenderBuf) {
      if (r.asset.tag != null) {
        _friendBuf.add(r);
        final key = _tileKey(r.asset.coordinate);
        (_friendTileLookup[key] ??= []).add(r);
      } else {
        _structureBuf.add(r);
      }
    }

    final dimStructures = assetDimOpacity < 1.0;
    final applyStructureFilter = structureOpacity < 1.0 || structCf != null;
    final dimFriends = assetDimOpacity < 1.0;
    final applyFriendLayer = friendCf != null || dimFriends;

    // Prepare structure paint for per-cell drawing when interleaving.
    Paint? structFilterPaint;
    if (applyStructureFilter || dimStructures) {
      final effectiveOpacity =
          (dimStructures ? assetDimOpacity : 1.0) * structureOpacity;
      structFilterPaint = Paint()
        ..color = Color.fromRGBO(255, 255, 255, effectiveOpacity);
      if (structCf != null) {
        structFilterPaint.colorFilter = structCf;
      }
    }

    // Walk all assets in depth order; interleave per-tile.
    _drawnFriends.clear();

    if (showDrawOrder) {
      // --- Debug draw-order mode: spectral-tint every cell & friend ---
      for (final r in _assetRenderBuf) {
        final center = r.asset.toScreen(camera, size);
        if (center.dx < -_cullBuffer || center.dx > size.width + _cullBuffer ||
            center.dy < -_cullBuffer ||
            center.dy > size.height + _cullBuffer) {
          continue;
        }
        if (r.asset.tag != null) {
          if (_drawnFriends.contains(r)) continue;
          _drawFriendTinted(canvas, camera, size, r,
              IsoSpriteGrid.spectralColor(0.5));
          continue;
        }
        final key = _tileKey(r.asset.coordinate);
        final friendsHere = _friendTileLookup[key];
        if (friendsHere != null && friendsHere.isNotEmpty) {
          _drawStructureInterleavedTinted(
              canvas, camera, size, r, friendsHere);
          _drawnFriends.addAll(friendsHere);
        } else {
          _drawStructureTinted(canvas, camera, size, r);
        }
      }
    } else if (cellColorTheme != null) {
      // --- Color theme mode: tint structure cells by coordinate ---
      for (final r in _assetRenderBuf) {
        final center = r.asset.toScreen(camera, size);
        if (center.dx < -_cullBuffer || center.dx > size.width + _cullBuffer ||
            center.dy < -_cullBuffer ||
            center.dy > size.height + _cullBuffer) {
          continue;
        }
        if (r.asset.tag != null) {
          if (_drawnFriends.contains(r)) continue;
          _drawFriendFull(canvas, camera, size, r,
              applyFriendLayer: applyFriendLayer,
              friendCf: friendCf,
              dimFriends: dimFriends);
          continue;
        }
        final key = _tileKey(r.asset.coordinate);
        final friendsHere = _friendTileLookup[key];
        if (friendsHere != null && friendsHere.isNotEmpty) {
          _drawStructureInterleavedThemed(
              canvas, camera, size, r, friendsHere, cellColorTheme!);
          _drawnFriends.addAll(friendsHere);
        } else {
          _drawStructureThemed(canvas, camera, size, r, cellColorTheme!);
        }
      }
    } else {
      // --- Normal draw path ---
      // Attempt raster cache for static structures when no friends overlap.
      // Only track friend tiles that overlap structure tiles (those affect rendering).
      final structureKeys = <String>{};
      for (final s in _structureBuf) {
        structureKeys.add(_tileKey(s.asset.coordinate));
      }
      final friendKeys = _friendTileLookup.keys
          .where((k) => structureKeys.contains(k))
          .toSet();
      final cache = sceneRasterCache;
      final canUseCache = cache != null &&
          visibilityMap == null &&
          structFilterPaint == null;

      if (canUseCache &&
          cache.isValid(
            camera: camera,
            friendTileKeys: friendKeys,
            viewportSize: size,
          )) {
        // Draw cached static structures as single image.
        canvas.drawImage(cache.image!, cache.offset, Paint());
        // Still need to draw friends individually.
        for (final r in _assetRenderBuf) {
          if (r.asset.tag == null) continue;
          if (_drawnFriends.contains(r)) continue;
          final center = r.asset.toScreen(camera, size);
          if (center.dx < -_cullBuffer ||
              center.dx > size.width + _cullBuffer ||
              center.dy < -_cullBuffer ||
              center.dy > size.height + _cullBuffer) {
            continue;
          }
          _drawFriendFull(canvas, camera, size, r,
              applyFriendLayer: applyFriendLayer,
              friendCf: friendCf,
              dimFriends: dimFriends);
        }
      } else {
        // Standard per-asset draw. Record structures for cache if eligible.
        ui.PictureRecorder? recorder;
        Canvas drawCanvas = canvas;
        // Record to cache when no friend occupies a structure tile.
        if (canUseCache && cache.isCameraStable && friendKeys.isEmpty) {
          recorder = ui.PictureRecorder();
          drawCanvas = Canvas(recorder, Offset.zero & size);
        }

        for (final r in _assetRenderBuf) {
          final center = r.asset.toScreen(camera, size);
          if (center.dx < -_cullBuffer ||
              center.dx > size.width + _cullBuffer ||
              center.dy < -_cullBuffer ||
              center.dy > size.height + _cullBuffer) {
            continue;
          }

          if (r.asset.tag != null) {
            if (_drawnFriends.contains(r)) continue;
            _drawFriendFull(canvas, camera, size, r,
                applyFriendLayer: applyFriendLayer,
                friendCf: friendCf,
                dimFriends: dimFriends);
            continue;
          }

          // Structure — check visibility.
          if (visibilityMap != null) {
            final tileKey =
                '${r.asset.coordinate.x}:${r.asset.coordinate.y}';
            final tileVis =
                visibilityMap![tileKey] ?? TileVisibility.hidden;
            if (tileVis == TileVisibility.hidden) continue;
            if (tileVis == TileVisibility.fog) {
              final fogAlpha = fogOpacities[tileKey] ?? 0.0;
              final fogDim = (1.0 - fogAlpha).clamp(0.1, 1.0);
              _fogDimPaint.color =
                  Color.fromRGBO(255, 255, 255, fogDim);
              final key = _tileKey(r.asset.coordinate);
              final friendsHere = _friendTileLookup[key];
              drawCanvas.saveLayer(null, _fogDimPaint);
              if (friendsHere != null && friendsHere.isNotEmpty) {
                _drawStructureInterleaved(drawCanvas, camera, size, r, friendsHere,
                    applyFriendLayer: applyFriendLayer,
                    friendCf: friendCf,
                    dimFriends: dimFriends);
                _drawnFriends.addAll(friendsHere);
              } else {
                r.draw(drawCanvas, camera, size);
              }
              drawCanvas.restore();
              continue;
            }
          }

          final key = _tileKey(r.asset.coordinate);
          final friendsHere = _friendTileLookup[key];
          if (friendsHere != null && friendsHere.isNotEmpty) {
            if (structFilterPaint != null) {
              drawCanvas.saveLayer(null, structFilterPaint);
            }
            _drawStructureInterleaved(drawCanvas, camera, size, r, friendsHere,
                applyFriendLayer: applyFriendLayer,
                friendCf: friendCf,
                dimFriends: dimFriends);
            if (structFilterPaint != null) {
              drawCanvas.restore();
            }
            _drawnFriends.addAll(friendsHere);
          } else {
            if (structFilterPaint != null) {
              drawCanvas.saveLayer(null, structFilterPaint);
            }
            r.draw(drawCanvas, camera, size);
            if (structFilterPaint != null) {
              drawCanvas.restore();
            }
          }
        }

        // Finalize cache recording.
        if (recorder != null) {
          final picture = recorder.endRecording();
          // Also draw to the real canvas.
          canvas.drawPicture(picture);
          // Rasterize to image and store in cache.
          final image = picture.toImageSync(
            size.width.ceil(),
            size.height.ceil(),
          );
          picture.dispose();
          cache!.store(
            image: image,
            imageOffset: Offset.zero,
            camera: camera,
            friendTileKeys: friendKeys,
            viewportSize: size,
          );
        }
      }
    }

    // Draw dropped item bubbles on top of structures and friends
    if (droppedItems != null) {
      for (final coord in droppedItems!.allDroppedCoordinates) {
        final item = droppedItems!.getAt(coord);
        if (item != null) {
          _drawDroppedItemIndicator(canvas, size, coord, item);
        }
      }
    }

    // Draw queued TileAction icons (floating "!" above tiles)
    if (queuedActionCoordinates.isNotEmpty) {
      _drawQueuedActionIcons(canvas, size);
    }

    // Draw selection highlight
    // Passive tile glow (dim) under a selected entity
    if (passiveHighlightCoord != null && selectedTile == null) {
      _drawPassiveTileHighlight(canvas, size, passiveHighlightCoord!);
    }
    // Active tile selection (bright cyan outline) for direct tile clicks
    if (selectedTile != null) {
      _drawTileSelection(canvas, size, selectedTile!);
    }
    // Asset wireframe on top – structure=white, friend=gold, foliage=green
    for (final asset in selectedAssets) {
      final Color color;
      if (asset.tag != null) {
        color = Colors.amber;
      } else if (asset.category == AssetCategory.foliage) {
        color = Colors.lightGreenAccent;
      } else {
        color = Colors.white;
      }
      _drawAssetSelection(canvas, size, asset, color);
    }

    // Draw edit mode tile selection (cyan outline)
    if (editingTileCoord != null) {
      _drawEditTileSelection(canvas, size, editingTileCoord!);
    }

    // Draw click marker
    if (clickPosition != null) {
      _drawClickMarker(canvas, clickPosition!);
    }

    // Draw ghost path preview with white tint and flashing animation
    if (ghostPath != null && ghostFlashOpacity != null) {
      // Apply 50% white tint to ghost path base color
      final baseColor = Color.lerp(ghostPath!.style.color, Colors.white, 0.5)!;

      // Create ghost renderable with flashing animation
      final ghostRenderable = PathRenderable(
        path: PathEntry(
          id: 'ghost',
          coordinates: ghostPath!.coordinates,
          style: ghostPath!.style.copyWith(
            color: baseColor.withOpacity(ghostFlashOpacity!),
          ),
        ),
      );
      ghostRenderable.draw(canvas, camera, size);
    }

    // Draw coordinates if enabled
    if (showCoordinates) {
      _drawCoordinates(canvas, size);
    }

    // Draw hit box debug overlay
    if (showHitBoxes) {
      _drawHitBoxes(canvas, size);
    }
  }

  /// Draw hit testing bounding boxes and outline polygons for debugging
  void _drawHitBoxes(Canvas canvas, Size size) {
    final boundsPaint = Paint()
      ..color = Colors.yellow.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final outlinePaint = Paint()
      ..color = Colors.greenAccent.withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final outlineFillPaint = Paint()
      ..color = Colors.greenAccent.withOpacity(0.15)
      ..style = PaintingStyle.fill;

    for (final asset in assets) {
      final sprite = asset.asset.getSpriteForInstance(asset, camera);
      final tileCenter = asset.toScreen(camera, size);

      // Calculate sprite dimensions (same as IsoAsset.draw)
      final spriteWidth = sprite.size.width * asset.asset.scale * camera.zoom;
      final spriteHeight = sprite.size.height * asset.asset.scale * camera.zoom;

      final topLeft = IsoAsset.anchoredTopLeft(
          tileCenter, spriteWidth, spriteHeight, sprite);
      final spriteX = topLeft.dx;
      final spriteY = topLeft.dy;

      // Scale factors
      final scaleX = spriteWidth / sprite.size.width;
      final scaleY = spriteHeight / sprite.size.height;

      // Draw outline polygon if available
      if (sprite is VectorIsoSprite && sprite.outlinePolygon != null) {
        final outline = sprite.outlinePolygon!;
        if (outline.length >= 3) {
          // Transform polygon to screen coordinates
          final screenPolygon = <Offset>[];
          for (final p in outline) {
            screenPolygon.add(
              Offset(spriteX + p.dx * scaleX, spriteY + p.dy * scaleY),
            );
          }

          // Compute bounding box from actual polygon points
          var minX = screenPolygon[0].dx;
          var maxX = screenPolygon[0].dx;
          var minY = screenPolygon[0].dy;
          var maxY = screenPolygon[0].dy;
          for (final p in screenPolygon) {
            if (p.dx < minX) minX = p.dx;
            if (p.dx > maxX) maxX = p.dx;
            if (p.dy < minY) minY = p.dy;
            if (p.dy > maxY) maxY = p.dy;
          }
          final polygonBounds = Rect.fromLTRB(minX, minY, maxX, maxY);

          // Draw bounding box (from polygon bounds)
          canvas.drawRect(polygonBounds, boundsPaint);

          // Draw outline polygon
          final path = Path()..moveTo(screenPolygon[0].dx, screenPolygon[0].dy);
          for (var i = 1; i < screenPolygon.length; i++) {
            path.lineTo(screenPolygon[i].dx, screenPolygon[i].dy);
          }
          path.close();

          canvas.drawPath(path, outlineFillPaint);
          canvas.drawPath(path, outlinePaint);
        }
      } else {
        // Fallback: draw sprite rect as bounding box
        final spriteRect = Rect.fromLTWH(
          spriteX,
          spriteY,
          spriteWidth,
          spriteHeight,
        );
        canvas.drawRect(spriteRect, boundsPaint);
      }
    }

    // Draw debug info from last click if available
    if (hitTestDebugInfo != null) {
      _drawHitTestDebugInfo(canvas, hitTestDebugInfo!);
    }
  }

  /// Draw debug visualization for the last hit test
  void _drawHitTestDebugInfo(Canvas canvas, HitTestDebugInfo info) {
    // Draw click position marker
    final clickPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    canvas.drawCircle(info.clickPosition, 8, clickPaint);

    final clickOutlinePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(info.clickPosition, 8, clickOutlinePaint);

    // Draw tested polygons with different colors
    for (final (assetId, polygon) in info.testedPolygons) {
      if (polygon.length < 3) continue;

      final isHit = assetId == info.hitAssetId;
      final polyPaint = Paint()
        ..color = isHit
            ? Colors.cyan.withOpacity(0.8)
            : Colors.purple.withOpacity(0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isHit ? 3.0 : 1.5;

      final fillPaint = Paint()
        ..color = isHit
            ? Colors.cyan.withOpacity(0.3)
            : Colors.purple.withOpacity(0.1)
        ..style = PaintingStyle.fill;

      final path = Path()..moveTo(polygon[0].dx, polygon[0].dy);
      for (var i = 1; i < polygon.length; i++) {
        path.lineTo(polygon[i].dx, polygon[i].dy);
      }
      path.close();

      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, polyPaint);

      // Draw asset label
      final textPainter = TextPainter(
        text: TextSpan(
          text: assetId,
          style: TextStyle(
            color: isHit ? Colors.cyan : Colors.purple,
            fontSize: 10,
            backgroundColor: Colors.black54,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      // Find center of polygon for label
      var centerX = 0.0, centerY = 0.0;
      for (final p in polygon) {
        centerX += p.dx;
        centerY += p.dy;
      }
      centerX /= polygon.length;
      centerY /= polygon.length;

      textPainter.paint(
        canvas,
        Offset(
          centerX - textPainter.width / 2,
          centerY - textPainter.height / 2,
        ),
      );
    }

    // Draw info text at top
    final infoText =
        'Click: ${info.clickPosition.dx.toStringAsFixed(0)}, ${info.clickPosition.dy.toStringAsFixed(0)} | '
        'Tested: ${info.testedPolygons.length} polygons | '
        'Hit: ${info.hitAssetId ?? "none"}';

    final infoPainter = TextPainter(
      text: TextSpan(
        text: infoText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          backgroundColor: Colors.black87,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    infoPainter.layout();
    infoPainter.paint(canvas, const Offset(10, 10));
  }

  /// Depth in screen-space pixels for the tile extrusion effect.
  static const double _tileDepthPx = 300.0;

  /// Grid direction for each diamond edge: edge [i]→[i+1] faces this neighbor.
  static const List<(int, int)> _edgeDirs = [
    (0, -1), // edge 0→1 faces north (y-1)
    (1, 0),  // edge 1→2 faces east  (x+1)
    (0, 1),  // edge 2→3 faces south (y+1)
    (-1, 0), // edge 3→0 faces west  (x-1)
  ];

  /// Earthy brown base for depth faces (independent of tile material color).
  static const Color _depthBaseColor = Color(0xFF5C3A1E);

  void _drawTileDepthFaces(
    Canvas canvas,
    IsoCamera camera,
    Size size,
    _TileRenderable renderable,
  ) {
    if (renderable.visibility == TileVisibility.hidden) return;

    final tile = renderable.tile;
    final coord = tile.coordinate;
    final angleRad = camera.view.angleRad;

    final points = coord.getDiamondPoints(camera, size);
    final elevDy = tile.elevation * renderable.terrainAmplitude * camera.zoom;
    if (elevDy != 0) {
      for (var i = 0; i < points.length; i++) {
        points[i] = Offset(points[i].dx, points[i].dy - elevDy);
      }
    }

    final depthPx = _tileDepthPx * camera.zoom;

    for (var e = 0; e < 4; e++) {
      final dir = _edgeDirs[e];
      final nx = coord.x + dir.$1;
      final ny = coord.y + dir.$2;
      final neighborKey = '$nx:$ny';

      if (!voidTileKeys!.contains(neighborKey)) continue;

      // Only draw faces whose outward normal points toward the camera.
      final depthContrib =
          IsoProjection.depthForAngle(dir.$1, dir.$2, angleRad);
      if (depthContrib <= 0) continue;

      final a = points[e];
      final b = points[(e + 1) % 4];
      final aBottom = Offset(a.dx, a.dy + depthPx);
      final bBottom = Offset(b.dx, b.dy + depthPx);

      final face = Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy)
        ..lineTo(bBottom.dx, bBottom.dy)
        ..lineTo(aBottom.dx, aBottom.dy)
        ..close();

      final darkenFactor = depthContrib > 0.5 ? 0.20 : 0.40;
      _depthFillPaint.color = _darken(_depthBaseColor, darkenFactor)
          .withValues(alpha: renderable.tileFillOpacity);
      canvas.drawPath(face, _depthFillPaint);
      _depthStrokePaint.color = const Color(0xFF000000)
          .withValues(alpha: 0.30 * renderable.tileFillOpacity);
      canvas.drawPath(face, _depthStrokePaint);

      if (renderable.fogOverlayOpacity > 0.001) {
        _fogPaint.color =
            _bgColor.withValues(alpha: renderable.fogOverlayOpacity);
        canvas.drawPath(face, _fogPaint);
      }
    }
  }

  /// Collect the top-surface diamond edges that border void tiles into [batch].
  /// Drawn as a single thick stroke after all tile fills/outlines so the
  /// boundary reads as one continuous cliff-edge line.
  void _collectVoidEdges(IsoCamera camera, Size size, Path batch) {
    for (final renderable in _tileRenderBuf) {
      if (renderable.visibility == TileVisibility.hidden) continue;

      final tile = renderable.tile;
      final coord = tile.coordinate;

      final points = coord.getDiamondPoints(camera, size);
      final elevDy = tile.elevation * renderable.terrainAmplitude * camera.zoom;
      if (elevDy != 0) {
        for (var i = 0; i < points.length; i++) {
          points[i] = Offset(points[i].dx, points[i].dy - elevDy);
        }
      }

      for (var e = 0; e < 4; e++) {
        final dir = _edgeDirs[e];
        final nx = coord.x + dir.$1;
        final ny = coord.y + dir.$2;
        if (!voidTileKeys!.contains('$nx:$ny')) continue;

        final a = points[e];
        final b = points[(e + 1) % 4];
        batch.moveTo(a.dx, a.dy);
        batch.lineTo(b.dx, b.dy);
      }
    }
  }

  static final Map<int, Path> _colorBatchPaths = {};
  static final Paint _batchFillPaint = Paint()..style = PaintingStyle.fill;

  void _batchTileFills(Canvas canvas, Size size, Path outlineBatch) {
    _colorBatchPaths.clear();
    for (final renderable in _tileRenderBuf) {
      if (renderable.visibility == TileVisibility.hidden) {
        renderable.drawTile(canvas, camera, size, outlineBatch);
        continue;
      }
      final points = renderable.tile.coordinate.getDiamondPoints(camera, size);
      final path = Path()
        ..moveTo(points[0].dx, points[0].dy)
        ..lineTo(points[1].dx, points[1].dy)
        ..lineTo(points[2].dx, points[2].dy)
        ..lineTo(points[3].dx, points[3].dy)
        ..close();

      final color = _darken(renderable.tile.color, 0.02)
          .withValues(alpha: tileFillOpacity);
      // ignore: deprecated_member_use
      (_colorBatchPaths[color.value] ??= Path()).addPath(path, Offset.zero);
      outlineBatch.addPath(path, Offset.zero);
    }
    // Draw all tile fills in color batches (one drawPath per unique color).
    for (final entry in _colorBatchPaths.entries) {
      // ignore: deprecated_member_use
      _batchFillPaint.color = Color(entry.key);
      canvas.drawPath(entry.value, _batchFillPaint);
    }
    // Draw fog overlays and material icons on top.
    for (final renderable in _tileRenderBuf) {
      if (renderable.visibility == TileVisibility.hidden) continue;
      if (renderable.fogOverlayOpacity > 0.001) {
        final points = renderable.tile.coordinate.getDiamondPoints(camera, size);
        final fogPath = Path()
          ..moveTo(points[0].dx, points[0].dy)
          ..lineTo(points[1].dx, points[1].dy)
          ..lineTo(points[2].dx, points[2].dy)
          ..lineTo(points[3].dx, points[3].dy)
          ..close();
        _batchFillPaint.color = IsoPainter._bgColor
            .withValues(alpha: renderable.fogOverlayOpacity);
        canvas.drawPath(fogPath, _batchFillPaint);
      }
      if (renderable.showMaterialEmoji &&
          renderable.tile.materialId != null &&
          renderable.tile.materialId!.isNotEmpty) {
        final iconAlpha = renderable.tileIconOpacity *
            (1.0 - renderable.fogOverlayOpacity);
        if (iconAlpha > 0.005) {
          final center = renderable.tile.coordinate.toScreen(camera, size);
          final iconSize = 12.0 * camera.zoom;
          final dst = Rect.fromCenter(
            center: center,
            width: iconSize,
            height: iconSize,
          );
          final cache = renderable.svgIconCache;
          if (cache?.hasIcon(renderable.tile.materialId!) == true) {
            cache!.drawIcon(canvas, dst, renderable.tile.materialId!,
                alpha: iconAlpha);
          } else {
            _batchFillPaint.color =
                renderable.tile.color.withValues(alpha: iconAlpha);
            canvas.drawCircle(center, 6.0 * camera.zoom, _batchFillPaint);
          }
        }
      }
    }
  }

  /// Sort items by depth for proper rendering order
  /// Uses view-aware depth to ensure correct front-to-back ordering
  void _sortByDepth(List<IsoRenderable> items, IsoViewDirection view) {
    items.sort((a, b) {
      final depthA = a.getDepthForView(view);
      final depthB = b.getDepthForView(view);
      return depthA.compareTo(depthB);
    });
  }

  static String _tileKey(IsoCoordinate c) => '${c.x}:${c.y}';

  /// Draw a friend with its carried-material emoji underneath.
  void _drawFriendFull(
    Canvas canvas, IsoCamera camera, Size size,
    _AssetRenderable r, {
    required bool applyFriendLayer,
    required ColorFilter? friendCf,
    required bool dimFriends,
  }) {
    final inst = r.asset;
    final mat = inst.carriedMaterial;
    final hasMat = mat != null && mat.isNotEmpty;
    final gathering =
        inst.gatherProgress > 0.0 && inst.gatherProgress < 1.0;
    if (hasMat || gathering) {
      _drawCapturedEmoji(canvas, size, inst);
    }
    if (applyFriendLayer) {
      final effectiveOpacity = dimFriends ? assetDimOpacity : 1.0;
      _viewFilterPaint.color =
          Color.fromRGBO(255, 255, 255, effectiveOpacity);
      _viewFilterPaint.colorFilter = friendCf;
      canvas.saveLayer(null, _viewFilterPaint);
    }
    r.draw(canvas, camera, size);
    if (applyFriendLayer) {
      canvas.restore();
      _viewFilterPaint.colorFilter = null;
    }
  }

  /// Draw a structure with its grid cells interleaved with friends by depth.
  void _drawStructureInterleaved(
    Canvas canvas, IsoCamera camera, Size size,
    _AssetRenderable structure,
    List<_AssetRenderable> friends, {
    required bool applyFriendLayer,
    required ColorFilter? friendCf,
    required bool dimFriends,
  }) {
    final viewAngle = IsoProjection.angleForView(camera.view.index);
    final tx = structure.asset.coordinate.x;
    final ty = structure.asset.coordinate.y;

    _interleaveBuf.clear();
    for (final f in friends) {
      final fx =
          f.asset.fractionalX ?? f.asset.coordinate.x.toDouble();
      final fy =
          f.asset.fractionalY ?? f.asset.coordinate.y.toDouble();
      final depth = IsoAssetInstance.friendDepthOnTile(
          fx, fy, tx, ty, viewAngle);
      _interleaveBuf.add((depth, () {
        _drawFriendFull(canvas, camera, size, f,
            applyFriendLayer: applyFriendLayer,
            friendCf: friendCf,
            dimFriends: dimFriends);
      }));
    }
    _interleaveBuf.sort((a, b) => a.$1.compareTo(b.$1));

    structure.asset.drawInterleaved(canvas, camera, size, _interleaveBuf);
  }

  static final Paint _drawOrderCirclePaint = Paint();
  static final Paint _drawOrderStrokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = Colors.white;
  static final Paint _drawOrderLayerPaint = Paint();
  static final Paint _drawOrderTintPaint = Paint();
  static final List<(double, void Function(Color))> _tintedInterleaveBuf = [];

  /// Compute the sprite destination rect for an asset instance.
  Rect _computeSpriteRect(
      IsoAssetInstance inst, IsoSprite sprite, IsoCamera cam, Size viewport) {
    final x = inst.fractionalX ?? inst.coordinate.x.toDouble();
    final y = inst.fractionalY ?? inst.coordinate.y.toDouble();
    final isoPos = IsoProjection.isoToScreen(x, y, viewIndex: cam.view.index);
    final heightOffset = inst.coordinate.h * IsoProjection.heightPerLevel;
    final worldPos = Offset(isoPos.dx, isoPos.dy - heightOffset);
    final tileCenter = cam.worldToScreen(worldPos, viewport);
    final spriteWidth = sprite.size.width * inst.asset.scale * cam.zoom;
    final spriteHeight = sprite.size.height * inst.asset.scale * cam.zoom;
    final topLeft = IsoAsset.anchoredTopLeft(
        tileCenter, spriteWidth, spriteHeight, sprite);
    return Rect.fromLTWH(topLeft.dx, topLeft.dy, spriteWidth, spriteHeight);
  }

  /// Draw a structure with spectral tint (no friends on tile).
  void _drawStructureTinted(
    Canvas canvas, IsoCamera cam, Size viewport, _AssetRenderable r,
  ) {
    final inst = r.asset;
    final sprite = inst.asset.getSpriteForView(
        cam.view, rotationOffset: inst.rotationOffset);
    if (sprite is VectorIsoSprite && sprite.grid != null) {
      final dstRect = _computeSpriteRect(inst, sprite, cam, viewport);
      sprite.grid!.drawAllTinted(canvas, dstRect, cam.view.index);
    } else {
      r.draw(canvas, cam, viewport);
    }
  }

  /// Draw a structure interleaved with friends, all with spectral tints.
  void _drawStructureInterleavedTinted(
    Canvas canvas, IsoCamera cam, Size viewport,
    _AssetRenderable structure, List<_AssetRenderable> friends,
  ) {
    final inst = structure.asset;
    final sprite = inst.asset.getSpriteForView(
        cam.view, rotationOffset: inst.rotationOffset);

    if (sprite is! VectorIsoSprite || sprite.grid == null) {
      structure.draw(canvas, cam, viewport);
      for (final f in friends) {
        _drawFriendTinted(canvas, cam, viewport, f, Colors.white);
      }
      return;
    }

    final viewAngle = IsoProjection.angleForView(cam.view.index);
    final tx = inst.coordinate.x;
    final ty = inst.coordinate.y;
    final dstRect = _computeSpriteRect(inst, sprite, cam, viewport);

    _tintedInterleaveBuf.clear();
    for (final f in friends) {
      final fx = f.asset.fractionalX ?? f.asset.coordinate.x.toDouble();
      final fy = f.asset.fractionalY ?? f.asset.coordinate.y.toDouble();
      final depth =
          IsoAssetInstance.friendDepthOnTile(fx, fy, tx, ty, viewAngle);
      _tintedInterleaveBuf.add((depth, (Color tint) {
        _drawFriendTinted(canvas, cam, viewport, f, tint);
      }));
    }
    _tintedInterleaveBuf.sort((a, b) => a.$1.compareTo(b.$1));

    sprite.grid!.drawInterleavedTinted(
      canvas, dstRect, _tintedInterleaveBuf, cam.view.index);
  }

  /// Draw a structure with a per-cell color theme (no friends on tile).
  void _drawStructureThemed(
    Canvas canvas, IsoCamera cam, Size viewport, _AssetRenderable r,
    List<List<Color>> theme,
  ) {
    final inst = r.asset;
    final sprite = inst.asset.getSpriteForView(
        cam.view, rotationOffset: inst.rotationOffset);
    if (sprite is VectorIsoSprite && sprite.grid != null) {
      final dstRect = _computeSpriteRect(inst, sprite, cam, viewport);
      sprite.grid!.drawAllWithTheme(canvas, dstRect, theme, cam.view.index);
    } else {
      r.draw(canvas, cam, viewport);
    }
  }

  /// Draw a structure interleaved with friends, using per-cell color theme.
  void _drawStructureInterleavedThemed(
    Canvas canvas, IsoCamera cam, Size viewport,
    _AssetRenderable structure, List<_AssetRenderable> friends,
    List<List<Color>> theme,
  ) {
    final inst = structure.asset;
    final sprite = inst.asset.getSpriteForView(
        cam.view, rotationOffset: inst.rotationOffset);

    if (sprite is! VectorIsoSprite || sprite.grid == null) {
      _drawStructureThemed(canvas, cam, viewport, structure, theme);
      for (final f in friends) {
        f.draw(canvas, cam, viewport);
      }
      return;
    }

    final viewAngle = IsoProjection.angleForView(cam.view.index);
    final tx = inst.coordinate.x;
    final ty = inst.coordinate.y;
    final dstRect = _computeSpriteRect(inst, sprite, cam, viewport);

    final friendEntries = <(double, VoidCallback)>[];
    for (final f in friends) {
      final fx = f.asset.fractionalX ?? f.asset.coordinate.x.toDouble();
      final fy = f.asset.fractionalY ?? f.asset.coordinate.y.toDouble();
      final depth =
          IsoAssetInstance.friendDepthOnTile(fx, fy, tx, ty, viewAngle);
      friendEntries.add((depth, () {
        f.draw(canvas, cam, viewport);
      }));
    }
    friendEntries.sort((a, b) => a.$1.compareTo(b.$1));

    sprite.grid!.drawInterleavedWithTheme(
      canvas, dstRect, theme, friendEntries, cam.view.index);
  }

  /// Draw a friend with a spectral tint over its entire body, plus a
  /// disc indicator at its base for clarity.
  void _drawFriendTinted(
    Canvas canvas, IsoCamera cam, Size viewport,
    _AssetRenderable r, Color tint,
  ) {
    final center = r.asset.toScreen(cam, viewport);

    // Tint the friend body: saveLayer → draw → srcATop overlay → restore.
    final sprite = r.asset.asset.getSpriteForInstance(r.asset, cam);
    final sw = sprite.size.width * r.asset.asset.scale * cam.zoom;
    final sh = sprite.size.height * r.asset.asset.scale * cam.zoom;
    final tl = IsoAsset.anchoredTopLeft(center, sw, sh, sprite);
    final bounds =
        Rect.fromLTWH(tl.dx - 4, tl.dy - 4, sw + 8, sh + 8).inflate(sh);

    canvas.saveLayer(bounds, _drawOrderLayerPaint);
    r.draw(canvas, cam, viewport);
    _drawOrderTintPaint
      ..color = tint.withValues(alpha: 0.55)
      ..blendMode = BlendMode.srcATop;
    canvas.drawRect(bounds, _drawOrderTintPaint);
    canvas.restore();

    // Disc indicator at the base.
    final radius = 10.0 * cam.zoom;
    _drawOrderCirclePaint
      ..color = tint
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, _drawOrderCirclePaint);
    canvas.drawCircle(center, radius, _drawOrderStrokePaint);
  }

  /// Get visibility state for a tile from the visibility map
  TileVisibility _getVisibilityForTile(IsoTileData tile) {
    if (visibilityMap == null) return TileVisibility.visible;
    final key = '${tile.coordinate.x}:${tile.coordinate.y}';
    return visibilityMap![key] ?? TileVisibility.hidden;
  }

  /// Draw reference grid
  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    // Draw a grid of tiles around the camera position
    final range = IsoProjection.getVisibleRange(
      cameraPosition: camera.position,
      viewport: size,
      zoom: camera.zoom,
      viewIndex: camera.view.index,
      padding: 1,
    );

    for (var x = range.minX; x <= range.maxX; x++) {
      for (var y = range.minY; y <= range.maxY; y++) {
        final coord = IsoCoordinate(x: x, y: y);
        final points = coord.getDiamondPoints(camera, size);

        final path = Path()
          ..moveTo(points[0].dx, points[0].dy)
          ..lineTo(points[1].dx, points[1].dy)
          ..lineTo(points[2].dx, points[2].dy)
          ..lineTo(points[3].dx, points[3].dy)
          ..close();

        canvas.drawPath(path, gridPaint);
      }
    }
  }

  /// Draw coloured diamond overlays for tiles selected by the tile painter.
  /// Batch all tiles sharing a hatch pattern into one Path per pattern, then
  /// fill each batch with the shader in a single drawPath call.  This keeps
  /// the draw-call count proportional to distinct patterns, not tile count.
  void _drawTileHatches(Canvas canvas, Size size) {
    try {
      final renderer = hatchRenderer!;
      final map = materialHatchMap!;
      final batchPaths = <String, Path>{};
      final fogBatchPaths = <String, Path>{};
      final batchCounts = <String, int>{};
      double fogDimFactor = 1.0;

      for (final renderable in _tileRenderBuf) {
        if (renderable.visibility == TileVisibility.hidden) continue;
        final mat = renderable.tile.materialId;
        if (mat == null || mat.isEmpty) continue;
        final patternId = map[mat];
        if (patternId == null || !renderer.isReady(patternId)) continue;

        final points =
            renderable.tile.coordinate.getDiamondPoints(camera, size);

        final isFog = renderable.visibility == TileVisibility.fog;
        final targetMap = isFog ? fogBatchPaths : batchPaths;
        final p = targetMap.putIfAbsent(patternId, Path.new);
        p.moveTo(points[0].dx, points[0].dy);
        p.lineTo(points[1].dx, points[1].dy);
        p.lineTo(points[2].dx, points[2].dy);
        p.lineTo(points[3].dx, points[3].dy);
        p.close();
        batchCounts[patternId] = (batchCounts[patternId] ?? 0) + 1;

        if (isFog) {
          final fogAlpha = renderable.fogOverlayOpacity;
          final dim = (1.0 - fogAlpha).clamp(0.05, 1.0);
          if (dim < fogDimFactor) fogDimFactor = dim;
        }
      }

      final worldOrigin = camera.worldToScreen(Offset.zero, size);

      for (final entry in batchPaths.entries) {
        renderer.draw(canvas, entry.value, entry.key,
            origin: worldOrigin,
            scale: camera.zoom * hatchScale,
            opacity: hatchOpacity,
            brightness: hatchBrightness);
      }

      if (fogBatchPaths.isNotEmpty) {
        for (final entry in fogBatchPaths.entries) {
          renderer.draw(canvas, entry.value, entry.key,
              origin: worldOrigin,
              scale: camera.zoom * hatchScale,
              opacity: hatchOpacity * fogDimFactor,
              brightness: hatchBrightness);
        }
      }
    } catch (_) {}
  }

  void _drawPaintedTileOverlays(Canvas canvas, Size size) {
    final overlayPaint = Paint()
      ..color = paintColor!.withOpacity(paintOpacity)
      ..style = PaintingStyle.fill;

    // Build a lookup from tile key to IsoTileData for coordinate access.
    final tileByKey = <String, IsoTileData>{};
    for (final t in tiles) {
      tileByKey[t.coordinate.key] = t;
    }

    for (final key in paintedTiles!) {
      final tileData = tileByKey[key];
      if (tileData == null) continue;

      final points = tileData.coordinate.getDiamondPoints(camera, size);
      final path = Path()
        ..moveTo(points[0].dx, points[0].dy)
        ..lineTo(points[1].dx, points[1].dy)
        ..lineTo(points[2].dx, points[2].dy)
        ..lineTo(points[3].dx, points[3].dy)
        ..close();
      canvas.drawPath(path, overlayPaint);
    }
  }

  /// Draw per-tile coloured diamond overlays from [tileOverlays].
  ///
  /// Each entry maps a tile key ("x:y") to an RGBA [Color]. The alpha channel
  /// encodes the current opacity (e.g. fade-out from a [MapHologramManager]).
  void _drawTileOverlays(Canvas canvas, Size size) {
    // Build a lookup from tile key to IsoTileData for coordinate access.
    final tileByKey = <String, IsoTileData>{};
    for (final t in tiles) {
      tileByKey[t.coordinate.key] = t;
    }

    final paint = Paint()..style = PaintingStyle.fill;

    for (final entry in tileOverlays!.entries) {
      final tileData = tileByKey[entry.key];
      if (tileData == null) continue;

      paint.color = entry.value;
      final points = tileData.coordinate.getDiamondPoints(camera, size);
      final path = Path()
        ..moveTo(points[0].dx, points[0].dy)
        ..lineTo(points[1].dx, points[1].dy)
        ..lineTo(points[2].dx, points[2].dy)
        ..lineTo(points[3].dx, points[3].dy)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  /// Draw a dropped item indicator (white bubble with emoji) on a tile
  void _drawDroppedItemIndicator(
    Canvas canvas,
    Size size,
    IsoCoordinate coord,
    DroppedItem item,
  ) {
    final center = coord.toScreen(camera, size);

    // Check if visible on screen
    if (center.dx < -50 ||
        center.dx > size.width + 50 ||
        center.dy < -50 ||
        center.dy > size.height + 50) {
      return;
    }

    // Position slightly above the tile center
    final bubbleCenter = Offset(center.dx, center.dy - 12 * camera.zoom);
    final bubbleRadius = 10.0 * camera.zoom;

    // Draw white bubble background
    final bubblePaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(bubbleCenter, bubbleRadius, bubblePaint);

    // Draw bubble border
    final borderPaint = Paint()
      ..color = Colors.grey.shade400
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(bubbleCenter, bubbleRadius, borderPaint);

    // Draw material icon inside bubble (use color from materialId or default)
    final bubbleColor = materialIdToColor?[item.materialId] ??
        const Color(0xFF6B6B6B);
    _materialIconPaint.color = bubbleColor;
    canvas.drawCircle(bubbleCenter, bubbleRadius * 0.6, _materialIconPaint);

    // Draw amount label
    if (item.amount > 1) {
      final countPainter = TextPainter(
        text: TextSpan(
          text: 'x${item.amount}',
          style: TextStyle(
            fontSize: 8.0 * camera.zoom,
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      countPainter.layout();
      countPainter.paint(
        canvas,
        Offset(
          bubbleCenter.dx + bubbleRadius * 0.5,
          bubbleCenter.dy + bubbleRadius * 0.3,
        ),
      );
    }
  }

  // Shared paint for captured-emoji opacity layer.
  static final Paint _emojiCapturePaint = Paint();

  static final Paint _milkyFillPaint = Paint()
    ..style = PaintingStyle.fill;

  /// Draw a material emoji centred on the friend's position.
  ///
  /// This is drawn BEFORE the friend sprite so the translucent body
  /// overlays the emoji, creating the visual effect of "capturing" it.
  /// During the gathering phase, the emoji fades in with [gatherProgress].
  ///
  /// When the friend is fully carrying (gatherProgress == 1.0), a milky-white
  /// fill of the friend's outline polygon is drawn behind the material icon
  /// so the coloured circle reads clearly against any background.
  void _drawCapturedEmoji(Canvas canvas, Size size, IsoAssetInstance asset) {
    final materialId = asset.carriedMaterial;
    if (materialId == null || materialId.isEmpty) return;

    final tileCenter = asset.toScreen(camera, size);

    // Off-screen cull
    if (tileCenter.dx < -60 ||
        tileCenter.dx > size.width + 60 ||
        tileCenter.dy < -60 ||
        tileCenter.dy > size.height + 60) {
      return;
    }

    final iconOpacity = asset.gatherProgress.clamp(0.0, 1.0);
    final milkyOpacity = asset.milkyFillOpacity.clamp(0.0, 1.0);

    // Milky white background fill: only after gather completes, fades in over ~200ms.
    // Drawn only when milkyOpacity > 0 so it doesn't overlap the friend during gathering.
    if (milkyOpacity > 0.01) {
      final sprite = asset.asset.getSpriteForInstance(asset, camera);
      if (sprite is VectorIsoSprite &&
          sprite.outlinePolygon != null &&
          sprite.outlinePolygon!.length >= 3) {
        final spriteW = sprite.size.width * camera.zoom * asset.asset.scale;
        final spriteH = sprite.size.height * camera.zoom * asset.asset.scale;
        final topLeft = IsoAsset.anchoredTopLeft(
            tileCenter, spriteW, spriteH, sprite);
        final dest = Rect.fromLTWH(topLeft.dx, topLeft.dy, spriteW, spriteH);
        final scaleX = dest.width / sprite.originalSize.width;
        final scaleY = dest.height / sprite.originalSize.height;

        final fillPath = Path();
        for (var i = 0; i < sprite.outlinePolygon!.length; i++) {
          final p = Offset(
            dest.left + sprite.outlinePolygon![i].dx * scaleX,
            dest.top + sprite.outlinePolygon![i].dy * scaleY,
          );
          if (i == 0) {
            fillPath.moveTo(p.dx, p.dy);
          } else {
            fillPath.lineTo(p.dx, p.dy);
          }
        }
        fillPath.close();

        _milkyFillPaint.color =
            Color.fromRGBO(255, 255, 255, 0.5 * milkyOpacity);
        canvas.drawPath(fillPath, _milkyFillPaint);
      }
    }

    // Compute anchored sprite center for the icon overlay
    final emojiSprite = asset.asset.getSpriteForInstance(asset, camera);
    final eSpriteW = emojiSprite.size.width * camera.zoom * asset.asset.scale;
    final eSpriteH = emojiSprite.size.height * camera.zoom * asset.asset.scale;
    final eTL = IsoAsset.anchoredTopLeft(
        tileCenter, eSpriteW, eSpriteH, emojiSprite);
    final spriteCenter =
        Offset(eTL.dx + eSpriteW / 2, eTL.dy + eSpriteH / 2);

    final iconSize = 16.0 * camera.zoom * asset.asset.scale;
    final iconDst = Rect.fromCenter(
      center: spriteCenter,
      width: iconSize,
      height: iconSize,
    );

    if (svgIconCache?.hasIcon(materialId) == true) {
      svgIconCache!.drawIcon(canvas, iconDst, materialId, alpha: iconOpacity);
    } else {
      final color = materialIdToColor?[materialId] ?? const Color(0xFF6B6B6B);
      _materialIconPaint.color = color.withOpacity(iconOpacity);
      canvas.drawCircle(spriteCenter, iconSize / 2, _materialIconPaint);
    }
  }

  /// Draw coordinate labels on tiles
  void _drawCoordinates(Canvas canvas, Size size) {
    for (final tile in tiles) {
      final center = tile.coordinate.toScreen(camera, size);

      // Check if center is visible
      if (center.dx < 0 ||
          center.dx > size.width ||
          center.dy < 0 ||
          center.dy > size.height) {
        continue;
      }

      final text = '${tile.coordinate.x},${tile.coordinate.y}';
      final textPainter = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final offset = Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      );

      // Draw background
      canvas.drawRect(
        offset & textPainter.size,
        Paint()..color = Colors.black.withOpacity(0.6),
      );

      // Draw text
      textPainter.paint(canvas, offset);
    }
  }

  /// Draw selection highlight on a tile (matches asset wireframe style)
  void _drawTileSelection(Canvas canvas, Size size, IsoTileData tile) {
    final points = tile.coordinate.getDiamondPoints(camera, size);

    final path = Path()
      ..moveTo(points[0].dx, points[0].dy)
      ..lineTo(points[1].dx, points[1].dy)
      ..lineTo(points[2].dx, points[2].dy)
      ..lineTo(points[3].dx, points[3].dy)
      ..close();

    // Outer glow (wider, semi-transparent) - matches asset selection
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.cyanAccent.withOpacity(0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round,
    );

    // Inner bright line - matches asset selection
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.cyanAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
  }

  /// Dim diamond glow drawn under a selected entity (passive, not a selection).
  void _drawPassiveTileHighlight(
    Canvas canvas,
    Size size,
    IsoCoordinate coord,
  ) {
    final points = coord.getDiamondPoints(camera, size);

    final path = Path()
      ..moveTo(points[0].dx, points[0].dy)
      ..lineTo(points[1].dx, points[1].dy)
      ..lineTo(points[2].dx, points[2].dy)
      ..lineTo(points[3].dx, points[3].dy)
      ..close();

    // Subtle fill glow
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.cyanAccent.withOpacity(0.08)
        ..style = PaintingStyle.fill,
    );

    // Thin dim outline
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.cyanAccent.withOpacity(0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawEditTileSelection(Canvas canvas, Size size, IsoCoordinate coord) {
    final points = coord.getDiamondPoints(camera, size);

    final path = Path()
      ..moveTo(points[0].dx, points[0].dy)
      ..lineTo(points[1].dx, points[1].dy)
      ..lineTo(points[2].dx, points[2].dy)
      ..lineTo(points[3].dx, points[3].dy)
      ..close();

    // Cyan outline matching _drawTileSelection style
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.cyanAccent.withOpacity(0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.cyanAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
  }

  /// Floating "!" icon above tiles with queued TileActions.
  void _drawQueuedActionIcons(Canvas canvas, Size size) {
    final iconPaint = Paint()
      ..color = Colors.orangeAccent
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (final coord in queuedActionCoordinates) {
      final center = coord.toScreen(camera, size);
      final radius = 10.0 * camera.zoom;
      final floatOffset = 28.0 * camera.zoom;
      final iconCenter = Offset(center.dx, center.dy - floatOffset);

      canvas.drawCircle(iconCenter, radius, iconPaint);
      canvas.drawCircle(iconCenter, radius, borderPaint);

      final tp = TextPainter(
        text: TextSpan(
          text: '!',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14.0 * camera.zoom,
            fontWeight: FontWeight.bold,
            height: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(
          iconCenter.dx - tp.width / 2,
          iconCenter.dy - tp.height / 2,
        ),
      );
    }
  }

  /// Draw selection highlight for selected asset using wireframe edges.
  /// [color] is type-based: white for structures, amber for friends.
  void _drawAssetSelection(
    Canvas canvas,
    Size size,
    IsoAssetInstance asset,
    Color color,
  ) {
    final sprite = asset.asset.getSpriteForInstance(asset, camera);

    if (sprite is VectorIsoSprite &&
        (sprite.foregroundWireframeEdges.isNotEmpty ||
            sprite.backgroundWireframeEdges.isNotEmpty)) {
      // Calculate destination rect (use fractional pos when moving)
      final tileCenter = asset.toScreen(camera, size);
      final spriteWidth = sprite.size.width * camera.zoom * asset.asset.scale;
      final spriteHeight = sprite.size.height * camera.zoom * asset.asset.scale;

      final topLeft = IsoAsset.anchoredTopLeft(
          tileCenter, spriteWidth, spriteHeight, sprite);

      final dest = Rect.fromLTWH(topLeft.dx, topLeft.dy, spriteWidth, spriteHeight);

      // Foliage uses a rectangular bounding box derived from the outline
      // polygon's extents, not the polygon shape itself.
      if (asset.category == AssetCategory.foliage &&
          sprite.outlinePolygon != null &&
          sprite.outlinePolygon!.length >= 3) {
        final scaleX = dest.width / sprite.originalSize.width;
        final scaleY = dest.height / sprite.originalSize.height;

        double minPx = double.infinity, minPy = double.infinity;
        double maxPx = double.negativeInfinity, maxPy = double.negativeInfinity;
        for (final pt in sprite.outlinePolygon!) {
          final sx = dest.left + pt.dx * scaleX;
          final sy = dest.top + pt.dy * scaleY;
          if (sx < minPx) minPx = sx;
          if (sy < minPy) minPy = sy;
          if (sx > maxPx) maxPx = sx;
          if (sy > maxPy) maxPy = sy;
        }

        final bboxRect = Rect.fromLTRB(minPx, minPy, maxPx, maxPy);

        canvas.drawRect(
          bboxRect,
          Paint()
            ..color = color.withOpacity(0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.0
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
        canvas.drawRect(
          bboxRect,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      } else if (!showNonBoundaryEdges &&
          sprite.outlinePolygon != null &&
          sprite.outlinePolygon!.length >= 3) {
        // Boundary-only mode: draw only the traced outline polygon
        final scaleX = dest.width / sprite.originalSize.width;
        final scaleY = dest.height / sprite.originalSize.height;

        final path = Path();
        for (var i = 0; i < sprite.outlinePolygon!.length; i++) {
          final p = Offset(
            dest.left + sprite.outlinePolygon![i].dx * scaleX,
            dest.top + sprite.outlinePolygon![i].dy * scaleY,
          );
          if (i == 0) {
            path.moveTo(p.dx, p.dy);
          } else {
            path.lineTo(p.dx, p.dy);
          }
        }
        path.close();

        // Outer glow
        canvas.drawPath(
          path,
          Paint()
            ..color = color.withOpacity(0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.0
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );

        // Inner bright line
        canvas.drawPath(
          path,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      } else {
        // Full wireframe mode: draw all foreground + background edges

        // Draw background edges first (hidden edges) - thinner and more subtle
        if (sprite.backgroundWireframeEdges.isNotEmpty) {
          final bgGlowPaint = Paint()
            ..color = color.withOpacity(0.15)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0
            ..strokeCap = StrokeCap.round;

          sprite.drawBackgroundWireframe(canvas, dest, bgGlowPaint);

          final bgLinePaint = Paint()
            ..color = color.withOpacity(0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8
            ..strokeCap = StrokeCap.round;

          sprite.drawBackgroundWireframe(canvas, dest, bgLinePaint);
        }

        // Draw foreground edges (visible edges) - bolder and brighter
        if (sprite.foregroundWireframeEdges.isNotEmpty) {
          final fgGlowPaint = Paint()
            ..color = color.withOpacity(0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.0
            ..strokeCap = StrokeCap.round;

          sprite.drawForegroundWireframe(canvas, dest, fgGlowPaint);

          final fgBrightPaint = Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..strokeCap = StrokeCap.round;

          sprite.drawForegroundWireframe(canvas, dest, fgBrightPaint);
        }
      }
    } else {
      // Fallback to circle for raster sprites or sprites without wireframe
      final center = asset.toScreen(camera, size);
      canvas.drawCircle(
        center,
        30 * camera.zoom,
        Paint()
          ..color = color.withOpacity(0.3)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        center,
        30 * camera.zoom,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
    }
  }

  /// Draw click position marker
  void _drawClickMarker(Canvas canvas, Offset position) {
    const size = 12.0;

    // Outer circle
    canvas.drawCircle(
      position,
      size,
      Paint()
        ..color = Colors.redAccent.withOpacity(0.3)
        ..style = PaintingStyle.fill,
    );

    // Inner circle
    canvas.drawCircle(
      position,
      3,
      Paint()
        ..color = Colors.redAccent
        ..style = PaintingStyle.fill,
    );

    // Crosshair
    canvas.drawLine(
      Offset(position.dx - size, position.dy),
      Offset(position.dx + size, position.dy),
      Paint()
        ..color = Colors.redAccent
        ..strokeWidth = 1.5,
    );
    canvas.drawLine(
      Offset(position.dx, position.dy - size),
      Offset(position.dx, position.dy + size),
      Paint()
        ..color = Colors.redAccent
        ..strokeWidth = 1.5,
    );
  }

  static final Paint _dashPaint = Paint()
    ..color = Colors.white
    ..strokeWidth = 3.0
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  void _drawDragPreviewPath(Canvas canvas, DragPathPreview preview) {
    final waypoints = preview.waypoints;
    if (waypoints.isEmpty) return;
    if (waypoints.length == 1) {
      canvas.drawCircle(
        waypoints.first,
        6,
        Paint()
          ..color = preview.color
          ..style = PaintingStyle.fill,
      );
      return;
    }

    final paint = _dashPaint..color = preview.color;
    const dashLen = 10.0;
    const gapLen = 6.0;
    const totalLen = dashLen + gapLen;

    for (int i = 0; i < waypoints.length - 1; i++) {
      final start = waypoints[i];
      final end = waypoints[i + 1];
      final dx = end.dx - start.dx;
      final dy = end.dy - start.dy;
      final dist = Offset(dx, dy).distance;
      if (dist < 0.5) continue;

      if (preview.style == DragPathStyle.dashed) {
        final steps = (dist / totalLen).ceil();
        final ux = dx / dist;
        final uy = dy / dist;
        for (int j = 0; j < steps; j++) {
          final sx = start.dx + ux * j * totalLen;
          final sy = start.dy + uy * j * totalLen;
          final ex = start.dx + ux * (j * totalLen + dashLen).clamp(0.0, dist);
          final ey = start.dy + uy * (j * totalLen + dashLen).clamp(0.0, dist);
          canvas.drawLine(Offset(sx, sy), Offset(ex, ey), paint);
        }
      } else {
        canvas.drawLine(start, end, paint);
      }
    }

    // Draw endpoint circle
    canvas.drawCircle(
      waypoints.last,
      6,
      Paint()
        ..color = preview.endpointColor ?? preview.color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant IsoPainter oldDelegate) {
    return oldDelegate.camera != camera ||
        oldDelegate.tiles != tiles ||
        oldDelegate.paths != paths ||
        oldDelegate.assets != assets ||
        oldDelegate.ghostPath != ghostPath ||
        oldDelegate.visibilityMap != visibilityMap ||
        oldDelegate.showGrid != showGrid ||
        oldDelegate.showCoordinates != showCoordinates ||
        oldDelegate.selectedTile != selectedTile ||
        oldDelegate.selectedAssets != selectedAssets ||
        oldDelegate.clickPosition != clickPosition ||
        oldDelegate.editingTileCoord != editingTileCoord ||
        oldDelegate.pathEditMode != pathEditMode ||
        oldDelegate.editingPathId != editingPathId ||
        oldDelegate.ghostFlashOpacity != ghostFlashOpacity ||
        oldDelegate.showHitBoxes != showHitBoxes ||
        oldDelegate.hitTestDebugInfo != hitTestDebugInfo ||
        oldDelegate.showMaterialEmojis != showMaterialEmojis ||
        oldDelegate.materialIconStyle != materialIconStyle ||
        oldDelegate.droppedItems != droppedItems ||
        oldDelegate.paintedTiles != paintedTiles ||
        oldDelegate.paintColor != paintColor ||
        oldDelegate.paintOpacity != paintOpacity ||
        oldDelegate.assetDimOpacity != assetDimOpacity ||
        oldDelegate.dragPreviewPath != dragPreviewPath ||
        oldDelegate.fogOpacities != fogOpacities ||
        oldDelegate.voidTileKeys != voidTileKeys ||
        oldDelegate.cellColorTheme != cellColorTheme;
  }
}

/// Painter specifically for tile rendering (can be optimized separately)
class IsoTileRenderer {
  const IsoTileRenderer();

  /// Render a single tile diamond
  void renderTile(
    Canvas canvas,
    IsoCoordinate coordinate,
    Color color,
    IsoCamera camera,
    Size viewport, {
    bool showBorder = true,
  }) {
    final points = coordinate.getDiamondPoints(camera, viewport);

    final path = Path()
      ..moveTo(points[0].dx, points[0].dy)
      ..lineTo(points[1].dx, points[1].dy)
      ..lineTo(points[2].dx, points[2].dy)
      ..lineTo(points[3].dx, points[3].dy)
      ..close();

    // Fill
    canvas.drawPath(path, Paint()..color = color);

    // Border
    if (showBorder) {
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.black.withOpacity(0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }
  }

  /// Render a tile with height/elevation
  void renderElevatedTile(
    Canvas canvas,
    IsoCoordinate coordinate,
    Color color,
    double height,
    IsoCamera camera,
    Size viewport,
  ) {
    // Draw the sides first (darker)
    final basePoints = coordinate.getDiamondPoints(camera, viewport);
    final topCoord = coordinate.copyWith(h: coordinate.h + 1);
    final topPoints = topCoord.getDiamondPoints(camera, viewport);

    final sideColor = Color.lerp(color, Colors.black, 0.3)!;

    // Right side
    final rightPath = Path()
      ..moveTo(basePoints[1].dx, basePoints[1].dy)
      ..lineTo(topPoints[1].dx, topPoints[1].dy)
      ..lineTo(topPoints[2].dx, topPoints[2].dy)
      ..lineTo(basePoints[2].dx, basePoints[2].dy)
      ..close();
    canvas.drawPath(rightPath, Paint()..color = sideColor);

    // Left side
    final leftPath = Path()
      ..moveTo(basePoints[3].dx, basePoints[3].dy)
      ..lineTo(topPoints[3].dx, topPoints[3].dy)
      ..lineTo(topPoints[0].dx, topPoints[0].dy)
      ..lineTo(basePoints[0].dx, basePoints[0].dy)
      ..close();
    canvas.drawPath(
      leftPath,
      Paint()..color = Color.lerp(color, Colors.black, 0.4)!,
    );

    // Top face
    renderTile(canvas, topCoord, color, camera, viewport);
  }
}
