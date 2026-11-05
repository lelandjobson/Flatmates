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
import '../protoplane/focus_view.dart';
import '../protoplane/wall_reveal.dart';
import '../protoplane/dev_settings.dart';
import '../ui/game/dev_tools_button.dart';
import '../protoplane/bedrooms.dart';
import '../protoplane/residents.dart';
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
  late ProtoplaneController model;
  late ProtoplaneStorage storage;
  final devSettings = ProtoplaneSettings();
  int appliedProtoplaneCells = 3;
  late GridConnections appliedGridConnections = GridConnections.orthogonal;
  final settingsStore = ProtoplaneStorage(fileName: 'settings.json');
  String? settingsError;
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
        math.min(320, math.max(170, viewport.width * .45)),
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
    if (widget.controller == null) {
      model.setProtoplaneCells(devSettings.protoplaneCells);
    }
    storage = widget.storage ?? ProtoplaneStorage();
    camera = Camera(
      name: 'Protoplane',
      position: Vector3(7, 9, 7),
      target: Vector3.zero(),
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
      distance: 11,
      minDistance: 2,
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
      settingsError = null;
      _applyDevSettings();
    } catch (_) {
      if (mounted) setState(() => settingsError = 'Could not load settings');
    }
  }

  Offset? _lastDiscoveryTarget;
  void _configureOrbit() {
    mapCamera.strictZoomBounds = true;
    mapCamera.setDistanceLimits(
      devSettings.nearestDistance,
      devSettings.farthestDistance,
      applyPose: false,
    );
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
    if ((model.tool != CraftTool.pencil || model.selectedMotif != null) &&
        pencilDwell.tail != null) {
      pencilDwell.cancel();
    }
    if (model.pencilPreviewUpdate) {
      setState(() {});
      return;
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
    if (_lastPlane != model.activePlaneId) {
      final traversing =
          _lastPlane != null && model.activePlane != null && worldPose != null;
      if (traversing) {
        contextTransitionFrom
          ..clear()
          ..addEntries(
            scene.meshes.map((m) => MapEntry(m.id, m.material.opacity)),
          );
      } else {
        contextTransitionFrom.clear();
      }
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
    if (model.activePlane == null &&
        !viewport.isEmpty &&
        !transition.isAnimating) {
      _setHover(
        controls.showReticle ? _pick(controls.worldAim(viewport)) : null,
      );
    }
    setState(() {});
  }

  void _cameraChanged() {
    if (_disposed) return;
    scene.markNeedsPaint();
    if (model.activePlane == null && !transition.isAnimating && !loading) {
      final target = Offset(mapCamera.lookAt.x, -mapCamera.lookAt.z);
      if (_lastDiscoveryTarget != target) {
        _lastDiscoveryTarget = target;
        model.discoverAt(target);
      }
    }
    _applyHighlight();
    if (model.activePlane == null &&
        !transition.isAnimating &&
        !viewport.isEmpty) {
      _setHover(
        controls.showReticle ? _pick(controls.worldAim(viewport)) : null,
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

  void _refreshScene() {
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
      meshes.add(_planeMesh(active)..groundPlane = true);
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
            opacity: o.id == active.owner ? .4 : 1,
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
        final target =
            adjacentFocusContext(
                  active,
                  p,
                  model.objects,
                  model.planes,
                  tiles: devSettings.focusContextTiles,
                  terrain: model.landscape.terrain,
                ) &&
                (!devSettings.hideOrthogonalContext ||
                    sameFocusOrientation(active, p))
            ? devSettings.focusContextOpacity
            : 0.0;
        if (target == 0 &&
            contextFade.value >= .999 &&
            !contextTransitionFrom.containsKey(p.id) &&
            !additions.any((m) => contextTransitionFrom.containsKey(m.id))) {
          return;
        }
        for (final mesh in additions) {
          if (focusedMeshIds.contains(mesh.id)) continue;
          meshes.add(mesh);
          contextOpacity[mesh.id] = target;
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
    } else if (contextPlane != null) {
      for (final mesh in meshes) {
        if (focusedMeshIds.contains(mesh.id)) continue;
        final p =
            model.planes[mesh.id] ??
            model.planes[model.objects[mesh.id]?.planeId];
        if (p != null) {
          contextOpacity[mesh.id] =
              adjacentFocusContext(
                contextPlane!,
                p,
                model.objects,
                model.planes,
                tiles: devSettings.focusContextTiles,
                terrain: model.landscape.terrain,
              )
              ? devSettings.focusContextOpacity
              : 0;
        }
      }
    }
    // Terrain edge meshes are cached; focus cropping must never leak into a
    // later focus or the overall view.
    for (final mesh in meshes) {
      mesh.cropBox = null;
    }
    if (active != null) {
      final crop = devSettings.focusCropEnabled
          ? focusCropBox(
              active,
              xPadding: devSettings.focusCropX,
              zPadding: devSettings.focusCropZ,
              above: devSettings.focusCropAbove,
              below: devSettings.focusCropBelow,
            )
          : null;
      final ownerPlane = model.planes[model.objects[active.owner]?.planeId];
      for (final mesh in meshes) {
        if (mesh.id == active.id ||
            (mesh.id == active.owner &&
                (ownerPlane == null ||
                    sameFocusOrientation(active, ownerPlane))) ||
            mesh.id == model.editId ||
            mesh.id.startsWith('preview') ||
            mesh.id.startsWith('cut-')) {
          continue;
        }
        final terrainWall = mesh.id.startsWith('terrain-wall-');
        CraftObject? object = model.objects[mesh.id];
        object ??= model.objects.values
            .where((o) => mesh.id.startsWith('${o.id}-'))
            .firstOrNull;
        final plane = model.planes[mesh.id] ?? model.planes[object?.planeId];
        final sameOrientation = terrainWall
            ? !isFloorOrientation(active)
            : plane == null ||
                  sameFocusOrientation(
                    active,
                    plane,
                    upright: object?.kind == CraftKind.screen,
                  );
        if (devSettings.hideOrthogonalContext && !sameOrientation) {
          contextOpacity[mesh.id] = 0;
        } else if (terrainWall ||
            (mesh.id == active.owner && !sameOrientation)) {
          contextOpacity[mesh.id] = devSettings.focusContextOpacity;
        }
        if (crop != null) {
          // Fully contained atlas sprites retain the existing fast batch path.
          final world = mesh.transformMatrix;
          if (!mesh.geometry.vertices.every(
            (p) => crop.contains(world.transformed3(p)),
          )) {
            mesh.cropBox = crop;
          }
        }
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
    residents.sync(
      scene,
      model.bedrooms.where(
        (b) =>
            model.activePlane == null ||
            (preview && model.activeBedroom?.floorId == b.floorId),
      ),
      model.objects,
      model.planes,
    );
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
  }

  void _applyHighlight() {
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
      var opacity = baseOpacity[mesh.id] ?? original.opacity;
      if (model.activePlane == null) {
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
    final pose = focusPlanePose(
      camera,
      plane,
      viewport,
      preview: preview,
      contextTiles: devSettings.focusContextTiles,
      safeZone: _safeZone,
      safeZoneFill: devSettings.safeZoneFill,
    );
    semiFocusPose = _Pose.at(pose.position, pose.target, pose.up, pose.fov);
    final full = focusPlanePose(
      camera,
      plane,
      viewport,
      fullFocus: true,
      contextTiles: devSettings.focusContextTiles,
      safeZone: _safeZone,
      safeZoneFill: devSettings.safeZoneFill,
    );
    fullFocusPose = _Pose.at(full.position, full.target, full.up, full.fov);
    _transition(_zoomFocusPose());
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

  void _enter(_Hit hit) {
    worldPose ??= _Pose(camera);
    mapLook ??= mapCamera.lookAt;
    mapDistance = mapCamera.distance;
    mapYaw = mapCamera.yaw;
    mapCamera.pauseForHandoff();
    selectedObject = hit.object;
    preview = false;
    _setHover(null);
    final surface = hit.object == null ? hit.plane : 'surface-${hit.object}';
    final destination = model.planes.containsKey(surface) ? surface : hit.plane;
    model.enter(model.surfaceFusion.canonical[destination] ?? destination);
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
      if (devSettings.fog.enabled &&
          model.discoveryDistance(Offset(p.x, -p.z)) >=
              devSettings.fog.style.margin + devSettings.fog.style.softness) {
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
    if (model.activePlane == null) return;
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
        if (preview) {
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
        (model.tool == CraftTool.scissors || model.tool == CraftTool.place) &&
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
    final oldPositions = pointers.values.toList();
    pointers[e.pointer] = e.localPosition;
    final delta = e.localPosition - (previous ?? e.localPosition);
    if (down != null && (e.localPosition - down!).distance > 6) moved = true;
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
      if (model.activePlane != null) {
        multiMoved.add(e.pointer);
        if (pointers.length != 2 || multiMoved.length < 2) return;
        multiMoved.clear();
      }
      final values = pointers.values.toList();
      final span = (values[0] - values[1]).distance;
      final ratio = lastSpan > 0 ? span / lastSpan : 1.0;
      final dx =
          ((values[0] + values[1]) / 2 -
                  (oldPositions[0] + oldPositions[1]) / 2)
              .dx;
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
      if (swipe != null && model.activePlane != null) {
        _navigatePlane(swipe);
      } else if (!planeSwipe.consumed &&
          !transition.isAnimating &&
          (model.activePlane == null || planeSwipe.zooming)) {
        _navigateMulti(dx, ratio);
      } else if (model.activePlane == null && !transition.isAnimating) {
        _navigateMulti(dx, ratio);
      }
      if (model.activePlane == null || planeSwipe.zooming) lastSpan = span;
    } else if (!multi && model.activePlane == null) {
      if (controls.profile.worldDrag(pointers: 1, buttons: e.buttons) ==
          WorldDrag.rotate) {
        mapCamera.restorePose(
          lookAt: mapCamera.lookAt,
          distance: mapCamera.distance,
          yaw: mapCamera.yaw - delta.dx * .008,
        );
      } else {
        mapCamera.pan(delta);
      }
    } else if (!multi && devToolsOpen && model.activePlane != null) {
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
      if (!devToolsOpen || model.activePlane == null) _tap(e.localPosition);
    }
    drawing = pulling = false;
    multi = secondary = false;
    setState(() {
      livePointer = null;
    });
    if (model.activePlane == null && !transition.isAnimating) {
      mapCamera.endZoom();
    }
  }

  void _cancel(PointerCancelEvent e) {
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

  void _navigateMulti(double dx, double ratio) {
    if (model.activePlane == null) {
      if ((ratio - 1).abs() > .004) mapCamera.zoomByScale(ratio);
      mapCamera.restorePose(
        lookAt: mapCamera.lookAt,
        distance: mapCamera.distance,
        yaw: mapCamera.yaw - dx * .008,
      );
    } else {
      _zoomCrafting(ratio);
    }
  }

  void _trackpadStart(PointerPanZoomStartEvent event) {
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
    if (model.activePlane == null) {
      _navigateMulti(event.panDelta.dx, event.scale / trackpadScale);
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
        _navigateMulti(0, event.scale / trackpadScale);
      }
    }
    if (model.activePlane == null || planeSwipe.zooming) {
      trackpadScale = event.scale;
    }
  }

  void _trackpadEnd(PointerPanZoomEndEvent event) {
    if (devSettings.showGestureDebug) gestureDebug.end(event.pointer);
    trackpadActive = false;
    controls.end();
    if (model.activePlane == null && !transition.isAnimating) {
      mapCamera.endZoom();
    }
  }

  void _tap(Offset point) {
    if (model.activePlane == null) {
      final hit = _pick(controls.worldAim(viewport));
      if (hit != null) _enter(hit);
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
    if (!_disposed && devSettings.showGestureDebug && e is PointerScrollEvent) {
      gestureDebug.scrollEvent(e.pointer, e.localPosition, e.scrollDelta);
    }
    if (e is! PointerScrollEvent || transition.isAnimating) return;
    controls.hover(e.kind, e.localPosition);
    if (model.activePlane == null) {
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
            if (model.activePlane != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _focusPlane();
              });
            }
          }
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
                            FogOverlay(
                              key: const ValueKey('paper-fog'),
                              model: model,
                              camera: camera,
                              settings: devSettings.fog,
                              cameraChanges: scene,
                              animate: widget.animateFog,
                            ),
                            IgnorePointer(
                              child: CustomPaint(
                                key: const ValueKey('adjacent-grid-overlay'),
                                painter: AdjacentGridPainter(
                                  model,
                                  camera,
                                  scene,
                                  enabled: !preview,
                                  opacity: Curves.easeInOutSine.transform(
                                    contextFade.value,
                                  ),
                                ),
                              ),
                            ),
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
                                  traceOverride: drawing ? null : releasedTrace,
                                  lineOpacity: drawing
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
                                  tileGridOpacity: devSettings.tileGridOpacity,
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
                if (model.activePlane == null && controls.showReticle)
                  Positioned.fill(
                    child: ViewCrosshair(
                      position: controls.worldAim(viewport),
                      selectable: hover != null,
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
                          Row(
                            children: [
                              DevToolsButton(
                                active: devToolsOpen,
                                onPressed: _toggleDevTools,
                              ),
                              _button('Back', Icons.arrow_back, () {
                                if (model.activePlane != null) {
                                  model.leave();
                                } else {
                                  context.goNamed('dev_routes');
                                }
                              }),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  model.editId != null
                                      ? 'Edit ${model.objects[model.editId]?.kind.label ?? ''}'
                                      : model.activePlane == null
                                      ? 'protoplane_concept'
                                      : model.activePlane!.wallCandidate
                                      ? 'Wall protoplane'
                                      : model.activePlane!.owner == null
                                      ? 'Ground protoplane'
                                      : model
                                                .objects[model
                                                    .activePlane!
                                                    .owner]
                                                ?.kind
                                                .label ??
                                            'Protoplane',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                  maxLines: 2,
                                ),
                              ),
                              if (saving)
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              GameViewUndoRedoBar(
                                canUndo:
                                    model.canUndo && !loading && !loadFailed,
                                canRedo:
                                    model.canRedo && !loading && !loadFailed,
                                onUndo: model.undo,
                                onRedo: model.redo,
                              ),
                            ],
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
                if (model.activePlane != null && !loading && !loadFailed) ...[
                  if (!devToolsOpen)
                    Positioned(
                      left: 10,
                      top: math.max(130, viewport.height * .35),
                      bottom: viewport.height < 500 ? 80 : 120,
                      width: viewport.height < 500 ? 104 : 52,
                      child: SingleChildScrollView(
                        key: _leftToolsKey,
                        child: _tools(),
                      ),
                    ),
                  Positioned(
                    right: 10,
                    top: math.max(130, viewport.height * .35),
                    bottom: 120,
                    width: model.paperSurface && model.tool == CraftTool.pencil
                        ? 112
                        : 64,
                    child: SingleChildScrollView(
                      key: _rightToolsKey,
                      child:
                          model.paperSurface && model.tool == CraftTool.pencil
                          ? _pencilSidebar()
                          : _paperSelector(),
                    ),
                  ),
                  Positioned(
                    bottom: 12 + MediaQuery.paddingOf(context).bottom,
                    left: 76,
                    right: 76,
                    child: SizedBox(key: _footerKey, child: _bottomControls()),
                  ),
                ],
                if (devToolsOpen && _devToolsRect != null)
                  Positioned.fromRect(
                    rect: _devToolsRect!,
                    child: ProtoplaneDevToolsPanel(
                      key: const ValueKey('docked-devtools'),
                      settings: devSettings,
                      store: settingsStore,
                      changed: _applyDevSettings,
                      onClose: _toggleDevTools,
                      initialError: settingsError,
                      revealAllAreas: (model.revealAllAreas),
                      clearWorld: loading || loadFailed
                          ? null
                          : () {
                              _resetPointGestures();
                              drawing = pulling = false;
                              livePointer = null;
                              model.clearWorld();
                            },
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

  Widget _tools() {
    final buttons = <Widget>[
      _button(
        'Scissors',
        Icons.content_cut,
        () => model.selectTool(CraftTool.scissors),
        active: model.tool == CraftTool.scissors,
      ),
      if (model.paperSurface) ...[
        const SizedBox(height: 8),
        _button('Pencil', Icons.edit_outlined, () {
          model.selectedMotif = null;
          model.selectTool(CraftTool.pencil);
        }, active: model.tool == CraftTool.pencil),
      ],
      if (model.paperSurface || model.graphitePlane != null) ...[
        const SizedBox(height: 8),
        _button(
          'Eraser',
          Icons.cleaning_services_outlined,
          () => model.selectTool(CraftTool.eraser),
          active: model.tool == CraftTool.eraser,
        ),
      ],
      ...[
        const SizedBox(height: 8),
        _button(
          'Place',
          Icons.add_box_outlined,
          () => model.selectTool(CraftTool.place),
          active: model.tool == CraftTool.place,
        ),
      ],
      const SizedBox(height: 8),
      _button(
        'Volume',
        Icons.open_in_full,
        () => model.selectTool(CraftTool.volume),
        active: model.tool == CraftTool.volume,
      ),
      const SizedBox(height: 8),
      _button(
        preview ? 'Grid' : '3D',
        preview ? Icons.grid_on : Icons.view_in_ar,
        _togglePreview,
        active: preview,
      ),
      if (selectedObject != null && model.editId == null) ...[
        const SizedBox(height: 8),
        if (model.transformations(selectedObject!).isNotEmpty)
          _button('Transform', Icons.transform, () async {
            final id = selectedObject!;
            final kind = await showModalBottomSheet<CraftKind>(
              context: context,
              builder: (context) => SafeArea(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final kind in model.transformations(id))
                      ListTile(
                        title: Text(kind.label),
                        trailing: Text(
                          '${model.transformationQuote(id, kind)}',
                        ),
                        onTap: () => Navigator.pop(context, kind),
                      ),
                  ],
                ),
              ),
            );
            if (kind != null && mounted) model.transformObject(id, kind);
          }),
        _button('Edit', Icons.edit, () {
          final o = model.objects[selectedObject];
          if (o != null) model.enter(o.planeId, editObject: o.id);
        }),
      ],
    ];
    if (viewport.height < 500) {
      return Wrap(
        spacing: 4,
        runSpacing: 4,
        alignment: WrapAlignment.center,
        children: buttons.where((w) => w is! SizedBox).toList(),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: buttons);
  }

  Widget _pencilSidebar() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        '${((model.balances[PaperMaterial.graphite] ?? 0) + model.graphiteMilli / 1000).toStringAsFixed(3)} graphite',
        textAlign: TextAlign.center,
      ),
      for (final motif in model.discoveredMotifs)
        TextButton(
          onPressed: () => model.selectMotif(motif),
          child: Column(
            children: [
              CustomPaint(
                size: const Size(24, 24),
                painter: _MotifThumbnail(motif),
              ),
              Text(motif.label, textAlign: TextAlign.center),
            ],
          ),
        ),
      if (model.selectedMotif != null)
        _button('Rotate', Icons.rotate_right, model.rotateMotif),
      if (model.error != null && model.previewMarks.isNotEmpty)
        _button('Retry', Icons.check, model.commitPencil),
    ],
  );

  Widget _paperSelector() => (Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final material in model.materials)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Tooltip(
            message: material.label,
            child: Container(
              width: 58,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: material.base,
                borderRadius: BorderRadius.circular(8),
                border: material.craftable
                    ? Border.all(color: Colors.white, width: 2)
                    : null,
              ),
              child: Column(
                children: [
                  Text(
                    material.label,
                    style: TextStyle(
                      fontSize: 10,
                      color: material == PaperMaterial.graphite
                          ? Colors.white
                          : Colors.black,
                    ),
                  ),
                  Text(
                    '${model.balances[material]}',
                    style: TextStyle(
                      color: material == PaperMaterial.graphite
                          ? Colors.white
                          : Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  ));

  Widget _bottomControls() {
    final selected = model.objects[model.editId ?? model.activePlane?.owner];
    final linear = selected?.linear;
    final candidate = model.previewObject;
    final harvest = model.harvestPreview;
    final yields = harvest?.units;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (selected != null && linear != null && model.draft.path.isEmpty)
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xe6222222),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Decrease extent',
                  onPressed: linear.extent > .25
                      ? () => model.resizeLinear(
                          selected.id,
                          extent: linear.extent - .25,
                        )
                      : null,
                  icon: const Icon(Icons.remove),
                ),
                Text(
                  '${selected.kind == CraftKind.wall ? 'Height' : 'Reach'} ${linear.extent.toStringAsFixed(2)}',
                ),
                IconButton(
                  tooltip: 'Increase extent',
                  onPressed: () => model.resizeLinear(
                    selected.id,
                    extent: linear.extent + .25,
                  ),
                  icon: const Icon(Icons.add),
                ),
                if (selected.kind == CraftKind.floor)
                  TextButton(
                    onPressed: () =>
                        model.resizeLinear(selected.id, flip: true),
                    child: const Text('Flip'),
                  ),
              ],
            ),
          ),

        if (yields != null || harvestNotice != null)
          Container(
            key: const ValueKey('harvest-yield'),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (const Color(0xe6222222)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final color in model.materials)
                  if ((yields?[color] ?? harvestNotice?[color] ?? 0) > 0)
                    Text(
                      '${color.label} +${yields != null ? ((yields[color] ?? 0) + model.landscape.remainders[color]! + 1e-9).floor() : harvestNotice![color]}',
                      style: TextStyle(
                        color: color == PaperMaterial.graphite
                            ? Colors.white70
                            : paperColors[color],
                        fontSize: 12,
                      ),
                    ),
              ],
            ),
          ),
        if (candidate != null &&
            (model.drawingReady ||
                (model.tool == CraftTool.volume &&
                    model.editId != null &&
                    model.draft.path.isEmpty)))
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (const Color(0xe6222222)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (viewport.width > 420 && viewport.height > 520)
                      SizedBox(
                        width: 86,
                        height: 64,
                        child: _ObjectPreview(
                          object: candidate,
                          plane: model.objectPlane(candidate),
                        ),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            candidate.kind.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${model.quote} units',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                          if (model.tool == CraftTool.volume)
                            Text(
                              'Depth ${model.previewDepth.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Clear',
                      onPressed: model.clearDraft,
                      icon: const Icon(Icons.close, size: 18),
                    ),
                    if (model.editId == null &&
                        !model.closed &&
                        !devSettings.resetDrawingOnRelease)
                      FilledButton(
                        onPressed: () => _completeDrawing(allowOpen: true),
                        child: const Text('Finish'),
                      ),
                    if (model.editId != null)
                      FilledButton(
                        onPressed: () {
                          if (model.draft.path.isNotEmpty) {
                            _completeDrawing(allowOpen: true);
                          } else {
                            model.applyEdit();
                          }
                        },
                        child: const Text('Apply'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        if (candidate == null && model.draft.path.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: _button('Clear', Icons.close, model.clearDraft),
          ),
        const SizedBox(height: 8),
        if (!model.paperSurface)
          SizedBox(
            height: 46,
            child: PageView.builder(
              key: ValueKey(model.activePlaneId),
              controller: gridPager,
              itemCount: model.activePlane!.grids.length,
              onPageChanged: (i) {
                outgoingGrid = model.grid;
                model.selectGrid(i);
                acetate.forward(from: 0);
              },
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: model.gridIndex == i
                        ? ((const Color(0xcc555555)))
                        : ((const Color(0x99292929))),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Text(
                    model.terrainColumn.isNotEmpty
                        ? 'Ground'
                        : model.activePlane!.grids[i].name,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ),
            ),
          ),
      ],
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

class _ObjectPreview extends StatefulWidget {
  const _ObjectPreview({required this.object, required this.plane});
  final CraftObject object;
  final CraftPlane plane;
  @override
  State<_ObjectPreview> createState() => _ObjectPreviewState();
}

class _ObjectPreviewState extends State<_ObjectPreview> {
  late final Scene scene;
  @override
  void initState() {
    super.initState();
    scene = Scene(globalIllumination: .8);
    _update();
  }

  @override
  void didUpdateWidget(covariant _ObjectPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  void _update() {
    final p = widget.plane, o = widget.object;
    final center = p.point(o.region.bounds.center, o.depth * .5);
    final extent = math.max(
      math.max(o.region.bounds.width, o.region.bounds.height),
      o.depth,
    );
    scene.camera = Camera(
      name: 'Craft preview',
      position:
          center +
          (p.normal * 1.6 + p.u - p.v * .6).normalized() *
              math.max(.2, extent * 2.7),
      target: center,
      up: p.v,
      fovDegrees: 40,
      near: .001,
    );
    scene.setMeshes(objectMeshes(o, p));
  }

  @override
  Widget build(BuildContext context) => SceneView(scene: scene);
  @override
  void dispose() {
    scene.dispose();
    super.dispose();
  }
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
