import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../data/asset_database.dart';
import '../data/placed_asset_database.dart';
import '../geometry/geometry.dart';
import '../geometry/geometries.dart';
import '../geometry/prefabs/prefab_factory.dart';
import '../rendering/iso/iso_asset.dart';
import '../rendering/iso/iso_camera.dart';
import '../rendering/iso/iso_coordinate.dart';
import '../rendering/iso/iso_painter.dart';
import '../rendering/iso/iso_projection.dart';
import '../rendering/iso/iso_vector_generator.dart';
import '../rendering/lights.dart';
import '../rendering/mesh.dart';
import '../rendering/scene/camera.dart';
import '../rendering/scene/scene.dart';
import '../tiles/tiles.dart' show GeometryFeature;

/// Visual style used for the 2D/3D crossfade region of the transition.
enum TransitionStyle {
  fade,
  horizontalWipe,
  verticalWipe,
  circleCrop;

  String get displayName {
    switch (this) {
      case TransitionStyle.fade:
        return 'Fade';
      case TransitionStyle.horizontalWipe:
        return 'Horizontal Wipe';
      case TransitionStyle.verticalWipe:
        return 'Vertical Wipe';
      case TransitionStyle.circleCrop:
        return 'Circle Crop';
    }
  }
}

/// Orchestrates the multi-phase cinematic transition from the 2D isometric
/// map view to the 3D structure interior.
class MapTo3DTransition {
  MapTo3DTransition({
    required TickerProvider vsync,
  }) {
    _controller = AnimationController(
      vsync: vsync,
      duration: forwardDuration,
    )..addListener(_onTick);
  }

  // ---------------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------------

  static const Duration forwardDuration = Duration(milliseconds: 2000);
  static const Duration reverseDuration = Duration(milliseconds: 1000);

  /// Phase boundaries (normalised t values).
  static const double phaseAEnd = 0.0;
  static const double phaseBEnd = 0.25;
  static const double phaseCStart = 0.0;
  static const double phaseCEnd = 0.90;

  /// 3D spacing between adjacent tile grid cells.
  static const double tileSpacing = 512.0;

  /// Maps IsoProjection.heightPerLevel to 3D world units.  Derived so that
  /// a tile at elevation `h` in 3D projects to the same screen-Y offset as
  /// `h * heightPerLevel * zoom` in the 2D axonometric view:
  ///
  ///   heightScale = 4 · heightPerLevel · tileSpacing / (√6 · tileWidth)
  static final double heightScale = 4 *
      IsoProjection.heightPerLevel *
      tileSpacing /
      (math.sqrt(6) * IsoProjection.tileWidth);

  /// Camera elevation factor.  For the 3D orthographic projection to
  /// reproduce the 2D axonometric diamond ratio (tileWidth:tileHeight = 2:1)
  /// the elevation must satisfy  e/√(1+e²) = 0.5  →  e = 1/√3.
  static final double elevationFactor = 1.0 / math.sqrt(3);

  /// Far-field camera distance for the ortho overview.
  static const double farDistance = 2000.0;

  /// Arrangement camera defaults (must match room_editor_view).
  static final Vector3 arrangementCamPos = Vector3(600, 450, 600);
  static final Vector3 arrangementCamTarget = Vector3.zero();

  /// Zoom-to-fit orthoScale computed from the target structure mesh.
  double _fitOrthoScale = 200.0;

  /// Combined mesh scale factor applied to the target structure in the
  /// transition scene (meshScale * normFactor).  Used to compensate the
  /// RoomEditorView camera so a scale-1.0 mesh looks the same size.
  double _targetMeshScaleFactor = 1.0;

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  late final AnimationController _controller;
  AnimationController get controller => _controller;

  Scene? _scene;
  Scene? get scene => _scene;

  Camera? _camera;
  Camera? get camera => _camera;

  double get progress => _controller.value;
  bool get isAnimating => _controller.isAnimating;
  bool get isForwardComplete => _controller.isCompleted;
  bool get isReverseComplete => _controller.isDismissed;

  double get fitOrthoScale => _fitOrthoScale;
  double get azimuthRad => _camStartAzimuthRad;
  double get targetMeshScaleFactor => _targetMeshScaleFactor;

  /// Meshes tagged by category for selective fading.
  final List<_TaggedMesh> _taggedMeshes = [];

  /// Camera start (far-field ortho) and zoom-to-fit endpoint.
  Vector3? _camStartPos;
  double _camStartOrthoScale = 500;
  double _camStartAzimuthRad = 0;

  /// IsoCamera state at the moment the transition began.
  Offset? preTransitionCameraPosition;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  void dispose() {
    _controller
      ..removeListener(_onTick)
      ..dispose();
    _scene?.dispose();
    _scene = null;
    _camera = null;
    _taggedMeshes.clear();
  }

  // ---------------------------------------------------------------------------
  // Build the 3D shadow scene
  // ---------------------------------------------------------------------------

  /// Populate the transition scene from visible tiles, placed assets, and a
  /// target structure entry.
  void buildScene({
    required List<IsoTileData> tiles,
    required List<IsoAssetInstance> assets,
    required IsoCoordinate targetCoord,
    required PlacedAssetDatabase placedAssetDb,
    required AssetDatabase assetDb,
  }) {
    _taggedMeshes.clear();
    _scene?.dispose();

    _scene = Scene(globalIllumination: 0.35)
      ..addLight(DirectionalLight(
        color: Colors.white,
        intensity: 0.7,
        direction: Vector3(-0.4, -0.8, -0.5),
      ));

    _buildTileMeshes(tiles, targetCoord);
    _buildAssetMeshes(assets, targetCoord, placedAssetDb, assetDb);
    _buildInteriorMeshes();
  }

  // --- Tile meshes -----------------------------------------------------------

  void _buildTileMeshes(List<IsoTileData> tiles, IsoCoordinate targetCoord) {
    for (var i = 0; i < tiles.length; i++) {
      final tile = tiles[i];
      final dx = (tile.coordinate.x - targetCoord.x).toDouble();
      final dy = (tile.coordinate.y - targetCoord.y).toDouble();
      final ex = dx * tileSpacing;
      final ez = dy * tileSpacing;
      final ey = tile.elevation * heightScale;

      final half = tileSpacing * 0.5;
      final geometry = Geometry(
        id: 'tile_$i',
        name: 'Tile $i',
        vertices: [
          Vector3(ex - half, ey, ez - half),
          Vector3(ex + half, ey, ez - half),
          Vector3(ex + half, ey, ez + half),
          Vector3(ex - half, ey, ez + half),
        ],
        faces: [
          [0, 1, 2, 3],
        ],
        colorSeed: i,
      );

      final dist = math.sqrt(dx * dx + dy * dy);
      final mesh = Mesh(
        id: 'tile_$i',
        name: 'Tile $i',
        geometry: geometry,
        material: MaterialModel(
          color: tile.color,
          doubleSided: true,
          wireframe: true,
        ),
      );
      _scene!.addMesh(mesh);
      _taggedMeshes.add(_TaggedMesh(
        mesh: mesh,
        category: _MeshCategory.tile,
        distanceToTarget: dist,
      ));
    }
  }

  // --- Asset meshes ----------------------------------------------------------

  void _buildAssetMeshes(
    List<IsoAssetInstance> assets,
    IsoCoordinate targetCoord,
    PlacedAssetDatabase placedAssetDb,
    AssetDatabase assetDb,
  ) {
    final definitionCache = <String, AssetDefinition?>{};

    for (var i = 0; i < assets.length; i++) {
      final instance = assets[i];
      final coord = instance.coordinate;
      final dx = (coord.x - targetCoord.x).toDouble();
      final dy = (coord.y - targetCoord.y).toDouble();
      final isTarget = dx == 0 && dy == 0;
      final dist = math.sqrt(dx * dx + dy * dy);

      PlacedAssetEntry? placedEntry;
      for (final id in placedAssetDb.placedAssetIds) {
        final e = placedAssetDb.getAsset(id);
        if (e != null && e.coordinate.samePosition(coord)) {
          placedEntry = e;
          break;
        }
      }

      GeometryPrefabs? prefab;
      Color meshColor = Colors.white;
      double meshScale = 1.0;

      if (placedEntry != null) {
        final typeId = placedEntry.typeId;
        if (!definitionCache.containsKey(typeId)) {
          definitionCache[typeId] = assetDb.getAssetDefinitionSync(typeId);
        }
        final def = definitionCache[typeId];
        if (def != null) {
          prefab = def.prefab;
          meshColor = def.color ?? Colors.white;
          meshScale = def.scale;
        }
      }

      Geometry geometry;
      Vector3? visualScale;

      if (prefab != null) {
        final feature = GeometryFeature(
          id: 'asset_$i',
          geometry: prefab,
          scale: 1.0,
          color: meshColor,
        );
        geometry = buildGeometry(feature);

        // Derive the same auto-fit orthoScale that IsoVectorGenerator uses
        // when rendering the 2D sprite (orthoScale = maxExtent * 1.15).
        // The norm factor maps from the tile-calibrated 3D camera to the
        // sprite camera so the mesh matches the sprite content size:
        //   normFactor = tileSpacing / (2 · √2 · spriteOrthoScale)
        double maxExt = 0;
        for (final v in geometry.vertices) {
          maxExt = math.max(
              maxExt, math.max(v.x.abs(), math.max(v.y.abs(), v.z.abs())));
        }
        final spriteOrtho = math.max(maxExt * 1.15, 120.0);
        final normFactor = tileSpacing / (2.0 * math.sqrt2 * spriteOrtho);
        visualScale = Vector3.all(meshScale * normFactor);

        if (isTarget) {
          _fitOrthoScale = math.max(maxExt * meshScale * normFactor * 2.6, 200.0);
          _targetMeshScaleFactor = meshScale * normFactor;
        }
      } else if (instance.tag != null) {
        final feature = GeometryFeature(
          id: 'friend_$i',
          geometry: GeometryPrefabs.cube,
          scale: 0.2,
          color: Colors.cyan,
        );
        geometry = buildGeometry(feature);
      } else {
        continue;
      }

      final mesh = Mesh(
        id: isTarget ? 'target_structure' : 'asset_$i',
        name: isTarget ? 'Target Structure' : 'Asset $i',
        geometry: geometry,
        material: MaterialModel(
          color: meshColor,
          doubleSided: true,
          wireframe: true,
        ),
        position: isTarget
            ? Vector3.zero()
            : Vector3(dx * tileSpacing, 0, dy * tileSpacing),
        scale: visualScale,
      );
      _scene!.addMesh(mesh);
      _taggedMeshes.add(_TaggedMesh(
        mesh: mesh,
        category: isTarget
            ? _MeshCategory.targetStructure
            : _MeshCategory.asset,
        distanceToTarget: dist,
      ));
    }
  }

  // --- Interior objects ------------------------------------------------------

  void _buildInteriorMeshes() {
    final s = _targetMeshScaleFactor;
    final cubeFold = GeodesicFoldFactories.cube(50);
    final cubeGeo = cubeFold.toGeometry(foldValue: 1);
    final smallCubeFold = GeodesicFoldFactories.cube(30);
    final smallCubeGeo = smallCubeFold.toGeometry(foldValue: 1);

    void addInterior(String id, Geometry geo, Vector3 pos) {
      final mesh = Mesh(
        id: id,
        name: id,
        geometry: geo,
        material: MaterialModel(
          color: Colors.teal,
          doubleSided: true,
          opacity: 0.0,
        ),
        position: pos * s,
        scale: Vector3.all(s),
      );
      _scene!.addMesh(mesh);
      _taggedMeshes.add(_TaggedMesh(
        mesh: mesh,
        category: _MeshCategory.interior,
        distanceToTarget: 0,
      ));
    }

    addInterior('int_table', cubeGeo, Vector3(0, -150, 0));
    addInterior('int_painting', smallCubeGeo, Vector3(0, 0, -200));
    addInterior('int_shelf', smallCubeGeo, Vector3(200, -30, 0));
  }

  // ---------------------------------------------------------------------------
  // Camera alignment
  // ---------------------------------------------------------------------------

  /// Create and align a 3D Camera to match the 2D IsoCamera view.
  void alignCamera(IsoCamera isoCamera, Size viewport) {
    final viewIndex = isoCamera.view.index;
    final viewAngles = worldViewAngles(IsoProjection.viewCount);
    final azimuthDeg = viewAngles[viewIndex];
    final azimuthRad = azimuthDeg * math.pi / 180.0;

    final camPos = Vector3(
      farDistance * math.cos(azimuthRad),
      farDistance * elevationFactor,
      farDistance * math.sin(azimuthRad),
    );

    final zoom = isoCamera.zoom;

    // Derived from equating the 2D axonometric formula
    //   dx = (rx−ry)·tileWidth/2·zoom,  dy = (rx+ry)·tileHeight/2·zoom
    // with the 3D orthographic projection through the view matrix at the
    // elevation factor above.  Both yield the same screen coordinates when:
    //   orthoScale = tileSpacing · vpHeight / (tileWidth · √2 · zoom)
    final orthoScale = tileSpacing *
        viewport.height /
        (IsoProjection.tileWidth * math.sqrt2 * zoom);

    _camera = Camera(
      name: 'Transition',
      position: camPos,
      target: Vector3.zero(),
      projection: ProjectionType.orthographic,
      orthographicScale: orthoScale,
      fovDegrees: 60,
      near: 0.1,
      far: 5000,
    );

    _camStartPos = Vector3.copy(camPos);
    _camStartOrthoScale = orthoScale;
    _camStartAzimuthRad = azimuthRad;

    _scene?.camera = _camera;
  }

  // ---------------------------------------------------------------------------
  // Animation driver
  // ---------------------------------------------------------------------------

  void forward() {
    _controller.duration = forwardDuration;
    _controller.forward(from: 0);
  }

  void reverse() {
    _controller.duration = reverseDuration;
    _controller.reverse(from: 1.0);
  }

  void _onTick() {
    final t = _controller.value;
    _updatePhase(t);
    _scene?.markNeedsPaint();
  }

  // ---------------------------------------------------------------------------
  // Phase progress helpers
  // ---------------------------------------------------------------------------

  /// Returns 0-1 progress within Phase A.
  double get phaseAProgress => _phaseProgress(0.0, phaseAEnd);

  /// Returns 0-1 progress within Phase B.
  double get phaseBProgress => _phaseProgress(phaseAEnd, phaseBEnd);

  /// Returns 0-1 progress within Phase C.
  double get phaseCProgress => _phaseProgress(phaseCStart, phaseCEnd);

  /// Returns 0-1 progress within Phase D.
  double get phaseDProgress => _phaseProgress(phaseCEnd, 1.0);

  double _phaseProgress(double start, double end) {
    final t = _controller.value;
    if (t <= start) return 0.0;
    if (t >= end) return 1.0;
    return (t - start) / (end - start);
  }

  // ---------------------------------------------------------------------------
  // Phase updates
  // ---------------------------------------------------------------------------

  void _updatePhase(double t) {
    if (_camera == null || _camStartPos == null) return;

    // Phase C: zoom camera + fade periphery + fade in interior
    // (now starts simultaneously with Phase B)
    if (phaseCProgress > 0) {
      final cProgress = Curves.easeInOut.transform(phaseCProgress);
      _lerpCamera(cProgress);
      _fadePeriphery(cProgress);
      _fadeInterior(cProgress);
    }
  }

  void _lerpCamera(double t) {
    final cam = _camera!;
    final startPos = _camStartPos!;

    // Zoom-to-fit endpoint: stay on the same azimuth, move closer.
    final endDist = _fitOrthoScale * 2;
    final endPos = Vector3(
      endDist * math.cos(_camStartAzimuthRad),
      endDist * elevationFactor,
      endDist * math.sin(_camStartAzimuthRad),
    );

    final pos = Vector3(
      startPos.x + (endPos.x - startPos.x) * t,
      startPos.y + (endPos.y - startPos.y) * t,
      startPos.z + (endPos.z - startPos.z) * t,
    );
    cam.setPosition(pos);

    // Target stays at origin throughout.
    cam.setTarget(Vector3.zero());

    // Stay orthographic, lerp scale to zoom-to-fit.
    cam.projection = ProjectionType.orthographic;
    cam.orthographicScale =
        _camStartOrthoScale + (_fitOrthoScale - _camStartOrthoScale) * t;
  }

  void _fadePeriphery(double t) {
    for (final tagged in _taggedMeshes) {
      if (tagged.category == _MeshCategory.targetStructure ||
          tagged.category == _MeshCategory.interior) {
        continue;
      }
      final dist = tagged.distanceToTarget;
      double fadeStart;
      if (dist > 3) {
        fadeStart = 0.0;
      } else if (dist > 1) {
        fadeStart = 0.2;
      } else {
        fadeStart = 0.5;
      }
      final fadeEnd = fadeStart + 0.5;
      final fadeT = ((t - fadeStart) / (fadeEnd - fadeStart)).clamp(0.0, 1.0);
      final opacity = 1.0 - fadeT;

      final old = tagged.mesh.material;
      if ((old.opacity - opacity).abs() > 0.01) {
        tagged.mesh.material = MaterialModel(
          color: old.color,
          doubleSided: old.doubleSided,
          wireframe: old.wireframe,
          opacity: opacity,
        );
      }
    }
  }

  void _fadeInterior(double t) {
    final interiorT = ((t - 0.6) / 0.3).clamp(0.0, 1.0);
    for (final tagged in _taggedMeshes) {
      if (tagged.category != _MeshCategory.interior) continue;
      final old = tagged.mesh.material;
      if ((old.opacity - interiorT).abs() > 0.01) {
        tagged.mesh.material = MaterialModel(
          color: old.color,
          doubleSided: old.doubleSided,
          wireframe: false,
          opacity: interiorT,
        );
      }
    }
  }

  void _transitionTargetMaterial(double t) {
    final solidT = ((t - 0.3) / 0.4).clamp(0.0, 1.0);
    for (final tagged in _taggedMeshes) {
      if (tagged.category != _MeshCategory.targetStructure) continue;
      final shouldBeWireframe = solidT < 0.5;
      final old = tagged.mesh.material;
      if (old.wireframe != shouldBeWireframe) {
        tagged.mesh.material = MaterialModel(
          color: old.color,
          doubleSided: old.doubleSided,
          wireframe: shouldBeWireframe,
          opacity: old.opacity,
        );
      }
    }
  }

  /// No-op kept for API compatibility; reverse plays phases backwards naturally.
  void resetForReverse() {}

  /// Extract the final scene for handoff to RoomEditorView.
  /// Returns the scene and camera; the caller takes ownership.
  (Scene, Camera)? extractFinalScene() {
    if (_scene == null || _camera == null) return null;
    final s = _scene!;
    final c = _camera!;
    _scene = null;
    _camera = null;
    return (s, c);
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

enum _MeshCategory { tile, asset, targetStructure, interior }

class _TaggedMesh {
  _TaggedMesh({
    required this.mesh,
    required this.category,
    required this.distanceToTarget,
  });

  final Mesh mesh;
  final _MeshCategory category;
  final double distanceToTarget;
}
