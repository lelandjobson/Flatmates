import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../debug/perf_debug.dart';
import '../debug/scene_paint_stats.dart';
import '../crafting/placed_paper.dart';
import '../gameplay/landscape_cover.dart';
import '../gameplay/friends/friend_instance.dart';
import '../gameplay/friends/friend_instance_store.dart';
import '../gameplay/friends/friend_mesh_sync.dart';
import '../gameplay/game_history.dart';
import '../gameplay/gizmo/gizmo_resolver.dart';
import '../gameplay/gizmo/gizmo_target.dart';
import '../gameplay/graph/connection_graph.dart';
import '../gameplay/recording/game_recording.dart';
import '../gameplay/recording/game_recording_io.dart';
import '../gameplay/eraser/eraser_filter.dart';
import '../gameplay/eraser/world_eraser.dart';
import '../gameplay/paths/path_mesh.dart';
import '../gameplay/paths/path_store.dart';
import '../gameplay/walls/wall_mesh.dart';
import '../gameplay/walls/wall_regions.dart';
import '../gameplay/walls/wall_store.dart';
import '../gameplay/day_night/day_night_lighting.dart';
import '../gameplay/paint/face_paint_store.dart';
import '../gameplay/paint/ground_shadow_model.dart';
import '../gameplay/picking/volume_face_picker.dart';
import '../gameplay/viewers/face_turn.dart';
import '../gameplay/viewers/focus_crop.dart';
import '../gameplay/viewers/focus_region.dart';
import '../gameplay/viewers/game_viewer.dart';
import '../gameplay/viewers/world_plane.dart';
import '../gameplay/volumes/volume.dart';
import '../gameplay/volumes/volume_box_mesh.dart';
import '../gameplay/volumes/volume_store.dart';
import '../gameplay/volumes/volume_tool_3d.dart';
import '../user/friend_provider.dart';
import '../gestures/gesture_system.dart';
import '../landscape/landscape_generator.dart';
import '../landscape/landscape_grid.dart';
import '../landscape/landscape_material.dart';
import '../landscape/landscape_plane_painter.dart';
import '../theme/world_theme.dart';
import '../rendering/lights.dart';
import '../rendering/map/map_aabb.dart';
import '../rendering/map/map_octree.dart';
import '../rendering/map/map_scene_streamer.dart';
import '../rendering/scene/camera.dart';
import '../rendering/scene/camera_controller.dart';
import '../rendering/scene/map_look_camera_controller.dart';
import '../rendering/scene/plane_look_camera_controller.dart';
import '../rendering/scene/scene.dart';
import '../rendering/scene/scene_hit_tester.dart';
import '../rendering/scene_view.dart';
import '../ui/fm_dev_back_button.dart';
import '../ui/fm_safe_area.dart';
import '../ui/fm_screen.dart';
import '../ui/game/connection_graph_overlay.dart';
import '../ui/game/crop_box_gizmo.dart';
import '../ui/game/day_advance_overlay.dart';
import '../ui/game/day_cycle_hud.dart';
import '../ui/game/dev_tools_button.dart';
import '../ui/game/dev_tools_panel.dart';
import '../ui/game/frame_stats_hud.dart';
import '../ui/game/eraser_brush_overlay.dart';
import '../ui/game/friend_eye_overlay.dart';
import '../ui/game/eraser_filter_panel.dart';
import '../ui/game/game_tool_sidebar.dart';
import '../ui/game/wall_region_overlay.dart';
import '../ui/game/gizmo_bounds_overlay.dart';
import '../ui/game/plane_subtile_grid_overlay.dart';
import '../ui/game/scene_transform_gizmo.dart';
import '../ui/game/tool_3d_work_area.dart';
import '../ui/game/volume_door_overlay.dart';
import '../ui/game/volume_ground_shadow_overlay.dart';
import '../ui/game/volume_face_paint_overlay.dart';
import '../ui/game/volume_grow_overlay.dart';
import '../ui/game/volume_transform_gizmo.dart';

/// Core 3D game view. Starts from the map bench scene (landscape + look
/// camera) without the bench tools/assets panel.
class GameView extends StatefulWidget {
  const GameView({super.key});

  @override
  State<GameView> createState() => _GameViewState();
}

class _GameViewState extends State<GameView> with TickerProviderStateMixin {
  static const _tilesSide = 16;
  static const _tileWorld = 8.0;

  final _viewportKey = GlobalKey();
  final _volumes = VolumeStore(
    grid: const VolumeGrid(
      tilesSide: _tilesSide,
      tileSize: _tileWorld,
      subtilesPerTile: VolumeGrid.defaultSubtilesPerTile,
    ),
  );
  late final PathStore _paths = PathStore(grid: _volumes.grid);
  late final WallStore _walls = WallStore(grid: _volumes.grid);
  final _friends = FriendInstanceStore();

  late final Camera _camera;
  late final MapLookCameraController _look;
  late final Scene _scene;
  late final LandscapeGenParams _params;
  final WorldTheme _theme = WorldTheme.paperDiorama;
  late GroundShadowModel _groundShadow;
  late final MapOctree _octree;
  late final MapSceneStreamer _streamer;

  ui.Image? _atlas;

  bool _baking = false;
  String? _status;
  String? _error;

  bool _volumesTool = false;
  bool _pathsTool = false;
  bool _wallsTool = false;
  bool _worldEraserTool = false;
  bool _selectTool = false;
  bool _paintTool = false;
  bool _fillTool = false;
  bool _eraseTool = false;
  PaperColor _paintColor = PaperColor.pink;
  final _facePaint = FacePaintStore();
  FacePaintKey? _focusedFace;
  bool _graphVisible = true;
  ConnectionGraph _graph = ConnectionGraph.empty;

  GameViewerKind _viewer = GameViewerKind.map3d;
  final _perf = PerfDebugSettings();
  SceneLayerMask get _layers =>
      SceneLayerMask.forViewer(_viewer).hiding(_perf.hiddenLayers);
  bool get _isPlane2d => _viewer == GameViewerKind.plane2d;
  bool get _isFocus3d => _viewer == GameViewerKind.focus3d;
  FocusRegion? _focusRegion;
  FocusCrop? _focusCropBounds;
  FocusCrop? _focusCrop;
  bool _cropTool = false;
  CropHandle? _cropDragHandle;
  FocusCrop? _cropDragSnapshot;
  OrbitCameraController? _orbit;
  Timer? _pendingFocusTimer;
  PlaneLookCameraController? _planeLook;
  late final AnimationController _viewerAnim;
  bool _viewerReturning = false;
  Vector3? _camFromPos;
  Vector3? _camToPos;
  Vector3? _camFromTarget;
  Vector3? _camToTarget;
  Vector3? _camFromUp;
  Vector3? _camToUp;
  double _camFromFov = 50;
  double _camToFov = 50;
  Vector3? _mapSnapLook;
  double _mapSnapDistance = 0;
  double _mapSnapYaw = 0;
  DateTime? _lastClickTime;
  Offset? _lastClickPos;
  LandscapeGenerator? _landscapeGen;
  LandscapeGrid? _grid;
  Timer? _paintDebounce;
  (int, int)? _paintLastCell;
  bool _recordingBusy = false;

  int _mouseButtons = 0;
  Size _viewportSize = Size.zero;
  int _cullRadius = 4;

  Offset? _pendingToolDown;
  bool _toolDidMove = false;
  bool _handleDragging = false;
  (int, int)? _pathStrokeLast;
  Vector3? _wallStrokeLast;
  Vector3? _eraserCursor;
  List<WallRegion> _wallRegions = const [];
  GameSnapshot? _wallSessionBefore;
  bool _wallSessionPushed = false;
  final _eraserFilter = EraserFilter();

  bool _isMultiTouch = false;
  bool _panZoomActive = false;
  bool _pinchEpisode = false;
  bool _toolsSuppressedUntilPointersUp = false;
  int _pointerCount = 0;
  double _pinchSpanScale = 1;

  bool _devToolsOpen = false;
  bool _gizmoMode = false;
  int _dayNumber = 1;
  bool _isNight = false;
  double _dayNightProgress = 0;
  NightSwatch _nightSwatch = NightSwatch.invertedTwilight;
  bool _dayNightBusy = false;
  bool _advancingDay = false;
  int _advanceToDay = 2;
  late final AnimationController _sunsetAnim;
  GizmoTarget? _gizmoSelected;
  GizmoTarget? _gizmoDownTarget;
  Vector3? _gizmoGroundStart;
  Vector3? _gizmoFriendStartPos;
  SceneGizmoAxis? _gizmoAxis;
  GameSnapshot? _gizmoVolumeBefore;

  VolumeHandle? _dragHandle;
  BoxPrimitive? _dragBoxSnapshot;
  Vector3? _dragStartHit;
  Vector3? _dragPlanePoint;
  GameSnapshot? _dragBefore;
  GameSnapshot? _strokeBefore;
  bool _strokePushed = false;
  final _history = GameHistory();

  double get _worldSize => _tilesSide * _tileWorld;
  double get _mapHalf => _worldSize * 0.5;

  bool get _editing => _volumes.isEditing;

  bool get _showGizmos =>
      _gizmoMode && _viewer == GameViewerKind.map3d && !_editing;

  bool get _toolsBlocked =>
      _toolsSuppressedUntilPointersUp ||
      _isMultiTouch ||
      _panZoomActive ||
      _pinchEpisode ||
      _pointerCount >= 2;

  void _lockToolsForMultiTouch() {
    _toolsSuppressedUntilPointersUp = true;
  }

  void _maybeUnlockToolsAfterPointersUp() {
    if (_pointerCount <= 0 && !_panZoomActive) {
      _pointerCount = 0;
      final wasLocked = _toolsBlocked;
      _toolsSuppressedUntilPointersUp = false;
      _isMultiTouch = false;
      _pinchEpisode = false;
      if (wasLocked && mounted) setState(() {});
    }
  }

  void _cancelPendingToolDown() {
    _pendingToolDown = null;
  }

  void _queueToolPointerDown(Offset local) {
    _pendingToolDown = local;
  }

  void _flushPendingToolDown() {
    final pos = _pendingToolDown;
    if (pos == null) return;
    _pendingToolDown = null;
    if (_toolsBlocked) return;
    _toolDidMove = false;
    _pathStrokeLast = _pathsTool ? _tileAt(pos) : null;
    _wallStrokeLast = _wallsTool
        ? _camera.intersectGround(pos, _viewportSize)
        : null;
    if (_worldEraserTool) {
      _eraserCursor = _camera.intersectGround(pos, _viewportSize);
    }
    if (_showGizmos) {
      _gizmoDownTarget = _hitGizmoTarget(pos);
      _gizmoGroundStart = _camera.intersectGround(pos, _viewportSize);
    }
  }

  GameSnapshot _capture(String label) => GameSnapshot.capture(
    volumes: _volumes,
    paths: _paths,
    walls: _walls,
    landscape: _grid,
    facePaint: _facePaint,
    label: label,
  );

  bool _commitAction(String label, bool Function() apply) {
    final before = _capture(label);
    if (!apply()) return false;
    _history.pushSnapshot(before);
    _syncWorld();
    setState(() {});
    return true;
  }

  void _ensureStrokeHistory(String label) {
    _strokeBefore ??= _capture(label);
  }

  void _recordStrokeIfNeeded() {
    final before = _strokeBefore;
    if (before == null || _strokePushed) return;
    _history.pushSnapshot(before);
    _strokePushed = true;
  }

  void _endStrokeHistory() {
    _strokeBefore = null;
    _strokePushed = false;
  }

  void _endWallSession() {
    _wallSessionBefore = null;
    _wallSessionPushed = false;
  }

  void _ensureWallSession() {
    _wallSessionBefore ??= _capture('paint walls');
  }

  void _recordWallSessionMutation() {
    final before = _wallSessionBefore;
    if (before == null || _wallSessionPushed) return;
    _history.pushSnapshot(before);
    _wallSessionPushed = true;
  }

  void _undo() {
    if (_handleDragging) return;
    _endStrokeHistory();
    _endWallSession();
    final snap = _history.undo(_capture('current'));
    if (snap == null) return;
    _applySnapshot(snap);
  }

  void _redo() {
    if (_handleDragging) return;
    _endStrokeHistory();
    _endWallSession();
    final snap = _history.redo(_capture('current'));
    if (snap == null) return;
    _applySnapshot(snap);
  }

  void _applySnapshot(GameSnapshot snap) {
    snap.applyTo(
      volumes: _volumes,
      paths: _paths,
      walls: _walls,
      landscape: _grid,
      facePaint: _facePaint,
    );
    _syncWorld();
    _schedulePaintRebake();
    final selected = _gizmoSelected;
    if (selected is VolumeGizmoTarget) {
      final volume = _volumes.volumeById(selected.volume.id);
      _gizmoSelected = volume == null
          ? null
          : VolumeGizmoTarget(
              volume: volume,
              store: _volumes,
              blocked: _paths.contains,
            );
    }
    final face = _focusedFace;
    if (_isPlane2d && face != null) {
      final stillThere = _volumes.visibleVolumes.any(
        (v) => v.id == face.volumeId && v.cellAt(face.tx, face.ty) != null,
      );
      if (!stillThere) {
        _returnToMap3d();
        return;
      }
    }
    setState(() {});
  }

  Future<void> _populateRecording() async {
    if (_baking || _recordingBusy) return;
    if (_editing) {
      _volumes.cancelDraft();
      _syncWorld();
    }
    final before = _capture('populate recording');
    setState(() {
      _recordingBusy = true;
      _status = 'Loading recording…';
    });
    try {
      final recording = await GameRecordingIo.loadDefault();
      if (!mounted) return;
      recording.applyTo(
        volumes: _volumes,
        paths: _paths,
        walls: _walls,
        facePaint: _facePaint,
        friends: _friends,
        landscape: _grid,
        generator: _landscapeGen,
      );
      _history.pushSnapshot(before);
      _syncWorld();
      _schedulePaintRebake();
      final face = _focusedFace;
      if ((_isPlane2d || _isFocus3d) && face != null) {
        final stillThere = _volumes.visibleVolumes.any(
          (v) => v.id == face.volumeId && v.cellAt(face.tx, face.ty) != null,
        );
        if (!stillThere) {
          _returnToMap3d();
          _status = 'Populated $kDefaultGameRecordingPath';
          return;
        }
      }
      _status = 'Populated $kDefaultGameRecordingPath';
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Populate failed: $e');
    } finally {
      if (mounted) setState(() => _recordingBusy = false);
    }
  }

  Future<void> _saveRecording() async {
    if (_recordingBusy || !_history.canUndo) return;
    setState(() {
      _recordingBusy = true;
      _status = 'Saving recording…';
    });
    try {
      final recording = GameRecording.capture(
        volumes: _volumes,
        paths: _paths,
        walls: _walls,
        facePaint: _facePaint,
        friends: _friends,
        landscape: _grid,
      );
      final path = await GameRecordingIo.saveDefault(recording);
      if (!mounted) return;
      setState(() => _status = 'Recorded to $path');
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Record failed: $e');
    } finally {
      if (mounted) setState(() => _recordingBusy = false);
    }
  }

  /// Second finger / trackpad pinch: camera only; tools stay dead until lift.
  void _enterPinchExclusiveMode() {
    _lockToolsForMultiTouch();
    _pinchEpisode = true;
    _cancelPendingToolDown();
    _pathStrokeLast = null;
    _wallStrokeLast = null;
    _toolDidMove = false;
    if (_handleDragging && (_gizmoSelected != null || _gizmoAxis != null)) {
      _endGizmoDrag();
      return;
    }
    if (_handleDragging) _onHandleDragEnd();
    if (_cropDragHandle != null) _onCropDragEnd();
    _endStrokeHistory();
    if (mounted) setState(() {});
  }

  bool get _confirmEnabled {
    if (_volumes.phase == VolumeEditPhase.editing) return true;
    if (_volumes.phase != VolumeEditPhase.pickingAccess) return false;
    if (!_volumes.requiresAccessibleSide) return true;
    return _volumes.draftCell?.accessibleSides.isNotEmpty ?? false;
  }

  @override
  void initState() {
    super.initState();
    _params = LandscapeGenParams(
      tilesSide: _tilesSide,
      colorSigma: WorldTheme.paperDiorama.colorSigma,
      gradients: WorldTheme.paperDiorama.gradients,
    ).clamped();
    _groundShadow = GroundShadowModel(
      lightX: _theme.shade.lightX,
      lightY: _theme.shade.lightY,
      lightZ: _theme.shade.lightZ,
    );

    final half = _mapHalf;
    _camera = Camera(
      name: 'gameview-cam',
      position: Vector3(0, half, 0),
      target: Vector3.zero(),
      projection: ProjectionType.perspective,
      fovDegrees: 50,
      near: 1,
      far: _worldSize * 8,
    );
    _look = MapLookCameraController(
      camera: _camera,
      vsync: this,
      lookAt: Vector3.zero(),
      minDistance: 28,
      maxDistance: _worldSize * 1.2,
      ladderZoom: false,
      boundsMin: Vector3(-half, 0, -half),
      boundsMax: Vector3(half, 0, half),
    )..addListener(_onCameraChanged);

    _scene = Scene(globalIllumination: 0.25)
      ..camera = _camera
      ..addLight(
        DirectionalLight(
          color: Colors.white,
          intensity: 0.95,
          direction: Vector3(-0.6, -1, -0.4),
        ),
      )
      ..addLight(
        DirectionalLight(
          color: Colors.white70,
          intensity: 0.35,
          direction: Vector3(0.4, -0.5, 0.6),
        ),
      )
      ..addListener(_onSceneChanged);

    _octree = MapOctree(
      bounds: MapAabb(Vector3(-half, 0, -half), Vector3(half, 24, half)),
      minLeafSize: _tileWorld,
    );
    _streamer = MapSceneStreamer(
      scene: _scene,
      octree: _octree,
      tileSize: _tileWorld,
      tilesSide: _tilesSide,
      loadPadding: 0,
      unloadPadding: 0,
    );

    _bakeLandscape();
    _refreshStatus();
    _viewerAnim =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 750),
          )
          ..addListener(_onViewerAnimTick)
          ..addStatusListener(_onViewerAnimStatus);
    _sunsetAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..addListener(_onSunsetTick);
  }

  DayNightLighting get _lighting => DayNightLighting.lerp(
    DayNightLighting.day(_theme),
    _nightSwatch.lighting,
    _dayNightProgress,
  );

  void _onSunsetTick() {
    _dayNightProgress = _sunsetAnim.value;
    _applyDayNightLighting();
    if (mounted) setState(() {});
  }

  void _applyDayNightLighting() {
    final lit = _lighting;
    _groundShadow = lit.shadow;
    _scene.globalIllumination = lit.globalIllumination;
    _scene.setLights(lit.lights);
  }

  Future<void> _endDayOrNight() async {
    if (_dayNightBusy || _advancingDay) return;
    if (!_isNight) {
      setState(() => _dayNightBusy = true);
      await _sunsetAnim.forward(from: _dayNightProgress);
      if (!mounted) return;
      setState(() {
        _isNight = true;
        _dayNightProgress = 1;
        _dayNightBusy = false;
      });
      _applyDayNightLighting();
      return;
    }
    setState(() {
      _advanceToDay = _dayNumber + 1;
      _advancingDay = true;
    });
  }

  void _onAdvanceReadyForDay() {
    _isNight = false;
    _dayNumber = _advanceToDay;
    _dayNightProgress = 0;
    _sunsetAnim.value = 0;
    _applyDayNightLighting();
    if (mounted) setState(() {});
  }

  void _onAdvanceFinished() {
    if (mounted) setState(() => _advancingDay = false);
  }

  void _setDayNightProgress(double t) {
    _sunsetAnim.stop();
    _dayNightProgress = t.clamp(0.0, 1.0);
    _applyDayNightLighting();
    setState(() {});
  }

  void _setNightSwatch(NightSwatch swatch) {
    _nightSwatch = swatch;
    _applyDayNightLighting();
    setState(() {});
  }

  @override
  void dispose() {
    _paintDebounce?.cancel();
    _pendingFocusTimer?.cancel();
    _history.dispose();
    _sunsetAnim
      ..removeListener(_onSunsetTick)
      ..dispose();
    _viewerAnim
      ..removeListener(_onViewerAnimTick)
      ..removeStatusListener(_onViewerAnimStatus)
      ..dispose();
    _orbit
      ?..removeListener(_onCameraChanged)
      ..dispose();
    _planeLook
      ?..removeListener(_onCameraChanged)
      ..dispose();
    _look
      ..removeListener(_onCameraChanged)
      ..dispose();
    _scene.removeListener(_onSceneChanged);
    _atlas?.dispose();
    PerfDebugSettings.resetEngineFlags();
    PaintStatsProbe.reset();
    super.dispose();
  }

  void _onCameraChanged() {
    _look.setViewportSize(_viewportSize);
    _planeLook?.setViewportSize(_viewportSize);
    _orbit?.setViewportSize(_viewportSize);
    _scene.markNeedsPaint();
    _scheduleStream();
    if (mounted) {
      setState(_refreshStatus);
    }
  }

  void _onSceneChanged() {
    if (mounted) setState(_refreshStatus);
  }

  void _scheduleStream() {
    final (tx, ty) = _look.lookAtTile(
      tileSize: _tileWorld,
      tilesSide: _tilesSide,
    );
    unawaited(_streamer.sync(lookTx: tx, lookTy: ty, drawRadius: _cullRadius));
  }

  void _refreshStatus() {
    if (_error != null) return;
    if (_baking) return;
    final (tx, ty) = _look.lookAtTile(
      tileSize: _tileWorld,
      tilesSide: _tilesSide,
    );
    _status =
        '${_viewer.name} · Tile ($tx, $ty) · ${_look.zoomLabel} · '
        'cull ±$_cullRadius · '
        'drawn ${_streamer.drawnCount}/${_streamer.placedCount}';
  }

  void _syncWorld() {
    syncVolumeMeshes(
      _scene,
      _volumes,
      committed: _theme.volume,
      draftColor: _theme.volumeDraft,
    );
    syncPathMeshes(_scene, _paths, _volumes, color: _theme.path);
    syncWallMeshes(_scene, _walls, color: _theme.wall);
    syncFriendMeshes(_scene, _friends, tileSize: _tileWorld);
    _wallRegions = computeEnclosedRegions(_walls);
    _graph = ConnectionGraph.build(volumes: _volumes, paths: _paths);
    _facePaint.prune(_volumes);
    _applyLayerVisibility();
    _syncGroundCoverage();
  }

  void _syncGroundCoverage() {
    final grid = _grid;
    final gen = _landscapeGen;
    if (grid == null || gen == null) return;
    if (syncGroundCoverage(
      grid: grid,
      volumes: _volumes,
      paths: _paths,
      generator: gen,
    )) {
      _schedulePaintRebake();
    }
  }

  void _applyLayerVisibility() {
    final showVol = _layers.shows(SceneLayer.volumes);
    final showPath = _layers.shows(SceneLayer.paths);
    final showWall = _layers.shows(SceneLayer.walls);
    for (final mesh in _scene.meshes) {
      if (mesh.id.startsWith('volume_')) {
        mesh.visible =
            showVol && _meshVisibleInFocus(mesh.id, prefix: 'volume');
      } else if (mesh.id.startsWith('path_')) {
        mesh.visible = showPath && _meshVisibleInFocus(mesh.id, prefix: 'path');
      } else if (mesh.id.startsWith('wall_')) {
        mesh.visible = showWall && _wallMeshVisible(mesh.id);
      } else if (mesh.id.startsWith('friend_')) {
        mesh.visible = _layers.shows(SceneLayer.friends);
      } else {
        mesh.visible =
            _focusRegion == null && _layers.shows(SceneLayer.streamerCrafts);
      }
    }
  }

  bool _focusTileVisible(int tx, int ty) {
    final region = _focusRegion;
    if (region == null) return true;
    if (!region.contains(tx, ty)) return false;
    final crop = _focusCrop;
    if (crop == null) return true;
    return crop.intersectsTile(_volumes.grid, tx, ty);
  }

  Set<(int, int)>? _focusVisibleTiles() {
    final region = _focusRegion;
    if (region == null) return null;
    return {
      for (final tile in region.tiles)
        if (_focusTileVisible(tile.$1, tile.$2)) tile,
    };
  }

  bool _meshVisibleInFocus(String id, {required String prefix}) {
    final tile = _tileFromMeshId(id, prefix: prefix);
    if (tile == null) return _focusRegion == null;
    if (!_focusTileVisible(tile.$1, tile.$2)) return false;
    final crop = _focusCrop;
    if (crop == null) return true;
    if (prefix == 'volume') {
      final parts = id.split('_');
      if (parts.length < 4) return true;
      final volumeId = int.tryParse(parts[1]);
      if (volumeId == null) return true;
      final volume = _volumeById(volumeId);
      final cell = volume?.cellAt(tile.$1, tile.$2);
      if (cell == null) return true;
      return crop.intersectsWorld(
        cell.box.worldMin(_volumes.grid, cell.tx, cell.ty),
        cell.box.worldMax(_volumes.grid, cell.tx, cell.ty),
        _volumes.grid,
      );
    }
    final (tileMin, tileMax) = _volumes.grid.tileAabb(tile.$1, tile.$2);
    return crop.intersectsWorld(
      tileMin,
      Vector3(tileMax.x, kPathHeight, tileMax.z),
      _volumes.grid,
    );
  }

  void _applyFocusCrop(FocusCrop crop) {
    _focusCrop = crop;
    final orbit = _orbit;
    if (orbit != null) {
      orbit.setPanBounds(
        crop.worldMin(_volumes.grid),
        crop.worldMax(_volumes.grid),
      );
    }
    _applyLayerVisibility();
    _scene.markNeedsPaint();
  }

  void _toggleCropTool() {
    if (!_isFocus3d) return;
    setState(() => _cropTool = !_cropTool);
  }

  void _resetFocusCrop() {
    final bounds = _focusCropBounds;
    if (bounds == null) return;
    _applyFocusCrop(bounds);
    setState(() {});
  }

  (int tx, int ty)? _tileFromMeshId(String id, {required String prefix}) {
    final parts = id.split('_');
    if (prefix == 'path') {
      if (parts.length < 3) return null;
      final tx = int.tryParse(parts[1]);
      final ty = int.tryParse(parts[2]);
      if (tx == null || ty == null) return null;
      return (tx, ty);
    }
    if (parts.length < 4) return null;
    final tx = int.tryParse(parts[parts.length - 2]);
    final ty = int.tryParse(parts.last);
    if (tx == null || ty == null) return null;
    return (tx, ty);
  }

  bool _pathBlocked(int tx, int ty) => _volumes.isOccupied(tx, ty);

  bool _wallMeshVisible(String id) {
    final edge = wallEdgeFromMeshId(id);
    if (edge == null) return _focusRegion == null;
    for (final tile in tilesTouchingWall(edge)) {
      if (_volumes.grid.inBounds(tile.$1, tile.$2) &&
          _focusTileVisible(tile.$1, tile.$2)) {
        return true;
      }
    }
    return _focusRegion == null;
  }

  (int, int)? _tileAt(Offset local) {
    final hit = _camera.intersectGround(local, _viewportSize);
    if (hit == null) return null;
    return _volumes.grid.tileAtWorld(hit);
  }

  Future<void> _bakeLandscape() async {
    setState(() {
      _baking = true;
      _status = 'Baking landscape…';
    });
    try {
      final generator = LandscapeGenerator(_params);
      _landscapeGen = generator;
      final grid = LandscapeGrid.fromGenerator(generator);
      _grid = grid;
      final image = await generator.bakeAtlasFromGrid(grid, theme: _theme);
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() {
        _atlas?.dispose();
        _atlas = image;
        _baking = false;
        _refreshStatus();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _baking = false;
        _error = 'Landscape bake failed: $e';
      });
    }
  }

  Offset _toLocal(Offset global) {
    final box = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return global;
    return box.globalToLocal(global);
  }

  void _toggleVolumes() {
    _pendingFocusTimer?.cancel();
    setState(() {
      if (_volumesTool && _editing) {
        _volumes.cancelDraft();
        _syncWorld();
      }
      _volumesTool = !_volumesTool;
      if (_volumesTool) {
        _pathsTool = false;
        _wallsTool = false;
        _worldEraserTool = false;
        _selectTool = false;
        _endWallSession();
      }
    });
  }

  void _togglePaths() {
    _pendingFocusTimer?.cancel();
    setState(() {
      if (_editing) {
        _volumes.cancelDraft();
        _syncWorld();
      }
      _pathsTool = !_pathsTool;
      if (_pathsTool) {
        _volumesTool = false;
        _wallsTool = false;
        _worldEraserTool = false;
        _selectTool = false;
        _endWallSession();
      }
    });
  }

  void _toggleWalls() {
    _pendingFocusTimer?.cancel();
    setState(() {
      if (_editing) {
        _volumes.cancelDraft();
        _syncWorld();
      }
      _wallsTool = !_wallsTool;
      if (_wallsTool) {
        _volumesTool = false;
        _pathsTool = false;
        _worldEraserTool = false;
        _selectTool = false;
      } else {
        _endWallSession();
      }
    });
  }

  void _toggleWorldEraser() {
    _pendingFocusTimer?.cancel();
    setState(() {
      if (_editing) {
        _volumes.cancelDraft();
        _syncWorld();
      }
      _worldEraserTool = !_worldEraserTool;
      if (_worldEraserTool) {
        _volumesTool = false;
        _pathsTool = false;
        _wallsTool = false;
        _selectTool = false;
        _endWallSession();
      } else {
        _eraserCursor = null;
      }
    });
  }

  void _toggleGraph() {
    setState(() => _graphVisible = !_graphVisible);
  }

  void _toggleSelect() {
    _pendingFocusTimer?.cancel();
    setState(() {
      if (_editing) {
        _volumes.cancelDraft();
        _syncWorld();
      }
      _selectTool = !_selectTool;
      if (_selectTool) {
        _volumesTool = false;
        _pathsTool = false;
        _wallsTool = false;
        _endWallSession();
        _worldEraserTool = false;
      }
    });
  }

  void _isolateLookAt() {
    if (_viewer != GameViewerKind.map3d || _viewerAnim.isAnimating) return;
    final tile = _volumes.grid.tileAtWorld(_look.lookAt);
    if (tile == null) return;
    final (tx, ty) = tile;
    FocusRegion region = FocusRegion.aroundTile(
      grid: _volumes.grid,
      tx: tx,
      ty: ty,
    );
    for (final volume in _volumes.visibleVolumes) {
      if (volume.cellAt(tx, ty) == null) continue;
      region = FocusRegion.aroundVolume(grid: _volumes.grid, volume: volume);
      break;
    }
    _enterFocus3d(region);
  }

  void _togglePaint() {
    setState(() {
      _paintTool = !_paintTool;
      if (_paintTool) {
        _eraseTool = false;
        _fillTool = false;
      }
    });
  }

  void _toggleFill() {
    setState(() {
      _fillTool = !_fillTool;
      if (_fillTool) {
        _paintTool = false;
        _eraseTool = false;
      }
    });
  }

  void _toggleErase() {
    setState(() {
      _eraseTool = !_eraseTool;
      if (_eraseTool) {
        _paintTool = false;
        _fillTool = false;
      }
    });
  }

  Vector3 _lerpVec(Vector3 a, Vector3 b, double t) => Vector3(
    a.x + (b.x - a.x) * t,
    a.y + (b.y - a.y) * t,
    a.z + (b.z - a.z) * t,
  );

  void _onViewerAnimTick() {
    final fromP = _camFromPos;
    final toP = _camToPos;
    final fromT = _camFromTarget;
    final toT = _camToTarget;
    final fromU = _camFromUp;
    final toU = _camToUp;
    if (fromP == null || toP == null || fromT == null || toT == null) return;
    if (fromU == null || toU == null) return;
    final t = Curves.easeOutCubic.transform(_viewerAnim.value);
    _camera.setPosition(_lerpVec(fromP, toP, t));
    _camera.setTarget(_lerpVec(fromT, toT, t));
    _camera.setUp(_lerpVec(fromU, toU, t));
    _camera.fovDegrees = _camFromFov + (_camToFov - _camFromFov) * t;
    _scene.markNeedsPaint();
    if (mounted) setState(() {});
  }

  void _onViewerAnimStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_viewerReturning) {
      final look = _mapSnapLook;
      if (look != null) {
        _look.restorePose(
          lookAt: look,
          distance: _mapSnapDistance,
          yaw: _mapSnapYaw,
        );
      }
      _camera.fovDegrees = 50;
      _orbit
        ?..removeListener(_onCameraChanged)
        ..dispose();
      _orbit = null;
      _focusRegion = null;
      _focusCrop = null;
      _focusCropBounds = null;
      _cropTool = false;
      _cropDragHandle = null;
      _cropDragSnapshot = null;
      _planeLook
        ?..removeListener(_onCameraChanged)
        ..dispose();
      _planeLook = null;
      _viewerReturning = false;
      _viewer = GameViewerKind.map3d;
      _focusedFace = null;
      _paintTool = false;
      _fillTool = false;
      _eraseTool = false;
      _applyLayerVisibility();
      if (mounted) setState(() {});
      return;
    }
    if (_isFocus3d) {
      _orbit?.jumpTo(
        position: _camera.position,
        target: _camera.target,
        setFocus: false,
      );
      return;
    }
    _planeLook?.applyPoseNow();
  }

  void _enterPlane2d(WorldPlane plane, {FacePaintKey? face}) {
    if (_viewerAnim.isAnimating) return;
    _pendingFocusTimer?.cancel();
    _look.pauseForHandoff();
    if (_editing) {
      _volumes.cancelDraft();
      _syncWorld();
    }
    _focusedFace = face;
    _mapSnapLook = _look.lookAt;
    _mapSnapDistance = _look.distance;
    _mapSnapYaw = _look.yaw;
    _camFromPos = Vector3.copy(_camera.position);
    _camFromTarget = _camera.target;
    _camFromUp = _camera.up;
    _camFromFov = _camera.fovDegrees;

    _planeLook
      ?..removeListener(_onCameraChanged)
      ..dispose();
    final planeLook = PlaneLookCameraController(camera: _camera, plane: plane)
      ..setViewportSize(_viewportSize);
    _camToPos = Vector3.copy(_camera.position);
    _camToTarget = Vector3.copy(_camera.target);
    _camToUp = Vector3.copy(_camera.up);
    _camToFov = _camera.fovDegrees;
    _camera.setPosition(_camFromPos!);
    _camera.setTarget(_camFromTarget!);
    _camera.setUp(_camFromUp!);
    _camera.fovDegrees = _camFromFov;

    _planeLook = planeLook..addListener(_onCameraChanged);
    _viewer = GameViewerKind.plane2d;
    _viewerReturning = false;
    _selectTool = false;
    _volumesTool = false;
    _pathsTool = false;
    _wallsTool = false;
    _worldEraserTool = false;
    _endWallSession();
    _paintLastCell = null;
    setState(() {});
    _viewerAnim.forward(from: 0);
  }

  void _retargetPlane2dFace({
    required VolumeCell cell,
    required VolumeFace face,
    required int volumeId,
    bool coplanar = false,
  }) {
    if (_viewerAnim.isAnimating) return;
    final look = _planeLook;
    if (look == null || !_isPlane2d) return;
    final key = _focusedFace;
    if (key != null &&
        key.volumeId == volumeId &&
        key.tx == cell.tx &&
        key.ty == cell.ty &&
        key.face == face) {
      return;
    }
    _focusedFace = FacePaintKey(
      volumeId: volumeId,
      tx: cell.tx,
      ty: cell.ty,
      face: face,
    );
    _paintLastCell = null;
    if (coplanar) {
      if (mounted) setState(() {});
      return;
    }
    _camFromPos = Vector3.copy(_camera.position);
    _camFromTarget = Vector3.copy(_camera.target);
    _camFromUp = Vector3.copy(_camera.up);
    _camFromFov = _camera.fovDegrees;
    final nextPlane = WorldPlane.fromVolumeFace(
      grid: _volumes.grid,
      cell: cell,
      face: face,
    );
    final projected = nextPlane.projectPoint(look.lookAt);
    final (u, v) = nextPlane.toUv(projected);
    look.attachPlane(nextPlane, u: u, v: v);
    _camToPos = Vector3.copy(_camera.position);
    _camToTarget = Vector3.copy(_camera.target);
    _camToUp = Vector3.copy(_camera.up);
    _camToFov = _camera.fovDegrees;
    _camera.setPosition(_camFromPos!);
    _camera.setTarget(_camFromTarget!);
    _camera.setUp(_camFromUp!);
    _camera.fovDegrees = _camFromFov;
    _viewerReturning = false;
    if (mounted) setState(() {});
    _viewerAnim.forward(from: 0);
  }

  Volume? _volumeById(int id) {
    for (final volume in _volumes.visibleVolumes) {
      if (volume.id == id) return volume;
    }
    return null;
  }

  void _maybeTurnPlane2dFace() {
    if (!_isPlane2d || _viewerAnim.isAnimating) return;
    final key = _focusedFace;
    final look = _planeLook;
    if (key == null || look == null) return;
    if (_viewportSize.width < 1 || _viewportSize.height < 1) return;
    final volume = _volumeById(key.volumeId);
    final cell = volume?.cellAt(key.tx, key.ty);
    if (volume == null || cell == null) return;
    final next = nextPlane2dFaceTurn(
      volumeId: volume.id,
      cell: cell,
      face: key.face,
      lookAt: look.lookAt,
      screenCenter: Offset(
        _viewportSize.width * 0.5,
        _viewportSize.height * 0.5,
      ),
      project: (world) => _camera.projectToScreen(world, _viewportSize),
      grid: _volumes.grid,
      volumes: _volumes.visibleVolumes,
      currentPlane: look.plane,
    );
    if (next == null) return;
    _retargetPlane2dFace(
      cell: next.cell,
      face: next.face,
      volumeId: next.volumeId,
      coplanar: next.coplanar,
    );
  }

  void _enterFocus3d(FocusRegion region) {
    if (_viewerAnim.isAnimating) return;
    if (_viewer != GameViewerKind.map3d) return;
    _pendingFocusTimer?.cancel();
    _look.pauseForHandoff();
    if (_editing) {
      _volumes.cancelDraft();
      _syncWorld();
    }
    _mapSnapLook = _look.lookAt;
    _mapSnapDistance = _look.distance;
    _mapSnapYaw = _look.yaw;
    _camFromPos = Vector3.copy(_camera.position);
    _camFromTarget = _camera.target;
    _camFromUp = _camera.up;
    _camFromFov = _camera.fovDegrees;

    final (aabbMin, aabbMax) = region.contentAabb(
      grid: _volumes.grid,
      volumes: _volumes,
      paths: _paths,
    );
    final center = Vector3(
      (aabbMin.x + aabbMax.x) * 0.5,
      (aabbMin.y + aabbMax.y) * 0.5,
      (aabbMin.z + aabbMax.z) * 0.5,
    );
    final extent = math.max(
      aabbMax.x - aabbMin.x,
      math.max(aabbMax.y - aabbMin.y, aabbMax.z - aabbMin.z),
    );
    final minD = math.max(extent * 0.35, 6.0);
    final maxD = math.max(extent * 5.0, minD + 8.0);
    final halfFov = 50 * math.pi / 360;
    final framed = (extent * 0.55) / math.tan(halfFov);
    final distance = framed.clamp(minD, maxD);

    _orbit
      ?..removeListener(_onCameraChanged)
      ..dispose();
    _planeLook
      ?..removeListener(_onCameraChanged)
      ..dispose();
    _planeLook = null;

    final orbit = OrbitCameraController(
      camera: _camera,
      target: center,
      minDistance: minD,
      maxDistance: maxD,
    )..setViewportSize(_viewportSize);
    orbit.setPanBounds(aabbMin, aabbMax);
    orbit.setPose(target: center, radius: distance);
    _camera.setUp(Vector3(0, 1, 0));
    _camera.fovDegrees = 50;
    _camToPos = Vector3.copy(_camera.position);
    _camToTarget = _camera.target;
    _camToUp = Vector3(0, 1, 0);
    _camToFov = 50;
    _camera.setPosition(_camFromPos!);
    _camera.setTarget(_camFromTarget!);
    _camera.setUp(_camFromUp!);
    _camera.fovDegrees = _camFromFov;

    _orbit = orbit..addListener(_onCameraChanged);
    _focusRegion = region;
    final isolation = FocusCrop.fromIsolation(
      region: region,
      grid: _volumes.grid,
      contentMaxY: aabbMax.y,
    );
    _focusCropBounds = isolation;
    _focusCrop = isolation;
    _cropTool = false;
    orbit.setPanBounds(
      isolation.worldMin(_volumes.grid),
      isolation.worldMax(_volumes.grid),
    );
    _viewer = GameViewerKind.focus3d;
    _viewerReturning = false;
    _selectTool = false;
    _volumesTool = false;
    _pathsTool = false;
    _wallsTool = false;
    _worldEraserTool = false;
    _endWallSession();
    _applyLayerVisibility();
    setState(() {});
    _viewerAnim.forward(from: 0);
  }

  void _returnToMap3d() {
    if (_viewer != GameViewerKind.plane2d &&
        _viewer != GameViewerKind.focus3d) {
      return;
    }
    if (_viewerAnim.isAnimating) return;
    _camFromPos = Vector3.copy(_camera.position);
    _camFromTarget = _camera.target;
    _camFromUp = _camera.up;
    _camFromFov = _camera.fovDegrees;
    final look = _mapSnapLook ?? Vector3.zero();
    final dist = _mapSnapDistance > 0 ? _mapSnapDistance : _look.distance;
    final yaw = _mapSnapYaw;
    final h = dist * math.cos(_look.pitch);
    _camToPos = Vector3(
      look.x - h * math.cos(yaw),
      look.y + dist * math.sin(_look.pitch),
      look.z - h * math.sin(yaw),
    );
    _camToTarget = Vector3(look.x, 0, look.z);
    _camToUp = Vector3(0, 1, 0);
    _camToFov = 50;
    _viewerReturning = true;
    _viewerAnim.forward(from: 0);
  }

  void _schedulePaintRebake() {
    _paintDebounce?.cancel();
    _paintDebounce = Timer(const Duration(milliseconds: 40), () {
      unawaited(_rebakeLandscape());
    });
  }

  Future<void> _rebakeLandscape() async {
    final gen = _landscapeGen;
    final grid = _grid;
    if (gen == null || grid == null) return;
    try {
      final image = await gen.bakeAtlasFromGrid(grid, theme: _theme);
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() {
        _atlas?.dispose();
        _atlas = image;
      });
    } catch (_) {}
  }

  (int wx, int wy)? _groundPixelAt(Offset local) {
    final plane = _planeLook?.plane;
    if (plane == null || _focusedFace != null || !plane.isGround) return null;
    final grid = _grid;
    if (grid == null) return null;
    final ray = _camera.unprojectRay(local, _viewportSize);
    if (ray == null) return null;
    final hit = plane.intersectRay(ray.origin, ray.direction);
    if (hit == null) return null;
    final half = _worldSize * 0.5;
    if (hit.x < -half || hit.x >= half || hit.z < -half || hit.z >= half) {
      return null;
    }
    final u = ((hit.x + half) / _worldSize).clamp(0.0, 1.0 - 1e-9);
    final v = ((hit.z + half) / _worldSize).clamp(0.0, 1.0 - 1e-9);
    final wx = (u * grid.side).floor().clamp(0, grid.side - 1);
    final wy = (v * grid.side).floor().clamp(0, grid.side - 1);
    return (wx, wy);
  }

  VolumeCell? _focusedCell() {
    final key = _focusedFace;
    if (key == null) return null;
    for (final volume in _volumes.visibleVolumes) {
      if (volume.id != key.volumeId) continue;
      return volume.cellAt(key.tx, key.ty);
    }
    return null;
  }

  (int u, int v)? _facePixelAt(Offset local) {
    final plane = _planeLook?.plane;
    final key = _focusedFace;
    final cell = _focusedCell();
    if (plane == null || key == null || cell == null) return null;
    final ray = _camera.unprojectRay(local, _viewportSize);
    if (ray == null) return null;
    final hit = plane.intersectRay(ray.origin, ray.direction);
    if (hit == null) return null;
    return FacePaintStore.pixelAt(
      world: hit,
      grid: _volumes.grid,
      cell: cell,
      face: key.face,
    );
  }

  void _strokePaint(Offset local) {
    if (_viewerAnim.isAnimating) return;
    final focus = _focusedFace;
    if (focus != null) {
      _strokeFace(local, focus);
      return;
    }
    _strokeLandscape(local);
  }

  void _strokeFace(Offset local, FacePaintKey key) {
    final cell = _focusedCell();
    if (cell == null) return;
    final pixel = _facePixelAt(local);
    if (pixel == null) return;
    _ensureStrokeHistory(_eraseTool ? 'erase' : 'paint');
    final canvas = _facePaint.canvasFor(
      volumeId: key.volumeId,
      cell: cell,
      face: key.face,
    );
    var changed = false;
    final last = _paintLastCell;
    if (last != null) {
      for (final p in _bresenham(last, pixel)) {
        if (_eraseTool) {
          if (canvas.erase(p.$1, p.$2)) changed = true;
        } else if (_paintTool) {
          if (canvas.paint(p.$1, p.$2, _paintColor)) changed = true;
        }
      }
    } else {
      if (_eraseTool) {
        changed = canvas.erase(pixel.$1, pixel.$2);
      } else if (_paintTool) {
        changed = canvas.paint(pixel.$1, pixel.$2, _paintColor);
      }
    }
    _paintLastCell = pixel;
    if (changed) {
      _recordStrokeIfNeeded();
      setState(() {});
    }
  }

  void _fillAt(Offset local) {
    if (_viewerAnim.isAnimating) return;
    final focus = _focusedFace;
    if (focus != null) {
      final cell = _focusedCell();
      final pixel = _facePixelAt(local);
      if (cell == null || pixel == null) return;
      final canvas = _facePaint.canvasFor(
        volumeId: focus.volumeId,
        cell: cell,
        face: focus.face,
      );
      final before = _capture('fill');
      if (canvas.fill(pixel.$1, pixel.$2, _paintColor)) {
        _history.pushSnapshot(before);
        setState(() {});
      }
      return;
    }
    final grid = _grid;
    final cell = _groundPixelAt(local);
    if (grid == null || cell == null) return;
    final before = _capture('fill');
    if (grid.fill(cell.$1, cell.$2, _paintColor)) {
      _history.pushSnapshot(before);
      _schedulePaintRebake();
    }
  }

  void _strokeLandscape(Offset local) {
    if (_viewerAnim.isAnimating) return;
    final cell = _groundPixelAt(local);
    if (cell == null) return;
    final grid = _grid;
    if (grid == null) return;
    _ensureStrokeHistory(_eraseTool ? 'erase' : 'paint');
    var changed = false;
    final last = _paintLastCell;
    if (last != null) {
      for (final p in _bresenham(last, cell)) {
        if (_eraseTool) {
          if (grid.erase(p.$1, p.$2)) changed = true;
        } else if (_paintTool) {
          if (grid.paint(p.$1, p.$2, _paintColor)) changed = true;
        }
      }
    } else {
      if (_eraseTool) {
        changed = grid.erase(cell.$1, cell.$2);
      } else if (_paintTool) {
        changed = grid.paint(cell.$1, cell.$2, _paintColor);
      }
    }
    _paintLastCell = cell;
    if (changed) {
      _recordStrokeIfNeeded();
      _schedulePaintRebake();
    }
  }

  Iterable<(int, int)> _bresenham((int, int) a, (int, int) b) sync* {
    var x0 = a.$1;
    var y0 = a.$2;
    final x1 = b.$1;
    final y1 = b.$2;
    final dx = (x1 - x0).abs();
    final dy = (y1 - y0).abs();
    final sx = x0 < x1 ? 1 : -1;
    final sy = y0 < y1 ? 1 : -1;
    var err = dx - dy;
    while (true) {
      yield (x0, y0);
      if (x0 == x1 && y0 == y1) break;
      final e2 = 2 * err;
      if (e2 > -dy) {
        err -= dy;
        x0 += sx;
      }
      if (e2 < dx) {
        err += dx;
        y0 += sy;
      }
    }
  }

  void _onSelectClick(Offset local) {
    final now = DateTime.now();
    final lastT = _lastClickTime;
    final lastP = _lastClickPos;
    _lastClickTime = now;
    _lastClickPos = local;
    final isDouble =
        lastT != null &&
        lastP != null &&
        now.difference(lastT).inMilliseconds < 400 &&
        (local - lastP).distanceSquared < 100;
    if (isDouble) {
      _pendingFocusTimer?.cancel();
      final face = const VolumeFacePicker().pick(
        screen: local,
        viewport: _viewportSize,
        camera: _camera,
        store: _volumes,
      );
      if (face != null) {
        _enterPlane2d(
          WorldPlane.fromVolumeFace(
            grid: _volumes.grid,
            cell: face.cell,
            face: face.face,
          ),
          face: FacePaintKey(
            volumeId: face.volumeId,
            tx: face.cell.tx,
            ty: face.cell.ty,
            face: face.face,
          ),
        );
        return;
      }
      final ground = _camera.intersectGround(local, _viewportSize);
      if (ground == null) return;
      _enterPlane2d(
        WorldPlane.ground(
          origin: ground,
          subtileSize: _volumes.grid.subtileSize,
        ),
      );
      return;
    }

    final region = _focusRegionFromClick(local);
    if (region == null) return;
    _pendingFocusTimer?.cancel();
    _pendingFocusTimer = Timer(const Duration(milliseconds: 400), () {
      if (!mounted || _viewer != GameViewerKind.map3d) return;
      _enterFocus3d(region);
    });
  }

  FocusRegion? _focusRegionFromClick(Offset local) {
    final face = const VolumeFacePicker().pick(
      screen: local,
      viewport: _viewportSize,
      camera: _camera,
      store: _volumes,
    );
    if (face != null) {
      for (final volume in _volumes.visibleVolumes) {
        if (volume.id != face.volumeId) continue;
        return FocusRegion.aroundVolume(grid: _volumes.grid, volume: volume);
      }
    }
    final tile = _tileAt(local);
    if (tile == null) return null;
    return FocusRegion.aroundTile(
      grid: _volumes.grid,
      tx: tile.$1,
      ty: tile.$2,
    );
  }

  void _placeCubeboy() {
    final lookTile = _volumes.grid.tileAtWorld(_look.lookAt);
    final tx = lookTile?.$1 ?? _tilesSide ~/ 2;
    final ty = lookTile?.$2 ?? _tilesSide ~/ 2;
    final center = _volumes.grid.tileCenter(tx, ty);
    center.y = FriendMeshLayout.sitOnGroundY(tileSize: _tileWorld);
    final instance = FriendInstance(
      id: MockFriendProvider.generateGuid(),
      friend: kCubeboyFriend,
      position: center,
    );
    _friends.add(instance);
    syncFriendMeshes(_scene, _friends, tileSize: _tileWorld);
    _applyLayerVisibility();
    if (_showGizmos) {
      _gizmoSelected = FriendGizmoTarget(instance, tileSize: _tileWorld);
    }
    setState(() {});
  }

  void _setGizmoMode(bool enabled) {
    setState(() {
      _gizmoMode = enabled;
      if (!enabled) _clearGizmoSelection();
    });
  }

  void _onPerfChanged() {
    _perf.applyEngineFlags();
    _applyLayerVisibility();
    setState(() {});
  }

  void _clearGizmoSelection() {
    _applyVolumePreview(null, Vector3.zero());
    if (_gizmoSelected is VolumeGizmoTarget) {
      (_gizmoSelected as VolumeGizmoTarget).resetDrag();
    }
    _gizmoSelected = null;
    _gizmoDownTarget = null;
    _gizmoGroundStart = null;
    _gizmoFriendStartPos = null;
    _gizmoAxis = null;
    _gizmoVolumeBefore = null;
  }

  GizmoTarget? _hitGizmoTarget(Offset local) {
    final tester = SceneHitTester(
      scene: _scene,
      camera: _camera,
      viewportSize: _viewportSize,
    );
    for (final hit in tester.hitTestAll(local)) {
      final mesh = _scene.meshById(hit.meshId);
      if (mesh != null && !mesh.visible) continue;
      final target = resolveGizmoTarget(
        meshId: hit.meshId,
        friends: _friends,
        volumes: _volumes,
        tileSize: _tileWorld,
        pathBlocked: _paths.contains,
      );
      if (target != null) return target;
    }
    return null;
  }

  void _applyVolumePreview(int? volumeId, Vector3 offset) {
    for (final mesh in _scene.meshes) {
      final parsed = parseVolumeMeshIdParts(mesh.id);
      if (parsed == null) continue;
      if (volumeId != null && parsed.volumeId != volumeId) continue;
      mesh.setPosition(volumeId == null ? Vector3.zero() : offset);
    }
    _scene.markNeedsPaint();
  }

  void _syncGizmoMeshes() {
    syncFriendMeshes(_scene, _friends, tileSize: _tileWorld);
    final selected = _gizmoSelected;
    if (selected is VolumeGizmoTarget) {
      _applyVolumePreview(selected.volume.id, selected.previewOffset);
    }
    _applyLayerVisibility();
  }

  void _onGizmoTap(Offset local) {
    final target = _hitGizmoTarget(local);
    setState(() {
      if (target == null) {
        _clearGizmoSelection();
      } else {
        _gizmoSelected = target;
      }
    });
  }

  void _beginGizmoGroundDrag() {
    final target = _gizmoDownTarget;
    if (target == null) return;
    _gizmoSelected = target;
    _handleDragging = true;
    if (target is FriendGizmoTarget) {
      _gizmoFriendStartPos = Vector3.copy(target.instance.position);
    } else if (target is VolumeGizmoTarget) {
      target.resetDrag();
      _gizmoVolumeBefore = _capture('move volume');
    }
  }

  void _updateGizmoGroundDrag(Offset local) {
    final target = _gizmoSelected;
    final start = _gizmoGroundStart;
    final ground = _camera.intersectGround(local, _viewportSize);
    if (target == null || start == null || ground == null) return;
    final delta = Vector3(ground.x - start.x, 0, ground.z - start.z);
    if (target is FriendGizmoTarget) {
      final origin = _gizmoFriendStartPos;
      if (origin == null) return;
      target.setPosition(origin + delta);
    } else if (target is VolumeGizmoTarget) {
      final (dtx, dty) = target.applyTotalDelta(delta);
      if (dtx != 0 || dty != 0) {
        _facePaint.remapVolumeTiles(target.volume.id, dtx, dty);
        _syncWorld();
      }
    }
    _syncGizmoMeshes();
    setState(() {});
  }

  void _endGizmoDrag() {
    final selected = _gizmoSelected;
    final before = _gizmoVolumeBefore;
    if (selected is VolumeGizmoTarget) {
      if (before != null &&
          (selected.committedDtx != 0 || selected.committedDty != 0)) {
        _history.pushSnapshot(before);
      }
      selected.resetDrag();
      _syncWorld();
    }
    _handleDragging = false;
    _gizmoAxis = null;
    _gizmoDownTarget = null;
    _gizmoGroundStart = null;
    _gizmoFriendStartPos = null;
    _gizmoVolumeBefore = null;
    _dragStartHit = null;
    _dragPlanePoint = null;
    setState(() {});
  }

  void _onGizmoHandleStart(SceneGizmoAxis axis, Offset global) {
    if (_toolsBlocked || !_showGizmos) return;
    final target = _gizmoSelected;
    if (target == null) return;
    final local = _toLocal(global);
    final center = target.worldCenter;
    final planePoint = center + axis.direction * kSceneGizmoStemOut;
    final ray = _camera.unprojectRay(local, _viewportSize);
    if (ray == null) return;
    var planeN = axis.direction.cross(_camera.forward.cross(axis.direction));
    if (planeN.length2 < 1e-8) {
      planeN = Vector3.copy(_camera.up);
    }
    planeN.normalize();
    final startHit = Camera.intersectPlane(
      ray: ray,
      point: planePoint,
      normal: planeN,
    );
    if (startHit == null) return;
    _handleDragging = true;
    _gizmoAxis = axis;
    _dragPlanePoint = planePoint;
    _dragStartHit = startHit;
    if (target is FriendGizmoTarget) {
      _gizmoFriendStartPos = Vector3.copy(target.instance.position);
    } else if (target is VolumeGizmoTarget) {
      target.resetDrag();
      _gizmoVolumeBefore = _capture('move volume');
    }
  }

  void _onGizmoHandleUpdate(SceneGizmoAxis axis, Offset global) {
    final target = _gizmoSelected;
    final startHit = _dragStartHit;
    final planePoint = _dragPlanePoint;
    if (target == null || startHit == null || planePoint == null) return;
    if (_gizmoAxis != null && axis != _gizmoAxis) return;
    final delta = sceneAxisDragDelta(
      camera: _camera,
      viewport: _viewportSize,
      screen: _toLocal(global),
      axis: axis.direction,
      planePoint: planePoint,
      startHit: startHit,
    );
    if (delta == null) return;
    final worldDelta = axis.direction * delta;
    if (target is FriendGizmoTarget) {
      final origin = _gizmoFriendStartPos;
      if (origin == null) return;
      target.setPosition(origin + worldDelta);
    } else if (target is VolumeGizmoTarget) {
      final (dtx, dty) = target.applyTotalDelta(worldDelta);
      if (dtx != 0 || dty != 0) {
        _facePaint.remapVolumeTiles(target.volume.id, dtx, dty);
        _syncWorld();
      }
    }
    _syncGizmoMeshes();
    setState(() {});
  }

  void _onTileTap(Offset local) {
    if (_toolsBlocked || _editing || _handleDragging) return;
    if (_showGizmos) {
      _onGizmoTap(local);
      return;
    }
    if (_selectTool && _viewer == GameViewerKind.map3d) {
      _onSelectClick(local);
      return;
    }
    if (_isPlane2d) return;
    if (_wallsTool) {
      final hit = _camera.intersectGround(local, _viewportSize);
      if (hit == null) return;
      _ensureWallSession();
      if (_walls.toggleAtMidpoint(hit)) {
        _recordWallSessionMutation();
        _syncWorld();
        setState(() {});
      }
      return;
    }
    final tile = _tileAt(local);
    if (tile == null) return;
    final (tx, ty) = tile;
    if (_volumesTool) {
      if (_paths.contains(tx, ty)) return;
      _commitAction('place volume', () => _volumes.startNew(tx, ty));
      return;
    }
    if (_pathsTool) {
      _commitAction(
        'place path',
        () => _paths.addIsland(tx, ty, blocked: _pathBlocked),
      );
      return;
    }
    if (_worldEraserTool) {
      final hit = _camera.intersectGround(local, _viewportSize);
      if (hit == null) return;
      _commitAction(
        'erase',
        () => eraseWorld(
          world: hit,
          radius: _eraserFilter.worldRadius(_tileWorld),
          filter: _eraserFilter,
          walls: _walls,
          paths: _paths,
          volumes: _volumes,
        ),
      );
    }
  }

  void _paintPathTo(Offset local) {
    if (_toolsBlocked) return;
    final tile = _tileAt(local);
    if (tile == null) return;
    if (_pathBlocked(tile.$1, tile.$2)) return;
    _ensureStrokeHistory('paint path');
    final last = _pathStrokeLast ?? tile;
    if (_paths.paintStroke(last, tile, blocked: _pathBlocked)) {
      _recordStrokeIfNeeded();
      _syncWorld();
      setState(() {});
    }
    _pathStrokeLast = tile;
  }

  void _paintWallTo(Offset local) {
    if (_toolsBlocked) return;
    final hit = _camera.intersectGround(local, _viewportSize);
    if (hit == null) return;
    final last = _wallStrokeLast ?? hit;
    _ensureWallSession();
    if (_walls.paintStroke(last, hit)) {
      _recordWallSessionMutation();
      _syncWorld();
      setState(() {});
    }
    _wallStrokeLast = hit;
  }

  void _eraseWorldTo(Offset local) {
    if (_toolsBlocked) return;
    final hit = _camera.intersectGround(local, _viewportSize);
    if (hit == null) return;
    _eraserCursor = hit;
    _ensureStrokeHistory('erase');
    if (eraseWorld(
      world: hit,
      radius: _eraserFilter.worldRadius(_tileWorld),
      filter: _eraserFilter,
      walls: _walls,
      paths: _paths,
      volumes: _volumes,
    )) {
      _recordStrokeIfNeeded();
      _syncWorld();
    }
    setState(() {});
  }

  void _onGrow(VolumeGrowCandidate candidate) {
    if (_toolsBlocked) return;
    if (_paths.contains(candidate.tx, candidate.ty)) return;
    _commitAction('grow volume', () => _volumes.startGrow(candidate));
  }

  void _onCancel() {
    _commitAction('cancel volume', () {
      if (!_volumes.isEditing) return false;
      _volumes.cancelDraft();
      return true;
    });
  }

  void _onConfirm() {
    if (_volumes.phase == VolumeEditPhase.editing) {
      _commitAction('confirm volume', () => _volumes.confirmEdit());
    } else if (_volumes.phase == VolumeEditPhase.pickingAccess) {
      _commitAction('confirm access', () => _volumes.confirmAccess());
    }
  }

  void _onToggleAccess(VolumeSide side) {
    if (_toolsBlocked) return;
    _commitAction('toggle access', () {
      if (_volumes.phase != VolumeEditPhase.pickingAccess) return false;
      _volumes.toggleAccess(side);
      return true;
    });
  }

  void _onHandleDragStart(VolumeHandle handle, Offset global) {
    if (_toolsBlocked) return;
    final cell = _volumes.draftCell;
    if (cell == null) return;
    final local = _toLocal(global);
    final face = cell.box.faceCenter(_volumes.grid, cell.tx, cell.ty, handle);
    final planePoint = face + handle.axis * kVolumeHandleStemOut;
    final ray = _camera.unprojectRay(local, _viewportSize);
    if (ray == null) return;
    var planeN = handle.axis.cross(_camera.forward.cross(handle.axis));
    if (planeN.length2 < 1e-8) {
      planeN = Vector3.copy(_camera.up);
    }
    planeN.normalize();
    final startHit = Camera.intersectPlane(
      ray: ray,
      point: planePoint,
      normal: planeN,
    );
    if (startHit == null) return;
    _handleDragging = true;
    _dragHandle = handle;
    _dragBoxSnapshot = cell.box.clone();
    _dragBefore = _capture('resize volume');
    _dragPlanePoint = planePoint;
    _dragStartHit = startHit;
  }

  void _onHandleDragUpdate(VolumeHandle handle, Offset global) {
    final cell = _volumes.draftCell;
    final snapshot = _dragBoxSnapshot;
    final startHit = _dragStartHit;
    final planePoint = _dragPlanePoint;
    if (_toolsBlocked) return;
    if (cell == null ||
        snapshot == null ||
        startHit == null ||
        planePoint == null) {
      return;
    }
    if (_dragHandle != null && handle != _dragHandle) return;
    final delta = axisDragDelta(
      camera: _camera,
      viewport: _viewportSize,
      screen: _toLocal(global),
      axis: handle.axis,
      planePoint: planePoint,
      startHit: startHit,
    );
    if (delta == null) return;
    cell.box.setFrom(snapshot);
    cell.box.applyHandleDelta(
      grid: _volumes.grid,
      tx: cell.tx,
      ty: cell.ty,
      handle: handle,
      delta: delta,
    );
    _syncWorld();
    setState(() {});
  }

  void _onHandleDragEnd() {
    final cell = _volumes.draftCell;
    final startBox = _dragBoxSnapshot;
    final before = _dragBefore;
    if (cell != null &&
        startBox != null &&
        before != null &&
        !cell.box.sameAs(startBox)) {
      _history.pushSnapshot(before);
    }
    _handleDragging = false;
    _dragHandle = null;
    _dragBoxSnapshot = null;
    _dragStartHit = null;
    _dragPlanePoint = null;
    _dragBefore = null;
  }

  void _onCropDragStart(CropHandle handle, Offset global) {
    if (_toolsBlocked) return;
    final crop = _focusCrop;
    if (crop == null) return;
    final local = _toLocal(global);
    final face = crop.faceCenter(_volumes.grid, handle);
    final planePoint = face + handle.axis * kVolumeHandleStemOut;
    final ray = _camera.unprojectRay(local, _viewportSize);
    if (ray == null) return;
    var planeN = handle.axis.cross(_camera.forward.cross(handle.axis));
    if (planeN.length2 < 1e-8) {
      planeN = Vector3.copy(_camera.up);
    }
    planeN.normalize();
    final startHit = Camera.intersectPlane(
      ray: ray,
      point: planePoint,
      normal: planeN,
    );
    if (startHit == null) return;
    _handleDragging = true;
    _cropDragHandle = handle;
    _cropDragSnapshot = crop;
    _dragPlanePoint = planePoint;
    _dragStartHit = startHit;
  }

  void _onCropDragUpdate(CropHandle handle, Offset global) {
    final snapshot = _cropDragSnapshot;
    final bounds = _focusCropBounds;
    final startHit = _dragStartHit;
    final planePoint = _dragPlanePoint;
    if (_toolsBlocked || snapshot == null || bounds == null) return;
    if (startHit == null || planePoint == null) return;
    if (_cropDragHandle != null && handle != _cropDragHandle) return;
    final delta = axisDragDelta(
      camera: _camera,
      viewport: _viewportSize,
      screen: _toLocal(global),
      axis: handle.axis,
      planePoint: planePoint,
      startHit: startHit,
    );
    if (delta == null) return;
    final next = snapshot.applyHandleDelta(
      handle: handle,
      delta: delta,
      grid: _volumes.grid,
      bounds: bounds,
    );
    _applyFocusCrop(next);
    setState(() {});
  }

  void _onCropDragEnd() {
    _handleDragging = false;
    _cropDragHandle = null;
    _cropDragSnapshot = null;
    _dragStartHit = null;
    _dragPlanePoint = null;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse) {
      _mouseButtons = event.buttons;
    }
    _pointerCount++;
    if (_pointerCount >= 2 ||
        _toolsSuppressedUntilPointersUp ||
        _panZoomActive ||
        _pinchEpisode) {
      _enterPinchExclusiveMode();
      return;
    }
    _queueToolPointerDown(event.localPosition);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.kind == PointerDeviceKind.mouse) {
      _mouseButtons = event.buttons;
    }
    if (_toolsBlocked) {
      _cancelPendingToolDown();
      return;
    }
    if (_pendingToolDown != null) {
      if ((event.localPosition - _pendingToolDown!).distance <
          kDragSlopThreshold) {
        return;
      }
      _flushPendingToolDown();
    }
    _onToolPointerMove(event);
  }

  void _onPointerUp(PointerEvent event) {
    if (event.kind == PointerDeviceKind.mouse) {
      _mouseButtons = 0;
    }
    _pointerCount = math.max(0, _pointerCount - 1);
    final suppress = _toolsBlocked || _pinchEpisode;
    if (!suppress && _pendingToolDown != null) {
      _flushPendingToolDown();
    } else {
      _cancelPendingToolDown();
    }
    _maybeUnlockToolsAfterPointersUp();
    if (suppress) {
      _pathStrokeLast = null;
      _wallStrokeLast = null;
      _endStrokeHistory();
      return;
    }
    _onToolPointerUp(event.localPosition);
  }

  void _onPointerCancel(PointerEvent event) {
    _pointerCount = 0;
    _mouseButtons = 0;
    _cancelPendingToolDown();
    _enterPinchExclusiveMode();
    if (!_panZoomActive) _maybeUnlockToolsAfterPointersUp();
  }

  void _onPointerHover(PointerHoverEvent event) {
    if (!_worldEraserTool || _isPlane2d || _toolsBlocked) return;
    _eraserCursor = _camera.intersectGround(event.localPosition, _viewportSize);
    setState(() {});
  }

  void _onToolPointerMove(PointerMoveEvent event) {
    if (_handleDragging) return;
    _toolDidMove = true;
    if (_showGizmos && _gizmoDownTarget != null) {
      _beginGizmoGroundDrag();
      _updateGizmoGroundDrag(event.localPosition);
      return;
    }
    if (_isPlane2d &&
        (_paintTool || _eraseTool) &&
        (event.kind != PointerDeviceKind.mouse ||
            (_mouseButtons & kPrimaryButton) != 0)) {
      _strokePaint(event.localPosition);
      return;
    }
    final pathPainting =
        !_isPlane2d &&
        _pathsTool &&
        (event.kind != PointerDeviceKind.mouse ||
            (_mouseButtons & kPrimaryButton) != 0);
    if (pathPainting) {
      _paintPathTo(event.localPosition);
      return;
    }
    final wallPainting =
        !_isPlane2d &&
        _wallsTool &&
        (event.kind != PointerDeviceKind.mouse ||
            (_mouseButtons & kPrimaryButton) != 0);
    if (wallPainting) {
      _paintWallTo(event.localPosition);
      return;
    }
    final worldErasing =
        !_isPlane2d &&
        _worldEraserTool &&
        (event.kind != PointerDeviceKind.mouse ||
            (_mouseButtons & kPrimaryButton) != 0);
    if (worldErasing) {
      _eraseWorldTo(event.localPosition);
      return;
    }
    if (!_isPlane2d && _worldEraserTool) {
      _eraserCursor = _camera.intersectGround(
        event.localPosition,
        _viewportSize,
      );
      setState(() {});
    }
    final mouse = event.kind == PointerDeviceKind.mouse;
    final secondary = (_mouseButtons & kSecondaryButton) != 0;
    final primary = (_mouseButtons & kPrimaryButton) != 0;
    if (!mouse || secondary || primary) {
      if (_isFocus3d && !_viewerAnim.isAnimating) {
        _orbit?.orbit(event.delta);
      } else if (_isPlane2d && !_viewerAnim.isAnimating) {
        _planeLook?.pan(event.delta);
        _maybeTurnPlane2dFace();
      } else if (_viewer == GameViewerKind.map3d) {
        _look.pan(event.delta);
      }
    }
  }

  void _onToolPointerUp(Offset local) {
    if (_handleDragging && (_gizmoSelected != null || _gizmoAxis != null)) {
      _endGizmoDrag();
      _toolDidMove = false;
      _pathStrokeLast = null;
      _wallStrokeLast = null;
      return;
    }
    final moved = _toolDidMove;
    _pathStrokeLast = null;
    _wallStrokeLast = null;
    _toolDidMove = false;
    if (_isPlane2d && (_paintTool || _eraseTool)) {
      if (!moved) _strokePaint(local);
      _paintLastCell = null;
      _endStrokeHistory();
      return;
    }
    if (_isPlane2d && _fillTool) {
      if (!moved) _fillAt(local);
      _paintLastCell = null;
      _endStrokeHistory();
      return;
    }
    _paintLastCell = null;
    if (!moved) _onTileTap(local);
    _endStrokeHistory();
  }

  void _onLookGesture(GestureState state) {
    final isTwoFinger =
        state.pointerCount >= 2 ||
        (state.type == GestureType.twoFingerDrag && state.pointers.isEmpty);

    final orbit = _orbit;
    if (_isFocus3d && orbit != null && !_viewerAnim.isAnimating) {
      if (isTwoFinger) {
        if (state.pointers.isEmpty) _panZoomActive = true;
        if (!_isMultiTouch) {
          _isMultiTouch = true;
          _enterPinchExclusiveMode();
          _pinchSpanScale = state.spanScale <= 1e-6 ? 1.0 : state.spanScale;
        }
        orbit.pan(state.focalDelta);
        final span = state.spanScale <= 1e-6 ? 1.0 : state.spanScale;
        final scaleChange = span / _pinchSpanScale;
        _pinchSpanScale = span;
        if (scaleChange < 1 && orbit.radius / scaleChange > orbit.maxDistance) {
          _returnToMap3d();
          return;
        }
        orbit.zoomByScale(scaleChange);
        return;
      }
      if (_isMultiTouch) {
        _isMultiTouch = false;
        _panZoomActive = false;
        _pinchSpanScale = 1;
        _maybeUnlockToolsAfterPointersUp();
      }
      return;
    }

    final planeLook = _planeLook;
    if (_isPlane2d && planeLook != null && !_viewerAnim.isAnimating) {
      if (isTwoFinger) {
        if (state.pointers.isEmpty) _panZoomActive = true;
        if (!_isMultiTouch) {
          _isMultiTouch = true;
          _enterPinchExclusiveMode();
          planeLook.beginZoom();
          _pinchSpanScale = state.spanScale <= 1e-6 ? 1.0 : state.spanScale;
        }
        planeLook.pan(state.focalDelta);
        final span = state.spanScale <= 1e-6 ? 1.0 : state.spanScale;
        final scaleChange = span / _pinchSpanScale;
        _pinchSpanScale = span;
        if (planeLook.zoomByScale(scaleChange)) {
          _returnToMap3d();
        } else {
          _maybeTurnPlane2dFace();
        }
        return;
      }
      if (_isMultiTouch) {
        _isMultiTouch = false;
        _panZoomActive = false;
        _pinchSpanScale = 1;
        planeLook.endZoom();
        _maybeUnlockToolsAfterPointersUp();
      }
      return;
    }

    if (isTwoFinger) {
      if (state.pointers.isEmpty) _panZoomActive = true;
      if (!_isMultiTouch) {
        _isMultiTouch = true;
        _enterPinchExclusiveMode();
        _look.beginZoom();
        _pinchSpanScale = state.spanScale <= 1e-6 ? 1.0 : state.spanScale;
      }
      _look.pan(state.focalDelta);
      final span = state.spanScale <= 1e-6 ? 1.0 : state.spanScale;
      final scaleChange = span / _pinchSpanScale;
      _pinchSpanScale = span;
      _look.zoomByScale(scaleChange);
      return;
    }

    if (_isMultiTouch) {
      _isMultiTouch = false;
      _panZoomActive = false;
      _pinchSpanScale = 1;
      _look.endZoom();
      _maybeUnlockToolsAfterPointersUp();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FmScreen(
      backgroundColor: _lighting.background,
      overlays: [
        const FmDevBackButton(),
        FmSafePositioned(
          top: 8,
          left: 0,
          right: 0,
          child: Center(
            child: DayCycleHud(
              dayNumber: _dayNumber,
              isNight: _isNight,
              busy: _dayNightBusy || _advancingDay,
              onEndPhase: _endDayOrNight,
            ),
          ),
        ),
        _StatusChip(
          status: _error ?? _status,
          busy: _baking,
          isError: _error != null,
        ),
        FrameStatsHud(expanded: _perf.showDetails),
        if (_perf.showOverlay)
          Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            height: 90,
            child: IgnorePointer(child: PerformanceOverlay.allEnabled()),
          ),
        FmSafePositioned(
          top: 48,
          left: 12,
          child: ListenableBuilder(
            listenable: _history,
            builder: (context, _) {
              return GameLayerSidebar(
                graphActive: _graphVisible,
                onToggleGraph: _toggleGraph,
                onPopulateRecording: _populateRecording,
                onSaveRecording: _saveRecording,
                canSaveRecording: _history.canUndo,
              );
            },
          ),
        ),
        if (_isPlane2d) ...[
          FmSafePositioned(
            top: 48,
            right: 12,
            child: GameViewerBackButton(onPressed: _returnToMap3d),
          ),
          FmSafePositioned(
            top: 96,
            right: 12,
            child: GamePlane2dSidebar(
              paintActive: _paintTool,
              onTogglePaint: _togglePaint,
              fillActive: _fillTool,
              onToggleFill: _toggleFill,
              eraseActive: _eraseTool,
              onToggleErase: _toggleErase,
              paintColor: _paintColor,
              onPaintColor: (c) => setState(() => _paintColor = c),
              resolvePaper: _theme.paper,
              telephoto: _planeLook?.telephoto ?? false,
              onToggleTelephoto: () {
                final look = _planeLook;
                if (look == null || _viewerAnim.isAnimating) return;
                look.setTelephoto(!look.telephoto);
                setState(() {});
              },
            ),
          ),
        ] else if (_isFocus3d) ...[
          FmSafePositioned(
            top: 48,
            right: 12,
            child: GameViewerBackButton(onPressed: _returnToMap3d),
          ),
          FmSafePositioned(
            top: 96,
            right: 12,
            child: GameFocus3dSidebar(
              cropActive: _cropTool,
              onToggleCrop: _toggleCropTool,
              showReset:
                  _focusCrop != null &&
                  _focusCropBounds != null &&
                  !_focusCrop!.sameAs(_focusCropBounds!),
              onReset: _resetFocusCrop,
            ),
          ),
        ] else ...[
          FmSafePositioned(
            top: 48,
            right: 12,
            child: GameToolSidebar(
              volumesActive: _volumesTool,
              onToggleVolumes: _toggleVolumes,
              pathsActive: _pathsTool,
              onTogglePaths: _togglePaths,
              wallsActive: _wallsTool,
              onToggleWalls: _toggleWalls,
              eraserActive: _worldEraserTool,
              onToggleEraser: _toggleWorldEraser,
              selectActive: _selectTool,
              onToggleSelect: _toggleSelect,
              onIsolate: _isolateLookAt,
              showShapeButton: _volumesTool || _editing,
              onVolumeShape: () {},
            ),
          ),
          if (_worldEraserTool)
            FmSafePositioned(
              top: 48,
              right: 64,
              child: EraserFilterPanel(
                filter: _eraserFilter,
                onChanged: () => setState(() {}),
              ),
            ),
          FmSafePositioned(
            bottom: 12,
            left: 12,
            child: GameViewRotateButton(
              clockwise: false,
              onPressed: _look.rotateCounterClockwise,
            ),
          ),
          FmSafePositioned(
            bottom: 12,
            right: 12,
            child: GameViewRotateButton(
              clockwise: true,
              onPressed: _look.rotateClockwise,
            ),
          ),
        ],
        if (_devToolsOpen)
          FmSafePositioned(
            bottom: 84,
            right: 12,
            child: DevToolsPanel(
              showGizmos: _gizmoMode,
              onShowGizmosChanged: _setGizmoMode,
              onPlaceCubeboy: _placeCubeboy,
              nightSwatchId: _nightSwatch.id,
              onNightSwatchChanged: _setNightSwatch,
              dayNightProgress: _dayNightProgress,
              onDayNightProgressChanged: _setDayNightProgress,
              perf: _perf,
              onPerfChanged: _onPerfChanged,
            ),
          ),
        FmSafePositioned(
          bottom: 56,
          right: 12,
          child: DevToolsButton(
            active: _devToolsOpen,
            onPressed: () => setState(() => _devToolsOpen = !_devToolsOpen),
          ),
        ),
        FmSafePositioned(
          bottom: 12,
          left: 0,
          right: 0,
          child: Center(
            child: ListenableBuilder(
              listenable: _history,
              builder: (context, _) {
                return GameViewUndoRedoBar(
                  canUndo: _history.canUndo,
                  canRedo: _history.canRedo,
                  onUndo: _undo,
                  onRedo: _redo,
                );
              },
            ),
          ),
        ),
        if (_advancingDay)
          Positioned.fill(
            child: DayAdvanceOverlay(
              nextDay: _advanceToDay,
              onReadyForDay: _onAdvanceReadyForDay,
              onFinished: _onAdvanceFinished,
            ),
          ),
      ],
      background: _buildViewport(),
    );
  }

  Widget _buildViewport() {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        _look.setViewportSize(_viewportSize);
        _planeLook?.setViewportSize(_viewportSize);
        _orbit?.setViewportSize(_viewportSize);
        return GestureClassifier(
          onGestureUpdate: _onLookGesture,
          child: Listener(
            key: _viewportKey,
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerHover: _onPointerHover,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerCancel,
            onPointerPanZoomStart: (_) {
              _panZoomActive = true;
              _enterPinchExclusiveMode();
            },
            onPointerPanZoomEnd: (_) {
              _panZoomActive = false;
              _maybeUnlockToolsAfterPointersUp();
            },
            onPointerSignal: (signal) {
              if (signal is PointerScrollEvent) {
                if (_isPlane2d &&
                    !_viewerAnim.isAnimating &&
                    _planeLook != null) {
                  if (_planeLook!.zoomByScroll(signal.scrollDelta.dy)) {
                    _returnToMap3d();
                  }
                } else if (_isFocus3d &&
                    !_viewerAnim.isAnimating &&
                    _orbit != null) {
                  final orbit = _orbit!;
                  final factor = math.exp(
                    signal.scrollDelta.dy * orbit.zoomSensitivity,
                  );
                  if (factor > 1 && orbit.radius * factor > orbit.maxDistance) {
                    _returnToMap3d();
                  } else {
                    orbit.zoomByScroll(signal.scrollDelta.dy);
                  }
                } else if (_viewer == GameViewerKind.map3d) {
                  _look.zoomByScroll(signal.scrollDelta.dy);
                }
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_layers.shows(SceneLayer.landscape))
                  CustomPaint(
                    painter: LandscapePlanePainter(
                      camera: _camera,
                      listenable: _scene,
                      image: _atlas,
                      worldSize: _worldSize,
                      tilesSide: _tilesSide,
                      pixelsPerTile: _volumes.grid.subtilesPerTile,
                      backgroundColor: _lighting.background,
                      modulateColor: _dayNightProgress <= 0
                          ? null
                          : Color.lerp(
                              Colors.white,
                              _lighting.background,
                              _dayNightProgress * 0.42,
                            ),
                      visibleTiles: _focusVisibleTiles(),
                      clipMinX: _focusCrop?.worldMin(_volumes.grid).x,
                      clipMaxX: _focusCrop?.worldMax(_volumes.grid).x,
                      clipMinZ: _focusCrop?.worldMin(_volumes.grid).z,
                      clipMaxZ: _focusCrop?.worldMax(_volumes.grid).z,
                      hideGround:
                          _focusCrop != null && !_focusCrop!.includesGround,
                    ),
                    isComplex: true,
                    willChange: true,
                    child: const SizedBox.expand(),
                  ),
                if (_layers.shows(SceneLayer.landscape) &&
                    !(_focusCrop != null && !_focusCrop!.includesGround))
                  Positioned.fill(
                    child: VolumeGroundShadowOverlay(
                      volumes: _volumes,
                      camera: _camera,
                      viewport: _viewportSize,
                      model: _groundShadow,
                      listenable: _scene,
                      tileVisible: _focusTileVisible,
                    ),
                  ),
                SizedBox.expand(
                  child: SceneView(
                    scene: _scene,
                    debugOptions: const SceneDebugOptions(
                      showWorldXyPlane: false,
                    ),
                  ),
                ),
                if (_layers.shows(SceneLayer.friends))
                  Positioned.fill(
                    child: FriendEyeOverlay(
                      friends: _friends,
                      camera: _camera,
                      viewport: _viewportSize,
                      tileSize: _tileWorld,
                      subtilesPerTile: _volumes.grid.subtilesPerTile,
                      listenable: _scene,
                    ),
                  ),
                if (_layers.shows(SceneLayer.volumes))
                  Positioned.fill(
                    child: VolumeFacePaintOverlay(
                      store: _facePaint,
                      volumes: _volumes,
                      camera: _camera,
                      viewport: _viewportSize,
                      listenable: _scene,
                      tileVisible: _focusTileVisible,
                      shade: _lighting.shade,
                      grain: _theme.grain,
                      theme: _theme,
                    ),
                  ),
                if (_layers.shows(SceneLayer.volumes))
                  Positioned.fill(
                    child: VolumeDoorOverlay(
                      volumes: _volumes,
                      camera: _camera,
                      viewport: _viewportSize,
                      listenable: _scene,
                      tileVisible: _focusTileVisible,
                    ),
                  ),
                if (_isPlane2d && _planeLook != null)
                  Positioned.fill(
                    child: PlaneSubtileGridOverlay(
                      plane: _planeLook!.plane,
                      camera: _camera,
                      viewport: _viewportSize,
                      lookAt: _planeLook!.lookAt,
                      listenable: _scene,
                    ),
                  ),
                if (_graphVisible && _layers.shows(SceneLayer.connectionGraph))
                  Positioned.fill(
                    child: ConnectionGraphOverlay(
                      graph: _graph,
                      grid: _volumes.grid,
                      camera: _camera,
                      viewport: _viewportSize,
                      listenable: _scene,
                      tileVisible: _focusTileVisible,
                    ),
                  ),
                if (_layers.shows(SceneLayer.worldBorder))
                  Positioned.fill(
                    child: WorldBorderOverlay(
                      store: _walls,
                      camera: _camera,
                      viewport: _viewportSize,
                      listenable: _scene,
                    ),
                  ),
                if (_layers.shows(SceneLayer.walls))
                  Positioned.fill(
                    child: WallRegionOverlay(
                      regions: _wallRegions,
                      store: _walls,
                      camera: _camera,
                      viewport: _viewportSize,
                      listenable: _scene,
                      tileVisible: _focusTileVisible,
                    ),
                  ),
                if (_lighting.wash.a > 0)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(color: _lighting.wash),
                    ),
                  ),
                if (_worldEraserTool && !_isPlane2d)
                  Positioned.fill(
                    child: EraserBrushOverlay(
                      worldCenter: _eraserCursor,
                      radius: _eraserFilter.worldRadius(_tileWorld),
                      camera: _camera,
                      viewport: _viewportSize,
                      listenable: _scene,
                    ),
                  ),
                if (_showGizmos && _gizmoSelected != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: GizmoBoundsOverlay(
                        target: _gizmoSelected!,
                        camera: _camera,
                        viewport: _viewportSize,
                        listenable: _scene,
                      ),
                    ),
                  ),
                if (_showGizmos && _gizmoSelected != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: _toolsBlocked,
                      child: SceneTransformGizmo(
                        target: _gizmoSelected!,
                        camera: _camera,
                        viewport: _viewportSize,
                        onDragStart: _onGizmoHandleStart,
                        onDragUpdate: _onGizmoHandleUpdate,
                        onDragEnd: _endGizmoDrag,
                      ),
                    ),
                  ),
                if (!_isPlane2d &&
                    !_isFocus3d &&
                    _layers.shows(SceneLayer.volumeTools) &&
                    _volumesTool &&
                    !_editing)
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: _toolsBlocked,
                      child: VolumeGrowOverlay(
                        store: _volumes,
                        camera: _camera,
                        viewport: _viewportSize,
                        onGrow: _onGrow,
                        blocked: _paths.contains,
                      ),
                    ),
                  ),
                if (!_isPlane2d &&
                    !_isFocus3d &&
                    _layers.shows(SceneLayer.volumeTools) &&
                    _volumes.phase == VolumeEditPhase.editing)
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: _toolsBlocked,
                      child: VolumeTransformGizmo(
                        store: _volumes,
                        camera: _camera,
                        viewport: _viewportSize,
                        onDragStart: _onHandleDragStart,
                        onDragUpdate: _onHandleDragUpdate,
                        onDragEnd: _onHandleDragEnd,
                      ),
                    ),
                  ),
                if (!_isPlane2d &&
                    !_isFocus3d &&
                    _layers.shows(SceneLayer.volumeTools) &&
                    _volumes.phase == VolumeEditPhase.pickingAccess)
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: _toolsBlocked,
                      child: VolumeAccessOverlay(
                        store: _volumes,
                        camera: _camera,
                        viewport: _viewportSize,
                        onToggle: _onToggleAccess,
                      ),
                    ),
                  ),
                if (!_isPlane2d &&
                    !_isFocus3d &&
                    _layers.shows(SceneLayer.volumeTools) &&
                    _editing)
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: _toolsBlocked,
                      child: Tool3dWorkAreaLayer(
                        camera: _camera,
                        viewport: _viewportSize,
                        tool: VolumeTool3d(_volumes),
                        listenable: _scene,
                        topRight: VolumeCancelButton(onPressed: _onCancel),
                        bottomRight: VolumeConfirmButton(
                          onPressed: _onConfirm,
                          enabled: _confirmEnabled,
                        ),
                      ),
                    ),
                  ),
                if (_isFocus3d && _cropTool && _focusCrop != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: _toolsBlocked,
                      child: CropBoxGizmo(
                        crop: _focusCrop!,
                        grid: _volumes.grid,
                        camera: _camera,
                        viewport: _viewportSize,
                        onDragStart: _onCropDragStart,
                        onDragUpdate: _onCropDragUpdate,
                        onDragEnd: _onCropDragEnd,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.status,
    required this.busy,
    required this.isError,
  });

  final String? status;
  final bool busy;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return FmSafePositioned(
      top: 44,
      left: 88,
      right: 96,
      child: IgnorePointer(
        child: Text(
          status ?? '',
          style: TextStyle(
            color: isError
                ? Colors.redAccent
                : busy
                ? Colors.amberAccent
                : Colors.white70,
            fontSize: 12,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
