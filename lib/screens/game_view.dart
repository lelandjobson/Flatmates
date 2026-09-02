import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../debug/perf_debug.dart';
import '../debug/scene_paint_stats.dart';
import '../crafting/placed_paper.dart';
import '../gameplay/landscape_cover.dart';
import '../gameplay/flatmates/flatmate_pathfinder.dart';
import '../gameplay/friends/friend_instance.dart';
import '../gameplay/friends/friend_instance_store.dart';
import '../gameplay/friends/friend_mesh_sync.dart';
import '../gameplay/game_history.dart';
import '../gameplay/gizmo/gizmo_resolver.dart';
import '../gameplay/gizmo/gizmo_target.dart';
import '../gameplay/graph/connection_graph.dart';
import '../gameplay/recording/game_recording.dart';
import '../gameplay/recording/game_recording_io.dart';
import '../gameplay/eraser/erase_preview.dart';
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
import '../gameplay/picking/focus_click.dart';
import '../gameplay/picking/focus_sticker.dart';
import '../gameplay/picking/map_selector.dart';
import '../gameplay/picking/selectable.dart';
import '../gameplay/picking/selection_actions.dart';
import '../gameplay/picking/volume_face_picker.dart';
import '../gameplay/viewers/coplanar_faces.dart';
import '../gameplay/viewers/face_turn.dart';
import '../gameplay/viewers/focus_crop.dart';
import '../gameplay/viewers/focus_region.dart';
import '../gameplay/viewers/game_viewer.dart';
import '../gameplay/viewers/world_plane.dart';
import '../gameplay/volumes/volume.dart';
import '../gameplay/volumes/volume_box_mesh.dart';
import '../gameplay/volumes/volume_door.dart';
import '../gameplay/volumes/volume_program.dart';
import '../gameplay/volumes/volume_solid_sync.dart';
import '../gameplay/vision/map_vision.dart';
import '../gameplay/volumes/volume_store.dart';
import '../user/friend_provider.dart';
import '../gestures/gesture_system.dart';
import '../landscape/landscape_ca.dart';
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
import '../rendering/scene/grid_motif.dart';
import '../rendering/scene/camera_controller.dart';
import '../rendering/scene/map_look_camera_controller.dart';
import '../rendering/scene/plane_look_camera_controller.dart';
import '../rendering/scene/scene.dart';
import '../rendering/scene/scene_hit_tester.dart';
import '../rendering/scene_view.dart';
import '../ui/fm_dev_back_button.dart';
import '../ui/fm_haptics.dart';
import '../ui/fm_safe_area.dart';
import '../ui/fm_screen.dart';
import '../ui/game/connection_graph_overlay.dart';
import '../ui/game/crop_box_gizmo.dart';
import '../ui/game/day_advance_overlay.dart';
import '../ui/game/day_cycle_hud.dart';
import '../ui/game/dev_tools_button.dart';
import '../ui/game/dev_tools_panel.dart';
import '../ui/game/frame_stats_hud.dart';
import '../ui/game/flatmate_path_overlay.dart';
import '../ui/game/friend_eye_overlay.dart';
import '../ui/game/eraser_filter_panel.dart';
import '../ui/game/game_focus_tool_column.dart';
import '../ui/game/game_tool_carousel.dart';
import '../ui/game/game_tool_sidebar.dart';
import '../ui/game/placement_ghost_overlay.dart';
import '../ui/game/selection_context_sidebar.dart';
import '../ui/game/selection_highlight_overlay.dart';
import '../ui/game/selection_highlight_style.dart';
import '../ui/game/view_crosshair.dart';
import '../ui/game/view_lock_button.dart';
import '../ui/game/wall_region_overlay.dart';
import '../ui/game/gizmo_bounds_overlay.dart';
import '../ui/game/plane_subtile_grid_overlay.dart';
import '../ui/game/scene_transform_gizmo.dart';
import '../ui/object_radial_menu.dart';
import '../ui/game/volume_door_overlay.dart';
import '../ui/game/volume_ground_shadow_overlay.dart';
import '../ui/game/volume_face_paint_overlay.dart';
import '../ui/game/volume_program_overlay.dart';
import '../ui/game/volume_transform_gizmo.dart';

/// Core 3D game view. Starts from the map bench scene (landscape + look
/// camera) without the bench tools/assets panel.
class GameView extends StatefulWidget {
  const GameView({super.key});

  @override
  State<GameView> createState() => _GameViewState();
}

class _GameViewState extends State<GameView> with TickerProviderStateMixin {
  static const _tilesSide = MapVisionConfig.defaultWorldTilesSide;
  static const _tileWorld = 8.0;
  final _vision = MapVision(config: MapVisionConfig.game);

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
  late final GridMotif _pathGrid;

  bool _baking = false;
  String? _status;
  String? _error;

  GameMapTool _mapTool = GameMapTool.select;
  bool get _isSelectTool => _mapTool == GameMapTool.select;
  bool get _isPlaceTool =>
      _mapTool == GameMapTool.volume ||
      _mapTool == GameMapTool.path ||
      _mapTool == GameMapTool.wall;
  bool get _volumesTool => _mapTool == GameMapTool.volume;
  bool get _pathsTool => _mapTool == GameMapTool.path;
  bool get _wallsTool => _mapTool == GameMapTool.wall;
  bool get _worldEraserTool => _mapTool == GameMapTool.delete;
  bool get _lookSplitsPath =>
      _paths.connectionAcross(_walls.hitEdgeAtMidpoint(_look.lookAt));
  bool _viewLocked = false;
  bool _paintTool = false;
  bool _fillTool = false;
  bool _eraseTool = false;
  bool _paintGroupExpanded = false;
  bool _stickerGroupExpanded = true;
  FocusStickerKind? _stickerPalette;
  _FocusStickerSel? _selectedSticker;
  _LooseSticker? _looseSticker;
  _FocusStickerSel? _stickerDragHit;
  bool _tileWorkFocus = false;
  Set<(int, int)>? _focusWorkTiles;
  PaperColor _paintColor = PaperColor.pink;
  final _facePaint = FacePaintStore();
  final _programs = VolumeProgramStore();
  FacePaintKey? _focusedFace;
  bool _interiorFocus = false;
  bool _doorFaceFocus = false;
  int? _programVolumeId;
  int? _volumeInteriorId;
  bool _showVolumeExterior = false;
  SelectableHit? _hoverHit;
  SelectableHit? _selectedHit;
  bool _graphVisible = true;
  ConnectionGraph _graph = ConnectionGraph.empty;

  GameViewerKind _viewer = GameViewerKind.map3d;
  final _perf = PerfDebugSettings();
  SceneLayerMask get _layers =>
      SceneLayerMask.forViewer(_viewer).hiding(_perf.hiddenLayers);
  bool get _isPlane2d => _viewer == GameViewerKind.plane2d;
  bool get _isFocus3d => _viewer == GameViewerKind.focus3d;
  bool get _isVolumeInterior => _viewer == GameViewerKind.volumeInterior;
  bool get _isOrbitViewer => _isFocus3d || _isVolumeInterior;
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
  (int, int)? _volumeStrokeLast;
  Vector3? _wallStrokeLast;
  List<WallRegion> _wallRegions = const [];
  GameSnapshot? _wallSessionBefore;
  bool _wallSessionPushed = false;
  final _eraserFilter = EraserFilter();
  ErasePreview _erasePreview = const ErasePreview();

  bool _isMultiTouch = false;
  bool _twoFingerOrbit = false;
  bool _twoFingerPinch = false;
  bool _panZoomActive = false;
  bool _pinchEpisode = false;
  bool _toolsSuppressedUntilPointersUp = false;
  int _pointerCount = 0;
  double _pinchSpanScale = 1;

  bool _devToolsOpen = false;
  bool _gizmoMode = false;
  bool _springyLookPeek = true;
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

  late final Ticker _flatmateTicker;
  Duration? _lastFlatmateTick;
  Flatmate? _flatmateDown;
  bool _flatmateDragging = false;
  List<(int, int)>? _flatmatePreview;
  final _flatmatePathfinder = FlatmatePathfinder();

  VolumeHandle? _dragHandle;
  VolumeCell? _dragCell;
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

  (List<(int, int)>, Color)? get _flatmateRouteOverlay {
    final preview = _flatmatePreview;
    if (preview != null && preview.length >= 2) {
      final color = (_flatmateDown?.friend.color ?? Colors.white)
          .withValues(alpha: 0.9);
      return (preview, color);
    }
    for (final flatmate in _friends.instances) {
      if (flatmate.movement.tiles.length >= 2) {
        return (
          flatmate.movement.tiles,
          flatmate.friend.color.withValues(alpha: 0.7),
        );
      }
    }
    return null;
  }

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
    final strokePos = _isMapUnlocked ? _viewportCenter : pos;
    _pathStrokeLast = _pathsTool ? _tileAt(strokePos) : null;
    _volumeStrokeLast = _volumesTool ? _tileAt(strokePos) : null;
    _wallStrokeLast = _wallsTool
        ? _camera.intersectGround(strokePos, _viewportSize)
        : null;
    if (_isPlane2d && !_focusPaintTools) {
      _stickerDragHit = _hitFocusSticker(strokePos);
      if (_stickerDragHit != null) _selectedSticker = _stickerDragHit;
    } else {
      _stickerDragHit = null;
    }
    if (_viewer == GameViewerKind.map3d && !_editing) {
      _flatmateDown = _hitFlatmate(pos);
    }
    if (_showGizmos && _flatmateDown == null) {
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
    programs: _programs,
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

  void _hapticPlace(int size) => unawaited(fmHapticPlace(size));

  void _hapticDelete(int size) => unawaited(fmHapticDelete(size));

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
      programs: _programs,
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
      _finishOpenVolume();
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
    _volumeStrokeLast = null;
    _toolDidMove = false;
    if (_flatmateDragging) {
      _cancelFlatmateDrag();
    }
    if (_handleDragging && (_gizmoSelected != null || _gizmoAxis != null)) {
      _endGizmoDrag();
      return;
    }
    if (_handleDragging) _onHandleDragEnd();
    if (_cropDragHandle != null) _onCropDragEnd();
    _endStrokeHistory();
    if (mounted) setState(() {});
  }

  bool get _volumeFocused => _volumes.draftVolume != null;

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
      minDistance: 42,
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

    _pathGrid = GridMotif.subtileLines(worldSize: _volumes.grid.subtileSize);
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
    _flatmateTicker = createTicker(_onFlatmateTick);
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
    _runMorningLandscapeCa();
    if (mounted) setState(() {});
  }

  void _runMorningLandscapeCa() {
    final grid = _grid;
    final gen = _landscapeGen;
    if (grid == null || gen == null) return;
    final before = _capture('day $_dayNumber landscape CA');
    final filled = MorningLandscapeCA.run(
      grid: grid,
      generator: gen,
      regions: _wallRegions,
      subtilesPerTile: _volumes.grid.subtilesPerTile,
    );
    if (filled == 0) return;
    _history.pushSnapshot(before);
    unawaited(_rebakeLandscape());
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

  void _setCloseZoom(double value) {
    _look.setMinDistance(value);
    if (mounted) setState(() {});
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
    _flatmateTicker.dispose();
    _scene.removeListener(_onSceneChanged);
    _atlas?.dispose();
    _pathGrid.dispose();
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
      _refreshHover();
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
    final lockLabel = _viewLocked ? 'locked' : 'unlocked';
    final hover = _hoverHit?.debugLabel ?? 'none';
    _status =
        '${_viewer.name} · $lockLabel · Tile ($tx, $ty) · '
        'dist ${_look.distance.toStringAsFixed(1)} · ${_look.zoomLabel} · '
        'hover $hover · faceZoom < ${kSelectVolumeFacesBelowDistance.toStringAsFixed(0)} · '
        'cull ±$_cullRadius · '
        'drawn ${_streamer.drawnCount}/${_streamer.placedCount}';
  }

  void _syncWorld() {
    final interiorSpec = _isVolumeInterior
        ? volumeInteriorViewSpec(showExterior: _showVolumeExterior)
        : null;
    syncVolumeSurfaces(
      volumes: _volumes,
      paint: _facePaint,
      programs: _programs,
    );
    syncVolumeMeshes(
      _scene,
      _volumes,
      committed: _theme.volume,
      draftColor: _theme.volumeDraft,
      hideCeilingVolumeIds: {
        if (_interiorFocus && _programVolumeId != null) _programVolumeId!,
        if (interiorSpec != null &&
            interiorSpec.hideRoof &&
            _volumeInteriorId != null)
          _volumeInteriorId!,
      },
      inwardWallsOnlyVolumeIds: {
        if (interiorSpec != null &&
            interiorSpec.hideOutwardFaces &&
            _volumeInteriorId != null)
          _volumeInteriorId!,
      },
    );
    syncInteriorGround(
      _scene,
      enabled: _isVolumeInterior,
      grid: _volumes.grid,
    );
    syncPathMeshes(_scene, _paths, _volumes, color: _theme.path);
    syncWallMeshes(_scene, _walls, color: _theme.wall);
    syncFriendMeshes(_scene, _friends, tileSize: _tileWorld);
    _wallRegions = computeEnclosedRegions(_walls);
    _graph = ConnectionGraph.build(volumes: _volumes, paths: _paths);
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
    _rebuildVision();
    final showVol = _layers.shows(SceneLayer.volumes);
    final showPath = _layers.shows(SceneLayer.paths);
    final showWall = _layers.shows(SceneLayer.walls);
    for (final mesh in _scene.meshes) {
      if (mesh.id == kInteriorGroundMeshId) {
        mesh.visible = _isVolumeInterior;
        continue;
      }
      if (_isVolumeInterior) {
        mesh.visible = _meshVisibleInVolumeInterior(mesh.id);
        continue;
      }
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

  void _rebuildVision() {
    _vision.rebuild(
      grid: _volumes.grid,
      sources: [
        for (final flatmate in _friends.instances)
          ..._friendVisionSources(flatmate),
        for (final volume in _volumes.visibleVolumes)
          for (final cell in volume.cells)
            VisionSource(
              tx: cell.tx,
              ty: cell.ty,
              radius: _vision.config.structureViewRadius,
            ),
      ],
    );
  }

  List<VisionSource> _friendVisionSources(FriendInstance flatmate) {
    final tile = _volumes.grid.tileAtWorld(flatmate.position);
    if (tile == null) return const [];
    return [
      VisionSource(
        tx: tile.$1,
        ty: tile.$2,
        radius: flatmate.friend.stats.viewRadius,
      ),
    ];
  }

  bool _focusTileVisible(int tx, int ty) {
    if (!_vision.isVisible(tx, ty)) return false;
    final region = _focusRegion;
    if (region == null) return true;
    if (!region.contains(tx, ty)) return false;
    final crop = _focusCrop;
    if (crop == null) return true;
    return crop.intersectsTile(_volumes.grid, tx, ty);
  }

  Set<(int, int)> _focusVisibleTiles() {
    final region = _focusRegion;
    final tiles = region == null ? _vision.visibleTiles : region.tiles;
    return {
      for (final tile in tiles)
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

  bool _canEditTile(int tx, int ty) => _vision.isVisible(tx, ty);

  bool _canEditWorld(Vector3 hit) {
    final tile = _volumes.grid.tileAtWorld(hit);
    return tile != null && _canEditTile(tile.$1, tile.$2);
  }

  bool _meshVisibleInVolumeInterior(String id) {
    final focusId = _volumeInteriorId;
    if (focusId == null) return false;
    if (id.startsWith('volume_')) {
      final parts = id.split('_');
      if (parts.length < 4) return false;
      return int.tryParse(parts[1]) == focusId;
    }
    if (id.startsWith('wall_')) {
      final edge = wallEdgeFromMeshId(id);
      if (edge == null) return false;
      final volume = _volumes.volumeById(focusId);
      if (volume == null) return false;
      for (final tile in tilesTouchingWall(edge)) {
        if (volume.cellAt(tile.$1, tile.$2) != null) return true;
      }
      return false;
    }
    return false;
  }

  bool _wallMeshVisible(String id) {
    final edge = wallEdgeFromMeshId(id);
    if (edge == null) return _focusRegion == null;
    for (final tile in tilesTouchingWall(edge)) {
      if (_volumes.grid.inBounds(tile.$1, tile.$2) &&
          _focusTileVisible(tile.$1, tile.$2)) {
        return true;
      }
    }
    return false;
  }

  (int, int)? _tileAt(Offset local) {
    final hit = _camera.intersectGround(local, _viewportSize);
    if (hit == null) return null;
    return _volumes.grid.tileAtWorld(hit);
  }

  bool get _isMapUnlocked =>
      _viewer == GameViewerKind.map3d && !_viewLocked;

  Offset get _viewportCenter =>
      Offset(_viewportSize.width * 0.5, _viewportSize.height * 0.5);

  SelectableHit? _pickAt(Offset screen) {
    if (_viewportSize.isEmpty) return null;
    return const MapSelector().pick(
      screen: screen,
      viewport: _viewportSize,
      camera: _camera,
      distance: _look.distance,
      volumes: _volumes,
      friends: _friends,
      regions: _wallRegions,
      paths: _paths,
      tileSize: _tileWorld,
    );
  }

  void _refreshHover([Offset? pointer]) {
    if (_viewer != GameViewerKind.map3d || _viewportSize.isEmpty) {
      _hoverHit = null;
      return;
    }
    final screen = _isMapUnlocked ? _viewportCenter : (pointer ?? _viewportCenter);
    final next = _pickAt(screen);
    if (next == null) {
      _hoverHit = null;
      _erasePreview = const ErasePreview();
      return;
    }
    if (_worldEraserTool) {
      final tx = next.tx;
      final ty = next.ty;
      _erasePreview = (tx == null || ty == null)
          ? const ErasePreview()
          : erasePreviewAt(
              tx: tx,
              ty: ty,
              filter: _eraserFilter,
              volumes: _volumes,
              paths: _paths,
              walls: _walls,
              primary: next,
            );
    } else {
      _erasePreview = const ErasePreview();
    }
    if (next.sameAs(_hoverHit)) return;
    _hoverHit = next;
  }

  void _setSelectedHit(SelectableHit? hit) {
    _selectedHit = hit;
    _hoverHit = hit ?? _hoverHit;
    if (hit != null &&
        (hit.kind == SelectableKind.volume ||
            hit.kind == SelectableKind.volumeFace) &&
        hit.tx != null &&
        hit.ty != null) {
      _volumes.focusAt(hit.tx!, hit.ty!);
    } else {
      _volumes.clearFocus();
    }
  }

  void _finishOpenVolume() {
    if (!_volumes.isEditing) return;
    _volumes.commitKeepFocus();
    _syncWorld();
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

  void _setMapTool(GameMapTool tool) {
    _pendingFocusTimer?.cancel();
    setState(() {
      if (_editing) {
        _finishOpenVolume();
      }
      if (_mapTool == tool) {
        if (tool == GameMapTool.select) return;
        if (_wallsTool) _endWallSession();
        _mapTool = GameMapTool.select;
        return;
      }
      _mapTool = tool;
      if (!_wallsTool) _endWallSession();
    });
    _refreshHover();
  }

  void _toggleGraph() {
    setState(() => _graphVisible = !_graphVisible);
  }

  void _toggleViewLock() {
    _pendingFocusTimer?.cancel();
    setState(() {
      _viewLocked = !_viewLocked;
      if (_viewLocked && _editing) {
        _finishOpenVolume();
      }
    });
    _refreshHover();
  }

  void _isolateLookAt() {
    if (_viewer != GameViewerKind.map3d || _viewerAnim.isAnimating) return;
    final tile = _volumes.grid.tileAtWorld(_look.lookAt);
    if (tile == null) return;
    final (tx, ty) = tile;
    Volume? volume;
    for (final candidate in _volumes.visibleVolumes) {
      if (candidate.cellAt(tx, ty) == null) continue;
      volume = candidate;
      break;
    }
    if (volume != null) {
      _enterVolumeInterior(volume);
      return;
    }
    _enterFocus3d(
      isolateFocusRegion(
        grid: _volumes.grid,
        tx: tx,
        ty: ty,
        volume: volume,
        wallRegions: _wallRegions,
      ),
    );
  }

  void _togglePaint() {
    setState(() {
      _paintTool = !_paintTool;
      if (_paintTool) {
        _eraseTool = false;
        _fillTool = false;
        _stickerPalette = null;
      }
    });
  }

  void _toggleFill() {
    setState(() {
      _fillTool = !_fillTool;
      if (_fillTool) {
        _paintTool = false;
        _eraseTool = false;
        _stickerPalette = null;
      }
    });
  }

  void _toggleErase() {
    setState(() {
      _eraseTool = !_eraseTool;
      if (_eraseTool) {
        _paintTool = false;
        _fillTool = false;
        _stickerPalette = null;
      }
    });
  }

  void _selectStickerKind(FocusStickerKind kind) {
    setState(() {
      _paintTool = false;
      _fillTool = false;
      _eraseTool = false;
      _stickerPalette = _stickerPalette == kind ? null : kind;
    });
  }

  void _clearFocusStickers() {
    _stickerPalette = null;
    _selectedSticker = null;
    _looseSticker = null;
    _stickerDragHit = null;
    _tileWorkFocus = false;
    _focusWorkTiles = null;
    _paintGroupExpanded = false;
    _stickerGroupExpanded = true;
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
      _interiorFocus = false;
      _doorFaceFocus = false;
      _programVolumeId = null;
      _volumeInteriorId = null;
      _showVolumeExterior = false;
      _syncWorld();
      _paintTool = false;
      _fillTool = false;
      _eraseTool = false;
      _clearFocusStickers();
      _applyLayerVisibility();
      if (mounted) setState(() {});
      return;
    }
    if (_isOrbitViewer) {
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
      _finishOpenVolume();
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
    _mapTool = GameMapTool.select;
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
      _finishOpenVolume();
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
    _mapTool = GameMapTool.select;
    _endWallSession();
    _applyLayerVisibility();
    setState(() {});
    _viewerAnim.forward(from: 0);
  }

  void _enterVolumeInterior(Volume volume) {
    if (volume.cells.isEmpty) return;
    if (_viewerAnim.isAnimating) return;
    if (_viewer != GameViewerKind.map3d) return;
    _pendingFocusTimer?.cancel();
    _look.pauseForHandoff();
    if (_editing) {
      _finishOpenVolume();
    }
    _mapSnapLook = _look.lookAt;
    _mapSnapDistance = _look.distance;
    _mapSnapYaw = _look.yaw;
    _camFromPos = Vector3.copy(_camera.position);
    _camFromTarget = _camera.target;
    _camFromUp = _camera.up;
    _camFromFov = _camera.fovDegrees;

    var aabbMin = volume.cells.first.box.worldMin(
      _volumes.grid,
      volume.cells.first.tx,
      volume.cells.first.ty,
    );
    var aabbMax = volume.cells.first.box.worldMax(
      _volumes.grid,
      volume.cells.first.tx,
      volume.cells.first.ty,
    );
    for (final cell in volume.cells.skip(1)) {
      final min = cell.box.worldMin(_volumes.grid, cell.tx, cell.ty);
      final max = cell.box.worldMax(_volumes.grid, cell.tx, cell.ty);
      aabbMin = Vector3(
        math.min(aabbMin.x, min.x),
        math.min(aabbMin.y, min.y),
        math.min(aabbMin.z, min.z),
      );
      aabbMax = Vector3(
        math.max(aabbMax.x, max.x),
        math.max(aabbMax.y, max.y),
        math.max(aabbMax.z, max.z),
      );
    }
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
    _focusRegion = null;
    _focusCropBounds = null;
    _focusCrop = null;
    _cropTool = false;
    _volumeInteriorId = volume.id;
    _showVolumeExterior = false;
    _viewer = GameViewerKind.volumeInterior;
    _viewerReturning = false;
    _mapTool = GameMapTool.select;
    _endWallSession();
    _syncWorld();
    setState(() {});
    _viewerAnim.forward(from: 0);
  }

  void _returnToMap3d() {
    if (_viewer != GameViewerKind.plane2d &&
        _viewer != GameViewerKind.focus3d &&
        _viewer != GameViewerKind.volumeInterior) {
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
    final ppt = _volumes.grid.subtilesPerTile;
    if (!_vision.isVisible(wx ~/ ppt, wy ~/ ppt)) return null;
    return (wx, wy);
  }

  bool _inFocusWorkPixels(int px, int py) {
    final tiles = _focusWorkTiles;
    if (tiles == null || tiles.isEmpty) return true;
    final ppt = _params.pixelsPerTile;
    return tiles.contains((px ~/ ppt, py ~/ ppt));
  }

  bool get _focusPaintTools => _paintTool || _fillTool || _eraseTool;

  FocusWorkSurface get _focusWorkSurface =>
      _doorFaceFocus ? FocusWorkSurface.facade : FocusWorkSurface.floor;

  Vector3? _planeHitAt(Offset local) {
    final plane = _planeLook?.plane;
    if (plane == null) return null;
    final ray = _camera.unprojectRay(local, _viewportSize);
    if (ray == null) return null;
    return plane.intersectRay(ray.origin, ray.direction);
  }

  bool _stampCoplanarFace({
    required Vector3 world,
    required List<CoplanarFace> faces,
    required WorldPlane plane,
  }) {
    final target = pickCoplanarFace(
      world: world,
      plane: plane,
      grid: _volumes.grid,
      volumes: _volumes.visibleVolumes,
      faces: faces,
    );
    if (target == null) return false;
    final pixel = FacePaintStore.pixelAt(
      world: world,
      grid: _volumes.grid,
      cell: target.cell,
      face: target.face,
    );
    if (pixel == null) return false;
    final canvas = _facePaint.canvasFor(
      volumeId: target.volumeId,
      cell: target.cell,
      face: target.face,
    );
    if (_eraseTool) return canvas.erase(pixel.$1, pixel.$2);
    if (_paintTool) return canvas.paint(pixel.$1, pixel.$2, _paintColor);
    return false;
  }

  void _strokePaint(Offset local) {
    if (_viewerAnim.isAnimating) return;
    if (_focusedFace != null) {
      _strokeFace(local);
      return;
    }
    _strokeLandscape(local);
  }

  void _strokeFace(Offset local) {
    final plane = _planeLook?.plane;
    final hit = _planeHitAt(local);
    if (plane == null || hit == null) return;
    final lattice = plane.latticeIndex(hit);
    _ensureStrokeHistory(_eraseTool ? 'erase' : 'paint');
    final faces = collectCoplanarFaces(
      plane: plane,
      grid: _volumes.grid,
      volumes: _volumes.visibleVolumes,
    );
    var changed = false;
    final last = _paintLastCell;
    final steps = last == null ? [lattice] : _bresenham(last, lattice);
    for (final step in steps) {
      final world = last == null && step == lattice
          ? hit
          : plane.latticeCellCenter(step.$1, step.$2);
      if (_stampCoplanarFace(world: world, faces: faces, plane: plane)) {
        changed = true;
      }
    }
    _paintLastCell = lattice;
    if (changed) {
      _recordStrokeIfNeeded();
      setState(() {});
    }
  }

  void _fillAt(Offset local) {
    if (_viewerAnim.isAnimating) return;
    if (_focusedFace != null) {
      final plane = _planeLook?.plane;
      final hit = _planeHitAt(local);
      if (plane == null || hit == null) return;
      final target = pickCoplanarFace(
        world: hit,
        plane: plane,
        grid: _volumes.grid,
        volumes: _volumes.visibleVolumes,
      );
      if (target == null) return;
      final pixel = FacePaintStore.pixelAt(
        world: hit,
        grid: _volumes.grid,
        cell: target.cell,
        face: target.face,
      );
      if (pixel == null) return;
      final canvas = _facePaint.canvasFor(
        volumeId: target.volumeId,
        cell: target.cell,
        face: target.face,
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
    final ppt = _params.pixelsPerTile;
    final region = wallRegionContaining(
      _wallRegions,
      cell.$1 ~/ ppt,
      cell.$2 ~/ ppt,
    );
    final changed = region == null
        ? (_inFocusWorkPixels(cell.$1, cell.$2) &&
            grid.fill(cell.$1, cell.$2, _paintColor))
        : grid.fillConnectedMaterial(
            cell.$1,
            cell.$2,
            _paintColor,
            allow: (x, y) =>
                region.tiles.contains((x ~/ ppt, y ~/ ppt)) &&
                _inFocusWorkPixels(x, y),
          );
    if (changed) {
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
            if (!_inFocusWorkPixels(p.$1, p.$2)) continue;
        if (_eraseTool) {
          if (grid.erase(p.$1, p.$2)) changed = true;
        } else if (_paintTool) {
          if (grid.paint(p.$1, p.$2, _paintColor)) changed = true;
        }
      }
    } else if (_inFocusWorkPixels(cell.$1, cell.$2)) {
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

  void _onSelectionClick(Offset local) {
    final hit = _pickAt(_isMapUnlocked ? _viewportCenter : local);
    if (hit != null && hit.isCreatedObject) {
      _setSelectedHit(hit);
      setState(() {});
      return;
    }
    if (_isMapUnlocked) {
      final dest = _camera.intersectGround(local, _viewportSize);
      if (dest != null) _look.animateLookAt(dest);
      _setSelectedHit(null);
      setState(() {});
      return;
    }
    _setSelectedHit(hit);
    setState(() {});
  }

  void _onSelectToolClick(Offset local) {
    final hit = _pickAt(_isMapUnlocked ? _viewportCenter : local);
    if (hit != null && canFocusHit(hit)) {
      _setSelectedHit(hit);
      _focusHit(hit);
      return;
    }
    _onSelectionClick(local);
  }

  void _focusHit(SelectableHit hit) {
    if (hit.kind == SelectableKind.volumeFace) {
      final face = _volumeFaceHitFrom(hit);
      if (face != null) _enterFaceFocus(face);
      return;
    }
    if (hit.kind == SelectableKind.region ||
        hit.kind == SelectableKind.path ||
        hit.kind == SelectableKind.tile) {
      _enterTileWorkFocus(hit);
      return;
    }
    if (hit.volumeId != null) {
      final volume = _volumes.volumeById(hit.volumeId!);
      if (volume != null) {
        _enterVolumeInterior(volume);
        return;
      }
    }
    _isolateHit(hit);
  }

  void _placeAtCrosshair() {
    final center = _viewportCenter;
    if (_wallsTool) {
      final hit = _camera.intersectGround(center, _viewportSize);
      if (hit == null || !_canEditWorld(hit)) return;
      _ensureWallSession();
      final edge = _walls.hitEdgeAtMidpoint(hit);
      final removing = edge != null &&
          (_walls.contains(edge) || _paths.connectionAcross(edge));
      if (_walls.toggleAtMidpoint(hit, insteadOfAdd: _paths.severAcross)) {
        _recordWallSessionMutation();
        _syncWorld();
        if (removing) {
          _hapticDelete(1);
        } else {
          _hapticPlace(1);
        }
      }
      final tile = _volumes.grid.tileAtWorld(hit);
      if (tile != null) {
        final region = wallRegionContaining(_wallRegions, tile.$1, tile.$2);
        _setSelectedHit(
          region != null
              ? SelectableHit.region(region, tx: tile.$1, ty: tile.$2)
              : SelectableHit.tile(tile.$1, tile.$2),
        );
      }
      setState(() {});
      return;
    }
    final tile = _tileAt(center);
    if (tile == null) return;
    final (tx, ty) = tile;
    if (!_canEditTile(tx, ty)) return;
    if (_volumesTool) {
      if (_paths.contains(tx, ty)) return;
      final placed = _commitAction('place volume', () {
        final added = !_volumes.isOccupied(tx, ty);
        final painted = _volumes.paintAt(tx, ty, blocked: _paths.contains);
        if (painted) {
          final keeper = _volumes.draftVolume?.id;
          if (keeper != null) _rekeyAbsorbed(keeper);
          if (added) stripSharedVolumeWalls(_walls, _volumes);
          _volumes.commitKeepFocus();
        }
        return painted;
      });
      if (placed) {
        _hapticPlace(_volumes.draftVolume?.cells.length ?? 1);
      }
      final draft = _volumes.draftVolume;
      final cell = _volumes.draftCell;
      if (draft != null) {
        _setSelectedHit(SelectableHit.volume(draft.id, cell: cell));
      }
      setState(() {});
      return;
    }
    if (_pathsTool) {
      if (_commitAction(
        'place path',
        () => _paths.placeAndJoin(
          tx,
          ty,
          blocked: _pathBlocked,
          walls: _walls,
        ),
      )) {
        _hapticPlace(1);
      }
      _setSelectedHit(SelectableHit.path(tx, ty));
      setState(() {});
      return;
    }
    if (_worldEraserTool) {
      _deleteAtPick(_pickAt(center));
    }
  }

  void _deleteAtPick(SelectableHit? hit) {
    final tx = hit?.tx;
    final ty = hit?.ty;
    if (tx == null || ty == null || !_canEditTile(tx, ty)) return;
    if (_volumes.isEditing) _volumes.commitKeepFocus();
    final preview = erasePreviewAt(
      tx: tx,
      ty: ty,
      filter: _eraserFilter,
      volumes: _volumes,
      paths: _paths,
      walls: _walls,
      primary: hit,
    );
    var deleteSize = preview.walls.length;
    for (final target in preview.hits) {
      if (target.volumeId != null) {
        deleteSize += _volumes.volumeById(target.volumeId!)?.cells.length ?? 1;
      } else {
        deleteSize += 1;
      }
    }
    if (_commitAction('erase', () {
      if (_eraserFilter.eraseAllOnTile) {
        return eraseAtTile(
          grid: _volumes.grid,
          tx: tx,
          ty: ty,
          filter: _eraserFilter,
          walls: _walls,
          paths: _paths,
          volumes: _volumes,
        );
      }
      final preview = erasePreviewAt(
        tx: tx,
        ty: ty,
        filter: _eraserFilter,
        volumes: _volumes,
        paths: _paths,
        walls: _walls,
        primary: hit,
      );
      var changed = false;
      for (final target in preview.hits) {
        switch (target.kind) {
          case SelectableKind.volume:
          case SelectableKind.volumeFace:
            final volume = target.volumeId == null
                ? null
                : _volumes.volumeById(target.volumeId!);
            if (volume != null && _volumes.removeVolume(volume)) {
              changed = true;
            }
          case SelectableKind.path:
            if (target.tx != null &&
                target.ty != null &&
                _paths.removeTile(target.tx!, target.ty!)) {
              changed = true;
            }
          case SelectableKind.tile:
          case SelectableKind.region:
          case SelectableKind.friend:
            break;
        }
      }
      for (final edge in preview.walls) {
        if (_walls.remove(edge)) changed = true;
      }
      return changed;
    })) {
      _hapticDelete(deleteSize);
    }
    _refreshHover();
    setState(() {});
  }

  void _onSelectionAction(SelectionActionId id) {
    final hit = _selectedHit;
    if (hit == null) return;
    switch (id) {
      case SelectionActionId.isolate:
        if (isolateOpensVolumeInterior(hit) && hit.volumeId != null) {
          final volume = _volumes.volumeById(hit.volumeId!);
          if (volume != null) {
            _enterVolumeInterior(volume);
            break;
          }
        }
        _isolateHit(hit);
      case SelectionActionId.program:
        final volume =
            hit.volumeId == null ? null : _volumes.volumeById(hit.volumeId!);
        if (volume != null) _enterInteriorFocus(volume);
      case SelectionActionId.delete:
        if (hit.volumeId != null) {
          final volume = _volumes.volumeById(hit.volumeId!);
          final size = volume?.cells.length ?? 1;
          if (_commitAction('delete volume', () {
            final live = _volumes.volumeById(hit.volumeId!);
            if (live == null) return false;
            return _volumes.removeVolume(live);
          })) {
            _hapticDelete(size);
          }
          _setSelectedHit(null);
          setState(() {});
        }
      case SelectionActionId.focusFace:
        final faceHit = _volumeFaceHitFrom(hit);
        if (faceHit != null) _enterFaceFocus(faceHit);
      case SelectionActionId.focusFriend:
        final friend =
            hit.friendId == null ? null : _friends.byId(hit.friendId!);
        if (friend != null) _look.animateLookAt(friend.position);
    }
  }

  VolumeFaceHit? _volumeFaceHitFrom(SelectableHit hit) {
    final cell = hit.cell;
    final face = hit.face;
    final volumeId = hit.volumeId;
    if (cell == null || face == null || volumeId == null) return null;
    return VolumeFaceHit(
      volumeId: volumeId,
      cell: cell,
      face: face,
      worldPoint: cell.box.worldCenter(_volumes.grid, cell.tx, cell.ty),
      t: 0,
    );
  }

  void _isolateHit(SelectableHit hit) {
    if (_viewer != GameViewerKind.map3d || _viewerAnim.isAnimating) return;
    if (hit.kind == SelectableKind.friend) {
      final friend = hit.friendId == null ? null : _friends.byId(hit.friendId!);
      if (friend != null) _look.animateLookAt(friend.position);
      return;
    }
    final tx = hit.tx;
    final ty = hit.ty;
    if (tx == null || ty == null) return;
    if (hit.kind == SelectableKind.region || hit.kind == SelectableKind.path) {
      _enterFocus3d(
        FocusRegion.aroundTile(grid: _volumes.grid, tx: tx, ty: ty),
      );
      return;
    }
    Volume? volume;
    if (hit.volumeId != null) volume = _volumes.volumeById(hit.volumeId!);
    _enterFocus3d(
      isolateFocusRegion(
        grid: _volumes.grid,
        tx: tx,
        ty: ty,
        volume: volume,
        wallRegions: _wallRegions,
      ),
    );
  }

  VolumeSide? _sideForFace(VolumeFace face) => switch (face) {
        VolumeFace.posX => VolumeSide.east,
        VolumeFace.negX => VolumeSide.west,
        VolumeFace.posZ => VolumeSide.south,
        VolumeFace.negZ => VolumeSide.north,
        VolumeFace.posY || VolumeFace.negY => null,
      };

  void _enterInteriorFocus(Volume volume) {
    if (!_programs.canAssignToVolume(volume)) return;
    final cell = volume.cells.firstWhere(
      _programs.canAssignProgram,
      orElse: () => volume.cells.first,
    );
    _interiorFocus = true;
    _doorFaceFocus = false;
    _tileWorkFocus = false;
    _programVolumeId = volume.id;
    _focusWorkTiles = {for (final c in volume.cells) (c.tx, c.ty)};
    _selectedSticker = null;
    _looseSticker = null;
    _stickerPalette = null;
    final center = cell.box.worldCenter(_volumes.grid, cell.tx, cell.ty);
    _enterPlane2d(
      WorldPlane.ground(
        origin: Vector3(center.x, 0, center.z),
        subtileSize: _volumes.grid.subtileSize,
      ),
    );
    _syncWorld();
  }

  void _enterTileWorkFocus(SelectableHit hit) {
    final tx = hit.tx;
    final ty = hit.ty;
    if (tx == null || ty == null) return;
    if (_viewer != GameViewerKind.map3d || _viewerAnim.isAnimating) return;
    _interiorFocus = false;
    _doorFaceFocus = false;
    _tileWorkFocus = true;
    _focusWorkTiles = hit.kind == SelectableKind.region && hit.region != null
        ? Set<(int, int)>.from(hit.region!.tiles)
        : {(tx, ty)};
    final volume = _volumes.volumeAt(tx, ty);
    _programVolumeId = volume?.id;
    _selectedSticker = null;
    _looseSticker = null;
    _stickerPalette = null;
    final center = _volumes.grid.tileCenter(tx, ty);
    _enterPlane2d(
      WorldPlane.ground(
        origin: Vector3(center.x, 0, center.z),
        subtileSize: _volumes.grid.subtileSize,
      ),
    );
    _syncWorld();
  }

  void _enterFaceFocus(VolumeFaceHit face) {
    _interiorFocus = false;
    _doorFaceFocus = true;
    _tileWorkFocus = false;
    _focusWorkTiles = {(face.cell.tx, face.cell.ty)};
    _programVolumeId = face.volumeId;
    _selectedSticker = null;
    _looseSticker = null;
    _stickerPalette = null;
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
  }

  void _placeProgramAt(Offset local) {
    final kind = programKindForSticker(
      _stickerPalette ?? FocusStickerKind.bedroom,
    );
    if (kind == null) return;
    final hit = _planeHitAt(local);
    if (hit == null) {
      _dropLoose(FocusStickerKind.bedroom, local);
      return;
    }
    final placed = _tryPlaceProgram(hit, kind);
    if (placed != null) {
      _looseSticker = null;
      _selectedSticker = _FocusStickerSel.program(placed.id);
      setState(() {});
      return;
    }
    _dropLoose(stickerKindForProgram(kind), local, world: hit);
  }

  ProgramStamp? _tryPlaceProgram(Vector3 hit, VolumeProgramKind kind) {
    final volumes = _programVolumeId == null
        ? _volumes.visibleVolumes
        : [
            if (_volumes.volumeById(_programVolumeId!) != null)
              _volumes.volumeById(_programVolumeId!)!,
          ];
    for (final volume in volumes) {
      for (final cell in volume.cells) {
        if (!_inFocusWorkTile(cell.tx, cell.ty)) continue;
        final pixel = FacePaintStore.pixelAt(
          world: hit,
          grid: _volumes.grid,
          cell: cell,
          face: VolumeFace.negY,
        );
        if (pixel == null) continue;
        final snapped = _programs.snapOrigin(
          cell: cell,
          u: pixel.$1,
          v: pixel.$2,
          volumeId: volume.id,
        );
        if (snapped == null) continue;
        ProgramStamp? stamp;
        _commitAction('place program', () {
          stamp = _programs.place(
            volume: volume,
            cell: cell,
            originU: snapped.$1,
            originV: snapped.$2,
            kind: kind,
          );
          return stamp != null;
        });
        if (stamp != null) _hapticPlace(2);
        return stamp;
      }
    }
    return null;
  }

  void _placeDoorAt(Offset local) {
    final key = _focusedFace;
    if (key == null) {
      _dropLoose(FocusStickerKind.door, local);
      return;
    }
    final side = _sideForFace(key.face);
    if (side == null) {
      _dropLoose(FocusStickerKind.door, local);
      return;
    }
    final volume = _volumes.volumeById(key.volumeId);
    final cell = volume?.cellAt(key.tx, key.ty);
    if (volume == null || cell == null) {
      _dropLoose(FocusStickerKind.door, local);
      return;
    }
    final hit = _planeHitAt(local);
    if (hit == null) {
      _dropLoose(FocusStickerKind.door, local);
      return;
    }
    final pixel = FacePaintStore.pixelAt(
      world: hit,
      grid: _volumes.grid,
      cell: cell,
      face: key.face,
    );
    if (pixel == null) {
      _dropLoose(FocusStickerKind.door, local, world: hit);
      return;
    }
    final faceW = switch (side) {
      VolumeSide.east || VolumeSide.west => cell.box.depthSubtiles,
      VolumeSide.north || VolumeSide.south => cell.box.widthSubtiles,
    };
    if (!doorOriginInBounds(originU: pixel.$1, faceWidth: faceW)) {
      _dropLoose(FocusStickerKind.door, local, world: hit);
      return;
    }
    if (_commitAction(
      'place door',
      () => _volumes.placeDoor(
        volume: volume,
        cell: cell,
        side: side,
        originU: pixel.$1,
      ),
    )) {
      _hapticPlace(1);
    }
    _looseSticker = null;
    _selectedSticker = _FocusStickerSel.door(
      volumeId: volume.id,
      tx: cell.tx,
      ty: cell.ty,
      side: side,
    );
    setState(() {});
  }

  bool _inFocusWorkTile(int tx, int ty) {
    final tiles = _focusWorkTiles;
    if (tiles == null || tiles.isEmpty) return true;
    return tiles.contains((tx, ty));
  }

  void _dropLoose(FocusStickerKind kind, Offset local, {Vector3? world}) {
    final at = world ?? _planeHitAt(local);
    _looseSticker = _LooseSticker(
      kind: kind,
      world: at ?? Vector3.zero(),
      valid: false,
    );
    _selectedSticker = const _FocusStickerSel.loose();
    setState(() {});
  }

  _FocusStickerSel? _hitFocusSticker(Offset local) {
    final hit = _planeHitAt(local);
    if (hit == null) return _looseSticker == null ? null : const _FocusStickerSel.loose();
    if (_doorFaceFocus) {
      final key = _focusedFace;
      final side = key == null ? null : _sideForFace(key.face);
      final volume = key == null ? null : _volumes.volumeById(key.volumeId);
      final cell = volume?.cellAt(key!.tx, key.ty);
      if (key != null && side != null && volume != null && cell != null) {
        final pixel = FacePaintStore.pixelAt(
          world: hit,
          grid: _volumes.grid,
          cell: cell,
          face: key.face,
        );
        if (pixel != null && cell.accessibleSides.contains(side)) {
          final door = volumeDoorForSide(
            cell.box,
            side,
            originU: cell.doorOrigins[side],
          );
          if (door != null && door.containsFacePixel(pixel.$1, pixel.$2)) {
            return _FocusStickerSel.door(
              volumeId: volume.id,
              tx: cell.tx,
              ty: cell.ty,
              side: side,
            );
          }
        }
      }
    } else {
      for (final stamp in _programs.stamps) {
        if (_programVolumeId != null && stamp.volumeId != _programVolumeId) {
          continue;
        }
        final volume = _volumes.volumeById(stamp.volumeId);
        final cell = volume?.cellAt(stamp.tx, stamp.ty);
        if (cell == null) continue;
        final pixel = FacePaintStore.pixelAt(
          world: hit,
          grid: _volumes.grid,
          cell: cell,
          face: VolumeFace.negY,
        );
        if (pixel == null) continue;
        if (pixel.$1 >= stamp.originU &&
            pixel.$1 < stamp.originU + stamp.width &&
            pixel.$2 >= stamp.originV &&
            pixel.$2 < stamp.originV + stamp.height) {
          return _FocusStickerSel.program(stamp.id);
        }
      }
    }
    if (_looseSticker != null) return const _FocusStickerSel.loose();
    return null;
  }

  void _onPlane2dTap(Offset local) {
    if (_fillTool) {
      _fillAt(local);
      return;
    }
    if (_paintTool || _eraseTool) {
      _strokePaint(local);
      return;
    }
    if (_stickerPalette == FocusStickerKind.door) {
      _placeDoorAt(local);
      return;
    }
    if (_stickerPalette == FocusStickerKind.bedroom ||
        _stickerPalette == FocusStickerKind.common) {
      _placeProgramAt(local);
      return;
    }
    final hit = _hitFocusSticker(local);
    _selectedSticker = hit;
    if (hit == null) _looseSticker = null;
    setState(() {});
  }

  void _deleteSelectedSticker() {
    final sel = _selectedSticker;
    if (sel == null) return;
    if (sel.loose) {
      _looseSticker = null;
      _selectedSticker = null;
      setState(() {});
      return;
    }
    if (sel.stampId != null) {
      if (_commitAction('remove program', () => _programs.remove(sel.stampId!))) {
        _hapticDelete(1);
      }
      _selectedSticker = null;
      setState(() {});
      return;
    }
    if (sel.doorVolumeId != null && sel.doorSide != null) {
      final volume = _volumes.volumeById(sel.doorVolumeId!);
      final cell = volume?.cellAt(sel.doorTx!, sel.doorTy!);
      if (volume != null && cell != null) {
        if (_commitAction(
          'remove door',
          () => _volumes.removeDoor(
            volume: volume,
            cell: cell,
            side: sel.doorSide!,
          ),
        )) {
          _hapticDelete(1);
        }
      }
      _selectedSticker = null;
      setState(() {});
    }
  }

  void _dragSelectedSticker(Offset local) {
    final sel = _stickerDragHit ?? _selectedSticker;
    if (sel == null) return;
    final hit = _planeHitAt(local);
    if (sel.loose || sel.stampId != null) {
      FocusStickerKind kind;
      if (sel.loose) {
        kind = _looseSticker?.kind ?? FocusStickerKind.bedroom;
      } else {
        VolumeProgramKind found = VolumeProgramKind.bedroom;
        for (final stamp in _programs.stamps) {
          if (stamp.id == sel.stampId) {
            found = stamp.kind;
            break;
          }
        }
        kind = stickerKindForProgram(found);
      }
      if (hit == null) {
        _looseSticker = _LooseSticker(kind: kind, world: Vector3.zero(), valid: false);
        _selectedSticker = const _FocusStickerSel.loose();
        setState(() {});
        return;
      }
      final placed = _previewProgramValid(hit, kind);
      _looseSticker = _LooseSticker(kind: kind, world: hit, valid: placed);
      _selectedSticker = const _FocusStickerSel.loose();
      setState(() {});
      return;
    }
    if (sel.doorVolumeId != null) {
      _looseSticker = _LooseSticker(
        kind: FocusStickerKind.door,
        world: hit ?? Vector3.zero(),
        valid: hit != null && _doorValidAt(hit),
      );
      _selectedSticker = const _FocusStickerSel.loose();
      setState(() {});
    }
  }

  bool _previewProgramValid(Vector3 hit, FocusStickerKind kind) {
    final programKind = programKindForSticker(kind);
    if (programKind == null) return false;
    for (final volume in _volumes.visibleVolumes) {
      if (_programVolumeId != null && volume.id != _programVolumeId) continue;
      for (final cell in volume.cells) {
        if (!_inFocusWorkTile(cell.tx, cell.ty)) continue;
        final pixel = FacePaintStore.pixelAt(
          world: hit,
          grid: _volumes.grid,
          cell: cell,
          face: VolumeFace.negY,
        );
        if (pixel == null) continue;
        if (_programs.canPlace(
          volume: volume,
          cell: cell,
          originU: pixel.$1,
          originV: pixel.$2,
          ignoreStampId: _stickerDragHit?.stampId,
        )) {
          return true;
        }
      }
    }
    return false;
  }

  bool _doorValidAt(Vector3 hit) {
    final key = _focusedFace;
    final side = key == null ? null : _sideForFace(key.face);
    final volume = key == null ? null : _volumes.volumeById(key.volumeId);
    final cell = volume?.cellAt(key?.tx ?? -1, key?.ty ?? -1);
    if (key == null || side == null || volume == null || cell == null) {
      return false;
    }
    final pixel = FacePaintStore.pixelAt(
      world: hit,
      grid: _volumes.grid,
      cell: cell,
      face: key.face,
    );
    if (pixel == null) return false;
    final faceW = switch (side) {
      VolumeSide.east || VolumeSide.west => cell.box.depthSubtiles,
      VolumeSide.north || VolumeSide.south => cell.box.widthSubtiles,
    };
    return doorOriginInBounds(originU: pixel.$1, faceWidth: faceW);
  }

  void _commitStickerDrag() {
    final loose = _looseSticker;
    final drag = _stickerDragHit;
    _stickerDragHit = null;
    if (loose == null || !loose.valid) {
      setState(() {});
      return;
    }
    if (loose.kind == FocusStickerKind.door) {
      _placeDoorAt(_viewportCenterFromWorld(loose.world));
      return;
    }
    final kind = programKindForSticker(loose.kind);
    if (kind == null) return;
    if (drag?.stampId != null) {
      final moved = _tryMoveProgram(drag!.stampId!, loose.world);
      if (moved != null) {
        _looseSticker = null;
        _selectedSticker = _FocusStickerSel.program(moved.id);
        setState(() {});
        return;
      }
    }
    final placed = _tryPlaceProgram(loose.world, kind);
    if (placed != null) {
      _looseSticker = null;
      _selectedSticker = _FocusStickerSel.program(placed.id);
    }
    setState(() {});
  }

  ProgramStamp? _tryMoveProgram(int id, Vector3 hit) {
    for (final volume in _volumes.visibleVolumes) {
      if (_programVolumeId != null && volume.id != _programVolumeId) continue;
      for (final cell in volume.cells) {
        if (!_inFocusWorkTile(cell.tx, cell.ty)) continue;
        final pixel = FacePaintStore.pixelAt(
          world: hit,
          grid: _volumes.grid,
          cell: cell,
          face: VolumeFace.negY,
        );
        if (pixel == null) continue;
        ProgramStamp? next;
        _commitAction('move program', () {
          next = _programs.move(
            id: id,
            volume: volume,
            cell: cell,
            originU: pixel.$1,
            originV: pixel.$2,
          );
          return next != null;
        });
        if (next != null) return next;
      }
    }
    return null;
  }

  Offset _viewportCenterFromWorld(Vector3 world) {
    return _camera.projectToScreen(world, _viewportSize) ?? _viewportCenter;
  }

  List<Vector3>? get _looseDoorCorners {
    final loose = _looseSticker;
    if (loose == null || loose.kind != FocusStickerKind.door) return null;
    final key = _focusedFace;
    final side = key == null ? null : _sideForFace(key.face);
    final volume = key == null ? null : _volumes.volumeById(key.volumeId);
    final cell = volume?.cellAt(key?.tx ?? -1, key?.ty ?? -1);
    if (key != null && side != null && volume != null && cell != null) {
      final pixel = FacePaintStore.pixelAt(
        world: loose.world,
        grid: _volumes.grid,
        cell: cell,
        face: key.face,
      );
      final door = volumeDoorForSide(
        cell.box,
        side,
        originU: pixel?.$1,
      );
      if (door != null) {
        return doorWorldCorners(
          grid: _volumes.grid,
          tx: cell.tx,
          ty: cell.ty,
          box: cell.box,
          door: door,
        );
      }
    }
    final s = _volumes.grid.subtileSize;
    final p = loose.world;
    return [
      Vector3(p.x, p.y, p.z),
      Vector3(p.x + 2 * s, p.y, p.z),
      Vector3(p.x + 2 * s, p.y + 4 * s, p.z),
      Vector3(p.x, p.y + 4 * s, p.z),
    ];
  }

  List<Vector3>? get _looseProgramCorners {
    final loose = _looseSticker;
    if (loose == null || loose.kind == FocusStickerKind.door) return null;
    final s = _volumes.grid.subtileSize;
    for (final volume in _volumes.visibleVolumes) {
      for (final cell in volume.cells) {
        final pixel = FacePaintStore.pixelAt(
          world: loose.world,
          grid: _volumes.grid,
          cell: cell,
          face: VolumeFace.negY,
        );
        if (pixel == null) continue;
        final min = cell.box.worldMin(_volumes.grid, cell.tx, cell.ty);
        final x0 = min.x + pixel.$1 * s;
        final z0 = min.z + pixel.$2 * s;
        final y = min.y + 0.08;
        return [
          Vector3(x0, y, z0),
          Vector3(x0, y, z0 + 6 * s),
          Vector3(x0 + 6 * s, y, z0 + 6 * s),
          Vector3(x0 + 6 * s, y, z0),
        ];
      }
    }
    final p = loose.world;
    return [
      Vector3(p.x, 0.08, p.z),
      Vector3(p.x, 0.08, p.z + 6 * s),
      Vector3(p.x + 6 * s, 0.08, p.z + 6 * s),
      Vector3(p.x + 6 * s, 0.08, p.z),
    ];
  }

  Offset? get _selectedStickerScreen {
    final sel = _selectedSticker;
    if (sel == null) return null;
    if (sel.loose) {
      final corners = _looseSticker?.kind == FocusStickerKind.door
          ? _looseDoorCorners
          : _looseProgramCorners;
      return _quadCenter(corners);
    }
    if (sel.stampId != null) {
      for (final stamp in _programs.stamps) {
        if (stamp.id != sel.stampId) continue;
        final volume = _volumes.volumeById(stamp.volumeId);
        final cell = volume?.cellAt(stamp.tx, stamp.ty);
        if (cell == null) return null;
        final min = cell.box.worldMin(_volumes.grid, cell.tx, cell.ty);
        final s = _volumes.grid.subtileSize;
        final y = min.y + 0.08;
        return _quadCenter([
          Vector3(min.x + stamp.originU * s, y, min.z + stamp.originV * s),
          Vector3(
            min.x + stamp.originU * s,
            y,
            min.z + (stamp.originV + stamp.height) * s,
          ),
          Vector3(
            min.x + (stamp.originU + stamp.width) * s,
            y,
            min.z + (stamp.originV + stamp.height) * s,
          ),
          Vector3(
            min.x + (stamp.originU + stamp.width) * s,
            y,
            min.z + stamp.originV * s,
          ),
        ]);
      }
    }
    if (sel.doorVolumeId != null && sel.doorSide != null) {
      final volume = _volumes.volumeById(sel.doorVolumeId!);
      final cell = volume?.cellAt(sel.doorTx!, sel.doorTy!);
      if (volume == null || cell == null) return null;
      final door = volumeDoorForSide(
        cell.box,
        sel.doorSide!,
        originU: cell.doorOrigins[sel.doorSide!],
      );
      if (door == null) return null;
      return _quadCenter(
        doorWorldCorners(
          grid: _volumes.grid,
          tx: cell.tx,
          ty: cell.ty,
          box: cell.box,
          door: door,
        ),
      );
    }
    return null;
  }

  Offset? _quadCenter(List<Vector3>? corners) {
    if (corners == null || corners.isEmpty) return null;
    var x = 0.0;
    var y = 0.0;
    var n = 0;
    for (final c in corners) {
      final p = _camera.projectToScreen(c, _viewportSize);
      if (p == null) continue;
      x += p.dx;
      y += p.dy;
      n++;
    }
    if (n == 0) return null;
    return Offset(x / n, y / n);
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

  void _setSpringyLookPeek(bool enabled) {
    setState(() => _springyLookPeek = enabled);
    if (!enabled) _look.endPitchPeek();
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

  Flatmate? _hitFlatmate(Offset local) {
    final target = _hitGizmoTarget(local);
    return target is FriendGizmoTarget ? target.instance : null;
  }

  (int, int)? _tileOfFlatmate(Flatmate flatmate) {
    return _volumes.grid.tileAtWorld(flatmate.position);
  }

  List<(int, int)>? _routeForFlatmate(Flatmate flatmate, Offset local) {
    final start = _tileOfFlatmate(flatmate);
    final goal = _tileAt(local);
    if (start == null || goal == null) return null;
    return _flatmatePathfinder.findOnMap(
      start: start,
      goal: goal,
      grid: _volumes.grid,
      volumes: _volumes,
      paths: _paths,
      walls: _walls,
    );
  }

  void _updateFlatmatePreview(Offset local) {
    final flatmate = _flatmateDown;
    if (flatmate == null) return;
    _flatmateDragging = true;
    _handleDragging = true;
    _flatmatePreview = _routeForFlatmate(flatmate, local);
    setState(() {});
  }

  void _commitFlatmateDrag(Offset local) {
    final flatmate = _flatmateDown;
    final path = _flatmatePreview ??
        (flatmate == null ? null : _routeForFlatmate(flatmate, local));
    if (flatmate != null && path != null && path.length >= 2) {
      flatmate.movement.start(path);
      _applyFlatmatePose(flatmate);
      _ensureFlatmateTicker();
    }
    _cancelFlatmateDrag();
  }

  void _cancelFlatmateDrag() {
    _flatmateDragging = false;
    _flatmateDown = null;
    _flatmatePreview = null;
    if (_gizmoAxis == null) _handleDragging = false;
    if (mounted) setState(() {});
  }

  void _ensureFlatmateTicker() {
    if (!_flatmateTicker.isActive) {
      _lastFlatmateTick = null;
      _flatmateTicker.start();
    }
  }

  void _onFlatmateTick(Duration elapsed) {
    final last = _lastFlatmateTick ?? elapsed;
    _lastFlatmateTick = elapsed;
    final dt = (elapsed - last).inMicroseconds / 1e6;
    if (dt <= 0 || dt > 0.25) return;
    var moving = false;
    for (final flatmate in _friends.instances) {
      if (!flatmate.movement.isMoving && flatmate.movement.tiles.isEmpty) {
        continue;
      }
      final still = flatmate.movement.advance(
        dt: dt,
        baseTilesPerSecond: flatmate.friend.stats.tileSpeed,
        onPath: _paths.contains,
      );
      _applyFlatmatePose(flatmate);
      if (!still) flatmate.movement.clear();
      moving = moving || still;
    }
    syncFriendMeshes(_scene, _friends, tileSize: _tileWorld);
    _applyLayerVisibility();
    if (mounted) setState(() {});
    if (!moving && !_flatmateDragging) _flatmateTicker.stop();
  }

  void _applyFlatmatePose(Flatmate flatmate) {
    final sitY = FriendMeshLayout.sitOnGroundY(tileSize: _tileWorld);
    if (flatmate.movement.tiles.isNotEmpty) {
      flatmate.position.setFrom(
        flatmate.movement.worldPosition(_volumes.grid, sitY),
      );
      flatmate.yaw = flatmate.movement.facingYaw();
    }
    if (flatmate.position.y < sitY) flatmate.position.y = sitY;
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
        _programs.remapVolumeTiles(target.volume.id, dtx, dty);
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
        _programs.remapVolumeTiles(target.volume.id, dtx, dty);
        _syncWorld();
      }
    }
    _syncGizmoMeshes();
    setState(() {});
  }

  void _onTileTap(Offset local) {
    if (_toolsBlocked || _handleDragging) return;
    if (_flatmateDown != null) {
      if (_showGizmos) {
        _gizmoSelected = FriendGizmoTarget(
          _flatmateDown!,
          tileSize: _tileWorld,
        );
        setState(() {});
      }
      _flatmateDown = null;
      return;
    }
    if (_showGizmos) {
      _onGizmoTap(local);
      return;
    }
    if (_isPlane2d) {
      _onPlane2dTap(local);
      return;
    }
    if (_viewer == GameViewerKind.map3d && _isMapUnlocked) {
      if (_isPlaceTool || _worldEraserTool) {
        _placeAtCrosshair();
      } else {
        _onSelectToolClick(local);
      }
      return;
    }
    if (_viewer == GameViewerKind.map3d && _isSelectTool) {
      _onSelectToolClick(local);
      return;
    }
    if (_editing && !_volumesTool) return;
    if (_wallsTool) {
      final hit = _camera.intersectGround(local, _viewportSize);
      if (hit == null || !_canEditWorld(hit)) return;
      _ensureWallSession();
      final edge = _walls.hitEdgeAtMidpoint(hit);
      final removing = edge != null &&
          (_walls.contains(edge) || _paths.connectionAcross(edge));
      if (_walls.toggleAtMidpoint(hit, insteadOfAdd: _paths.severAcross)) {
        _recordWallSessionMutation();
        _syncWorld();
        if (removing) {
          _hapticDelete(1);
        } else {
          _hapticPlace(1);
        }
        setState(() {});
      }
      return;
    }
    final tile = _tileAt(local);
    if (tile == null) return;
    final (tx, ty) = tile;
    if (!_canEditTile(tx, ty)) return;
    if (_volumesTool) {
      if (_paths.contains(tx, ty)) return;
      _paintVolumeTo(local);
      return;
    }
    if (_pathsTool) {
      if (_commitAction(
        'place path',
        () => _paths.placeAndJoin(
          tx,
          ty,
          blocked: _pathBlocked,
          walls: _walls,
        ),
      )) {
        _hapticPlace(1);
      }
      return;
    }
    if (_worldEraserTool) {
      _deleteAtPick(_pickAt(local));
    }
  }

  void _rekeyAbsorbed(int keeperId) {
    for (final id in _volumes.lastAbsorbedIds) {
      _facePaint.rekeyVolume(id, keeperId);
      _programs.rekeyVolume(id, keeperId);
    }
    _volumes.lastAbsorbedIds.clear();
  }

  void _paintVolumeTo(Offset local) {
    if (_toolsBlocked) return;
    final tile = _tileAt(local);
    if (tile == null || !_canEditTile(tile.$1, tile.$2)) return;
    if (_paths.contains(tile.$1, tile.$2)) return;
    _ensureStrokeHistory('place volume');
    final last = _volumeStrokeLast ?? tile;
    var changed = false;
    for (final step in _bresenham(last, tile)) {
      if (_paths.contains(step.$1, step.$2)) break;
      final added = !_volumes.isOccupied(step.$1, step.$2);
      if (_volumes.paintAt(step.$1, step.$2, blocked: _paths.contains)) {
        final keeper = _volumes.draftVolume?.id;
        if (keeper != null) _rekeyAbsorbed(keeper);
        if (added) stripSharedVolumeWalls(_walls, _volumes);
        changed = true;
      }
    }
    _volumeStrokeLast = tile;
    if (changed) {
      _recordStrokeIfNeeded();
      _syncWorld();
      _hapticPlace(_volumes.draftVolume?.cells.length ?? 1);
      setState(() {});
    }
  }

  void _paintPathTo(Offset local) {
    if (_toolsBlocked) return;
    final tile = _tileAt(local);
    if (tile == null || !_canEditTile(tile.$1, tile.$2)) return;
    if (_pathBlocked(tile.$1, tile.$2)) return;
    _ensureStrokeHistory('paint path');
    final last = _pathStrokeLast ?? tile;
    if (_paths.paintStroke(
      last,
      tile,
      blocked: _pathBlocked,
      walls: _walls,
    )) {
      _recordStrokeIfNeeded();
      _syncWorld();
      _hapticPlace(1);
      setState(() {});
    }
    _pathStrokeLast = tile;
  }

  void _paintWallTo(Offset local) {
    if (_toolsBlocked) return;
    final hit = _camera.intersectGround(local, _viewportSize);
    if (hit == null || !_canEditWorld(hit)) return;
    final last = _wallStrokeLast ?? hit;
    _ensureWallSession();
    if (_walls.paintStroke(last, hit, insteadOfAdd: _paths.severAcross)) {
      _recordWallSessionMutation();
      _syncWorld();
      _hapticPlace(1);
      setState(() {});
    }
    _wallStrokeLast = hit;
  }


  void _onHandleDragStart(
    VolumeCell cell,
    VolumeHandle handle,
    Offset global,
  ) {
    if (_toolsBlocked) return;
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
    _volumes.draftCell = cell;
    _handleDragging = true;
    _dragHandle = handle;
    _dragCell = cell;
    _dragBoxSnapshot = cell.box.clone();
    _dragBefore = _capture('resize volume');
    _dragPlanePoint = planePoint;
    _dragStartHit = startHit;
  }

  void _onHandleDragUpdate(
    VolumeCell cell,
    VolumeHandle handle,
    Offset global,
  ) {
    final target = _dragCell ?? cell;
    final snapshot = _dragBoxSnapshot;
    final startHit = _dragStartHit;
    final planePoint = _dragPlanePoint;
    if (_toolsBlocked) return;
    if (snapshot == null || startHit == null || planePoint == null) {
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
    target.box.setFrom(snapshot);
    target.box.applyHandleDelta(
      grid: _volumes.grid,
      tx: target.tx,
      ty: target.ty,
      handle: handle,
      delta: delta,
    );
    _syncWorld();
    setState(() {});
  }

  void _onHandleDragEnd() {
    final cell = _dragCell ?? _volumes.draftCell;
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
    _dragCell = null;
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
      _volumeStrokeLast = null;
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
    if (_viewer == GameViewerKind.map3d) {
      _refreshHover(event.localPosition);
      setState(() {});
    }
  }

  void _onToolPointerMove(PointerMoveEvent event) {
    if (_handleDragging && !_flatmateDragging) return;
    _toolDidMove = true;
    if (_flatmateDown != null) {
      _updateFlatmatePreview(event.localPosition);
      return;
    }
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
    if (_isPlane2d &&
        _stickerDragHit != null &&
        (event.kind != PointerDeviceKind.mouse ||
            (_mouseButtons & kPrimaryButton) != 0)) {
      _dragSelectedSticker(event.localPosition);
      return;
    }
    final strokeTools = !_isMapUnlocked;
    final pathPainting =
        strokeTools &&
        !_isPlane2d &&
        _pathsTool &&
        (event.kind != PointerDeviceKind.mouse ||
            (_mouseButtons & kPrimaryButton) != 0);
    if (pathPainting) {
      _paintPathTo(event.localPosition);
      return;
    }
    final volumePainting =
        strokeTools &&
        !_isPlane2d &&
        _volumesTool &&
        (event.kind != PointerDeviceKind.mouse ||
            (_mouseButtons & kPrimaryButton) != 0);
    if (volumePainting) {
      _paintVolumeTo(event.localPosition);
      return;
    }
    final wallPainting =
        strokeTools &&
        !_isPlane2d &&
        _wallsTool &&
        (event.kind != PointerDeviceKind.mouse ||
            (_mouseButtons & kPrimaryButton) != 0);
    if (wallPainting) {
      _paintWallTo(event.localPosition);
      return;
    }
    final mouse = event.kind == PointerDeviceKind.mouse;
    final secondary = (_mouseButtons & kSecondaryButton) != 0;
    final primary = (_mouseButtons & kPrimaryButton) != 0;
    if (!mouse || secondary || primary) {
      if (_isOrbitViewer && !_viewerAnim.isAnimating) {
        _orbit?.orbit(event.delta);
      } else if (_isPlane2d && !_viewerAnim.isAnimating) {
        _planeLook?.pan(event.delta);
        _maybeTurnPlane2dFace();
      } else if (_viewer == GameViewerKind.map3d && _isMapUnlocked) {
        _look.pan(event.delta);
        // Unlocked drag only pans. Placement is click-at-crosshair.
      }
    }
  }

  void _onToolPointerUp(Offset local) {
    if (_flatmateDragging || (_flatmateDown != null && _toolDidMove)) {
      _commitFlatmateDrag(local);
      _toolDidMove = false;
      _pathStrokeLast = null;
      _wallStrokeLast = null;
      return;
    }
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
    _volumeStrokeLast = null;
    _toolDidMove = false;
    if (_isPlane2d) {
      if (_stickerDragHit != null && moved) {
        _commitStickerDrag();
      } else if (!moved) {
        _onPlane2dTap(local);
      }
      _paintLastCell = null;
      _endStrokeHistory();
      return;
    }
    _paintLastCell = null;
    if (!moved) _onTileTap(local);
    _endStrokeHistory();
    if (_volumesTool && _volumes.isEditing) {
      _volumes.commitKeepFocus();
      final draft = _volumes.draftVolume;
      final cell = _volumes.draftCell;
      if (draft != null) {
        _setSelectedHit(SelectableHit.volume(draft.id, cell: cell));
      }
      setState(() {});
    }
  }

  void _onLookGesture(GestureState state) {
    final isTwoFinger =
        state.pointerCount >= 2 ||
        (state.type == GestureType.twoFingerDrag && state.pointers.isEmpty);

    final orbit = _orbit;
    if (_isOrbitViewer && orbit != null && !_viewerAnim.isAnimating) {
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
        _twoFingerOrbit = false;
        _twoFingerPinch = false;
        _enterPinchExclusiveMode();
        _pinchSpanScale = state.spanScale <= 1e-6 ? 1.0 : state.spanScale;
        if (!_springyLookPeek) _look.beginZoom();
      }
      final span = state.spanScale <= 1e-6 ? 1.0 : state.spanScale;
      final scaleChange = span / _pinchSpanScale;
      _pinchSpanScale = span;
      if (_springyLookPeek) {
        if (!_twoFingerOrbit && !_twoFingerPinch) {
          if ((scaleChange - 1).abs() > 0.03) {
            _twoFingerPinch = true;
            _look.beginZoom();
          } else if (state.focalDelta.dy.abs() > 5) {
            _twoFingerOrbit = true;
          }
        }
        if (_twoFingerOrbit) {
          _look.peekPitchByDeltaY(state.focalDelta.dy);
        } else if (_twoFingerPinch) {
          _look.zoomByScale(scaleChange);
        }
      } else {
        _look.pan(state.focalDelta);
        _look.zoomByScale(scaleChange);
      }
      return;
    }

    if (_isMultiTouch) {
      _isMultiTouch = false;
      _twoFingerOrbit = false;
      _twoFingerPinch = false;
      _panZoomActive = false;
      _pinchSpanScale = 1;
      _look.endZoom();
      if (_springyLookPeek) _look.endPitchPeek();
      _maybeUnlockToolsAfterPointersUp();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FmScreen(
      backgroundColor:
          _isVolumeInterior ? const Color(0xFF050508) : _lighting.background,
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
                onIsolate: _isolateLookAt,
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
            child: GameFocusToolColumn(
              surface: _focusWorkSurface,
              paintExpanded: _paintGroupExpanded,
              onTogglePaintGroup: () => setState(() {
                _paintGroupExpanded = !_paintGroupExpanded;
              }),
              stickerExpanded: _stickerGroupExpanded,
              onToggleStickerGroup: () => setState(() {
                _stickerGroupExpanded = !_stickerGroupExpanded;
              }),
              paintActive: _paintTool,
              onTogglePaint: _togglePaint,
              fillActive: _fillTool,
              onToggleFill: _toggleFill,
              eraseActive: _eraseTool,
              onToggleErase: _toggleErase,
              paintColor: _paintColor,
              onPaintColor: (c) => setState(() => _paintColor = c),
              selectedSticker: _stickerPalette,
              onSelectSticker: _selectStickerKind,
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
          if (_selectedSticker != null &&
              _stickerDragHit == null &&
              _selectedStickerScreen != null)
            Positioned.fill(
              child: ObjectRadialMenu(
                center: _selectedStickerScreen!,
                actions: [
                  RadialAction(
                    icon: Icons.delete_outline,
                    label: 'Delete',
                    tint: const Color(0xFFEF5350),
                    side: RadialActionSide.bottom,
                    onTap: _deleteSelectedSticker,
                  ),
                ],
              ),
            ),
        ] else if (_isVolumeInterior) ...[
          FmSafePositioned(
            top: 48,
            right: 12,
            child: GameViewerBackButton(onPressed: _returnToMap3d),
          ),
          FmSafePositioned(
            top: 96,
            right: 12,
            child: GameVolumeInteriorSidebar(
              showExterior: _showVolumeExterior,
              onToggleExterior: () {
                setState(() => _showVolumeExterior = !_showVolumeExterior);
                _syncWorld();
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
          if (_worldEraserTool)
            FmSafePositioned(
              top: 48,
              right: 12,
              child: EraserFilterPanel(
                filter: _eraserFilter,
                onChanged: () {
                  _refreshHover();
                  setState(() {});
                },
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
          FmSafePositioned(
            bottom: 64,
            right: 12,
            child: ViewLockButton(
              locked: _viewLocked,
              onPressed: _toggleViewLock,
            ),
          ),
        ],
        if (_viewer == GameViewerKind.map3d && _selectedHit != null)
          FmSafePositioned(
            top: 200,
            left: 12,
            child: SelectionContextSidebar(
              title: _selectedHit!.kind.name,
              actions: inferSelectionActions(
                hit: _selectedHit!,
                volume: _selectedHit!.volumeId == null
                    ? null
                    : _volumes.volumeById(_selectedHit!.volumeId!),
                programs: _programs,
              ),
              onAction: _onSelectionAction,
            ),
          ),
        if (_devToolsOpen)
          FmSafePositioned(
            bottom: 196,
            right: 12,
            child: DevToolsPanel(
              showGizmos: _gizmoMode,
              onShowGizmosChanged: _setGizmoMode,
              onPlaceCubeboy: _placeCubeboy,
              nightSwatchId: _nightSwatch.id,
              onNightSwatchChanged: _setNightSwatch,
              dayNightProgress: _dayNightProgress,
              onDayNightProgressChanged: _setDayNightProgress,
              closeZoom: _look.minDistance,
              onCloseZoomChanged: _setCloseZoom,
              springyLookPeek: _springyLookPeek,
              onSpringyLookPeekChanged: _setSpringyLookPeek,
              perf: _perf,
              onPerfChanged: _onPerfChanged,
            ),
          ),
        FmSafePositioned(
          bottom: 148,
          right: 12,
          child: DevToolsButton(
            active: _devToolsOpen,
            onPressed: () => setState(() => _devToolsOpen = !_devToolsOpen),
          ),
        ),
        if (_viewer == GameViewerKind.map3d)
          FmSafePositioned(
            bottom: 68,
            left: 0,
            right: 0,
            child: GameToolCarousel(
              selected: _mapTool,
              onSelect: _setMapTool,
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
                final dy = -signal.scrollDelta.dy;
                if (_isPlane2d &&
                    !_viewerAnim.isAnimating &&
                    _planeLook != null) {
                  if (_planeLook!.zoomByScroll(dy)) {
                    _returnToMap3d();
                  }
                } else if (_isOrbitViewer &&
                    !_viewerAnim.isAnimating &&
                    _orbit != null) {
                  final orbit = _orbit!;
                  final factor = math.exp(dy * orbit.zoomSensitivity);
                  if (factor > 1 && orbit.radius * factor > orbit.maxDistance) {
                    _returnToMap3d();
                  } else {
                    orbit.zoomByScroll(dy);
                  }
                } else if (_viewer == GameViewerKind.map3d) {
                  _look.zoomByScroll(dy);
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
                    gridMotif: _layers.shows(SceneLayer.paths)
                        ? _pathGrid
                        : null,
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
                      selectedVolumeId: _selectedSticker?.doorVolumeId,
                      selectedTx: _selectedSticker?.doorTx,
                      selectedTy: _selectedSticker?.doorTy,
                      selectedSide: _selectedSticker?.doorSide,
                      selectedInvalid: _selectedSticker?.loose == true &&
                          _looseSticker?.kind == FocusStickerKind.door &&
                          _looseSticker?.valid == false,
                      draftCorners: _looseDoorCorners,
                      draftInvalid: _looseSticker?.kind == FocusStickerKind.door &&
                          _looseSticker?.valid == false,
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
                if (_flatmateRouteOverlay != null)
                  Positioned.fill(
                    child: FlatmatePathOverlay(
                      tiles: _flatmateRouteOverlay!.$1,
                      grid: _volumes.grid,
                      camera: _camera,
                      viewport: _viewportSize,
                      color: _flatmateRouteOverlay!.$2,
                      listenable: _scene,
                    ),
                  ),
                if (_showGizmos && _gizmoSelected is VolumeGizmoTarget)
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
                    !_isOrbitViewer &&
                    _layers.shows(SceneLayer.volumeTools) &&
                    _volumeFocused)
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: _toolsBlocked,
                      child: ListenableBuilder(
                        listenable: _scene,
                        builder: (context, _) {
                          return VolumeTransformGizmo(
                            store: _volumes,
                            camera: _camera,
                            viewport: _viewportSize,
                            onDragStart: _onHandleDragStart,
                            onDragUpdate: _onHandleDragUpdate,
                            onDragEnd: _onHandleDragEnd,
                          );
                        },
                      ),
                    ),
                  ),
                if (_layers.shows(SceneLayer.volumes) &&
                    (_interiorFocus ||
                        _tileWorkFocus ||
                        _programs.stamps.isNotEmpty ||
                        _looseSticker != null))
                  Positioned.fill(
                    child: VolumeProgramOverlay(
                      programs: _programs,
                      volumes: _volumes,
                      camera: _camera,
                      viewport: _viewportSize,
                      listenable: _scene,
                      volumeId: _interiorFocus ? _programVolumeId : null,
                      selectedId: _selectedSticker?.stampId,
                      selectedInvalid: _selectedSticker?.loose == true &&
                          _looseSticker != null &&
                          _looseSticker!.kind != FocusStickerKind.door &&
                          !_looseSticker!.valid,
                      draftCorners: _looseProgramCorners,
                      draftInvalid: _looseSticker != null &&
                          _looseSticker!.kind != FocusStickerKind.door &&
                          !_looseSticker!.valid,
                      draftKind: _looseSticker == null
                          ? null
                          : programKindForSticker(_looseSticker!.kind),
                    ),
                  ),
                if (_viewer == GameViewerKind.map3d &&
                    _worldEraserTool &&
                    !_erasePreview.isEmpty)
                  Positioned.fill(
                    child: SelectionHighlightOverlay(
                      hit: _erasePreview.hits.isEmpty
                          ? null
                          : _erasePreview.hits.first,
                      extraHits: _erasePreview.hits.length <= 1
                          ? const []
                          : _erasePreview.hits.sublist(1),
                      wallEdges: _erasePreview.walls,
                      volumes: _volumes,
                      friends: _friends,
                      camera: _camera,
                      viewport: _viewportSize,
                      listenable: _scene,
                      tileSize: _tileWorld,
                      style: SelectionHighlightStyle.delete,
                    ),
                  )
                else if (_viewer == GameViewerKind.map3d &&
                    (_hoverHit != null || _selectedHit != null))
                  Positioned.fill(
                    child: SelectionHighlightOverlay(
                      hit: _hoverHit ?? _selectedHit,
                      volumes: _volumes,
                      friends: _friends,
                      camera: _camera,
                      viewport: _viewportSize,
                      listenable: _scene,
                      tileSize: _tileWorld,
                    ),
                  ),
                if (_isMapUnlocked && _isPlaceTool && !_editing)
                  Positioned.fill(
                    child: PlacementGhostOverlay(
                      kind: _mapTool == GameMapTool.wall && _lookSplitsPath
                          ? PlacementGhostKind.pathSplit
                          : switch (_mapTool) {
                              GameMapTool.select => PlacementGhostKind.volume,
                              GameMapTool.volume => PlacementGhostKind.volume,
                              GameMapTool.path => PlacementGhostKind.path,
                              GameMapTool.wall => PlacementGhostKind.wall,
                              GameMapTool.delete => PlacementGhostKind.delete,
                            },
                      grid: _volumes.grid,
                      camera: _camera,
                      viewport: _viewportSize,
                      tile: _volumes.grid.tileAtWorld(_look.lookAt),
                      wallEdge: _walls.hitEdgeAtMidpoint(_look.lookAt),
                      listenable: _scene,
                      color: _mapTool == GameMapTool.wall && _lookSplitsPath
                          ? const Color(0xCCEF5350)
                          : const Color(0x99B3E5FC),
                    ),
                  ),
                if (_isMapUnlocked)
                  const Positioned.fill(child: ViewCrosshair()),
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

class _FocusStickerSel {
  const _FocusStickerSel.program(this.stampId)
      : doorVolumeId = null,
        doorTx = null,
        doorTy = null,
        doorSide = null,
        loose = false;

  const _FocusStickerSel.door({
    required int volumeId,
    required int tx,
    required int ty,
    required VolumeSide side,
  })  : stampId = null,
        doorVolumeId = volumeId,
        doorTx = tx,
        doorTy = ty,
        doorSide = side,
        loose = false;

  const _FocusStickerSel.loose()
      : stampId = null,
        doorVolumeId = null,
        doorTx = null,
        doorTy = null,
        doorSide = null,
        loose = true;

  final int? stampId;
  final int? doorVolumeId;
  final int? doorTx;
  final int? doorTy;
  final VolumeSide? doorSide;
  final bool loose;
}

class _LooseSticker {
  _LooseSticker({
    required this.kind,
    required this.world,
    required this.valid,
  });

  final FocusStickerKind kind;
  final Vector3 world;
  final bool valid;
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
