import '../protoplane/drawing_graph.dart';
import '../asmr/asmr_desk_chrome.dart' show AsmrMarqueePainter;
import '../gridcraft/edit.dart' show marqueePick;
import '../protoplane/drawing_visibility.dart';
import '../protoplane/construction.dart';
import '../rendering/scene/scene_hit_tester.dart';
import '../protoplane/construction_toolbar.dart';
import '../protoplane/parcels.dart';
import '../protoplane/parcel_overlay.dart';
import '../protoplane/geometry_benchmark.dart';
import '../protoplane/adjacent_grid_indicators.dart';
import '../protoplane/crumpled_paper.dart';
import '../protoplane/focus_context.dart';
import '../gestures/stroke_reversal.dart';
import '../protoplane/safe_zone.dart';
import '../protoplane/pencil_rendering.dart';
import '../protoplane/pencil_ink_effects.dart';
import '../protoplane/pencil.dart';
import '../protoplane/pencil_dwell.dart';
import 'dart:async';
import 'package:flutter/scheduler.dart';
import '../protoplane/graphite_pop_effects.dart';
import 'dart:ui' as ui;
import '../landscape/color_texture_catalog.dart';
import 'package:flutter/services.dart';
import '../protoplane/completion.dart';
import '../protoplane/paper_effects.dart';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../geometry/geometry.dart';
import '../gestures/game_controls.dart';
import '../gestures/gesture_debug.dart';
import '../protoplane/controller.dart';
import '../protoplane/fog_overlay.dart';
import '../protoplane/geometry.dart';
import '../protoplane/meshes.dart';
import '../protoplane/harvest_meshes.dart';
import '../protoplane/models.dart';
import '../protoplane/plane_navigation.dart';
import '../rendering/surface_edge_shading.dart';
import '../protoplane/storage.dart';
import '../protoplane/stroke_preview.dart';
import '../protoplane/wall_reveal.dart';
import '../protoplane/dev_settings.dart';
import '../ui/game/dev_tools_button.dart';
import '../protoplane/bedrooms.dart';
import '../protoplane/residents.dart';
import '../protoplane/housing.dart';
import '../protoplane/room_geometry.dart';
import '../ui/game/friend_eye_overlay.dart';
import '../gameplay/day_night/day_night_lighting.dart';
import '../rendering/mesh.dart';
import '../rendering/scene/camera.dart';
import '../rendering/scene/map_look_camera_controller.dart';
import '../rendering/scene/scene.dart';
import '../rendering/scene_view.dart';
import '../ui/game/game_tool_sidebar.dart';
import '../ui/game/view_crosshair.dart';
import '../ui/game/volume_transform_gizmo.dart' show axisDragDelta;

part 'protoplane_focus_tools.dart';
part 'protoplane_surface_view.dart';
part 'protoplane_room_camera.dart';

class ProtoplaneConceptView extends StatefulWidget {
  const ProtoplaneConceptView({
    super.key,
    this.controller,
    this.storage,
    this.entryFocusLevel,
    this.animateFog = true,
  });
  final bool animateFog;
  final double? entryFocusLevel;
  final ProtoplaneController? controller;
  final ProtoplaneStorage? storage;
  @override
  State<ProtoplaneConceptView> createState() => _ProtoplaneConceptViewState();
}

class _Pose {
  _Pose(Camera camera)
    : position = Vector3.copy(camera.position),
      target = camera.target,
      up = camera.up,
      fov = camera.fovDegrees;
  _Pose.at(this.position, this.target, this.up, this.fov);
  final Vector3 position, target, up;
  final double fov;
}

class _Hit {
  const _Hit(this.plane, this.object, this.distance);
  final String plane;
  final String? object;
  final double distance;
  String get id => object ?? plane;
}

class _ProtoplaneConceptViewState extends State<ProtoplaneConceptView>
    with TickerProviderStateMixin {
  final Map<int, Offset> _focusTouches = {};
  final List<int> _focusPath = [];
  Offset? _eraseStart, _eraseEnd, _focusLiveScreen;
  String? _focusGestureSurface, _constructionPreviewKey;
  bool _focusHadMultiple = false;
  ConstructionEvaluation? _constructionEvaluation;
  String? _createdEntityId, _aimedEntityName;
  Timer? _entityNameTimer, _residentTimer;
  String? _roomFocus;
  final Map<String, Set<String>> _sharedMeshRooms = {};
  String? _pinnedSurface;
  bool _selecting = false, _selectObjects = false;
  final List<_SurfacePick> _selection = [];
  Map<String, Path> _selectedPaths = {};
  String? _visiblePathsKey;
  Map<String, Path> _visiblePathsCache = {};
  final List<_SurfaceFocus> _surfaceFocus = [];
  Offset? _marqueeStart, _marqueeEnd;
  bool _surfaceMulti = false, _zoomExitConsumed = false;
  bool _isolateNavigation = false;
  List<Offset> _surfacePath = [], _fadingSurfacePath = [];
  String? _strokeSurface;
  Timer? _strokeFadeTimer, _zoomExitTimer;
  late final AnimationController _strokeFade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..addListener(_paintChanged);
  late final AnimationController _doorSwing = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  )..addListener(_paintDoorSwing);
  Set<String> _openDoorIds = {};
  Set<String> _swingingDoorIds = {};
  late final AnimationController _surfaceTransition = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );
  String? _currentRoom;
  int _roomZoomLevel = 0;
  bool _roomFrameScheduled = false, _roomZoomConsumed = false;
  double _roomPinch = 1;
  Timer? _roomWheelTimer;
  bool get _opening => !model.openingComplete && model.objects.isEmpty;
  bool get _surfaceDrawing =>
      model.constructionTool == ConstructionTool.volume ||
      model.constructionTool == ConstructionTool.scissors;

  String? _targetCacheKey;
  ({String planeId, DrawingSurface surface, Offset point})? _targetCache;
  CraftObject? _panelRoom;
  CraftPlane? _panelSource;
  List<RoomPanel> _panelCache = const [];
  List<RoomPanel> _focusedRoomPanels() {
    final room = model.objects[_roomFocus];
    if (room == null) return const [];
    final source = model.objectPlane(room);
    if (!identical(room, _panelRoom) || !identical(source, _panelSource)) {
      _panelRoom = room;
      _panelSource = source;
      _panelCache = roomPanels(room, source);
    }
    return _panelCache;
  }

  Timer? _backgroundTapTimer;
  Offset? _backgroundTapPoint;
  bool _exitingRoom = false;
  _Pose? _beforeRoom;
  ({Vector3 lookAt, double distance, double yaw})? _roomMapPose;
  late final AnimationController _roomReveal =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 350),
      )..addListener(() {
        if (!_disposed) {
          _applyHighlight();
          _paintChanged();
        }
      });

  bool get _focused => model.activePlane != null;
  bool get _drawingFocused =>
      _focused && model.constructionTool == ConstructionTool.pencil;
  bool get _placingConstruction =>
      model.constructionTool == ConstructionTool.paper ||
      model.constructionTool == ConstructionTool.fold;
  bool get _cameraUnlocked =>
      !_opening && !_drawingFocused && _surfacePath.isEmpty;
  void _updateFocusUi(VoidCallback action) => setState(action);
  late ProtoplaneController model;
  late ProtoplaneStorage storage;
  final devSettings = ProtoplaneSettings();
  int appliedProtoplaneCells = 1;
  late GridConnections appliedGridConnections = GridConnections.orthogonal;
  final settingsStore = ProtoplaneStorage(fileName: 'settings.json');
  String? settingsError;
  final _geometryBenchmark = GeometryBenchmark();
  late final Scene scene;
  late final GameControls controls;
  final residents = BedroomResidents();
  late final Camera camera;
  late final MapLookCameraController mapCamera;
  late final AnimationController transition,
      acetate,
      glow,
      extrusion,
      segmentGlow,
      closureWhite,
      releaseFade,
      pointGlow,
      contextFade,
      focusZoom;
  CraftPlane? contextPlane;
  final Map<String, double> contextOpacity = {}, baseOpacity = {};
  Set<String> focusedMeshIds = {};
  final Map<String, double> contextTransitionFrom = {};
  int appliedContextTiles = 2;
  double appliedSafeZoneFill = 1;
  final _viewportKey = GlobalKey(),
      _headerKey = GlobalKey(),
      _leftToolsKey = GlobalKey(),
      _rightToolsKey = GlobalKey(),
      _footerKey = GlobalKey();
  Rect? _safeZone, _devToolsRect;
  bool devToolsOpen = false;
  bool _safeZoneMeasurePending = false, _safeZoneRefocusPending = false;

  void _scheduleSafeZoneMeasure() {
    if (_safeZoneMeasurePending) return;
    _safeZoneMeasurePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _safeZoneMeasurePending = false;
      if (!mounted || _disposed) return;
      final root = _viewportKey.currentContext?.findRenderObject();
      if (root is! RenderBox || !root.hasSize) return;
      Rect? bounds(GlobalKey key) {
        final box = key.currentContext?.findRenderObject();
        if (box is! RenderBox || !box.hasSize || box.size.isEmpty) return null;
        return box.localToGlobal(Offset.zero, ancestor: root) & box.size;
      }

      final padding = MediaQuery.paddingOf(context);
      final header = bounds(_headerKey), footer = bounds(_footerKey);
      final left = padding.left + 12;
      final dockTop = (header?.bottom ?? padding.top + 64) + 8;
      final dockBottom = math.max(
        dockTop + 1,
        (footer?.top ?? viewport.height - padding.bottom - 12) - 8,
      );
      final dock = Rect.fromLTWH(
        left,
        dockTop,
        viewport.shortestSide < 600
            ? math.max(1, viewport.width - left - padding.right - 12)
            : 320,
        dockBottom - dockTop,
      );
      final dockChanged = _devToolsRect != dock;
      _devToolsRect = dock;
      final next = craftingSafeZone(
        viewport,
        header: header,
        left: devToolsOpen ? dock : bounds(_leftToolsKey),
        right: bounds(_rightToolsKey),
        footer: footer,
        insetLeft: padding.left,
        insetTop: padding.top,
        insetRight: padding.right,
        insetBottom: padding.bottom,
      );
      final previous = _safeZone;
      if (previous == null ||
          (previous.topLeft - next.topLeft).distance > .5 ||
          (previous.bottomRight - next.bottomRight).distance > .5) {
        _safeZone = next;
        _safeZoneRefocusPending = true;
        setState(() {});
      }
      if (dockChanged) setState(() {});
      if (_safeZoneRefocusPending &&
          model.activePlane != null &&
          !drawing &&
          !pulling &&
          !pencilDragging &&
          !model.erasing) {
        _safeZoneRefocusPending = false;
        _focusPlane();
      }
    });
  }

  late final PaperEffects paperEffects = PaperEffects(this)
    ..addListener(_effectsChanged);
  late final GraphitePops graphitePops = GraphitePops(this);
  late final List<(Offset, Offset)> _eraserSegments = [];
  Offset? _eraserLast;
  int? _eraserFrame;
  bool _eraserFeedback = false;
  int _effectEpoch = 0;
  bool _drawingReady = false;
  List<Offset> completedTrace = [];
  List<Offset> releasedTrace = [];
  double releasedWhite = 0;
  Offset? livePointer;
  int _lastStrokeLength = 0;
  final strokeShake = StrokeShake();
  bool strokeCancelled = false;
  late Map<int, double> dotFrom = {}, dotTo = {};
  String? dotGridKey;
  Map<int, double> get dotSelection {
    final t = Curves.easeOutCubic.transform(pointGlow.value);
    return {
      for (final i in {...dotFrom.keys, ...dotTo.keys})
        i: (dotFrom[i] ?? 0) + ((dotTo[i] ?? 0) - (dotFrom[i] ?? 0)) * t,
    };
  }

  double _depthFrom = 0, _depthTo = 0;
  CraftGrid? outgoingGrid;
  late final PageController gridPager;
  _Pose? from, to, worldPose, semiFocusPose, fullFocusPose;
  double focusScale = 1, displayedFocusScale = 1, zoomFromScale = 1;
  Vector3? mapLook;
  double mapDistance = 11, mapYaw = math.pi / 4;
  Size viewport = Size.zero;
  bool preview = false, loading = true, saving = false, loadFailed = false;
  bool _disposed = false;
  String? saveError, selectedObject;
  ui.Image? landscapePaperTexture;
  var harvestAtlas = HarvestMeshCache();
  CrumpledPaperResources? landscapeCrumple;
  bool pencilDragging = false;
  late final pencilDwell = PencilDwell(this, (from, to) {
    if (!pencilDragging ||
        model.tool != CraftTool.pencil ||
        !model.paperSurface) {
      return false;
    }
    final plane = model.activePlane!;
    final segments = List<PencilSegment>.of(_livePencilMarks());
    final committed = model.commitMarks([PencilSegment(from, to)]);
    if (committed) {
      pencilInk.playFill(
        plane,
        segments,
        reducedMotion: MediaQuery.disableAnimationsOf(context),
      );
    }
    return committed;
  })..addListener(_paintChanged);

  Offset? _pencilNode(Offset screen) {
    final plane = model.activePlane;
    if (plane == null || !model.paperSurface) return null;
    Offset? best;
    var distance = 24.0;
    for (final p in model.paperGrid.nodes) {
      if (!model.paperContains(p)) continue;
      final tail = pencilDwell.tail;
      if (tail != null &&
          (tail.dx - p.dx).abs() > geometryEpsilon &&
          (tail.dy - p.dy).abs() > geometryEpsilon) {
        continue;
      }
      final projected = camera.projectToScreen(plane.point(p, .008), viewport);
      if (projected == null) continue;
      final d = (projected - screen).distance;
      if (d < distance) {
        distance = d;
        best = p;
      }
    }
    return best;
  }

  Map<int, double> get _pencilDotSelection {
    final selection = pencilDwell.dotSelection;
    return {
      for (final (i, p) in (model.grid?.nodes ?? <Offset>[]).indexed)
        if ((selection[p] ?? 0) > .001) i: selection[p]!,
    };
  }

  Offset? _eraserPaperLast;
  final _eraserPaperSegments = <(Offset, Offset)>[];
  final pencilTextures = PencilTextureCache();
  late final pencilInk = PencilInkEffects(this)..addListener(_paintChanged);
  final edgeShading = SurfaceEdgeShadingCache();
  Timer? harvestNoticeTimer;
  Map<PaperColor, int>? harvestNotice;
  final Map<int, Offset> pointers = {};
  final planeSwipe = PlaneSwipe();
  final gestureDebug = GestureDebug();
  bool appliedGestureDebug = false;
  final Set<int> multiMoved = {};
  Offset? down, previous;
  bool secondary = false,
      moved = false,
      drawing = false,
      pulling = false,
      multi = false;
  double lastSpan = 0, pinch = 1, pullStartDepth = 0;
  double trackpadScale = 1;
  bool trackpadActive = false;
  Vector3? pullPlane, pullHit;
  _Hit? hover;
  String? previousHover;
  DateTime? lastTap;
  Offset? lastTapAt;
  String? _lastPlane;
  final Map<String, Color> baseColors = {};

  @override
  void initState() {
    super.initState();
    controls = loadGameControls();
    unawaited(_loadLandscapePaper());
    model = widget.controller ?? ProtoplaneController();
    devSettings.parcelSize = model.parcels.size;
    model.enableInPlaceDrawing();
    model.constructionTool = _opening ? ConstructionTool.volume : null;
    model.activePlaneId = _opening ? model.startingTile : null;
    _pinnedSurface = model.activePlaneId;
    storage = widget.storage ?? ProtoplaneStorage();
    camera = Camera(
      name: 'Protoplane',
      position: Vector3(.5, 4, -.5),
      target: Vector3(.5, 0, -.5),
      up: Vector3(0, 0, -1),
      fovDegrees: 50,
      near: .01,
    );
    final daylight = DayNightLighting.day();
    scene = Scene(globalIllumination: daylight.globalIllumination)
      ..camera = camera;
    scene.setLights(daylight.lights);
    mapCamera = MapLookCameraController(
      camera: camera,
      vsync: this,
      distance: _opening ? 2.5 : 8,
      lookAt: Vector3(.5, 0, -.5),
      pitch: math.pi / 2,
      minPitch: math.pi / 2,
      maxPitch: math.pi / 2,
      yaw: math.pi / 2,
      minDistance: 1.5,
      maxDistance: 25,
      ladderZoom: false,
      strictZoomBounds: true,
      boundsMin: Vector3(-4, 0, -4),
      boundsMax: Vector3(4, 0, 4),
    )..addListener(_cameraChanged);
    focusZoom =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 220),
        )..addListener(() {
          displayedFocusScale =
              zoomFromScale +
              (focusScale - zoomFromScale) *
                  Curves.easeOutCubic.transform(focusZoom.value);
          if (model.activePlane == null ||
              semiFocusPose == null ||
              fullFocusPose == null ||
              transition.isAnimating) {
            return;
          }
          final pose = _zoomFocusPose();
          camera.setPosition(pose.position);
          camera.setTarget(pose.target);
          camera.setUp(pose.up);
          camera.fovDegrees = pose.fov;
          scene.markNeedsPaint();
          setState(() {});
        });
    focusZoom.addStatusListener((status) {
      if (status == AnimationStatus.completed &&
          focusScale < .9 &&
          model.activePlane != null) {
        model.leave();
        pointers.clear();
        controls.cancel();
      }
    });
    transition =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 650),
          )
          ..addListener(_animateCamera)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed &&
                contextTransitionFrom.isNotEmpty) {
              contextTransitionFrom.clear();
              if (!_disposed) _refreshScene();
            }
          });
    acetate = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      value: 1,
    )..addListener(_paintChanged);
    glow =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 220),
          value: 1,
        )..addListener(() {
          _applyHighlight();
          _paintChanged();
        });
    extrusion =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 360),
          value: 1,
        )..addListener(() {
          if (!_disposed) _refreshScene();
        });
    gridPager = PageController(viewportFraction: .68, keepPage: false);
    model.addListener(_modelChanged);
    pointGlow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
      value: 1,
    )..addListener(_paintChanged);
    closureWhite = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..addListener(_paintChanged);
    releaseFade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
      value: 1,
    )..addListener(_paintChanged);
    segmentGlow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      value: 1,
    )..addListener(_paintChanged);
    controls.addListener(_controlsChanged);
    contextFade =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 650),
          )
          ..addListener(_applyHighlight)
          ..addStatusListener((status) {
            if (status == AnimationStatus.dismissed) contextPlane = null;
            if (!_disposed &&
                (status == AnimationStatus.completed ||
                    status == AnimationStatus.dismissed)) {
              _refreshScene();
            }
          });
    _residentTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_disposed || model.housing.tenants.isEmpty) return;
      residents.tickHousing(scene, .1);
      _applyHighlight();
      scene.markNeedsPaint();
    });
    model.onCommitted = _save;
    _configureOrbit();
    _lastDiscoveryTarget = Offset(mapCamera.lookAt.x, -mapCamera.lookAt.z);
    _refreshScene();
    if (widget.controller != null && widget.storage == null) {
      loading = false;
      model.onCommitted = null;
    } else {
      unawaited(_initializeWorld());
    }
  }

  Future<void> _initializeWorld() async {
    if (widget.controller == null) {
      await _loadDevSettings();
      if (!mounted) return;
    }
    await _load();
  }

  Future<void> _loadLandscapePaper() async {
    final image = await ColorTextureCatalog.load(ColorTextureCatalog.white);
    if (!mounted) {
      image?.dispose();
      return;
    }
    landscapePaperTexture = image;
    final crumple = await CrumpledPaperResources.load();
    if (!mounted) return;
    landscapeCrumple = crumple;
    harvestAtlas.setCrumpledPaper(crumple);
    harvestAtlas.setPaperTexture(image);
    _refreshScene();
    setState(() {});
  }

  Future<void> _loadDevSettings() async {
    try {
      final json = await settingsStore.load(
        (j) => ProtoplaneSettings()..load(j),
      );
      if (!mounted) return;
      if (json != null) devSettings.load(json);
      model.drawingImplement = DrawingImplement.pencil;
      model.lastDrawingImplement = DrawingImplement.pencil;
      settingsError = null;
      _applyDevSettings();
    } catch (_) {
      if (mounted) setState(() => settingsError = 'Could not load settings');
    }
  }

  bool get _parcelShopping =>
      !_geometryBenchmark.active &&
      model.activePlane == null &&
      !transition.isAnimating &&
      mapCamera.distance >= devSettings.parcelZoomNear &&
      mapCamera.distance <= devSettings.parcelZoomFar;

  ParcelId? _parcelAt(Offset screen) {
    if (viewport.isEmpty) return null;
    final ray = camera.unprojectRay(screen, viewport);
    if (ray == null) return null;
    final point = Camera.intersectPlane(
      ray: ray,
      point: Vector3.zero(),
      normal: Vector3(0, 1, 0),
    );
    if (point == null) return null;
    final id = model.parcels.at(Offset(point.x, -point.z));
    return model.parcels.visible(model.landscape.terrain).contains(id)
        ? id
        : null;
  }

  Offset? _lastDiscoveryTarget;
  void _configureOrbit() {
    mapCamera.strictZoomBounds = true;
    mapCamera.setDistanceLimits(
      1.5,
      devSettings.farthestDistance,
      applyPose: false,
    );
    if (_geometryBenchmark.active) {
      final half = _geometryBenchmark.side / 2;
      mapCamera.setPanBounds(
        Vector3(-half, 0, -half),
        Vector3(half, 0, half),
        applyPose: false,
      );
      return;
    }
    final areas = model.areas.values;
    if (areas.isNotEmpty) {
      final bounds = areas
          .map((a) => a.bounds)
          .reduce((a, b) => a.expandToInclude(b))
          .inflate(2);
      mapCamera.setPanBounds(
        Vector3(bounds.left, 0, -bounds.bottom),
        Vector3(bounds.right, 0, -bounds.top),
        applyPose: false,
      );
    } else {
      mapCamera.setPanBounds(
        Vector3(-4, 0, -4),
        Vector3(4, 0, 4),
        applyPose: false,
      );
    }
  }

  void _toggleDevTools() {
    _resetPointGestures();
    if (drawing || pulling || model.erasing || model.harvestPending) {
      model.cancelGesture();
    }
    pencilDwell.cancel();
    model.cancelPencil();
    pencilDragging = drawing = pulling = false;
    livePointer = null;
    setState(() => devToolsOpen = !devToolsOpen);
    _scheduleSafeZoneMeasure();
  }

  void _panFocused(Offset start, Offset end) {
    final a = _local(start), b = _local(end), plane = model.activePlane;
    if (a == null || b == null || plane == null) return;
    final delta = plane.point(a) - plane.point(b);
    camera.setPosition(camera.position + delta);
    camera.setTarget(camera.target + delta);
    _Pose? shift(_Pose? pose) => pose == null
        ? null
        : _Pose.at(
            pose.position + delta,
            pose.target + delta,
            pose.up,
            pose.fov,
          );
    semiFocusPose = shift(semiFocusPose);
    fullFocusPose = shift(fullFocusPose);
    scene.markNeedsPaint();
    setState(() {});
  }

  void _applyDevSettings() {
    if (!loading) model.setParcelSize(devSettings.parcelSize);
    model.setImpliedProtoplanes(devSettings.impliedProtoplanes);
    _configureOrbit();
    if (model.activePlane == null && !transition.isAnimating) {
      mapCamera.restorePose(
        lookAt: mapCamera.lookAt,
        distance: mapCamera.distance,
        yaw: mapCamera.yaw,
      );
    }
    if (appliedGestureDebug != devSettings.showGestureDebug) {
      appliedGestureDebug = devSettings.showGestureDebug;
      gestureDebug.clear();
    }
    if (appliedContextTiles != devSettings.focusContextTiles ||
        appliedSafeZoneFill != devSettings.safeZoneFill) {
      appliedSafeZoneFill = devSettings.safeZoneFill;
      appliedContextTiles = devSettings.focusContextTiles;
      if (model.activePlane != null) _focusPlane();
    }
    if (appliedGridConnections != devSettings.gridConnections) {
      appliedGridConnections = devSettings.gridConnections;
      _resetPointGestures();
      drawing = pulling = false;
      livePointer = null;
      model.setProtoplaneConnections(devSettings.gridConnections);
    }
    if (appliedProtoplaneCells != devSettings.protoplaneCells) {
      appliedProtoplaneCells = devSettings.protoplaneCells;
      _resetPointGestures();
      drawing = pulling = false;
      livePointer = null;
      model.setProtoplaneCells(devSettings.protoplaneCells);
      _refreshScene();
    }
    final lighting = DayNightLighting.day().copyWith(
      globalIllumination: devSettings.ambient,
      keyIntensity: devSettings.sun,
    );
    scene.globalIllumination = lighting.globalIllumination;
    scene.setLights(lighting.lights);
    _refreshScene();
    setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      saveError = null;
    });
    try {
      final json = await storage.load((j) {
        final validator = ProtoplaneController();
        try {
          validator.load(j);
        } finally {
          validator.dispose();
        }
      });
      if (!mounted) return;
      if (json != null) model.load(json);
      if (_opening) {
        model.constructionTool = ConstructionTool.volume;
        model.activePlaneId = model.startingTile;
        _pinnedSurface = model.startingTile;
        mapCamera.restorePose(
          lookAt: Vector3(.5, 0, -.5),
          distance: 2.5,
          yaw: math.pi / 2,
        );
      } else {
        model.constructionTool = null;
        model.activePlaneId = null;
        _pinnedSurface = null;
      }
      _refreshScene();
      if (json?['parcels'] != null) {
        devSettings.parcelSize = model.parcels.size;
      } else {
        model.setParcelSize(devSettings.parcelSize);
      }
      loadFailed = false;
      saveError = storage.recoveryMessage;
    } catch (_) {
      if (!mounted) return;
      loadFailed = true;
      saveError = 'Could not load world. Saved files were retained.';
    }
    if (mounted) {
      setState(() {
        loading = false;
      });
    }
  }

  Future<void> _clearSavedWorld() async {
    if (loading) return;
    setState(() {
      loading = true;
      saveError = null;
    });
    _resetPointGestures();
    _cancelFocusStroke();
    drawing = pulling = false;
    livePointer = null;
    model.constructionTool = null;
    final committed = model.onCommitted;
    model.onCommitted = null;
    try {
      model.clearWorld();
      if (widget.controller == null || widget.storage != null) {
        await storage.reset(model.toJson());
      }
      if (!mounted) return;
      loadFailed = false;
      saveError = null;
    } catch (_) {
      if (!mounted) return;
      loadFailed = true;
      saveError = 'Could not clear saved world. Try Clear world again.';
    } finally {
      if (mounted) {
        model.onCommitted = committed;
        setState(() => loading = false);
      }
    }
  }

  int pendingSaves = 0;
  void _save(Map<String, dynamic> json) {
    pendingSaves++;
    if (mounted) {
      setState(() {
        saving = true;
      });
    }
    unawaited(
      storage
          .save(json)
          .then((_) {
            if (mounted) {
              setState(() {
                saveError = null;
              });
            }
          })
          .catchError((Object _) {
            if (mounted) {
              setState(() {
                saveError = 'Could not save world';
              });
            }
          })
          .whenComplete(() {
            pendingSaves--;
            if (mounted) {
              setState(() {
                saving = pendingSaves > 0;
              });
            }
          }),
    );
  }

  void _effectsChanged() {
    if (_disposed) return;
    final hidden = paperEffects.hiddenIds;
    for (final mesh in scene.meshes) {
      mesh.visible = !hidden.any(
        (id) => mesh.id == id || mesh.id.startsWith('$id-'),
      );
    }
    scene.markNeedsPaint();
    if (mounted) setState(() {});
  }

  void _queueEraser(Offset screen) {
    final local = _localOn(model.eraserPlane, screen);
    if (local == null || !model.erasing) return;
    _eraserSegments.add((_eraserLast ?? local, local));
    _eraserLast = local;
    final paper = _local(screen);
    if (paper != null) {
      _eraserPaperSegments.add((_eraserPaperLast ?? paper, paper));
      _eraserPaperLast = paper;
    }
    _eraserFrame ??= SchedulerBinding.instance.scheduleFrameCallback((_) {
      _eraserFrame = null;
      _flushEraser();
    });
  }

  void _flushEraser() {
    if (!mounted || !model.erasing || _eraserSegments.isEmpty) return;
    final segments = List<(Offset, Offset)>.of(_eraserSegments);
    _eraserSegments.clear();
    final markSegments = List<(Offset, Offset)>.of(_eraserPaperSegments);
    _eraserPaperSegments.clear();
    final plane = model.eraserPlane!;
    final pieces = model.eraseStroke(segments, markSegments: markSegments);
    if (pieces.isEmpty) return;
    if (!MediaQuery.disableAnimationsOf(context)) {
      graphitePops.add(plane, pieces);
    }
    harvestNotice = Map.of(model.lastHarvest!);
    if (!_eraserFeedback && devSettings.haptics) {
      _eraserFeedback = true;
      unawaited(HapticFeedback.selectionClick().catchError((Object _) {}));
    }
  }

  void _resetEraser({bool clearEffects = false}) {
    if (_eraserFrame != null) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(_eraserFrame!);
    }
    _eraserFrame = null;
    _eraserSegments.clear();
    _eraserLast = null;
    _eraserPaperLast = null;
    _eraserPaperSegments.clear();
    _eraserFeedback = false;
    if (clearEffects) graphitePops.clear();
  }

  void _modelChanged() {
    if (_disposed) return;
    _validateSurfaceContext();
    if (!model.objects.containsKey(_currentRoom)) _currentRoom = null;
    _scheduleRoomFrame();
    final doors = {
      for (final room in model.objects.values)
        for (final o in room.openings)
          if (o.kind == 'door' && o.isFlap) o.id!,
    };
    final newDoors = doors.difference(_openDoorIds);
    _openDoorIds = doors;
    if (newDoors.isNotEmpty) {
      _swingingDoorIds = newDoors;
      _doorSwing.duration = MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 350);
      _doorSwing.forward(from: 0);
    }
    _targetCacheKey = null;
    if (_roomFocus != null &&
        model.objects[_roomFocus]?.kind != CraftKind.room) {
      _roomFocus = null;
      _roomReveal.stop();
      _roomReveal.value = 0;
      final map = _roomMapPose, pose = _beforeRoom;
      if (map != null) {
        mapCamera.restorePose(
          lookAt: map.lookAt,
          distance: map.distance,
          yaw: map.yaw,
        );
      }
      if (pose != null) {
        camera.setPosition(pose.position);
        camera.setTarget(pose.target);
        camera.setUp(pose.up);
        camera.fovDegrees = pose.fov;
      }
      _constructionEvaluation = null;
      _constructionPreviewKey = null;
    }
    if ((model.tool != CraftTool.pencil || model.selectedMotif != null) &&
        pencilDwell.tail != null) {
      pencilDwell.cancel();
    }
    if (model.pencilPreviewUpdate) {
      setState(() {});
      return;
    }
    if (_placingConstruction) {
      _constructionPreviewKey = null;
      _previewConstruction();
    }
    if (model.motifNotices.isNotEmpty) {
      final notices = List<PencilMotif>.of(model.motifNotices);
      model.motifNotices.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        for (final motif in notices) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  CustomPaint(
                    size: const Size(32, 32),
                    painter: _MotifThumbnail(motif),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text('motif discovered · ${motif.label}')),
                ],
              ),
            ),
          );
        }
      });
    }

    if (_effectEpoch != model.presentationEpoch ||
        _lastPlane != model.activePlaneId) {
      paperEffects.clear();
      pencilInk.clear();
      pencilDwell.cancel();
      _resetEraser(clearEffects: true);
      _effectEpoch = model.presentationEpoch;
    }
    if (!model.erasing && _eraserLast != null) {
      _resetEraser(clearEffects: model.lastHarvest == null);
    }
    _configureOrbit();
    _drawingReady = model.drawingReady;
    if (drawing) {
      closureWhite.animateTo(
        model.closed && _drawingReady ? 1 : 0,
        curve: Curves.easeOut,
      );
    }
    if (model.lastHarvest == null) harvestNotice = null;
    final path = model.draft.path;
    final selected = path.toSet();
    if (dotGridKey != model.draftKey) {
      dotFrom = {};
      dotTo = {for (final i in selected) i: 1};
      dotGridKey = model.draftKey;
      pointGlow.value = 1;
      _resetPointGestures();
    } else if (selected.length != dotTo.length ||
        selected.any((i) => !dotTo.containsKey(i))) {
      dotFrom = dotSelection;
      dotTo = {for (final i in selected) i: 1};
      pointGlow.forward(from: 0);
    }
    final length = path.length;
    if (drawing && length > _lastStrokeLength && length > 1) {
      segmentGlow.forward(from: 0);
    }
    _lastStrokeLength = length;
    final depth = model.previewObject?.depth ?? 0;
    if ((depth - _depthTo).abs() > .0001) {
      _depthFrom = _depthTo;
      _depthTo = depth;
      if (!pulling && depth > _depthFrom) {
        extrusion.forward(from: 0);
      } else {
        extrusion.value = 1;
      }
    }
    if (model.activePlane == null &&
        model.constructionTool == ConstructionTool.pencil) {
      model.constructionTool = null;
    }
    if (_lastPlane != model.activePlaneId) {
      _constructionEvaluation = null;
      _constructionPreviewKey = null;
      _cancelFocusStroke();
      final traversing =
          _lastPlane != null && model.activePlane != null && worldPose != null;
      contextTransitionFrom.clear();
      completedTrace = [];
      releasedTrace = [];
      releaseFade.value = 1;
      closureWhite.value = 0;
      focusZoom.stop();
      focusScale = displayedFocusScale =
          1 +
          (widget.entryFocusLevel ?? devSettings.entryFocusLevel).clamp(
            0.0,
            1.0,
          );
      semiFocusPose = fullFocusPose = null;
      if (model.activePlane != null) {
        contextPlane = model.activePlane;
        contextFade.forward();
      } else {
        contextFade.reverse();
      }
      if (model.activePlaneId != null && worldPose == null) {
        worldPose = _Pose(camera);
        mapCamera.pauseForHandoff();
      }
      _lastPlane = model.activePlaneId;
      if (model.activePlane == null) {
        // Claim the camera before another trackpad sample or gesture-end can
        // apply the map controller's pose. Waiting for layout makes that pose
        // become the animation's starting point, skipping the return motion.
        _restoreWorld();
      } else if (traversing && !viewport.isEmpty) {
        _focusPlane();
      } else {
        final planeId = model.activePlaneId;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              model.activePlaneId != planeId ||
              transition.isAnimating) {
            return;
          }
          if (gridPager.hasClients) gridPager.jumpToPage(model.gridIndex);
          _focusPlane();
        });
      }
    }
    _refreshScene();
    setState(() {});
  }

  void _paintChanged() {
    if (mounted) setState(() {});
  }

  void _controlsChanged() {
    if (_disposed) return;
    if (_roomFocus != null) _applyHighlight();
    _previewConstruction();
    _updateEntityHover();
    if (model.activePlane == null &&
        !viewport.isEmpty &&
        !transition.isAnimating) {
      _setHover(
        controls.showReticle && !_parcelShopping
            ? _pick(controls.worldAim(viewport))
            : null,
      );
    }
    setState(() {});
  }

  void _cameraChanged() {
    if (_disposed) return;
    _applyHighlight();
    _selectedPaths = {};
    if (_placingConstruction) {
      worldPose = _Pose(camera);
      _previewConstruction();
    }
    _updateEntityHover();
    scene.markNeedsPaint();
    if (!_geometryBenchmark.active &&
        model.activePlane == null &&
        !transition.isAnimating &&
        !loading) {
      final target = Offset(mapCamera.lookAt.x, -mapCamera.lookAt.z);
      if (_lastDiscoveryTarget != target) {
        _lastDiscoveryTarget = target;
        model.discoverAt(target);
      }
    }
    if (model.activePlane == null &&
        !transition.isAnimating &&
        !viewport.isEmpty) {
      _setHover(
        controls.showReticle && !_parcelShopping
            ? _pick(controls.worldAim(viewport))
            : null,
      );
    }
    if (mounted) setState(() {});
  }

  Mesh _planeMesh(CraftPlane plane) {
    final mesh = plane.id.startsWith('ground-')
        ? harvestAtlas.mesh(plane, model.landscape)
        : planeMesh(plane);
    if (model.isLandscapePaper(plane.id)) {
      pencilTextures.attach(
        [mesh],
        plane,
        plane.region,
        .001,
        model.marksOn(plane),
        opacity:
            !preview &&
                model.activePlaneId != null &&
                model.sameTerrainFocus(plane.id, model.activePlaneId!)
            ? .8
            : .35,
      );
    }
    return mesh;
  }

  List<Mesh> _objectMeshes(
    CraftObject object,
    CraftPlane plane, {
    double opacity = 1,
  }) {
    if (!_geometryBenchmark.active && !_ownsObject(object, plane)) return [];
    final surfaceId = 'surface-${object.id}';
    final canonical = model.surfaceFusion.canonical[surfaceId];
    // Editing a constituent still displays its original support geometry.
    if (canonical != null && model.editId == null) {
      if (canonical != surfaceId) return [];
      object = object.copyWith(region: model.planes[surfaceId]!.region);
    }
    final meshes = objectMeshes(object, plane, opacity: opacity);
    final surface = model.planes[surfaceId];
    if (surface != null && object.material == PaperMaterial.paperWhite) {
      final marks = model
          .marksOn(surface)
          .map((s) => s.map((p) => plane.local(surface.point(p))))
          .toList();
      pencilTextures.attach(
        meshes,
        plane,
        object.region,
        object.depth + .002,
        marks,
        opacity: model.activePlaneId == surfaceId && !preview ? .8 : .35,
      );
    }
    return meshes;
  }

  bool _ownsObject(CraftObject object, CraftPlane plane) {
    final center = plane.point(object.region.bounds.center);
    return model.parcels.owns(Offset(center.x, -center.z));
  }

  bool _parcelMeshVisible(Mesh mesh) {
    if (model.landscape.terrain.tiles.containsKey(mesh.id)) {
      return model.ownsTerrainTile(mesh.id);
    }
    if (mesh.id.startsWith('terrain-wall-')) {
      final id = mesh.id.substring('terrain-wall-'.length);
      if (model.landscape.terrain.tiles.containsKey(id)) {
        return model.ownsTerrainTile(id);
      }
      // Sheet-wide side/bottom meshes must not expose hidden terrain.
      return model.landscape.terrain.tiles.values
          .where((tile) => tile.sheet.id == id)
          .every((tile) => model.ownsTerrainTile(tile.id));
    }
    final plane = model.planes[mesh.id];
    if (plane != null) {
      final center = plane.point(plane.region.bounds.center);
      return model.parcels.owns(Offset(center.x, -center.z));
    }
    return true;
  }

  void _applyPhaseLighting() {
    final light = DayNightLighting.day().copyWith(
      globalIllumination:
          devSettings.ambient *
          (model.housing.phase == DayPhase.evening ? .57 : 1),
      keyIntensity: devSettings.sun,
      keyColor: model.housing.phase == DayPhase.evening
          ? const Color(0xffffbd80)
          : const Color(0xffffffff),
      keyDirection: model.housing.phase == DayPhase.afternoon
          ? Vector3(.6, -1, -.4)
          : Vector3(-.6, -1, -.4),
    );
    scene.globalIllumination = light.globalIllumination;
    scene.setLights(light.lights);
  }

  void _refreshScene() {
    _targetCacheKey = null;
    _applyPhaseLighting();
    pencilTextures.beginFrame();
    harvestAtlas.configureStyle(
      fill: devSettings.landscapeAppearance,
      grain: devSettings.paperTextureAppearance,
      strength: devSettings.paperTextureStrength,
      repeat: devSettings.paperTextureRepeat,
    );
    harvestAtlas.configureCrumple(
      strength: devSettings.foldStrength,
      scale: devSettings.foldScale,
      shadow: devSettings.bakedShadowIntensity,
      density: devSettings.foldDensity,
      distribution: devSettings.foldDistribution,
    );
    harvestAtlas.synchronize(model.planes.values, model.landscape);
    final meshes = <Mesh>[];
    meshes.addAll(harvestAtlas.walls(model.landscape.terrain));
    contextOpacity.clear();
    final active = model.activePlane;
    if (active == null) {
      meshes.addAll(
        model.planes.values
            .where(
              (p) =>
                  !p.id.startsWith('surface-') &&
                  !model.isPlane(p.id) &&
                  model.planeAvailable(p) &&
                  (model.surfaceFusion.canonical[p.id] ?? p.id) == p.id,
            )
            .map(_planeMesh),
      );
      // Ground tiles remain visible in their unoccupied portions.
      for (final p in model.planes.values.where(
        (p) => p.id.startsWith('ground-') && model.isPlane(p.id),
      )) {
        meshes.add(_planeMesh(p));
      }
      for (final o in model.objects.values) {
        final p = model.planes[o.planeId];
        if (p != null) meshes.addAll(_objectMeshes(o, p));
      }
    } else {
      if (_drawingFocused && !model.sharedLandscapeFocus) {
        meshes.add(_planeMesh(active)..groundPlane = true);
      }
      final edit = model.editId;
      for (final o in model.objects.values) {
        if (o.id == edit && !drawing) continue;
        final belongsToFloor =
            model.objects[active.owner]?.kind == CraftKind.floor &&
            (supportingFloor(o.id, model.objects, model.planes) ==
                    active.owner ||
                active.supports.contains(
                  supportingFloor(o.id, model.objects, model.planes),
                ));
        if (o.planeId == active.id ||
            model.sameTerrainFocus(o.planeId, active.id) ||
            o.id == active.owner ||
            (belongsToFloor &&
                sameFocusOrientation(
                  active,
                  model.planes[o.planeId]!,
                  upright: o.kind == CraftKind.screen,
                ))) {
          final existing = _objectMeshes(
            o,
            model.planes[o.planeId]!,
            opacity: 1,
          );
          if (o.id == active.owner) {
            for (final m in existing) {
              m.groundPlane = true;
            }
          }
          meshes.addAll(existing);
        }
      }
      var candidate = model.previewObject;
      if (candidate != null && extrusion.isAnimating) {
        candidate = candidate.copyWith(
          depth:
              _depthFrom +
              (_depthTo - _depthFrom) *
                  Curves.easeOutBack.transform(extrusion.value),
        );
      }
      if (candidate != null && !(drawing && model.tool == CraftTool.scissors)) {
        final cuts = model.cutObjects;
        if (cuts != null && edit != null) {
          for (var i = 0; i < cuts.length; i++) {
            meshes.addAll(
              _objectMeshes(
                cuts[i].copyWith(id: 'cut-$i'),
                active,
                opacity: .9,
              ),
            );
          }
        } else {
          meshes.addAll(
            _objectMeshes(
              candidate,
              model.objectPlane(candidate),
              opacity: preview ? 1 : .75,
            ),
          );
          for (final (i, part) in model.previewObjects.skip(1).indexed) {
            meshes.addAll(
              _objectMeshes(
                part.copyWith(id: 'preview-${i + 1}'),
                model.objectPlane(part),
                opacity: preview ? 1 : .75,
              ),
            );
          }
        }
      }
    }
    if (active != null) {
      final tile = model.landscape.terrain.tiles[active.id];
      if (tile != null) {
        for (final other in model.landscape.terrain.tiles.values.where(
          (t) => t.x == tile.x && t.y == tile.y && t.id != tile.id,
        )) {
          meshes.add(_planeMesh(model.planes[other.id]!));
        }
      }
    }
    if (active != null) {
      focusedMeshIds = meshes.map((m) => m.id).toSet();
      void addContext(Iterable<Mesh> additions, CraftPlane p) {
        for (final mesh in additions) {
          if (!focusedMeshIds.contains(mesh.id)) meshes.add(mesh);
        }
      }

      for (final p in model.planes.values.where(
        (p) =>
            !p.id.startsWith('surface-') &&
            model.planeAvailable(p) &&
            (model.surfaceFusion.canonical[p.id] ?? p.id) == p.id,
      )) {
        if (!focusedMeshIds.contains(p.id)) addContext([_planeMesh(p)], p);
      }
      for (final object in model.objects.values) {
        if (object.id != model.editId && !focusedMeshIds.contains(object.id)) {
          addContext(
            _objectMeshes(object, model.planes[object.planeId]!),
            model.planes[object.planeId]!,
          );
        }
      }
    }
    if (!_drawingFocused) {
      meshes.removeWhere(
        (m) =>
            model.planes.containsKey(m.id) &&
            !model.landscape.terrain.tiles.containsKey(m.id),
      );
    }
    for (final mesh in meshes) {
      mesh.cropBox = null;
    }
    final construction = _constructionEvaluation;
    if (construction != null &&
        construction.valid &&
        construction.tool != ConstructionTool.scissors) {
      for (final object in [construction.object!]) {
        meshes.addAll(
          _objectMeshes(
            object.copyWith(id: 'sticker-preview-${object.id}'),
            construction.frame!,
            opacity: .55,
          ),
        );
      }
    }
    if (construction?.valid == true &&
        construction!.tool == ConstructionTool.scissors) {
      final room = construction.object!;
      meshes.removeWhere(
        (m) => m.id == room.id || m.id.startsWith('${room.id}-'),
      );
      meshes.addAll(_objectMeshes(room, construction.frame!));
      final target = construction.target!;
      meshes.addAll(
        objectMeshes(
          CraftObject(
            id: 'sticker-preview-cut',
            planeId: target.planeId,
            kind: CraftKind.paperSheet,
            region: target.region,
            depth: .002,
          ),
          target.surface.frame,
          opacity: .4,
        ),
      );
    }
    if (!_geometryBenchmark.active) {
      meshes.removeWhere((mesh) => !_parcelMeshVisible(mesh));
    }
    if (_geometryBenchmark.active) {
      meshes.add(_geometryBenchmark.ground);
      meshes.addAll(_geometryBenchmark.meshes);
    }
    if (_opening) meshes.removeWhere((m) => m.id != model.startingTile);
    // Landscape is an invisible support plane; only its authoritative pips
    // are presented. Keep its planes in the model for picking and ownership.
    meshes.removeWhere(
      (m) => m.id.startsWith('ground-') || m.id.startsWith('terrain-wall-'),
    );
    _replaceSharedWallMeshes(meshes);
    for (final mesh in meshes) {
      final room = model.objects.values
          .where(
            (o) =>
                o.kind == CraftKind.room &&
                mesh.id.startsWith('${o.id}-floor-'),
          )
          .firstOrNull;
      if (room?.roomColor != null) {
        mesh.material = MaterialModel(
          color: Color.lerp(
            Color(room!.roomColor!),
            room.id == _currentRoom ? Colors.white : Colors.black,
            room.id == _currentRoom ? .15 : .1,
          )!,
          doubleSided: true,
          opacity: mesh.material.opacity,
        );
      }
    }
    baseOpacity
      ..clear()
      ..addEntries(meshes.map((m) => MapEntry(m.id, m.material.opacity)));
    baseColors
      ..clear()
      ..addEntries(meshes.map((m) => MapEntry(m.id, m.material.color)));
    edgeShading.synchronize(meshes);
    scene.setMeshes(meshes);
    if (model.housing.tenants.isNotEmpty) {
      residents.syncHousing(scene, model);
    } else {
      residents.sync(
        scene,
        model.bedrooms.where((room) {
          final floor = model.objects[room.floorId];
          final plane = floor == null ? null : model.planes[floor.planeId];
          return floor != null && plane != null && _ownsObject(floor, plane);
        }).toList(),
        model.objects,
        model.planes,
      );
    }
    final craftedIds = meshes.map((m) => m.id).toSet();
    for (final m in scene.meshes) {
      if (!craftedIds.contains(m.id)) {
        final source = m.material;
        final color = source.color;
        final gray = (.2126 * color.r + .7152 * color.g + .0722 * color.b);
        m.material = MaterialModel(
          color: Color.from(alpha: color.a, red: gray, green: gray, blue: gray),
          doubleSided: source.doubleSided,
          strokeEdges: source.strokeEdges,
          opacity: source.opacity,
        );
      }
      baseColors.putIfAbsent(m.id, () => m.material.color);
    }
    _effectsChanged();
    _applyHighlight();
    if (_doorSwing.isAnimating) _paintDoorSwing();
    _updateEntityHover();
  }

  void _applyHighlight() {
    final focusedPanels = _focusedRoomPanels();
    for (final mesh in scene.meshes) {
      final current =
          mesh.id == hover?.id || mesh.id.startsWith('${hover?.id}-');
      final old =
          mesh.id == previousHover || mesh.id.startsWith('$previousHover-');
      final strength = current
          ? glow.value
          : old
          ? 1 - glow.value
          : 0.0;
      final isLandscape =
          mesh.id.startsWith('ground-') || mesh.id.startsWith('terrain-wall-');
      final isCrafted =
          model.objects.keys.any(
            (id) => mesh.id == id || mesh.id.startsWith('$id-'),
          ) ||
          mesh.id == 'preview' ||
          mesh.id.startsWith('cut-') ||
          (!isLandscape && model.planes.containsKey(mesh.id));
      mesh.appearanceFilter = isLandscape
          ? null
          : isCrafted
          ? devSettings.craftedAppearance.filter
          : null;
      final original = mesh.material;
      var opacity = mesh.id.startsWith('friend_')
          ? 1.0
          : baseOpacity[mesh.id] ?? original.opacity;
      if (mesh.id.contains('-roof-')) opacity = 0;
      if (_surfaceFocus.isNotEmpty && !_surfaceMeshVisible(mesh.id)) {
        opacity *= 1 - _roomReveal.value;
      }
      if (_roomFocus != null &&
          _roomReveal.value > 0 &&
          _surfaceFocus.isEmpty) {
        var belongs = mesh.id.startsWith('sticker-preview-');
        final object = model.objects.values
            .where((o) => mesh.id == o.id || mesh.id.startsWith('${o.id}-'))
            .firstOrNull;
        if (object != null) {
          belongs =
              object.id == _roomFocus ||
              model.objectPlane(object).roomId == _roomFocus;
        }
        for (final tenant in model.housing.tenants.values) {
          if (tenant.roomId == _roomFocus &&
              mesh.id.startsWith('friend_${tenant.id}_')) {
            belongs = true;
          }
        }
        if (_sharedMeshRooms[mesh.id]?.contains(_roomFocus) == true) {
          belongs = true;
        }
        var hidden = !belongs;
        final room = model.objects[_roomFocus];
        if (room != null && object?.id == room.id) {
          for (final panel in focusedPanels) {
            if (mesh.id.startsWith('${room.id}-${panel.key}-')) {
              hidden = panel.key == 'roof';
            }
          }
        }
        if (hidden) opacity *= 1 - _roomReveal.value;
      }
      {
        final object = model.objects[mesh.id];
        if (object != null &&
            (object.kind == CraftKind.wall ||
                object.kind == CraftKind.door ||
                object.kind == CraftKind.window)) {
          opacity *= _wallOpacity(object);
        }
      }
      final isPlane = model.planes.containsKey(mesh.id);
      final contextTarget = contextOpacity[mesh.id];
      if (contextTarget != null) {
        opacity *=
            1 -
            (1 - contextTarget) *
                Curves.easeInOutSine.transform(contextFade.value);
      }
      if (contextTransitionFrom.isNotEmpty) {
        final start = contextTransitionFrom[mesh.id] ?? 0;
        final t = Curves.easeInOutSine.transform(transition.value);
        opacity = start + (opacity - start) * t;
      }
      mesh.material = MaterialModel(
        color: Color.lerp(
          baseColors[mesh.id] ?? original.color,
          (Colors.white),
          strength * .72,
        )!,
        perFaceColors: mesh.geometry.faceColors,
        exactPerFaceColors: mesh.geometry.faceColors != null,
        opacity: opacity,
        doubleSided: original.doubleSided,
        strokeEdges:
            isPlane &&
            contextTarget != null &&
            mesh.geometry.faceColors == null,
      );
    }
    scene.markNeedsPaint();
  }

  double _wallOpacity(CraftObject object) {
    if (object.kind != CraftKind.wall &&
        object.kind != CraftKind.door &&
        object.kind != CraftKind.window) {
      return 1;
    }
    final floorId = supportingFloor(object.id, model.objects, model.planes);
    final floor = model.objects[floorId];
    final floorPlane = floor == null ? null : model.planes[floor.planeId];
    final plane = model.planes[object.planeId];
    if (floor == null || floorPlane == null || plane == null) return 1;
    return wallRevealOpacity(
      camera: camera.position,
      target: camera.target,
      roomCenter: floorPlane.point(floor.region.bounds.center, floor.depth),
      wallCenter: plane.point(object.region.bounds.center),
      settings: WallRevealSettings(
        closeDistance: devSettings.wallNear,
        farDistance: devSettings.wallFar,
      ),
    );
  }

  void _setHover(_Hit? hit) {
    if (hit?.id == hover?.id) return;
    previousHover = hover?.id;
    hover = hit;
    glow.forward(from: 0);
  }

  void _transition(_Pose destination) {
    from = _Pose(camera);
    to = destination;
    transition.forward(from: 0);
  }

  void _animateCamera() {
    if (from == null || to == null) return;
    final t = Curves.easeInOutSine.transform(transition.value);
    camera.setPosition(from!.position * (1 - t) + to!.position * t);
    camera.setTarget(from!.target * (1 - t) + to!.target * t);
    camera.setUp((from!.up * (1 - t) + to!.up * t).normalized());
    camera.fovDegrees = from!.fov * (1 - t) + to!.fov * t;
    _applyHighlight();
    setState(() {});
  }

  void _focusPlane() {
    final plane = model.activePlane;
    if (plane == null || viewport.isEmpty) return;
    // Focus changes input ownership, never the incoming camera pose.
    semiFocusPose = fullFocusPose = worldPose ?? _Pose(camera);
  }

  _Pose _zoomFocusPose() {
    final semi = semiFocusPose!, full = fullFocusPose!;
    final t = Curves.easeInOutSine.transform(
      (displayedFocusScale - 1).clamp(0.0, 1.0),
    );
    return _Pose.at(
      semi.position * (1 - t) + full.position * t,
      semi.target * (1 - t) + full.target * t,
      (semi.up * (1 - t) + full.up * t).normalized(),
      semi.fov * (1 - t) + full.fov * t,
    );
  }

  void _zoomCrafting(double ratio) {
    if (transition.isAnimating ||
        semiFocusPose == null ||
        fullFocusPose == null) {
      return;
    }
    if (devSettings.disableFocusZoom) {
      pinch = (pinch * ratio).clamp(.5, 1.0);
      if (pinch < .9) {
        model.leave();
        pointers.clear();
        controls.cancel();
        pinch = 1;
      }
      return;
    }
    focusScale = (focusScale * ratio).clamp(.85, 2.0);
    zoomFromScale = displayedFocusScale;
    focusZoom.forward(from: 0);
  }

  void _restoreWorld() {
    preview = false;
    selectedObject = null;
    var target = worldPose;
    if (target == null) return;
    final offset = target.position - target.target;
    if (offset.length > 0) {
      target = _Pose.at(
        target.target +
            offset.normalized() *
                offset.length.clamp(
                  devSettings.nearestDistance,
                  devSettings.farthestDistance,
                ),
        target.target,
        target.up,
        target.fov,
      );
    }
    _transition(target);
    worldPose = null;
    mapLook = null;
  }

  void _togglePreview() {
    _resetPointGestures();
    if (model.activePlane == null) return;
    setState(() {
      preview = !preview;
      focusZoom.stop();
      focusScale = displayedFocusScale = preview
          ? 1
          : 1 +
                (widget.entryFocusLevel ?? devSettings.entryFocusLevel).clamp(
                  0.0,
                  1.0,
                );
    });
    _focusPlane();
    _refreshScene();
  }

  _Hit? _pick(Offset position) {
    final ray = camera.unprojectRay(position, viewport);
    if (ray == null) return null;
    _Hit? best;
    void consider(
      CraftPlane plane,
      Region region,
      String? object,
      double depth,
    ) {
      final p = Camera.intersectPlane(
        ray: ray,
        point: plane.origin + plane.normal * depth,
        normal: plane.normal,
      );
      if (p == null || !region.contains(plane.local(p))) return;
      if (!_geometryBenchmark.active &&
          !model.parcels.owns(Offset(p.x, -p.z))) {
        return;
      }
      if (object == null && best?.object != null) {
        // Glass candidates are selectable at their outlines over existing
        // objects, but their translucent interiors don't trap the reticle.
        final outlineHit = edges(region.outer).any((edge) {
          final a = camera.projectToScreen(plane.point(edge.$1), viewport);
          final b = camera.projectToScreen(plane.point(edge.$2), viewport);
          return a != null &&
              b != null &&
              _distanceToSegment(position, a, b) < 14;
        });
        if (!outlineHit) return;
      }
      final distance = (p - ray.origin).length;
      if (best == null ||
          distance < best!.distance - .0001 ||
          ((distance - best!.distance).abs() < .005 && object != null)) {
        best = _Hit(plane.id, object, distance);
      }
    }

    for (final object in model.objects.values) {
      if (_wallOpacity(object) < .35) continue;
      final plane = model.planes[object.planeId];
      if (plane != null) {
        if (object.kind == CraftKind.screen) {
          for (var i = 1; i < object.path.length; i++) {
            final a = plane.point(object.path[i - 1]),
                b = plane.point(object.path[i]);
            final panel = CraftPlane(
              id: plane.id,
              origin: a,
              u: (b - a).normalized(),
              v: plane.normal,
              region: rectangle((b - a).length, object.depth),
              grids: plane.grids,
            );
            consider(panel, panel.region, object.id, 0);
          }
        } else {
          consider(plane, object.region, object.id, object.depth + .002);
        }
      }
    }
    for (final plane in model.planes.values) {
      if (!plane.id.startsWith('surface-') &&
          (!_placingConstruction || model.isLandscapePaper(plane.id)) &&
          model.planeAvailable(plane) &&
          (model.surfaceFusion.canonical[plane.id] ?? plane.id) == plane.id) {
        for (final region in model.surfaceRegions(plane)) {
          consider(plane, region, null, 0);
        }
      }
    }
    return best;
  }

  int? _nodeAt(Offset at) {
    final plane = model.activePlane, grid = model.grid;
    if (plane == null || grid == null) return null;
    var distance = 24.0;
    int? result;
    for (var i = 0; i < grid.nodes.length; i++) {
      final p = camera.projectToScreen(
        plane.point(grid.nodes[i], .008),
        viewport,
      );
      if (p != null && (p - at).distance < distance) {
        distance = (p - at).distance;
        result = i;
      }
    }
    return result;
  }

  void _resetPointGestures() {
    strokeShake.reset();
  }

  Offset? _local(Offset at, [double depth = 0]) =>
      _localOn(model.activePlane, at, depth);
  Offset? _localOn(CraftPlane? plane, Offset at, [double depth = 0]) {
    final ray = camera.unprojectRay(at, viewport);
    if (plane == null || ray == null) return null;
    final p = Camera.intersectPlane(
      ray: ray,
      point: plane.origin + plane.normal * depth,
      normal: plane.normal,
    );
    return p == null ? null : plane.local(p);
  }

  void _down(PointerDownEvent e) {
    if (_surfaceDown(e)) return;
    if (_focusPointerDown(e)) return;
    if (_disposed) return;
    if (devSettings.showGestureDebug) {
      gestureDebug.down(
        e.pointer,
        e.localPosition,
        kind: e.kind.name,
        buttons: e.buttons,
      );
    }
    if (loading || loadFailed || transition.isAnimating) return;
    _resetPointGestures();
    strokeShake.reset();
    strokeCancelled = false;
    controls.begin(e.kind, e.localPosition);
    pointers[e.pointer] = e.localPosition;
    if (pointers.length > 1) {
      _roomPinch = 1;
      _roomZoomConsumed = false;
      pencilDwell.cancel();
      model.cancelPencil();
      pencilDragging = false;
      _resetPointGestures();
      if (drawing || pulling || model.erasing || model.harvestPending) {
        model.cancelGesture();
      }
      drawing = false;
      livePointer = null;
      pulling = false;
      if (!multi) {
        planeSwipe.start(pointers.values);
      } else {
        planeSwipe.consumed = true;
      }
      if (devSettings.showGestureDebug) {
        gestureDebug.recognition(
          zooming: planeSwipe.zooming,
          consumed: planeSwipe.consumed,
        );
      }
      multi = true;
      multiMoved.clear();
      final values = pointers.values.toList();
      lastSpan = (values[0] - values[1]).distance;
      pinch = 1;
      return;
    }
    down = previous = e.localPosition;
    moved = multi = false;
    secondary = e.buttons & (kSecondaryMouseButton | kMiddleMouseButton) != 0;
    if (_cameraUnlocked) return;
    if (devToolsOpen) {
      focusZoom.stop();
      focusScale = displayedFocusScale;
      return;
    }
    if (!controls.profile.canActivate(e.buttons)) return;
    if (model.paperSurface &&
        !secondary &&
        !preview &&
        model.tool == CraftTool.pencil) {
      final p = model.selectedMotif != null
          ? _local(e.localPosition, .008)
          : _pencilNode(e.localPosition);
      if (p == null) return;
      pencilDragging = true;
      if (model.selectedMotif != null) {
        model.beginPencil(p);
      } else {
        model.cancelPencil();
        pencilDwell.begin(p);
      }
      return;
    }
    if (model.tool == CraftTool.eraser && !secondary && !preview) {
      if (model.beginErasing()) {
        _resetEraser();
        _queueEraser(e.localPosition);
      }
      return;
    }
    if (model.tool == CraftTool.volume && model.previewObject != null) {
      final object = model.previewObject!;
      final point = _local(e.localPosition, object.depth);
      if (point != null && object.region.contains(point)) {
        model.beginGesture();
        pullStartDepth = model.previewDepth;
        if (pullStartDepth == 0) {
          model.setDepth(.035, continuous: true);
          pullStartDepth = .035;
        }
        {
          final plane = model.activePlane!;
          pullPlane = plane.point(point, pullStartDepth);
          final axis = plane.normal;
          var normal = axis.cross(camera.forward.cross(axis));
          if (normal.length2 < 1e-8) normal = camera.up;
          final ray = camera.unprojectRay(e.localPosition, viewport)!;
          pullHit = Camera.intersectPlane(
            ray: ray,
            point: pullPlane!,
            normal: normal.normalized(),
          );
          pulling = pullHit != null;
        }
        if (!pulling) model.finishGesture();
      }
    } else if (!preview &&
        (model.tool == CraftTool.scissors ||
            model.tool == CraftTool.place ||
            model.tool == CraftTool.lightPencil) &&
        !secondary) {
      final node = _nodeAt(e.localPosition);
      if (node != null) {
        model.placementSide =
            model.activePlane!.normal.dot(
                  camera.position - model.activePlane!.origin,
                ) <
                0
            ? -1
            : 1;
        model.beginGesture();
        drawing = true;
        strokeShake.update(e.localPosition, e.timeStamp);
        releaseFade.stop();
        releaseFade.value = 0;
        releasedTrace = [];
        closureWhite.value = model.closed && _drawingReady ? 1 : 0;
        livePointer = controls.craftingAim(e.localPosition);
        if (!model.draft.path.contains(node)) {
          model.appendNode(node);
        }
      }
    }
  }

  void _move(PointerMoveEvent e) {
    if (_surfaceMove(e)) return;
    if (_focusPointerMove(e)) return;
    if (_disposed) return;
    if (devSettings.showGestureDebug) {
      gestureDebug.move(e.pointer, e.localPosition);
    }
    if (!pointers.containsKey(e.pointer)) return;
    if (strokeCancelled) {
      pointers[e.pointer] = e.localPosition;
      return;
    }
    if (drawing &&
        model.tool == CraftTool.place &&
        pointers.length == 1 &&
        strokeShake.update(e.localPosition, e.timeStamp)) {
      model.cancelDrawingStroke();
      drawing = false;
      moved = true;
      strokeCancelled = true;
      livePointer = null;
      releasedTrace = [];
      setState(() {});
      return;
    }
    if (pointers.length > 1) strokeShake.reset();
    controls.move(e.kind, e.localPosition);
    pointers[e.pointer] = e.localPosition;
    final delta = e.localPosition - (previous ?? e.localPosition);
    if (down != null && (e.localPosition - down!).distance > 6) {
      moved = true;
      _backgroundTapTimer?.cancel();
    }
    if (pointers.length == 1 && pencilDragging) {
      if (model.selectedMotif != null) {
        final p = _local(e.localPosition, .008);
        if (p != null) model.extendPencil(p);
      } else {
        pencilDwell.pointAt(_pencilNode(e.localPosition));
      }
      previous = e.localPosition;
      return;
    }
    if (pointers.length == 1 && model.erasing) {
      _queueEraser(e.localPosition);
      previous = e.localPosition;
      return;
    }
    if (pointers.length >= 2) {
      if (_drawingFocused || _currentRoom != null) {
        multiMoved.add(e.pointer);
        if (pointers.length != 2 || multiMoved.length < 2) return;
        multiMoved.clear();
      }
      final values = pointers.values.toList();
      final span = (values[0] - values[1]).distance;
      final ratio = lastSpan > 0 ? span / lastSpan : 1.0;
      final swipe = planeSwipe.update(
        pointers.values,
        PlaneSwipe.threshold(viewport),
      );
      if (devSettings.showGestureDebug) {
        gestureDebug.recognition(
          swipe: swipe,
          zooming: planeSwipe.zooming,
          consumed: planeSwipe.consumed,
        );
      }
      if (_surfaceFocus.isEmpty && _currentRoom != null && !devToolsOpen) {
        if (swipe != null) _swipeRoom(swipe);
        _roomPinch *= ratio;
        _stepRoomZoom(_roomPinch);
        lastSpan = span;
        previous = e.localPosition;
        return;
      }
      if (swipe != null && _drawingFocused) {
        _navigatePlane(swipe);
      } else if (!planeSwipe.consumed &&
          !transition.isAnimating &&
          (_cameraUnlocked || planeSwipe.zooming)) {
        _navigateMulti(ratio);
      } else if (_cameraUnlocked && !transition.isAnimating) {
        _navigateMulti(ratio);
      }
      if (_cameraUnlocked || planeSwipe.zooming) lastSpan = span;
    } else if (!multi && _cameraUnlocked && moved) {
      if (controls.profile.worldDrag(
                pointers: 1,
                buttons: e.buttons,
                origin: down ?? e.localPosition,
                viewport: viewport,
                zones: devSettings.worldGestureZones,
              ) ==
              WorldDrag.rotate &&
          _surfaceFocus.isNotEmpty &&
          _surfaceFocus.last.inspect) {
        mapCamera.restorePose(
          lookAt: mapCamera.lookAt,
          distance: mapCamera.distance,
          yaw: mapCamera.yaw - delta.dx * .008,
        );
      } else if (_currentRoom == null || devToolsOpen) {
        mapCamera.pan(delta);
      }
    } else if (!multi && devToolsOpen && _drawingFocused) {
      _panFocused(previous ?? e.localPosition, e.localPosition);
    } else if (drawing) {
      livePointer = controls.craftingAim(e.localPosition);
      final plane = model.activePlane!, grid = model.grid!;
      final start = previous ?? e.localPosition, end = e.localPosition;
      final segment = end - start;
      final length2 = segment.distanceSquared;
      final candidates = <(double, int)>[];
      for (var i = 0; i < grid.nodes.length; i++) {
        final point = camera.projectToScreen(
          plane.point(grid.nodes[i], .008),
          viewport,
        );
        if (point == null) continue;
        final t = length2 == 0
            ? 1.0
            : (((point - start).dx * segment.dx +
                          (point - start).dy * segment.dy) /
                      length2)
                  .clamp(0.0, 1.0);
        if ((point - (start + segment * t)).distance < 19) {
          candidates.add((t, i));
        }
      }
      candidates.sort((a, b) => a.$1.compareTo(b.$1));
      for (final candidate in candidates) {
        final node = candidate.$2, path = model.draft.path;
        if (node == path.lastOrNull) continue;
        if (model.appendNode(node)) {
          if (model.closed) {
            livePointer = null;
            _resetPointGestures();
            break;
          }
        }
      }
      setState(() {});
    } else if (pulling && pullPlane != null && pullHit != null) {
      final delta = axisDragDelta(
        camera: camera,
        viewport: viewport,
        screen: e.localPosition,
        axis: model.activePlane!.normal,
        planePoint: pullPlane!,
        startHit: pullHit!,
      );
      if (delta != null) {
        model.setDepth(pullStartDepth + delta, continuous: true);
      }
    }
    previous = e.localPosition;
  }

  bool _completeDrawing({bool allowOpen = false}) {
    final trace = List<Offset>.of(model.trace);
    final result = model.commitDrawing(allowOpen: allowOpen);
    final created = result != null;
    if (created) {
      final reduced = MediaQuery.disableAnimationsOf(context);
      unawaited(
        paperEffects.play(
          result,
          duration: Duration(milliseconds: devSettings.effectDurationMs),
          shake: devSettings.screenShake,
          reducedMotion: reduced,
        ),
      );
      if (devSettings.haptics) {
        unawaited(
          (result.action == PaperAction.removal
                  ? HapticFeedback.mediumImpact()
                  : HapticFeedback.lightImpact())
              .catchError((Object _) {}),
        );
      }
      if (model.lastHarvest != null) {
        harvestNotice = Map.of(model.lastHarvest!);
        harvestNoticeTimer?.cancel();
        harvestNoticeTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() => harvestNotice = null);
        });
      }
      completedTrace = trace;
      segmentGlow.forward(from: 0);
      drawing = false;
      livePointer = null;
      moved = true;
    }
    return created;
  }

  void _fadeReleasedLine() {
    releasedTrace = List.of(model.trace);
    if (!model.closed && livePointer != null && model.grid != null) {
      final partial = liveStrokePreview(
        grid: model.grid!,
        path: model.draft.path,
        pointer: livePointer!,
        project: (p) =>
            camera.projectToScreen(model.activePlane!.point(p, .008), viewport),
      );
      if (partial.length > 1) releasedTrace.addAll(partial.skip(1));
    }
    releasedWhite = model.closed && _drawingReady ? 1 : closureWhite.value;
    releaseFade.forward(from: 0);
  }

  String? _pencilLiveKey;
  List<PencilSegment> _pencilLive = [];
  List<PencilSegment> _livePencilMarks([Offset? screen]) {
    if (!model.paperSurface || model.tool != CraftTool.pencil || preview) {
      return [];
    }
    if (model.selectedMotif != null || !pencilDragging) {
      return model.previewMarks;
    }
    final from = pencilDwell.tail, to = pencilDwell.target;
    if (from == null || to == null) return [];
    final key =
        '${identityHashCode(model)}/${model.activePlaneId}/${model.presentationEpoch}/${model.markingRevision}/$from/$to';
    if (key == _pencilLiveKey) return _pencilLive;
    _pencilLiveKey = key;
    // Clipping canonicalizes segment direction; restore the drag's tail-to-tip
    // order so the graphite wipe travels in the direction the user drew.
    final pieces =
        model
            .clipToPaper([PencilSegment(from, to)])
            .map(
              (s) =>
                  (s.a - from).distanceSquared <= (s.b - from).distanceSquared
                  ? s
                  : PencilSegment(s.b, s.a),
            )
            .toList()
          ..sort(
            (a, b) => (a.a - from).distanceSquared.compareTo(
              (b.a - from).distanceSquared,
            ),
          );
    return _pencilLive = pieces;
  }

  void _up(PointerUpEvent e) {
    if (_surfaceUp(e)) return;
    if (_focusPointerUp(e)) return;
    if (_disposed) return;
    if (devSettings.showGestureDebug) {
      gestureDebug.end(e.pointer, at: e.localPosition);
    }
    _resetPointGestures();
    if (!pointers.containsKey(e.pointer)) return;
    controls.move(e.kind, e.localPosition);
    controls.end();
    final pencilLine = pencilDragging
        ? _livePencilMarks(e.localPosition)
        : <PencilSegment>[];
    pointers.remove(e.pointer);
    if (pointers.isNotEmpty) return;
    strokeShake.reset();
    if (strokeCancelled) {
      strokeCancelled = false;
      drawing = false;
      moved = true;
      return;
    }
    if (pencilDragging) {
      final plane = model.activePlane!;
      if (model.selectedMotif != null && model.commitPencil()) {
        pencilInk.play(
          plane,
          pencilLine,
          reducedMotion: MediaQuery.disableAnimationsOf(context),
        );
      }
      pencilDwell.cancel();
      model.cancelPencil();
      pencilDragging = false;
      moved = true;
      return;
    }
    if (model.erasing) {
      _queueEraser(e.localPosition);
      _flushEraser();
      _resetEraser();
      model.finishErasing();
      harvestNoticeTimer?.cancel();
      harvestNoticeTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => harvestNotice = null);
      });
      moved = true;
      return;
    }
    if (drawing && model.tool == CraftTool.lightPencil && !multi) {
      model.finishGesture();
      drawing = false;
      moved = true;
      setState(() {
        livePointer = null;
      });
      return;
    }
    if (!moved && !multi && drawing && model.draft.path.length == 1) {
      model.cancelGesture();
      drawing = false;
    }
    if (drawing && !multi) _fadeReleasedLine();
    if (drawing && !multi && !secondary && model.draft.path.length > 1) {
      if (!_drawingReady || !_completeDrawing(allowOpen: true)) {
        // Keep only the captured fading trace. An invalid operation must not
        // survive as a selectable recipe or an editable pending candidate.
        model.finishGesture(resetDrawing: true);
        drawing = false;
        moved = true;
      }
    }
    if (drawing || pulling || model.erasing || model.harvestPending) {
      model.finishGesture(
        resetDrawing:
            drawing && devSettings.resetDrawingOnRelease && model.error == null,
      );
    }
    if (!moved && !multi && !drawing && !pulling && !secondary) {
      if (_handleRoomBackgroundTap(e.localPosition)) {
        // A second background tap exits; defer single-tap construction.
      } else if (_placingConstruction) {
        if (!devToolsOpen) {
          if (_parcelShopping) {
            _tap(e.localPosition);
          } else {
            _placeConstruction();
          }
        }
      } else if (!devToolsOpen || model.activePlane == null) {
        _tap(e.localPosition);
      }
    }
    drawing = pulling = false;
    multi = secondary = false;
    setState(() {
      livePointer = null;
    });
    if (_cameraUnlocked && !transition.isAnimating && _currentRoom == null) {
      mapCamera.endZoom();
    }
  }

  void _cancel(PointerCancelEvent e) {
    _cancelSurfaceGesture();
    if (_focusPointerCancel(e)) return;
    if (_disposed) return;
    if (devSettings.showGestureDebug) gestureDebug.cancel();
    pencilDwell.cancel();
    model.cancelPencil();
    pencilDragging = false;
    if (_disposed) return;
    _resetEraser(clearEffects: true);
    _resetPointGestures();
    pointers.clear();
    controls.cancel();
    if (drawing || pulling || model.erasing || model.harvestPending) {
      model.cancelGesture();
    }
    drawing = pulling = false;
    multi = secondary = false;
    setState(() {
      livePointer = null;
    });
  }

  void _navigatePlane(Offset swipe) {
    final plane = model.activePlane;
    if (plane == null || transition.isAnimating) return;
    final center = camera.projectToScreen(
      plane.point(plane.region.bounds.center),
      viewport,
    );
    if (center == null) return;
    final next = model.navigationGraph.inDirection(
      plane.id,
      swipe,
      center,
      (point) => camera.projectToScreen(point, viewport),
    );
    if (next == null) return;
    preview = false;
    selectedObject = null;
    model.enter(next);
  }

  void _navigateMulti(double ratio) {
    if (_cameraUnlocked) {
      if ((ratio - 1).abs() > .004) mapCamera.zoomByScale(ratio);
    } else {
      _zoomCrafting(ratio);
    }
  }

  void _trackpadStart(PointerPanZoomStartEvent event) {
    _cancelSurfaceGesture();
    if (_opening) return;
    _roomZoomConsumed = false;
    _roomPinch = 1;
    _backgroundTapTimer?.cancel();
    if (_drawingFocused) return;
    if (devSettings.showGestureDebug) {
      gestureDebug.down(
        event.pointer,
        event.localPosition,
        kind: 'trackpad',
        nativeTrackpad: true,
      );
    }
    trackpadActive = false;
    _resetPointGestures();
    if (loading || loadFailed || transition.isAnimating) return;
    if (drawing || pulling || model.erasing || model.harvestPending) {
      model.cancelGesture();
    }
    drawing = pulling = false;
    livePointer = null;
    controls.begin(event.kind, event.localPosition);
    trackpadScale = 1;
    trackpadActive = true;
    planeSwipe.startTrackpad();
    pinch = 1;
  }

  void _trackpadUpdate(PointerPanZoomUpdateEvent event) {
    if (devSettings.showGestureDebug && gestureDebug.trackpadOrigin != null) {
      gestureDebug.move(
        event.pointer,
        gestureDebug.trackpadOrigin! + event.pan,
      );
    }
    if (!trackpadActive || loading || loadFailed || transition.isAnimating) {
      return;
    }
    controls.move(event.kind, event.localPosition);
    if (_surfaceFocus.isNotEmpty) {
      _moveIsolated(event.panDelta, scale: event.scale / trackpadScale);
      trackpadScale = event.scale;
      return;
    }
    if (_currentRoom != null && !devToolsOpen) {
      final swipe = planeSwipe.updateTrackpad(
        event.pan,
        event.scale,
        event.rotation,
        PlaneSwipe.threshold(viewport),
      );
      if (swipe != null) _swipeRoom(swipe);
      _stepRoomZoom(event.scale);
      trackpadScale = event.scale;
      return;
    }
    if (_cameraUnlocked) {
      mapCamera.pan(event.panDelta);
      _navigateMulti(event.scale / trackpadScale);
    } else {
      final swipe = planeSwipe.updateTrackpad(
        event.pan,
        event.scale,
        event.rotation,
        PlaneSwipe.threshold(viewport),
      );
      if (devSettings.showGestureDebug) {
        gestureDebug.recognition(
          swipe: swipe,
          zooming: planeSwipe.zooming,
          consumed: planeSwipe.consumed,
        );
      }
      if (swipe != null) {
        _navigatePlane(swipe);
      } else if (planeSwipe.zooming) {
        _navigateMulti(event.scale / trackpadScale);
      }
    }
    if (_cameraUnlocked || planeSwipe.zooming) {
      trackpadScale = event.scale;
    }
  }

  void _trackpadEnd(PointerPanZoomEndEvent event) {
    _zoomExitConsumed = false;
    if (devSettings.showGestureDebug) gestureDebug.end(event.pointer);
    trackpadActive = false;
    controls.end();
    if (_cameraUnlocked &&
        !transition.isAnimating &&
        _surfaceFocus.isEmpty &&
        _currentRoom == null) {
      mapCamera.endZoom();
    }
  }

  void _tap(Offset point) {
    if (_parcelShopping) {
      final parcel = _parcelAt(point);
      if (parcel != null) model.buyParcel(parcel);
      return;
    }
    if (model.activePlane == null) {
      if (model.constructionTool == null) {
        _chooseSurface(point, point, tap: true);
      }
      return;
    }
    if (model.draft.path.isEmpty && model.editId == null) {
      final hit = _pick(point);
      if (hit?.object != null &&
          model.objects[hit!.object]?.linear != null &&
          'surface-${hit.object}' != model.activePlaneId) {
        selectedObject = hit.object;
        model.enter(
          model.surfaceFusion.canonical['surface-${hit.object}'] ??
              'surface-${hit.object}',
        );
        return;
      }
      if (hit != null &&
          hit.object == null &&
          hit.plane != model.activePlaneId &&
          !model.sameTerrainFocus(hit.plane, model.activePlaneId!) &&
          model.landscape.terrain.tiles.containsKey(hit.plane)) {
        model.enter(hit.plane);
        return;
      }
    }
    final now = DateTime.now();
    final hitObject =
        model.objects.values.where((o) {
          if (o.planeId != model.activePlaneId &&
              !model.sameTerrainFocus(o.planeId, model.activePlaneId!)) {
            return false;
          }
          final at = _localOn(model.planes[o.planeId], point);
          return at != null && o.region.contains(at);
        }).toList()..sort(
          (a, b) => model.planes[b.planeId]!.origin.y.compareTo(
            model.planes[a.planeId]!.origin.y,
          ),
        );
    final objectHit = hitObject.isNotEmpty;
    if (model.tool == CraftTool.scissors && !preview && !objectHit) {
      // Tapping an existing draft edge removes it and the connected suffix.
      final g = model.grid!, path = model.draft.path;
      for (var i = 1; i < path.length; i++) {
        final edge = g.connection(path[i - 1], path[i])!;
        final points = edge.points(g.nodes);
        for (var j = 1; j < points.length; j++) {
          final a = camera.projectToScreen(
            model.activePlane!.point(points[j - 1], .008),
            viewport,
          );
          final b = camera.projectToScreen(
            model.activePlane!.point(points[j], .008),
            viewport,
          );
          if (a != null && b != null && _distanceToSegment(point, a, b) < 12) {
            model.removeDraftEdge(i - 1);
            return;
          }
        }
      }
    }
    if (!objectHit && _nodeAt(point) == null) {
      if (lastTap != null &&
          now.difference(lastTap!).inMilliseconds < 330 &&
          (point - lastTapAt!).distance < 30) {
        lastTap = null;
        _togglePreview();
        return;
      }
      lastTap = now;
      lastTapAt = point;
    }
    if (objectHit && model.draft.path.isEmpty && model.editId == null) {
      final object = hitObject.first;
      selectedObject = object.id;
      model.enter('surface-${object.id}');
    }
  }

  void _scroll(PointerSignalEvent e) {
    if (_opening) return;
    if (_surfaceScroll(e)) return;
    _backgroundTapTimer?.cancel();
    if (!_disposed && devSettings.showGestureDebug && e is PointerScrollEvent) {
      gestureDebug.scrollEvent(e.pointer, e.localPosition, e.scrollDelta);
    }
    if (e is! PointerScrollEvent || transition.isAnimating || _drawingFocused) {
      return;
    }
    controls.hover(e.kind, e.localPosition);
    if (_currentRoom != null && !devToolsOpen) {
      _roomWheelTimer?.cancel();
      _roomPinch *= math.exp(-e.scrollDelta.dy * .003);
      _stepRoomZoom(_roomPinch);
      _roomWheelTimer = Timer(const Duration(milliseconds: 350), () {
        _roomZoomConsumed = false;
        _roomPinch = 1;
      });
      return;
    }
    if (_cameraUnlocked) {
      mapCamera.zoomByScroll(e.scrollDelta.dy);
    } else {
      _zoomCrafting(math.exp(-e.scrollDelta.dy * .002));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: (theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(
          primary: const Color(0xffeeeeee),
          secondary: const Color(0xffcccccc),
          onPrimary: const Color(0xff202020),
          onSecondary: const Color(0xff202020),
          primaryContainer: const Color(0xff444444),
          secondaryContainer: const Color(0xff444444),
          onPrimaryContainer: Colors.white,
          onSecondaryContainer: Colors.white,
          surface: const Color(0xff242424),
          surfaceContainerLow: const Color(0xff292929),
          surfaceContainer: const Color(0xff303030),
          surfaceContainerHigh: const Color(0xff363636),
          surfaceContainerHighest: const Color(0xff404040),
          surfaceTint: Colors.transparent,
          outline: const Color(0xff888888),
          outlineVariant: const Color(0xff555555),
        ),
      )),
      child: Builder(builder: _buildWorld),
    );
  }

  Widget _buildWorld(BuildContext context) {
    return Scaffold(
      backgroundColor: (const Color(0xff141414)),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final newSize = constraints.biggest;
          if (viewport != newSize) {
            viewport = newSize;
            mapCamera.setViewportSize(viewport);
            _scheduleRoomFrame(force: true);
            if (model.activePlane != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _focusPlane();
              });
            }
          }
          _scheduleRoomFrame();
          _scheduleSafeZoneMeasure();
          return SizedBox.expand(
            child: Stack(
              key: _viewportKey,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      key: const ValueKey('protoplane-background'),
                      decoration: BoxDecoration(
                        gradient: devSettings.backgroundGradient,
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _roomReveal,
                      builder: (context, _) => ColoredBox(
                        key: const ValueKey('room-background-shade'),
                        color: Colors.black.withValues(
                          alpha: .16 * _roomReveal.value,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Listener(
                    onPointerDown: _down,
                    onPointerMove: _move,
                    onPointerUp: _up,
                    onPointerCancel: _cancel,
                    onPointerSignal: _scroll,
                    onPointerPanZoomStart: _trackpadStart,
                    onPointerPanZoomUpdate: _trackpadUpdate,
                    onPointerPanZoomEnd: _trackpadEnd,
                    behavior: HitTestBehavior.opaque,
                    child: MouseRegion(
                      cursor:
                          model.activePlane == null &&
                              controls.hidesSystemCursor
                          ? SystemMouseCursors.none
                          : SystemMouseCursors.basic,
                      onEnter: (e) => controls.hover(e.kind, e.localPosition),
                      onExit: (_) {
                        controls.exit();
                        pencilDwell.pointAt(null);
                        _resetPointGestures();
                      },
                      onHover: (e) {
                        if (model.paperSurface &&
                            model.tool == CraftTool.pencil &&
                            model.selectedMotif == null &&
                            !preview) {
                          pencilDwell.pointAt(_pencilNode(e.localPosition));
                        }
                        if (model.paperSurface &&
                            model.tool == CraftTool.pencil &&
                            model.selectedMotif != null &&
                            !preview) {
                          final local = _local(e.localPosition, .008);
                          if (local != null) model.extendPencil(local);
                        }
                        controls.hover(e.kind, e.localPosition);
                      },
                      child: Transform.translate(
                        offset: paperEffects.shake,
                        transformHitTests: false,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            RepaintBoundary(
                              child: SceneView(
                                scene: scene,
                                debugOptions: SceneDebugOptions(
                                  showWorldXyPlane: false,
                                ),
                              ),
                            ),
                            FriendEyeOverlay(
                              friends: residents.friends,
                              camera: camera,
                              viewport: viewport,
                              tileSize: 1,
                              subtilesPerTile: BedroomResidents.subtiles,
                              listenable: scene,
                            ),
                            if (!_geometryBenchmark.active && !_parcelShopping)
                              FogOverlay(
                                key: const ValueKey('paper-fog'),
                                model: model,
                                camera: camera,
                                settings: devSettings.fog,
                                darkness: devSettings.backgroundDarkness,
                                horizonColor: devSettings.backgroundColors.last,
                                cameraChanges: scene,
                                animate: widget.animateFog,
                              ),
                            if (!_geometryBenchmark.active)
                              IgnorePointer(
                                child: CustomPaint(
                                  key: const ValueKey('parcel-overlay'),
                                  painter: ParcelPainter(
                                    parcels: model.parcels,
                                    available: model.parcels.visible(
                                      model.landscape.terrain,
                                    ),
                                    camera: camera,
                                    shopping: _parcelShopping,
                                    hovered:
                                        _parcelShopping && controls.showReticle
                                        ? _parcelAt(
                                            pointers.length == 1
                                                ? pointers.values.first
                                                : controls.worldAim(viewport),
                                          )
                                        : null,
                                    repaint: scene,
                                  ),
                                ),
                              ),
                            if (model.activePlane != null)
                              IgnorePointer(
                                child: DecoratedBox(
                                  key: const ValueKey('focus-vignette'),
                                  decoration: BoxDecoration(
                                    gradient: RadialGradient(
                                      radius: .85,
                                      colors: [
                                        Colors.transparent,
                                        Color(0x50000000),
                                      ],
                                      stops: [.5, 1],
                                    ),
                                  ),
                                  child: SizedBox.expand(),
                                ),
                              ),
                            if (model.activePlane != null)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                height: viewport.height * .25,
                                child: const IgnorePointer(
                                  child: DecoratedBox(
                                    key: ValueKey('focus-tools-gradient'),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.transparent,
                                          Colors.black,
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            IgnorePointer(
                              child: CustomPaint(
                                key: const ValueKey('adjacent-grid-overlay'),
                                painter: AdjacentGridPainter(
                                  model,
                                  camera,
                                  scene,
                                  enabled:
                                      _drawingFocused &&
                                      !preview &&
                                      !model.sharedLandscapeFocus,
                                  opacity: Curves.easeInOutSine.transform(
                                    contextFade.value,
                                  ),
                                ),
                              ),
                            ),
                            IgnorePointer(
                              child: CustomPaint(
                                key: const ValueKey('drawing-graph-overlay'),
                                painter: _DrawingGraphPainter(
                                  model,
                                  camera,
                                  scene,
                                  List.of(_focusPath),
                                  _eraseStart,
                                  _eraseEnd,
                                  _constructionEvaluation,
                                  _focusLiveScreen,
                                  _roomFocus,
                                ),
                              ),
                            ),
                            if (_drawingFocused)
                              IgnorePointer(
                                child: CustomPaint(
                                  key: const ValueKey('craft-grid-overlay'),
                                  painter: _GridPainter(
                                    model,
                                    camera,
                                    preview: preview,
                                    acetate: acetate.value,
                                    outgoingGrid: outgoingGrid,
                                    livePointer: drawing ? livePointer : null,
                                    ready: _drawingReady,
                                    segmentPulse: 1 - segmentGlow.value,
                                    completedTrace: completedTrace,
                                    traceOverride:
                                        drawing ||
                                            model.tool ==
                                                CraftTool.lightPencil ||
                                            model.tool == CraftTool.volume
                                        ? null
                                        : releasedTrace,
                                    lineOpacity:
                                        drawing ||
                                            model.tool ==
                                                CraftTool.lightPencil ||
                                            model.tool == CraftTool.volume
                                        ? 1
                                        : 1 -
                                              Curves.easeOut.transform(
                                                releaseFade.value,
                                              ),
                                    whiteMix: drawing
                                        ? closureWhite.value
                                        : releasedWhite,
                                    lineColor: model.tool == CraftTool.pencil
                                        ? const Color(0xff00cfee)
                                        : model.tool == CraftTool.scissors
                                        ? devSettings.cutLineColor
                                        : devSettings.lineColor,
                                    dotSelection: model.tool == CraftTool.pencil
                                        ? _pencilDotSelection
                                        : dotSelection,
                                    showGridLines: devSettings.gridLines,
                                    tileGridOpacity:
                                        devSettings.tileGridOpacity,
                                    hover: hover?.id,
                                    previousHover: previousHover,
                                    hoverFade: glow.value,
                                    focusFade: Curves.easeInOutSine.transform(
                                      contextFade.value,
                                    ),
                                  ),
                                ),
                              ),
                            IgnorePointer(
                              child: CustomPaint(
                                key: const ValueKey('pencil-ink-overlay'),
                                painter: PencilInkPainter(
                                  pencilInk,
                                  camera,
                                  plane: model.activePlane,
                                  live: _livePencilMarks(),
                                  dwellProgress: model.selectedMotif == null
                                      ? 0
                                      : null,
                                  enabled: !preview,
                                ),
                              ),
                            ),
                            IgnorePointer(
                              child: CustomPaint(
                                painter: GraphitePopsPainter(
                                  graphitePops,
                                  camera,
                                ),
                              ),
                            ),
                            IgnorePointer(
                              child: CustomPaint(
                                painter: PaperEffectsPainter(
                                  paperEffects,
                                  scene,
                                  lineColor: model.tool == CraftTool.scissors
                                      ? devSettings.cutLineColor
                                      : devSettings.lineColor,
                                  landscapeFilter: (null),
                                  craftedFilter:
                                      devSettings.craftedAppearance.filter,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (!_drawingFocused &&
                    !_surfaceDrawing &&
                    !_selecting &&
                    !_opening &&
                    controls.showReticle)
                  Positioned.fill(
                    child: ViewCrosshair(
                      position: controls.worldAim(viewport),
                      selectable: _placingConstruction
                          ? _constructionEvaluation?.valid == true
                          : hover != null,
                    ),
                  ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: devSettings.fog.enabled
                            ? const Color(0xbb202020)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        key: _headerKey,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!_opening) _housingHud(),
                          if (_opening)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _toggleDevTools,
                                child: const Text('devtools'),
                              ),
                            ),
                          if (model.error == null && saveError == null)
                            _bedroomStatus(),
                          if (model.error != null || saveError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xff382732),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        model.error ?? saveError!,
                                        style: const TextStyle(
                                          color: Color(0xffffc6cb),
                                        ),
                                      ),
                                    ),
                                    if (saveError != null)
                                      TextButton(
                                        onPressed: loading
                                            ? null
                                            : () {
                                                if (loadFailed) {
                                                  unawaited(_load());
                                                } else {
                                                  _save(model.toJson());
                                                }
                                              },
                                        child: const Text('Retry'),
                                      ),
                                    if (model.error != null)
                                      IconButton(
                                        onPressed: model.clearError,
                                        icon: const Icon(Icons.close, size: 18),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (!loading && !loadFailed && !devToolsOpen)
                  Positioned(
                    bottom: 12 + MediaQuery.paddingOf(context).bottom,
                    left: 12,
                    right: 12,
                    child: Center(
                      child: SizedBox(
                        key: _footerKey,
                        width: 320,
                        child: ConstructionToolbar(
                          key: const ValueKey('construction-toolbar'),
                          selected: model.constructionTool,
                          available: _availableSurfaceTools,
                          selectionControls: _selectionControls(),
                          paper: model.constructionPaper,
                          entityName:
                              model
                                  .objects[_createdEntityId]
                                  ?.constructionName ??
                              _surfaceContextName ??
                              _aimedEntityName,
                          onPaper: (paper) {
                            model.constructionPaper = paper;
                            _constructionPreviewKey = null;
                            _previewConstruction();
                            setState(() {});
                          },
                          onSelect: _selectConstructionTool,
                          stock:
                              model.balances[model.constructionPaper.material],
                          price: model.constructionPaper.material.purchasePrice,
                          onBuy: () =>
                              model.buyPaper(model.constructionPaper.material),
                        ),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _SurfaceGesturePainter(this)),
                  ),
                ),
                if (devToolsOpen && _devToolsRect != null)
                  Positioned.fromRect(
                    key: const ValueKey('protoplane-devtools-dock'),
                    rect: _devToolsRect!,
                    child: ProtoplaneDevToolsPanel(
                      key: const ValueKey('docked-devtools'),
                      benchmarkPanel: GeometryBenchmarkPanel(
                        benchmark: _geometryBenchmark,
                        scene: scene,
                        changed: () {
                          _configureOrbit();
                          _refreshScene();
                          setState(() {});
                        },
                      ),
                      settings: devSettings,
                      store: settingsStore,
                      changed: _applyDevSettings,
                      onClose: _toggleDevTools,
                      initialError: settingsError,
                      revealAllAreas: (model.revealAllAreas),
                      clearWorld: loading
                          ? null
                          : () => unawaited(_clearSavedWorld()),
                    ),
                  ),
                if (devSettings.showSafeZone && _safeZone != null)
                  Positioned.fromRect(
                    rect: _safeZone!,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        key: const ValueKey('craft-safe-zone'),
                        decoration: BoxDecoration(
                          color: const Color(0x087fffcc),
                          border: Border.all(
                            color: const Color(0xb37fffcc),
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (devSettings.showGestureDebug)
                  Positioned.fill(
                    child: GestureDebugOverlay(
                      key: const ValueKey('gesture-debug-overlay'),
                      debug: gestureDebug,
                      safeZone: _safeZone,
                    ),
                  ),
                if (loading) const Center(child: CircularProgressIndicator()),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _button(
    String label,
    IconData icon,
    VoidCallback? action, {
    bool active = false,
  }) => IconButton.filledTonal(
    tooltip: label,
    onPressed: action,
    style: IconButton.styleFrom(
      backgroundColor: active
          ? ((const Color(0xff555555)))
          : ((const Color(0xdd292929))),
      foregroundColor: Colors.white,
      minimumSize: const Size(44, 44),
    ),
    icon: label == 'Eraser'
        ? const CustomPaint(size: Size(21, 21), painter: EraserIconPainter())
        : Icon(icon, size: 21),
  );

  Widget _bedroomStatus() {
    if (model.bedrooms.isEmpty) return const SizedBox.shrink();
    final room = model.activeBedroom;
    if (model.activePlane != null) {
      if (room == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            room.usable
                ? '${room.resident!.label} · ${room.mood} · Comfort ${room.comfort}/100'
                : 'Bedroom · Missing: ${room.missing.join(', ')}',
            key: const ValueKey('bedroom-status'),
            maxLines: 2,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      );
    }
    final occupied = model.bedrooms.where((r) => r.usable).toList();
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Text(
            '${occupied.length} ${occupied.length == 1 ? 'flatmate' : 'flatmates'}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final room in occupied)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      avatar: const Icon(Icons.bed, size: 16),
                      label: Text(
                        '${room.resident!.label} · ${room.comfort}/100',
                      ),
                      onPressed: () {
                        selectedObject = room.floorId;
                        model.enter('surface-${room.floorId}');
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void reassemble() {
    super.reassemble();
    harvestAtlas.dispose();
    harvestAtlas = HarvestMeshCache()
      ..setPaperTexture(landscapePaperTexture)
      ..setCrumpledPaper(landscapeCrumple);
    edgeShading.clear();
    _refreshScene();
  }

  @override
  void dispose() {
    _entityNameTimer?.cancel();
    _roomWheelTimer?.cancel();
    _residentTimer?.cancel();
    _backgroundTapTimer?.cancel();
    _roomReveal.dispose();
    _surfaceTransition.dispose();
    _strokeFade.dispose();
    _doorSwing.dispose();
    _strokeFadeTimer?.cancel();
    _zoomExitTimer?.cancel();
    harvestNoticeTimer?.cancel();
    harvestAtlas.dispose();
    landscapePaperTexture?.dispose();
    edgeShading.dispose();
    pencilTextures.dispose();
    pencilDwell.dispose();
    pencilInk.dispose();
    _disposed = true;
    if (model.erasing) model.cancelGesture();
    _resetEraser();
    graphitePops.dispose();
    paperEffects.dispose();
    model.removeListener(_modelChanged);
    model.onCommitted = null;
    if (widget.controller == null) model.dispose();
    mapCamera.dispose();
    transition.dispose();
    focusZoom.dispose();
    acetate.dispose();
    glow.dispose();
    extrusion.dispose();
    segmentGlow.dispose();
    closureWhite.dispose();
    releaseFade.dispose();
    pointGlow.dispose();
    _resetPointGestures();
    controls.dispose();
    gestureDebug.dispose();
    contextFade.dispose();
    gridPager.dispose();
    scene.dispose();
    super.dispose();
  }
}

double _distanceToSegment(Offset p, Offset a, Offset b) {
  final d = b - a;
  if (d.distanceSquared == 0) return (p - a).distance;
  final t = (((p - a).dx * d.dx + (p - a).dy * d.dy) / d.distanceSquared).clamp(
    0.0,
    1.0,
  );
  return (p - (a + d * t)).distance;
}

class _GridPainter extends CustomPainter {
  _GridPainter(
    this.model,
    this.camera, {
    required this.preview,
    required this.acetate,
    this.livePointer,
    this.segmentPulse = 0,
    this.ready = false,
    this.completedTrace = const [],
    this.traceOverride,
    this.lineOpacity = 1,
    this.whiteMix = 0,
    Color? lineColor,
    Map<int, double>? dotSelection,
    this.outgoingGrid,
    this.hover,
    this.previousHover,
    this.showGridLines = false,
    this.tileGridOpacity = .12,
    this.hoverFade = 1,
    this.focusFade = 1,
  }) : _lineColor = lineColor,
       _dotSelection = dotSelection;
  final ProtoplaneController model;
  final Camera camera;
  final bool preview;
  final double acetate;
  final Offset? livePointer;
  final double segmentPulse;
  final bool ready;
  final List<Offset> completedTrace;
  final List<Offset>? traceOverride;
  final double lineOpacity, whiteMix;
  final Color? _lineColor;
  Color get lineColor => _lineColor ?? const Color(0xff7fff00);
  final Map<int, double>? _dotSelection;
  Map<int, double> get dotSelection => _dotSelection ?? const {};
  final CraftGrid? outgoingGrid;
  final String? hover, previousHover;
  final double hoverFade, focusFade;
  final bool showGridLines;
  final double tileGridOpacity;
  void drawDot(
    Canvas canvas,
    CraftPlane plane,
    Offset local,
    Size size,
    double lift,
    double radius,
    Paint paint,
    String style,
  ) {
    final center = camera.projectToScreen(plane.point(local, lift), size);
    final u = camera.projectToScreen(
      plane.point(local + const Offset(.01, 0), lift),
      size,
    );
    final v = camera.projectToScreen(
      plane.point(local + const Offset(0, .01), lift),
      size,
    );
    if (center == null || u == null || v == null) return;
    // Retain legibility while letting the plane's perspective flatten the glyph.
    final scale = math.max((u - center).distance, (v - center).distance) / .01;
    if (scale < 1e-6) return;
    final r = radius / scale;
    final points = <Offset>[];
    if (style == 'square') {
      points.addAll([
        Offset(-r, -r),
        Offset(r, -r),
        Offset(r, r),
        Offset(-r, r),
      ]);
    } else {
      final count = style == 'star' ? 10 : 32;
      for (var i = 0; i < count; i++) {
        final angle = -math.pi / 2 + i * math.pi * 2 / count;
        final length = style == 'star' ? (i.isEven ? r * 1.4 : r * .6) : r;
        points.add(Offset(math.cos(angle) * length, math.sin(angle) * length));
      }
    }
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final point = camera.projectToScreen(
        plane.point(local + points[i], lift),
        size,
      );
      if (point == null) return;
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(path..close(), paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (model.activePlane != null && model.tool == CraftTool.eraser) return;
    Path projected(
      CraftPlane plane,
      List<Offset> points, {
      double lift = .005,
      bool close = false,
    }) {
      final path = Path();
      var first = true;
      for (final p in points) {
        final screen = camera.projectToScreen(plane.point(p, lift), size);
        if (screen == null) continue;
        if (first) {
          path.moveTo(screen.dx, screen.dy);
          first = false;
        } else {
          path.lineTo(screen.dx, screen.dy);
        }
      }
      if (close) path.close();
      return path;
    }

    if (model.activePlane == null) {
      for (final p in model.planes.values) {
        if (p.id.startsWith('surface-') ||
            (model.isPlane(p.id) && !p.id.startsWith('ground-'))) {
          continue;
        }
        final regions = model.surfaceRegions(p);
        if (regions.isEmpty) continue;
        canvas.save();
        if (model.landscape.terrain.tiles.containsKey(p.id) == true) {
          final clip = Path()..fillType = PathFillType.evenOdd;
          for (final r in regions) {
            for (final ring in r.rings) {
              clip.addPath(projected(p, ring, close: true), Offset.zero);
            }
          }
          canvas.clipPath(clip);
        }
        canvas.drawPath(
          projected(p, p.region.outer, close: true),
          Paint()
            ..color = p.id == hover
                ? ((Colors.white))
                : ((const Color(0x66666666)))
            ..style = PaintingStyle.stroke
            ..strokeWidth = p.id == hover ? 2 : 1
            ..color = (p.id == hover ? Colors.white : const Color(0xff555555))
                .withValues(alpha: p.id == hover ? .45 : tileGridOpacity),
        );
        canvas.restore();
      }
      void dots(String? id, double opacity) {
        if (id == null || opacity <= 0) return;
        final surface = model.planes['surface-$id'] ?? model.planes[id];
        if (surface == null || surface.grids.isEmpty) return;
        final hoverGrid = surface.grids.first;
        for (final (nodeIndex, node) in hoverGrid.nodes.indexed) {
          if (!surface.region.contains(node)) continue;
          final point = camera.projectToScreen(surface.point(node, .008), size);
          if (point == null) continue;
          canvas.drawCircle(
            point,
            6,
            Paint()
              ..color = ((Colors.white)).withValues(alpha: .22 * opacity)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
          );
          drawDot(
            canvas,
            surface,
            node,
            size,
            .008,
            3.5,
            Paint()..color = ((Color.fromRGBO(210, 210, 210, opacity))),
            hoverGrid.dotStyle(nodeIndex),
          );
        }
      }

      dots(previousHover, 1 - hoverFade);
      dots(hover, hoverFade);
      return;
    }
    final plane = model.activePlane!, grid = model.grid!;
    if (preview) return;
    if (acetate < .5 && outgoingGrid != null) {
      final t = acetate * 2;
      canvas.save();
      canvas.translate(-t * size.width * .15, -t * 30);
      for (final edge in showGridLines ? outgoingGrid!.edges : <GridEdge>[]) {
        canvas.drawPath(
          projected(
            plane,
            edge.points(outgoingGrid!.nodes),
            lift: .008 + t * .18,
          ),
          Paint()
            ..color = Color.fromRGBO(130, 146, 176, (1 - t) * .4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..strokeCap = StrokeCap.round,
        );
      }
      canvas.restore();
    }
    final progress = Curves.easeOutCubic.transform(
      ((acetate - .35) / .65).clamp(0.0, 1.0),
    );
    final lift = .008 + (1 - progress) * .18;
    canvas.save();
    canvas.translate((1 - progress) * size.width * .13, -(1 - progress) * 20);
    final outline = projected(
      plane,
      plane.region.outer,
      lift: lift,
      close: true,
    );
    canvas.drawPath(
      outline,
      Paint()..color = Color.fromRGBO(190, 190, 190, .015 * progress),
    );
    canvas.drawPath(
      outline,
      Paint()
        ..color = Color.fromRGBO(85, 85, 85, tileGridOpacity * progress)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    for (final edge in showGridLines ? grid.edges : <GridEdge>[]) {
      canvas.drawPath(
        projected(plane, edge.points(grid.nodes), lift: lift),
        Paint()
          ..color = Color.fromRGBO(62, 73, 94, .65 * progress * focusFade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    for (final (nodeIndex, p) in grid.nodes.indexed) {
      if (!plane.region.contains(p)) continue;
      final selection = dotSelection[nodeIndex] ?? 0;
      final radius = 3.5 + 3.5 * selection;
      final fillRadius = 1.75 + 3.75 * selection;
      final screen = camera.projectToScreen(plane.point(p, lift), size);
      if (screen == null) continue;
      if (selection > .001) {
        canvas.drawCircle(
          screen,
          radius + 2,
          Paint()
            ..color = lineColor.withValues(alpha: .45 * selection * progress)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
      }
      drawDot(
        canvas,
        plane,
        p,
        size,
        lift,
        radius,
        Paint()..color = const Color(0xff181818),
        grid.dotStyle(nodeIndex),
      );
      drawDot(
        canvas,
        plane,
        p,
        size,
        lift,
        fillRadius,
        Paint()
          ..color = Color.lerp(
            const Color(0xffd2d2d2),
            lineColor,
            selection,
          )!.withValues(alpha: progress),
        grid.dotStyle(nodeIndex),
      );
    }
    final completion =
        model.trace.isEmpty && segmentPulse > 0 && completedTrace.isNotEmpty;
    final trace = traceOverride ?? (completion ? completedTrace : model.trace);
    final strokeColor = Color.lerp(lineColor, Colors.white, whiteMix)!;
    canvas.saveLayer(
      null,
      Paint()..color = Colors.white.withValues(alpha: lineOpacity),
    );
    if (trace.length > 1) {
      final valid = completion || ready;
      final color = strokeColor;
      final path = projected(plane, trace, lift: lift + .001);
      canvas.drawPath(
        path,
        Paint()
          ..color = strokeColor.withValues(alpha: valid ? .65 : .18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = valid ? 19 : 11
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      if (!valid && segmentPulse > 0 && model.draft.path.length >= 2) {
        final nodes = model.draft.path;
        final edge = grid.connection(nodes[nodes.length - 2], nodes.last)!;
        final latest = projected(
          plane,
          edge.points(grid.nodes, reversed: edge.a != nodes[nodes.length - 2]),
          lift: lift + .002,
        );
        canvas.drawPath(
          latest,
          Paint()
            ..color = strokeColor.withValues(alpha: .4 * segmentPulse)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 12
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
      }
    }
    if (livePointer != null) {
      final partial = liveStrokePreview(
        grid: grid,
        path: model.draft.path,
        pointer: livePointer!,
        project: (p) =>
            camera.projectToScreen(plane.point(p, lift + .001), size),
      );
      if (partial.length > 1) {
        final path = projected(plane, partial, lift: lift + .001);
        final color = strokeColor;
        canvas.drawPath(
          path,
          Paint()
            ..color = color.withValues(alpha: .25)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 11
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
        canvas.drawPath(
          path,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
        final tip = camera.projectToScreen(
          plane.point(partial.last, lift + .001),
          size,
        );
        if (tip != null) canvas.drawCircle(tip, 4, Paint()..color = color);
      }
    }
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => true;
}

class _MotifThumbnail extends CustomPainter {
  _MotifThumbnail(this.motif);
  final PencilMotif motif;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xffeee9de),
    );
    for (final s in motif.segments()) {
      canvas.drawLine(
        Offset(s.a.dx * size.width, s.a.dy * size.height),
        Offset(s.b.dx * size.width, s.b.dy * size.height),
        Paint()
          ..color = const Color(0xcc383838)
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_MotifThumbnail oldDelegate) => oldDelegate.motif != motif;
}
