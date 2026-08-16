import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../geometry/geometry.dart';
import '../../geometry/geometry_2d.dart';
import '../../geometry/geometry_algorithms.dart';
import '../../geometry/geometry_slicer.dart';
import '../../geometry/prefabs/prefab_factory.dart';
import '../../geometry/tessellation.dart';
import '../../rendering/lights.dart';
import '../../rendering/mesh.dart';
import '../../tiles/tiles.dart';
import '../../rendering/scene/camera.dart' as scene_camera;
import 'facing_sprite_ring.dart';
import 'friend_expression.dart';
import 'iso_projection.dart';
import 'iso_sprite.dart';
import 'iso_sprite_grid.dart';

/// Benchmark data collected during sprite generation.
///
/// Call [IsoVectorGenerator.lastBenchmark] after generation to retrieve the
/// timing breakdown, then [toString] or [toFileString] to format it.
class SpriteBenchmark {
  int originalFaces = 0;
  int tessellatedFaces = 0;
  final viewTimings = <_ViewTiming>[];
  final _total = Stopwatch();

  void start() => _total
    ..reset()
    ..start();
  void stop() => _total.stop();

  Duration get totalElapsed => _total.elapsed;

  @override
  String toString() {
    final buf = StringBuffer()
      ..writeln('=== Sprite Generation Benchmark ===')
      ..writeln('Faces: $originalFaces original → $tessellatedFaces tessellated '
          '(${tessellatedFaces == 0 ? 0 : (tessellatedFaces / math.max(1, originalFaces)).toStringAsFixed(1)}×)')
      ..writeln('Views: ${viewTimings.length}')
      ..writeln('Total: ${totalElapsed.inMilliseconds} ms')
      ..writeln('');

    if (viewTimings.isNotEmpty) {
      final avg = <String, int>{};
      for (final vt in viewTimings) {
        for (final e in vt.stages.entries) {
          avg[e.key] = (avg[e.key] ?? 0) + e.value;
        }
      }
      buf.writeln('Per-stage totals across all views:');
      for (final e in avg.entries) {
        buf.writeln('  ${e.key.padRight(22)} ${e.value} ms '
            '(avg ${(e.value / viewTimings.length).toStringAsFixed(1)} ms/view)');
      }
      buf.writeln('');

      for (var i = 0; i < viewTimings.length; i++) {
        final vt = viewTimings[i];
        buf.writeln('View $i (${vt.angleDeg.toStringAsFixed(1)}°): '
            '${vt.totalMs} ms');
        for (final e in vt.stages.entries) {
          buf.writeln('    ${e.key.padRight(20)} ${e.value} ms');
        }
      }
    }
    return buf.toString();
  }

  String toFileString() => '${DateTime.now().toIso8601String()}\n$this';
}

class _ViewTiming {
  _ViewTiming({required this.angleDeg});
  final double angleDeg;
  final stages = <String, int>{};
  int totalMs = 0;
}

/// Result of sprite generation including anchor offset for centering
class SpriteGenerationResult {
  const SpriteGenerationResult({
    required this.sprites,
    required this.anchorOffset,
  });

  final List<IsoSprite> sprites;

  /// Offset to center the geometry on the tile (normalized 0-1)
  final Offset anchorOffset;
}

/// Extended result that includes both cardinal (4) and all animation (16) sprites.
class FullSpriteGenerationResult {
  const FullSpriteGenerationResult({
    required this.cardinalSprites,
    required this.allSprites,
    required this.anchorOffset,
  });

  /// 4 cardinal sprites: [NW, SW, SE, NE] (indices 0-3)
  final List<IsoSprite> cardinalSprites;

  /// 16 sprites at 22.5-degree increments (index 0 = 45 deg / NW)
  final List<IsoSprite> allSprites;

  /// Offset to center the geometry on the tile (normalized 0-1)
  final Offset anchorOffset;
}

/// Result holding facing sprite rings per world view.
///
/// For each world view angle, a [FacingSpriteRing] is generated containing
/// sprites at evenly-spaced mesh rotation angles. The number of world views
/// and facing sprites per ring are both configurable.
class FacingRotationSpriteResult {
  const FacingRotationSpriteResult({
    required this.cardinalSprites,
    required this.facingSprites,
    required this.anchorOffset,
    this.expressionCardinalSprites,
    this.expressionFacingSprites,
  });

  /// 4 cardinal sprites at mesh rotation 0: [NW, SW, SE, NE]
  final List<IsoSprite> cardinalSprites;

  /// One [FacingSpriteRing] per world view angle.
  /// `facingSprites[worldViewIndex].getNearest(angleDeg)` returns the
  /// best sprite for a given facing direction.
  final List<FacingSpriteRing> facingSprites;

  /// Offset to center the geometry on the tile (normalized 0-1)
  final Offset anchorOffset;

  /// Expression-only sprites for 4 cardinal views (geometry excluded).
  /// Null when no expression was requested.
  final List<IsoSprite>? expressionCardinalSprites;

  /// Expression-only facing rings, one per world view angle.
  /// Null when no expression was requested.
  final List<FacingSpriteRing>? expressionFacingSprites;
}

/// Computes camera view angles for a given [worldViewCount].
///
/// Angles start at 45° (NW) and step **clockwise** to match the
/// [IsoViewDirection] enum order (nw → w → sw → s → se → e → ne → n).
/// For 8 views: [45, 0, 315, 270, 225, 180, 135, 90].
List<double> worldViewAngles(int worldViewCount) {
  final step = 360.0 / worldViewCount;
  return [
    for (var i = 0; i < worldViewCount; i++)
      (45.0 - IsoProjection.baseAngleDeg - i * step + 720.0) % 360.0,
  ];
}

/// Computes the cardinal indices (NW, SW, SE, NE) within a reversed-step
/// view angle list of size [worldViewCount].
///
/// Returns [NW_idx, SW_idx, SE_idx, NE_idx].
List<int> cardinalIndices(int worldViewCount) {
  final q = worldViewCount ~/ 4;
  return [
    0,
    worldViewCount - q,
    worldViewCount - 2 * q,
    worldViewCount - 3 * q,
  ];
}

/// Generates vector sprites from 3D geometry
class IsoVectorGenerator {
  /// Benchmark data from the most recent sprite generation call.
  /// Read this after calling any `generate*` method.
  static SpriteBenchmark? lastBenchmark;

  /// Multiplier applied to the longest model edge when computing the alpha
  /// threshold for boundary detection. Lower values produce tighter (more
  /// concave) boundaries; higher values approach the convex hull.
  /// Default is 1.1. Adjustable at runtime for visual debugging.
  static double alphaMultiplier = 1.1;

  /// Generate vector sprites for all 4 isometric views
  Future<List<IsoSprite>> generateVectorSprites(
    GeometryPrefabs geometryType,
    Color color, {
    double scale = 1.0,
  }) async {
    final result = await generateVectorSpritesWithOffset(
      geometryType,
      color,
      scale: scale,
    );
    return result.sprites;
  }

  /// Generate vector sprites with anchor offset for centering
  Future<SpriteGenerationResult> generateVectorSpritesWithOffset(
    GeometryPrefabs geometryType,
    Color color, {
    double scale = 1.0,
    FriendExpressionConfig? expression,
  }) async {
    // Size matches the tile bounding box logic used in IsoAssetLoader
    final width = IsoProjection.tileWidth; // 128.0
    final height = IsoProjection.tileHeight; // 64.0
    final size = Size(width, height);

    final sprites = <IsoSprite>[];
    final allBounds = <Rect>[];

    // Generate sprites from 4 angles: NW, SW, SE, NE
    final angles = [45.0, 135.0, 225.0, 315.0];

    for (final angle in angles) {
      final (sprite, _, bounds) = await _generateVectorViewWithBounds(
        geometryType,
        color,
        angle,
        size,
        scale,
        expression: expression,
      );
      sprites.add(sprite);
      if (bounds != null) {
        allBounds.add(bounds);
      }
    }

    final anchorOffset = _anchorFromBounds(allBounds, size);
    return SpriteGenerationResult(sprites: sprites, anchorOffset: anchorOffset);
  }

  /// Generate view sprites for all world view angles (no mesh rotation).
  ///
  /// The number of world views defaults to [IsoProjection.viewCount] but can
  /// be overridden via [worldViewCount]. Suitable for structures and other
  /// non-rotating assets that need correct intermediate-angle rendering.
  Future<FullSpriteGenerationResult> generateAllViewSprites(
    GeometryPrefabs geometryType,
    Color color, {
    double scale = 1.0,
    FriendExpressionConfig? expression,
    int? worldViewCount,
  }) async {
    final viewCount = worldViewCount ?? IsoProjection.viewCount;
    final width = IsoProjection.tileWidth;
    final height = IsoProjection.tileHeight;
    final size = Size(width, height);

    final viewAngles = worldViewAngles(viewCount);
    final allSprites = <IsoSprite>[];
    final allBounds = <Rect>[];

    for (final angle in viewAngles) {
      final (sprite, _, bounds) = await _generateVectorViewWithBounds(
        geometryType,
        color,
        angle,
        size,
        scale,
        expression: expression,
      );
      allSprites.add(sprite);
      if (bounds != null) {
        allBounds.add(bounds);
      }
    }

    // Extract the 4 cardinal sprites
    final cardinals = cardinalIndices(viewCount);
    final cardinalSprites = [for (final i in cardinals) allSprites[i]];

    final anchorOffset = _anchorFromBounds(allBounds, size);

    return FullSpriteGenerationResult(
      cardinalSprites: cardinalSprites,
      allSprites: allSprites,
      anchorOffset: anchorOffset,
    );
  }

  /// Generate facing sprite rings for all world view angles.
  ///
  /// For each of [worldViewCount] camera angles (default
  /// [IsoProjection.viewCount]), renders [facingSpriteCount] sprites with
  /// the mesh rotated evenly around the Y axis. Each world view produces
  /// one [FacingSpriteRing].
  ///
  /// Total sprites generated = worldViewCount * facingSpriteCount.
  Future<FacingRotationSpriteResult> generateFullRotationSprites(
    GeometryPrefabs geometryType,
    Color color, {
    double scale = 1.0,
    FriendExpressionConfig? expression,
    int facingSpriteCount = 16,
    int? worldViewCount,
    double meshRotationOffsetRad = 0.0,
  }) async {
    final viewCount = worldViewCount ?? IsoProjection.viewCount;
    final width = IsoProjection.tileWidth;
    final height = IsoProjection.tileHeight;
    final size = Size(width, height);

    final viewAngles = worldViewAngles(viewCount);
    final facingStepDeg = 360.0 / facingSpriteCount;
    final facingRings = <FacingSpriteRing>[];
    final exprFacingRings = <FacingSpriteRing>[];
    final allBounds = <Rect>[];
    final hasExpression = expression != null;

    for (final cameraAngle in viewAngles) {
      final sprites = <IsoSprite>[];
      final exprSprites = <IsoSprite>[];
      for (var rotIdx = 0; rotIdx < facingSpriteCount; rotIdx++) {
        final meshRotRad = rotIdx * facingStepDeg * math.pi / 180.0 + meshRotationOffsetRad;
        final (sprite, exprSprite, bounds) =
            await _generateVectorViewWithBounds(
          geometryType,
          color,
          cameraAngle,
          size,
          scale,
          expression: expression,
          meshRotationRad: meshRotRad,
        );
        sprites.add(sprite);
        if (exprSprite != null) exprSprites.add(exprSprite);
        if (bounds != null) {
          allBounds.add(bounds);
        }
      }
      facingRings.add(FacingSpriteRing(sprites));
      if (hasExpression) {
        exprFacingRings.add(FacingSpriteRing(exprSprites));
      }
    }

    // Cardinal sprites at mesh rotation 0 (default resting orientation)
    final cardinals = cardinalIndices(viewCount);
    final cardinalSprites = [
      for (final i in cardinals) facingRings[i].sprites[0],
    ];
    final exprCardinalSprites = hasExpression
        ? [for (final i in cardinals) exprFacingRings[i].sprites[0]]
        : null;

    final anchorOffset = _anchorFromBounds(allBounds, size);

    return FacingRotationSpriteResult(
      cardinalSprites: cardinalSprites,
      facingSprites: facingRings,
      anchorOffset: anchorOffset,
      expressionCardinalSprites: exprCardinalSprites,
      expressionFacingSprites: hasExpression ? exprFacingRings : null,
    );
  }

  // --------------- Geometry-accepting public API ---------------

  /// Generate 4 cardinal view sprites from a raw [Geometry].
  ///
  /// The ortho camera is sized using [IsoProjection.worldUnitsPerTile] so
  /// that a model spanning exactly that many units fills one tile.
  Future<SpriteGenerationResult> generateSpritesFromGeometry(
    Geometry geometry,
    Color color, {
    double scale = 1.0,
    bool closedSolid = false,
  }) async {
    final bench = SpriteBenchmark()..start();
    final width = IsoProjection.tileWidth;
    final height = IsoProjection.tileHeight;
    final size = Size(width, height);

    final fixedGeometry = closedSolid ? fixWindingOrder(geometry) : geometry;
    final tessGeometry = _tessellateForDepthSort(fixedGeometry);
    bench
      ..originalFaces = fixedGeometry.faces.length
      ..tessellatedFaces = tessGeometry.faces.length;

    final sprites = <IsoSprite>[];
    final allBounds = <Rect>[];
    final angles = [45.0, 135.0, 225.0, 315.0];

    for (final angle in angles) {
      final (sprite, _, bounds) = await _generateVectorViewFromGeometry(
        tessGeometry,
        color,
        angle,
        size,
        scale,
        benchmark: bench,
        edgeGeometry: fixedGeometry,
        closedSolid: closedSolid,
      );
      sprites.add(sprite);
      if (bounds != null) allBounds.add(bounds);
    }

    bench.stop();
    lastBenchmark = bench;
    if (kDebugMode) debugPrint(bench.toString());

    final anchorOffset = _anchorFromBounds(allBounds, size);
    return SpriteGenerationResult(sprites: sprites, anchorOffset: anchorOffset);
  }

  /// Generate view sprites for all world view angles from a raw [Geometry].
  Future<FullSpriteGenerationResult> generateAllViewSpritesFromGeometry(
    Geometry geometry,
    Color color, {
    double scale = 1.0,
    int? worldViewCount,
    bool closedSolid = false,
  }) async {
    final bench = SpriteBenchmark()..start();
    final viewCount = worldViewCount ?? IsoProjection.viewCount;
    final width = IsoProjection.tileWidth;
    final height = IsoProjection.tileHeight;
    final size = Size(width, height);

    final fixedGeometry = closedSolid ? fixWindingOrder(geometry) : geometry;
    final tessGeometry = _tessellateForDepthSort(fixedGeometry);
    bench
      ..originalFaces = fixedGeometry.faces.length
      ..tessellatedFaces = tessGeometry.faces.length;

    final viewAngles = worldViewAngles(viewCount);
    final allSprites = <IsoSprite>[];
    final allBounds = <Rect>[];

    for (final angle in viewAngles) {
      final (sprite, _, bounds) = await _generateVectorViewFromGeometry(
        tessGeometry,
        color,
        angle,
        size,
        scale,
        benchmark: bench,
        edgeGeometry: fixedGeometry,
        closedSolid: closedSolid,
      );
      allSprites.add(sprite);
      if (bounds != null) allBounds.add(bounds);
    }

    final cardinals = cardinalIndices(viewCount);
    final cardinalSprites = [for (final i in cardinals) allSprites[i]];
    final anchorOffset = _anchorFromBounds(allBounds, size);

    bench.stop();
    lastBenchmark = bench;
    if (kDebugMode) debugPrint(bench.toString());

    return FullSpriteGenerationResult(
      cardinalSprites: cardinalSprites,
      allSprites: allSprites,
      anchorOffset: anchorOffset,
    );
  }

  /// Render one view of a [Geometry] (expected to be pre-tessellated by the
  /// caller when depth-sort accuracy matters).
  ///
  /// Uses a fixed ortho scale derived from the 10:1 tile convention so that
  /// model units map predictably to tile sizes.
  Future<(VectorIsoSprite, VectorIsoSprite?, Rect?)>
      _generateVectorViewFromGeometry(
    Geometry geometry,
    Color color,
    double angle,
    Size size,
    double scale, {
    SpriteBenchmark? benchmark,
    Geometry? edgeGeometry,
    bool closedSolid = false,
  }) async {
    final sw = Stopwatch();
    final vt = benchmark != null ? (_ViewTiming(angleDeg: angle)) : null;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // For closed solids with fixed winding, backface culling is safe and
    // dramatically reduces face/edge counts.
    final doubleSided = !closedSolid;

    final mesh = Mesh(
      id: 'obj-sprite-mesh',
      name: 'OBJ Sprite',
      geometry: geometry,
      material: MaterialModel(color: color, doubleSided: doubleSided),
    );

    // Fixed ortho scale: half the tile-width convention, with margin.
    final orthoScale = (IsoProjection.worldUnitsPerTile / 2) * 1.15 * scale;

    final angleRad = angle * math.pi / 180.0;
    const distance = 200.0;

    final cameraPos = Vector3(
      distance * math.cos(angleRad),
      distance * 0.6,
      distance * math.sin(angleRad),
    );

    final camera = scene_camera.Camera(
      name: 'obj-vector-cam',
      position: cameraPos,
      target: Vector3.zero(),
      projection: scene_camera.ProjectionType.orthographic,
      orthographicScale: orthoScale,
      near: 0.1,
      far: 1000,
    );

    final lights = [
      DirectionalLight(
        color: Colors.white,
        intensity: 1.0,
        direction: Vector3(-0.85, -1.0, 0.35),
      ),
      DirectionalLight(
        color: Colors.white70,
        intensity: 0.3,
        direction: Vector3(0.5, -0.8, -0.3),
      ),
    ];

    // Position-based grid assignment via GeometrySlicer.
    // When edgeGeometry is provided, tessellated geometry is used for fill
    // and the original geometry for edge collection/classification.
    final renderResult = _renderMeshToCanvasWithBounds(
      canvas,
      mesh,
      camera,
      size,
      lights,
      0.4,
      assignGrid: true,
      timing: vt,
      edgeGeometry: edgeGeometry,
      skipEdgeClassify: closedSolid,
    );

    sw
      ..reset()
      ..start();
    final picture = recorder.endRecording();

    // Build 5x5 grid of cell pictures from the face-to-cell mapping.
    final grid = _buildSpriteGrid(renderResult.faces, picture, size);
    vt?.stages['grid_build'] = (sw..stop()).elapsedMilliseconds;

    sw
      ..reset()
      ..start();
    var outlinePolygon = traceOutlineFromEdges(renderResult.rawForeground);
    // Validate that the traced outline covers the projection adequately.
    // For some view angles, the trace may find a small internal loop rather
    // than the full outer boundary.
    if (outlinePolygon != null && renderResult.bounds != null) {
      final traceBounds = _boundsOfPoints(outlinePolygon);
      final fullBounds = renderResult.bounds!;
      final traceArea = traceBounds.width * traceBounds.height;
      final fullArea = fullBounds.width * fullBounds.height;
      if (fullArea > 0 && traceArea / fullArea < 0.25) {
        outlinePolygon = null;
      }
    }
    if (outlinePolygon == null &&
        renderResult.allProjectedPoints.isNotEmpty) {
      outlinePolygon = alphaHull(
        renderResult.allProjectedPoints,
        renderResult.rawAllFaceEdges,
        alphaMultiplier: alphaMultiplier,
      );
      if (outlinePolygon == null) {
        final hull = convexHull(renderResult.allProjectedPoints);
        if (hull.length >= 3) outlinePolygon = hull;
      }
    }
    vt?.stages['outline_trace'] = (sw..stop()).elapsedMilliseconds;

    final groundPoint = _computeGroundPoint(geometry, mesh.transformMatrix, camera, size);

    final sprite = VectorIsoSprite(
      picture,
      size,
      grid: grid,
      foregroundWireframeEdges: renderResult.foreground,
      backgroundWireframeEdges: renderResult.background,
      outlinePolygon: outlinePolygon,
      groundPoint: groundPoint,
    );

    if (vt != null) {
      vt.totalMs =
          vt.stages.values.fold<int>(0, (sum, ms) => sum + ms);
      benchmark!.viewTimings.add(vt);
    }

    return (sprite, null, renderResult.bounds);
  }

  /// Partition sorted projected faces by their grid cell assignment and
  /// record each non-empty cell into a separate [ui.Picture].
  IsoSpriteGrid? _buildSpriteGrid(
    List<_ProjectedFace> sortedFaces,
    ui.Picture combinedPicture,
    Size size,
  ) {
    if (sortedFaces.isEmpty) return null;

    // Group faces by cell.
    final buckets = List.generate(
      kSpriteGridSize,
      (_) => List<List<_ProjectedFace>?>.filled(kSpriteGridSize, null),
    );
    bool anyAssigned = false;

    for (final face in sortedFaces) {
      if (face.gridRow < 0 || face.gridCol < 0) continue;
      final r = face.gridRow;
      final c = face.gridCol;
      (buckets[r][c] ??= []).add(face);
      anyAssigned = true;
    }

    if (!anyAssigned) return null;

    final cellPictures = List.generate(
      kSpriteGridSize,
      (_) => List<ui.Picture?>.filled(kSpriteGridSize, null),
    );

    for (int r = 0; r < kSpriteGridSize; r++) {
      for (int c = 0; c < kSpriteGridSize; c++) {
        final bucket = buckets[r][c];
        if (bucket == null || bucket.isEmpty) continue;
        cellPictures[r][c] = _recordFaces(bucket, size);
      }
    }

    return IsoSpriteGrid(
      cells: cellPictures,
      combined: combinedPicture,
      size: size,
    );
  }

  // --------------- Shared helpers ---------------

  /// Tessellate geometry so that no face edge exceeds a target length derived
  /// from the model's bounding box. This mirrors the [RenderGroup] approach:
  /// smaller faces each get their own depth value, making the painter's
  /// algorithm sort correctly for overlapping/intersecting geometry.
  Geometry _tessellateForDepthSort(Geometry geometry) {
    final bounds = geometryBounds(geometry);
    if (bounds == null) return geometry;
    final dim = smallestDimension(bounds);
    if (dim <= 0) return geometry;
    final maxEdge = dim / kSpriteGridSize;
    return tessellateGeometry(geometry, maxEdge);
  }

  /// Compute average anchor offset from bounding boxes.
  Offset _anchorFromBounds(List<Rect> allBounds, Size size) {
    if (allBounds.isEmpty) return Offset.zero;
    double totalCenterX = 0;
    double totalCenterY = 0;
    for (final bounds in allBounds) {
      totalCenterX += bounds.center.dx / size.width;
      totalCenterY += bounds.center.dy / size.height;
    }
    final avgCenterX = totalCenterX / allBounds.length;
    final avgCenterY = totalCenterY / allBounds.length;
    return Offset(0.5 - avgCenterX, 0.5 - avgCenterY);
  }


  /// Generate a vector view and return geometry sprite, optional expression
  /// sprite, and bounding box.
  ///
  /// When [expression] is provided, the expression (eyes) is rendered into a
  /// **separate** [VectorIsoSprite] so that it can be composited with
  /// independent opacity (e.g. fully-opaque eyes on a translucent body).
  ///
  /// When [meshRotationRad] is provided, the mesh is rotated around the Y axis
  /// by that amount before rendering. This keeps the camera (and therefore
  /// lighting/shading) fixed while the friend appears to turn.
  Future<(VectorIsoSprite, VectorIsoSprite?, Rect?)>
      _generateVectorViewWithBounds(
    GeometryPrefabs geometryType,
    Color color,
    double angle,
    Size size,
    double scale, {
    FriendExpressionConfig? expression,
    double meshRotationRad = 0.0,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 1. Setup Scene
    final geometry = buildGeometry(
      GeometryFeature(id: 'sprite', geometry: geometryType, color: color),
    );

    final mesh = Mesh(
      id: 'sprite-mesh',
      name: 'Sprite',
      geometry: geometry,
      material: MaterialModel(color: color, doubleSided: true),
    );

    // Apply mesh rotation around Y axis (friend facing direction)
    if (meshRotationRad != 0.0) {
      mesh.setRotation(Vector3(0, meshRotationRad, 0));
    }

    // 2. Setup Camera — derive ortho scale from geometry extents so no
    //    geometry is ever clipped regardless of prefab or scale factor.
    double maxExtent = 0;
    for (final v in geometry.vertices) {
      final ax = v.x.abs(), ay = v.y.abs(), az = v.z.abs();
      if (ax > maxExtent) maxExtent = ax;
      if (ay > maxExtent) maxExtent = ay;
      if (az > maxExtent) maxExtent = az;
    }
    final orthoScale = math.max(maxExtent * 1.15, 120.0);

    final angleRad = angle * math.pi / 180.0;
    final distance = 200.0;

    final cameraPos = Vector3(
      distance * math.cos(angleRad),
      distance * 0.6,
      distance * math.sin(angleRad),
    );

    final camera = scene_camera.Camera(
      name: 'vector-cam',
      position: cameraPos,
      target: Vector3.zero(),
      projection: scene_camera.ProjectionType.orthographic,
      orthographicScale: orthoScale,
      near: 0.1,
      far: 1000,
    );

    // 3. Setup Lights
    final lights = [
      DirectionalLight(
        color: Colors.white,
        intensity: 1.0,
        direction: Vector3(-0.85, -1.0, 0.35),
      ),
      DirectionalLight(
        color: Colors.white70,
        intensity: 0.3,
        direction: Vector3(0.5, -0.8, -0.3),
      ),
    ];
    final globalIllumination = 0.4;

    // 4. Project and Draw geometry only (no expression)
    final renderResult = _renderMeshToCanvasWithBounds(
      canvas,
      mesh,
      camera,
      size,
      lights,
      globalIllumination,
      assignGrid: expression == null && meshRotationRad == 0.0,
    );

    // 5. End geometry recording
    final picture = recorder.endRecording();

    // 6. Build grid-based depth layers for structures (no expression, no
    //    mesh rotation). Friends use the combined picture only.
    IsoSpriteGrid? grid;
    if (expression == null && meshRotationRad == 0.0) {
      grid = _buildSpriteGrid(renderResult.faces, picture, size);
    }

    // Trace outline from raw foreground edges for hit testing
    var outlinePolygon = traceOutlineFromEdges(renderResult.rawForeground);
    if (outlinePolygon != null && renderResult.bounds != null) {
      final traceBounds = _boundsOfPoints(outlinePolygon);
      final fullBounds = renderResult.bounds!;
      final traceArea = traceBounds.width * traceBounds.height;
      final fullArea = fullBounds.width * fullBounds.height;
      if (fullArea > 0 && traceArea / fullArea < 0.25) {
        outlinePolygon = null;
      }
    }
    if (outlinePolygon == null &&
        renderResult.allProjectedPoints.isNotEmpty) {
      outlinePolygon = alphaHull(
        renderResult.allProjectedPoints,
        renderResult.rawAllFaceEdges,
        alphaMultiplier: alphaMultiplier,
      );
      if (outlinePolygon == null) {
        final hull = convexHull(renderResult.allProjectedPoints);
        if (hull.length >= 3) outlinePolygon = hull;
      }
    }

    final groundPoint = _computeGroundPoint(geometry, mesh.transformMatrix, camera, size);

    final sprite = VectorIsoSprite(
      picture,
      size,
      grid: grid,
      foregroundWireframeEdges: renderResult.foreground,
      backgroundWireframeEdges: renderResult.background,
      outlinePolygon: outlinePolygon,
      groundPoint: groundPoint,
    );

    // 6. Generate separate expression sprite if requested
    VectorIsoSprite? exprSprite;
    if (expression != null) {
      final exprRecorder = ui.PictureRecorder();
      final exprCanvas = Canvas(exprRecorder);
      _drawExpression(
        exprCanvas,
        camera,
        size,
        expression,
        angleRad,
        meshRotationRad,
      );
      final exprPicture = exprRecorder.endRecording();
      exprSprite = VectorIsoSprite(exprPicture, size);
    }

    return (sprite, exprSprite, renderResult.bounds);
  }

  /// Project two 3D eye positions to screen and draw white ellipses.
  ///
  /// Eye positions are computed from [meshRotationRad] (the direction the
  /// friend's front face is pointing) and then projected through the camera
  /// at [cameraAngleRad]. This way the eyes rotate with the mesh while
  /// shading stays consistent with the camera view.
  void _drawExpression(
    Canvas canvas,
    scene_camera.Camera camera,
    Size size,
    FriendExpressionConfig expr,
    double cameraAngleRad,
    double meshRotationRad,
  ) {
    final aspect = size.width / size.height;
    final projection = camera.projectionMatrix(aspect);
    final view = camera.viewMatrix;
    final mvp = projection * view;

    // Eyes are positioned relative to the mesh's facing direction, not the
    // camera.  "Forward" points in the direction the mesh rotation specifies.
    final forwardX = math.sin(meshRotationRad);
    final forwardZ = math.cos(meshRotationRad);

    // Right vector (perpendicular to forward on the XZ plane)
    final rightX = forwardZ;
    final rightZ = -forwardX;

    // Eye centres in world space
    final halfSpacing = expr.eyeSpacing / 2;
    final leftEye = Vector3(
      rightX * -halfSpacing + forwardX * expr.eyeForwardOffset,
      expr.eyeHeight,
      rightZ * -halfSpacing + forwardZ * expr.eyeForwardOffset,
    );
    final rightEye = Vector3(
      rightX * halfSpacing + forwardX * expr.eyeForwardOffset,
      expr.eyeHeight,
      rightZ * halfSpacing + forwardZ * expr.eyeForwardOffset,
    );

    // Use camera-relative right vector for projected radii sizing
    final camRightX = -math.sin(cameraAngleRad);
    final camRightZ = math.cos(cameraAngleRad);

    // Project to screen
    final leftScreen = _projectToScreen(leftEye, mvp, size);
    final rightScreen = _projectToScreen(rightEye, mvp, size);
    if (leftScreen == null || rightScreen == null) return;

    // Compute projected radii by projecting offset points
    final leftUp = _projectToScreen(
      Vector3(leftEye.x, leftEye.y + expr.eyeRadiusY, leftEye.z),
      mvp,
      size,
    );
    final leftRight = _projectToScreen(
      Vector3(
        leftEye.x + camRightX * expr.eyeRadiusX,
        leftEye.y,
        leftEye.z + camRightZ * expr.eyeRadiusX,
      ),
      mvp,
      size,
    );

    if (leftUp == null || leftRight == null) return;

    final projRY = (leftScreen - leftUp).distance;
    final projRX = (leftScreen - leftRight).distance;

    final eyePaint = Paint()
      ..color = expr.eyeColor
      ..style = PaintingStyle.fill;

    // Draw left eye
    canvas.save();
    canvas.translate(leftScreen.dx, leftScreen.dy);
    canvas.scale(projRX, projRY);
    canvas.drawOval(const Rect.fromLTWH(-1, -1, 2, 2), eyePaint);
    canvas.restore();

    // Draw right eye
    canvas.save();
    canvas.translate(rightScreen.dx, rightScreen.dy);
    canvas.scale(projRX, projRY);
    canvas.drawOval(const Rect.fromLTWH(-1, -1, 2, 2), eyePaint);
    canvas.restore();

  }

  (List<_ProjectedFace>, List<(Offset, Offset)>, List<(Offset, Offset)>)
  _renderMeshToCanvas(
    Canvas canvas,
    Mesh mesh,
    scene_camera.Camera camera,
    Size size,
    List<DirectionalLight> lights,
    double globalIllumination,
  ) {
    // Basic projection logic adapted from ScenePainter
    final aspect = size.width / size.height;
    final projection = camera.projectionMatrix(aspect);
    final view = camera.viewMatrix;
    final viewProjection = projection * view;
    final world = mesh.transformMatrix; // Identity for now

    final facesToDraw = <_ProjectedFace>[];
    final foregroundEdges = <(Offset, Offset)>[];
    final backgroundEdges = <(Offset, Offset)>[];

    final perFaceColors = mesh.geometry.faceColors;
    for (var fi = 0; fi < mesh.geometry.faces.length; fi++) {
      final face = mesh.geometry.faces[fi];
      if (face.length < 3) continue;

      final worldVertices = <Vector3>[];
      final points = <Offset>[];
      final depths = <double>[];
      var shouldDiscard = false;

      // Project vertices
      for (final index in face) {
        final localVertex = mesh.geometry.vertices[index];
        final worldPos = Vector3.copy(localVertex);
        world.transform3(worldPos);
        worldVertices.add(worldPos);

        final cameraSpace = Vector3.copy(worldPos);
        view.transform3(cameraSpace);
        depths.add(cameraSpace.z);

        final projected = _projectToScreen(worldPos, viewProjection, size);
        if (projected == null) {
          shouldDiscard = true;
          break;
        }
        points.add(projected);
      }

      if (shouldDiscard || points.length < 3) continue;

      // Backface culling and Shading
      final normal = _faceNormal(worldVertices);
      final faceCenter = Vector3.zero();
      for (final v in worldVertices) {
        faceCenter.add(v);
      }
      faceCenter.scale(1 / worldVertices.length);

      final toCamera = (camera.position - faceCenter)..normalize();
      final faceDot = normal.dot(toCamera);
      final facingCamera = faceDot > 0;
      final isDoubleSided = mesh.material.doubleSided;

      // Extract edges from this face using Ring2D
      final faceRing = Ring2D(points);
      final faceEdges = faceRing.edges.toList();

      // Determine if this face is visible or hidden
      if (faceDot <= -0.15 && !isDoubleSided) {
        // This face is culled (back-facing) - add to background edges
        backgroundEdges.addAll(faceEdges);
        continue;
      }

      // This face is visible - will be drawn
      final shadingNormal = facingCamera ? normal : -normal;
      final shade = _shadeForFace(shadingNormal, lights, globalIllumination);

      final baseColor = (perFaceColors != null && fi < perFaceColors.length)
          ? perFaceColors[fi]
          : mesh.material.color;
      final finalColor = _applyLighting(baseColor, shade);

      final depth = depths.reduce((a, b) => a + b) / depths.length;

      facesToDraw.add(
        _ProjectedFace(points: points, color: finalColor, depth: depth),
      );

      // Add edges to foreground (visible faces)
      foregroundEdges.addAll(faceEdges);
    }

    // Sort by depth (Painter's Algorithm)
    // For standard rendering (z-negative into screen), smaller depth is farther away?
    // In camera space: z is negative forward. So more negative = farther.
    // We want to draw far objects first.
    // Let's check ScenePainter sort: facesToDraw.sort((a, b) => a.depth.compareTo(b.depth));
    // If z is negative, -100 is < -10. So it draws -100 then -10. Correct.
    facesToDraw.sort((a, b) => a.depth.compareTo(b.depth));

    // Draw visible faces
    for (final face in facesToDraw) {
      final path = Path()..addPolygon(face.points, true);
      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = face.color;

      canvas.drawPath(path, paint);
    }

    // Use geometry algorithms to properly classify edges
    // An edge is truly in the foreground if it's not occluded by any foreground face
    final (classifiedForeground, classifiedBackground) = _classifyEdges(
      foregroundEdges,
      backgroundEdges,
      facesToDraw,
    );

    // Return sorted faces, foreground edges, and background edges
    return (facesToDraw, classifiedForeground, classifiedBackground);
  }

  /// Same as _renderMeshToCanvas but also returns the bounding box of projected points
  /// Renders a mesh onto the canvas and returns structured edge data.
  ///
  /// Returns a record with:
  /// - `faces`: Sorted projected faces (for painting).
  /// - `foreground`: Classified foreground edges (for wireframe rendering).
  /// - `background`: Classified background edges (for wireframe rendering).
  /// - `bounds`: Bounding rect of all projected vertices (may be null).
  /// - `rawForeground`: Raw foreground edges before occlusion classification
  ///   (for outline/silhouette tracing — these include edges that the
  ///   classifier would move to background, which are still part of the
  ///   shape's outer boundary).
  /// - `rawAllFaceEdges`: All projected face edges (front + back) before
  ///   classification, used for alpha threshold computation.
  /// - `allProjectedPoints`: Every projected vertex from all faces (front and
  ///   back), used for alpha hull boundary computation.
  ({
    List<_ProjectedFace> faces,
    List<(Offset, Offset)> foreground,
    List<(Offset, Offset)> background,
    Rect? bounds,
    List<(Offset, Offset)> rawForeground,
    List<(Offset, Offset)> rawAllFaceEdges,
    List<Offset> allProjectedPoints,
  })
  _renderMeshToCanvasWithBounds(
    Canvas canvas,
    Mesh mesh,
    scene_camera.Camera camera,
    Size size,
    List<DirectionalLight> lights,
    double globalIllumination, {
    bool assignGrid = false,
    _ViewTiming? timing,
    Geometry? edgeGeometry,
    bool skipEdgeClassify = false,
  }) {
    final sw = Stopwatch()..start();
    final aspect = size.width / size.height;
    final projection = camera.projectionMatrix(aspect);
    final view = camera.viewMatrix;
    final viewProjection = projection * view;
    final world = mesh.transformMatrix;
    final hasEdgeGeometry = edgeGeometry != null;

    final facesToDraw = <_ProjectedFace>[];
    final foregroundEdges = <(Offset, Offset)>[];
    final backgroundEdges = <(Offset, Offset)>[];
    final allPoints = <Offset>[];

    // --- Fill pass: uses mesh.geometry (possibly tessellated) ---
    final perFaceColors2 = mesh.geometry.faceColors;
    for (var fi = 0; fi < mesh.geometry.faces.length; fi++) {
      final face = mesh.geometry.faces[fi];
      if (face.length < 3) continue;

      final worldVertices = <Vector3>[];
      final points = <Offset>[];
      final depths = <double>[];
      var shouldDiscard = false;

      for (final index in face) {
        final localVertex = mesh.geometry.vertices[index];
        final worldPos = Vector3.copy(localVertex);
        world.transform3(worldPos);
        worldVertices.add(worldPos);

        final cameraSpace = Vector3.copy(worldPos);
        view.transform3(cameraSpace);
        depths.add(cameraSpace.z);

        final projected = _projectToScreen(worldPos, viewProjection, size);
        if (projected == null) {
          shouldDiscard = true;
          break;
        }
        points.add(projected);
        allPoints.add(projected);
      }

      if (shouldDiscard || points.length < 3) continue;

      final normal = _faceNormal(worldVertices);
      final faceCenter = Vector3.zero();
      for (final v in worldVertices) {
        faceCenter.add(v);
      }
      faceCenter.scale(1 / worldVertices.length);

      final toCamera = (camera.position - faceCenter)..normalize();
      final facingCamera = normal.dot(toCamera) > 0;
      final isDoubleSided = mesh.material.doubleSided;

      if (!facingCamera && !isDoubleSided) {
        if (!hasEdgeGeometry) {
          backgroundEdges.addAll(Ring2D(points).edges);
        }
        continue;
      }

      final shadingNormal = facingCamera ? normal : -normal;
      final shade = _shadeForFace(shadingNormal, lights, globalIllumination);
      final baseColor = (perFaceColors2 != null && fi < perFaceColors2.length)
          ? perFaceColors2[fi]
          : mesh.material.color;
      final finalColor = _applyLighting(baseColor, shade);
      final depth = depths.reduce((a, b) => a + b) / depths.length;

      int gridRow = -1;
      int gridCol = -1;
      if (assignGrid) {
        gridRow = GeometrySlicer.rowForZ(faceCenter.z);
        gridCol = GeometrySlicer.colForX(faceCenter.x);
      }

      facesToDraw.add(
        _ProjectedFace(
          points: points,
          color: finalColor,
          depth: depth,
          gridRow: gridRow,
          gridCol: gridCol,
        ),
      );
      if (!hasEdgeGeometry) {
        foregroundEdges.addAll(Ring2D(points).edges);
      }
    }
    timing?.stages['  face_projection'] = (sw..stop()).elapsedMilliseconds;
    sw
      ..reset()
      ..start();

    facesToDraw.sort((a, b) => a.depth.compareTo(b.depth));
    timing?.stages['  depth_sort'] = (sw..stop()).elapsedMilliseconds;
    sw
      ..reset()
      ..start();

    for (final face in facesToDraw) {
      final path = Path()..addPolygon(face.points, true);
      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = face.color;
      canvas.drawPath(path, paint);
    }
    timing?.stages['  canvas_draw'] = (sw..stop()).elapsedMilliseconds;
    sw
      ..reset()
      ..start();

    // --- Edge pass: uses edgeGeometry (original, non-tessellated) when
    // provided, keeping edge count low for O(E²) classification. ---
    final edgeFacePolygons = <_ProjectedFace>[];
    if (hasEdgeGeometry) {
      final isDoubleSided = mesh.material.doubleSided;
      for (var fi = 0; fi < edgeGeometry.faces.length; fi++) {
        final face = edgeGeometry.faces[fi];
        if (face.length < 3) continue;

        final worldVertices = <Vector3>[];
        final points = <Offset>[];
        final depths = <double>[];
        var shouldDiscard = false;

        for (final index in face) {
          final localVertex = edgeGeometry.vertices[index];
          final worldPos = Vector3.copy(localVertex);
          world.transform3(worldPos);
          worldVertices.add(worldPos);

          final cameraSpace = Vector3.copy(worldPos);
          view.transform3(cameraSpace);
          depths.add(cameraSpace.z);

          final projected = _projectToScreen(worldPos, viewProjection, size);
          if (projected == null) {
            shouldDiscard = true;
            break;
          }
          points.add(projected);
        }

        if (shouldDiscard || points.length < 3) continue;

        final normal = _faceNormal(worldVertices);
        final faceCenter = Vector3.zero();
        for (final v in worldVertices) {
          faceCenter.add(v);
        }
        faceCenter.scale(1 / worldVertices.length);

        final toCamera = (camera.position - faceCenter)..normalize();
        final facingCamera = normal.dot(toCamera) > 0;

        final faceRing = Ring2D(points);
        final faceEdges = faceRing.edges.toList();

        if (!facingCamera && !isDoubleSided) {
          backgroundEdges.addAll(faceEdges);
          continue;
        }

        final depth = depths.reduce((a, b) => a + b) / depths.length;
        edgeFacePolygons.add(_ProjectedFace(
          points: points,
          color: Colors.transparent,
          depth: depth,
        ));
        foregroundEdges.addAll(faceEdges);
      }
    }
    timing?.stages['  edge_projection'] = (sw..stop()).elapsedMilliseconds;
    sw
      ..reset()
      ..start();

    // Classify edges against the face set matching their geometry.
    // For closed solids with backface culling, visible edges are already
    // correctly partitioned by the normal test — skip the expensive O(N²)
    // occlusion check.
    final List<(Offset, Offset)> classifiedForeground;
    final List<(Offset, Offset)> classifiedBackground;
    if (skipEdgeClassify) {
      classifiedForeground = foregroundEdges;
      classifiedBackground = backgroundEdges;
    } else {
      final classifyFaces = hasEdgeGeometry ? edgeFacePolygons : facesToDraw;
      (classifiedForeground, classifiedBackground) = _classifyEdges(
        foregroundEdges,
        backgroundEdges,
        classifyFaces,
      );
    }
    timing?.stages['  edge_classify'] = (sw..stop()).elapsedMilliseconds;

    // Calculate bounding box from all projected points
    Rect? bounds;
    if (allPoints.isNotEmpty) {
      double minX = allPoints[0].dx;
      double maxX = allPoints[0].dx;
      double minY = allPoints[0].dy;
      double maxY = allPoints[0].dy;
      for (final p in allPoints) {
        if (p.dx < minX) minX = p.dx;
        if (p.dx > maxX) maxX = p.dx;
        if (p.dy < minY) minY = p.dy;
        if (p.dy > maxY) maxY = p.dy;
      }
      bounds = Rect.fromLTRB(minX, minY, maxX, maxY);
    }

    return (
      faces: facesToDraw,
      foreground: classifiedForeground,
      background: classifiedBackground,
      bounds: bounds,
      rawForeground: foregroundEdges,
      rawAllFaceEdges: [...foregroundEdges, ...backgroundEdges],
      allProjectedPoints: allPoints,
    );
  }

  // --- Edge Classification using Geometry Algorithms ---

  /// Classifies edges into foreground (visible) and background (occluded/hidden).
  ///
  /// Uses the geometry algorithms to:
  /// 1. Deduplicate edges that appear in both lists
  /// 2. Check if "foreground" edges are actually occluded by closer faces
  /// 3. Identify silhouette edges (edges on the boundary)
  (List<(Offset, Offset)>, List<(Offset, Offset)>) _classifyEdges(
    List<(Offset, Offset)> rawForegroundEdges,
    List<(Offset, Offset)> rawBackgroundEdges,
    List<_ProjectedFace> sortedFaces,
  ) {
    if (sortedFaces.isEmpty) {
      return (rawForegroundEdges, rawBackgroundEdges);
    }

    // Build a set of unique edges with their visibility status
    final edgeMap = <_EdgeKey, _EdgeInfo>{};

    // Process foreground edges first (they have priority)
    for (final edge in rawForegroundEdges) {
      final key = _EdgeKey.fromEdge(edge);
      edgeMap[key] = _EdgeInfo(edge: edge, isForeground: true);
    }

    // Process background edges (only add if not already in foreground)
    for (final edge in rawBackgroundEdges) {
      final key = _EdgeKey.fromEdge(edge);
      if (!edgeMap.containsKey(key)) {
        edgeMap[key] = _EdgeInfo(edge: edge, isForeground: false);
      }
      // If edge exists in both, it stays as foreground (silhouette edge)
    }

    // Now check each foreground edge for occlusion by closer faces
    // Convert faces to Polygon2D for point-in-polygon tests
    final facePolygons = sortedFaces
        .map((f) => (Polygon2D.simple(f.points), f.depth))
        .toList();

    final finalForeground = <(Offset, Offset)>[];
    final finalBackground = <(Offset, Offset)>[];

    for (final info in edgeMap.values) {
      if (!info.isForeground) {
        // Already classified as background
        finalBackground.add(info.edge);
        continue;
      }

      // Check if this foreground edge is occluded by any closer face
      final edgeMidpoint = Offset(
        (info.edge.$1.dx + info.edge.$2.dx) / 2,
        (info.edge.$1.dy + info.edge.$2.dy) / 2,
      );

      bool isOccluded = false;

      // Check against faces that are closer (higher in the sorted order = drawn later = closer)
      for (final (polygon, _) in facePolygons) {
        // Skip if this is the same face (edge belongs to this face)
        if (_edgeBelongsToPolygon(info.edge, polygon)) {
          continue;
        }

        // Check if edge midpoint is inside a closer face
        if (isPointInPolygon(edgeMidpoint, polygon)) {
          isOccluded = true;
          break;
        }
      }

      if (isOccluded) {
        finalBackground.add(info.edge);
      } else {
        finalForeground.add(info.edge);
      }
    }

    return (finalForeground, finalBackground);
  }

  /// Checks if an edge belongs to a polygon (is one of its edges).
  bool _edgeBelongsToPolygon((Offset, Offset) edge, Polygon2D polygon) {
    const epsilon = 1e-6;

    for (final polyEdge in polygon.exterior.edges) {
      // Check if edges match (in either direction)
      final matchForward =
          (edge.$1 - polyEdge.$1).distance < epsilon &&
          (edge.$2 - polyEdge.$2).distance < epsilon;
      final matchReverse =
          (edge.$1 - polyEdge.$2).distance < epsilon &&
          (edge.$2 - polyEdge.$1).distance < epsilon;

      if (matchForward || matchReverse) {
        return true;
      }
    }

    return false;
  }

  // --- Helper Methods (Adapted from ScenePainter) ---

  Vector3 _faceNormal(List<Vector3> vertices) {
    final a = vertices[0];
    final b = vertices[1];
    final c = vertices[2];
    final edge1 = b - a;
    final edge2 = c - a;
    final normal = edge1.cross(edge2);
    if (normal.length2 == 0) return Vector3.zero();
    return normal.normalized();
  }

  double _shadeForFace(
    Vector3 normal,
    List<DirectionalLight> lights,
    double globalIllumination,
  ) {
    if (normal.length2 == 0) return globalIllumination.clamp(0.0, 1.0);
    final normalizedNormal = normal.normalized();
    var lightContribution = 0.0;

    for (final light in lights) {
      final dir = (-light.direction).normalized();
      final intensity =
          math.max(0, normalizedNormal.dot(dir)) * light.intensity;
      lightContribution += intensity;
    }
    return (globalIllumination + lightContribution).clamp(0.0, 1.0);
  }

  Color _applyLighting(Color base, double factor) {
    final r = (base.red * factor).clamp(0, 255).toInt();
    final g = (base.green * factor).clamp(0, 255).toInt();
    final b = (base.blue * factor).clamp(0, 255).toInt();
    return Color.fromARGB(base.alpha, r, g, b);
  }

  Offset? _projectToScreen(Vector3 worldPos, Matrix4 mvp, Size size) {
    final clip = _transformPosition(mvp, worldPos);
    if (!_vector4IsFinite(clip) || clip.w.abs() <= 1e-3) return null;

    final ndcX = clip.x / clip.w;
    final ndcY = clip.y / clip.w;
    if (!ndcX.isFinite || !ndcY.isFinite) return null;

    final screenX = (ndcX * 0.5 + 0.5) * size.width;
    final screenY = (1 - (ndcY * 0.5 + 0.5)) * size.height;
    if (!screenX.isFinite || !screenY.isFinite) return null;

    return Offset(screenX, screenY);
  }

  Vector4 _transformPosition(Matrix4 matrix, Vector3 position) {
    final s = matrix.storage;
    final x = position.x;
    final y = position.y;
    final z = position.z;
    return Vector4(
      s[0] * x + s[4] * y + s[8] * z + s[12],
      s[1] * x + s[5] * y + s[9] * z + s[13],
      s[2] * x + s[6] * y + s[10] * z + s[14],
      s[3] * x + s[7] * y + s[11] * z + s[15],
    );
  }

  bool _vector4IsFinite(Vector4 value) {
    return value.x.isFinite &&
        value.y.isFinite &&
        value.z.isFinite &&
        value.w.isFinite;
  }

  /// Project the centroid of the bottom face of the geometry's AABB into
  /// sprite-local 2D coordinates.  The bottom face is the set of bounding-
  /// box vertices at the minimum Y (world-space up).
  Offset? _computeGroundPoint(
    Geometry geometry,
    Matrix4 worldMat,
    scene_camera.Camera camera,
    Size size,
  ) {
    if (geometry.vertices.isEmpty) return null;
    final aspect = size.width / size.height;
    final viewProj = camera.projectionMatrix(aspect) * camera.viewMatrix;

    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity;
    double minZ = double.infinity, maxZ = double.negativeInfinity;
    for (final v in geometry.vertices) {
      final wv = Vector3.copy(v);
      worldMat.transform3(wv);
      if (wv.x < minX) minX = wv.x;
      if (wv.x > maxX) maxX = wv.x;
      if (wv.y < minY) minY = wv.y;
      if (wv.z < minZ) minZ = wv.z;
      if (wv.z > maxZ) maxZ = wv.z;
    }
    return _projectToScreen(
      Vector3((minX + maxX) / 2, minY, (minZ + maxZ) / 2),
      viewProj,
      size,
    );
  }

  /// Record a list of pre-sorted projected faces into a [ui.Picture].
  ui.Picture _recordFaces(List<_ProjectedFace> faces, Size size) {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    for (final face in faces) {
      final path = Path()..addPolygon(face.points, true);
      c.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.fill
          ..color = face.color,
      );
    }
    return rec.endRecording();
  }

  static Rect _boundsOfPoints(List<Offset> points) {
    if (points.isEmpty) return Rect.zero;
    double minX = points[0].dx, maxX = points[0].dx;
    double minY = points[0].dy, maxY = points[0].dy;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }
}

class _ProjectedFace {
  _ProjectedFace({
    required this.points,
    required this.color,
    required this.depth,
    this.gridRow = -1,
    this.gridCol = -1,
  });

  final List<Offset> points;
  final Color color;
  final double depth;

  /// Grid cell row (Z axis), or -1 when grid assignment is not used.
  final int gridRow;

  /// Grid cell column (X axis), or -1 when grid assignment is not used.
  final int gridCol;
}

/// Key for deduplicating edges (order-independent).
class _EdgeKey {
  _EdgeKey(this.a, this.b);

  factory _EdgeKey.fromEdge((Offset, Offset) edge) {
    // Normalize edge direction for consistent hashing
    // Use lexicographic ordering: smaller point first
    if (edge.$1.dx < edge.$2.dx ||
        (edge.$1.dx == edge.$2.dx && edge.$1.dy < edge.$2.dy)) {
      return _EdgeKey(edge.$1, edge.$2);
    } else {
      return _EdgeKey(edge.$2, edge.$1);
    }
  }

  final Offset a;
  final Offset b;

  @override
  bool operator ==(Object other) {
    if (other is! _EdgeKey) return false;
    const epsilon = 1e-4; // Tolerance for floating point comparison
    return (a - other.a).distance < epsilon && (b - other.b).distance < epsilon;
  }

  @override
  int get hashCode {
    // Quantize to reduce floating point issues
    final ax = (a.dx * 100).round();
    final ay = (a.dy * 100).round();
    final bx = (b.dx * 100).round();
    final by = (b.dy * 100).round();
    return Object.hash(ax, ay, bx, by);
  }
}

/// Information about an edge for classification.
class _EdgeInfo {
  _EdgeInfo({required this.edge, required this.isForeground});

  final (Offset, Offset) edge;
  final bool isForeground;
}
