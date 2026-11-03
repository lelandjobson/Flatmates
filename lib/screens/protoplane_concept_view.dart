import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../geometry/geometry.dart';
import '../gestures/game_controls.dart';
import '../gestures/point_scrub.dart';
import '../protoplane/controller.dart';
import '../protoplane/geometry.dart';
import '../protoplane/meshes.dart';
import '../protoplane/models.dart';
import '../protoplane/plane_navigation.dart';
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
  });
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
  late final ProtoplaneController model;
  late final ProtoplaneStorage storage;
  final devSettings = ProtoplaneSettings();
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
      pointGlow,
      contextFade,
      focusZoom;
  CraftPlane? contextPlane;
  final Map<String, double> contextOpacity = {}, baseOpacity = {};
  Set<String> focusedMeshIds = {};
  bool autoCreating = false;
  List<Offset> completedTrace = [];
  Offset? livePointer;
  int _lastStrokeLength = 0;
  final pointScrub = PointScrub();
  Timer? backtrackHold;
  int? heldNode, blockedNode;
  String? gestureDraftKey;
  Offset? flashPoint;
  bool flashRemoved = false;
  List<int> lastFlashPath = [];
  String? lastFlashKey;
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
  final Map<int, Offset> pointers = {};
  final planeSwipe = PlaneSwipe();
  final Set<int> multiMoved = {};
  Offset? down, previous;
  bool secondary = false,
      moved = false,
      drawing = false,
      pulling = false,
      multi = false;
  double lastSpan = 0, pinch = 1, pullStartDepth = 0;
  double trackpadScale = 1;
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
    if (widget.controller == null) unawaited(_loadDevSettings());
    model = widget.controller ?? ProtoplaneController();
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
    transition = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..addListener(_animateCamera);
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
      duration: const Duration(milliseconds: 280),
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
    _refreshScene();
    if (widget.controller != null && widget.storage == null) {
      loading = false;
      model.onCommitted = null;
    } else {
      unawaited(_load());
    }
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

  void _applyDevSettings() {
    final lighting = DayNightLighting.day().copyWith(
      globalIllumination: devSettings.ambient,
      keyIntensity: devSettings.sun,
    );
    scene.globalIllumination = lighting.globalIllumination;
    scene.setLights(lighting.lights);
    _applyHighlight();
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

  void _modelChanged() {
    if (_disposed) return;
    final path = model.draft.path;
    if (lastFlashKey == model.draftKey &&
        model.grid != null &&
        path.length != lastFlashPath.length) {
      final removed = !autoCreating && path.length < lastFlashPath.length;
      final node = path.isEmpty
          ? lastFlashPath.last
          : removed
          ? lastFlashPath.last
          : path.last;
      if (node < model.grid!.nodes.length) {
        flashPoint = model.grid!.nodes[node];
        flashRemoved = removed;
        pointGlow.forward(from: 0);
      }
    } else if (lastFlashKey != model.draftKey) {
      flashPoint = null;
      _resetPointGestures();
    }
    lastFlashKey = model.draftKey;
    lastFlashPath = List.of(path);
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
      completedTrace = [];
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || transition.isAnimating) return;
        if (gridPager.hasClients) gridPager.jumpToPage(model.gridIndex);
        if (model.activePlane == null) {
          _restoreWorld();
        } else {
          _focusPlane();
        }
      });
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

  void _refreshScene() {
    final meshes = <Mesh>[];
    contextOpacity.clear();
    final active = model.activePlane;
    if (active == null) {
      meshes.addAll(
        model.planes.values
            .where((p) => !p.id.startsWith('surface-') && !model.isPlane(p.id))
            .map(planeMesh),
      );
      // Ground tiles remain visible in their unoccupied portions.
      for (final p in model.planes.values.where(
        (p) => p.id.startsWith('ground-') && model.isPlane(p.id),
      )) {
        meshes.add(planeMesh(p));
      }
      for (final o in model.objects.values) {
        final p = model.planes[o.planeId];
        if (p != null) meshes.addAll(objectMeshes(o, p));
      }
    } else {
      meshes.add(planeMesh(active)..groundPlane = true);
      final edit = model.editId;
      for (final o in model.objects.values) {
        if (o.id == edit) continue;
        final belongsToFloor =
            model.objects[active.owner]?.kind == CraftKind.floor &&
            supportingFloor(o.id, model.objects, model.planes) == active.owner;
        if (o.planeId == active.id ||
            o.id == active.owner ||
            (belongsToFloor &&
                o.kind != CraftKind.wall &&
                o.kind != CraftKind.window &&
                o.kind != CraftKind.door)) {
          final existing = objectMeshes(
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
      if (candidate != null) {
        final cuts = model.cutObjects;
        if (cuts != null && edit != null) {
          for (var i = 0; i < cuts.length; i++) {
            meshes.addAll(
              objectMeshes(cuts[i].copyWith(id: 'cut-$i'), active, opacity: .9),
            );
          }
        } else {
          meshes.addAll(
            objectMeshes(candidate, active, opacity: preview ? 1 : .75),
          );
        }
      }
    }
    if (active != null) {
      focusedMeshIds = meshes.map((m) => m.id).toSet();
      void addContext(Iterable<Mesh> additions, CraftPlane p) {
        final target =
            adjacentFocusContext(active, p, model.objects, model.planes)
            ? .18
            : 0.0;
        if (target == 0 && contextFade.value >= .999) return;
        for (final mesh in additions) {
          if (focusedMeshIds.contains(mesh.id)) continue;
          meshes.add(mesh);
          contextOpacity[mesh.id] = target;
        }
      }

      for (final p in model.planes.values.where(
        (p) => !p.id.startsWith('surface-'),
      )) {
        if (!focusedMeshIds.contains(p.id)) addContext([planeMesh(p)], p);
      }
      for (final object in model.objects.values) {
        if (object.id != model.editId && !focusedMeshIds.contains(object.id)) {
          addContext(
            objectMeshes(object, model.planes[object.planeId]!),
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
              )
              ? .18
              : 0;
        }
      }
    }
    baseOpacity
      ..clear()
      ..addEntries(meshes.map((m) => MapEntry(m.id, m.material.opacity)));
    baseColors
      ..clear()
      ..addEntries(meshes.map((m) => MapEntry(m.id, m.material.color)));
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
    for (final m in scene.meshes) {
      baseColors.putIfAbsent(m.id, () => m.material.color);
    }
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
      mesh.material = MaterialModel(
        color: Color.lerp(
          baseColors[mesh.id] ?? original.color,
          isPlane ? const Color(0xff9a8eec) : Colors.white,
          strength * .72,
        )!,
        opacity: opacity,
        doubleSided: true,
        strokeEdges: isPlane && contextTarget != null,
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
    scene.markNeedsPaint();
    setState(() {});
  }

  void _focusPlane() {
    final plane = model.activePlane;
    if (plane == null || viewport.isEmpty) return;
    final pose = focusPlanePose(camera, plane, viewport, preview: preview);
    semiFocusPose = _Pose.at(pose.position, pose.target, pose.up, pose.fov);
    final full = focusPlanePose(camera, plane, viewport, fullFocus: true);
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
    model.enter(model.planes.containsKey(surface) ? surface : hit.plane);
  }

  void _restoreWorld() {
    preview = false;
    selectedObject = null;
    final target = worldPose;
    if (target == null) return;
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
      if (!plane.id.startsWith('surface-')) {
        consider(plane, plane.region, null, 0);
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
    backtrackHold?.cancel();
    backtrackHold = null;
    heldNode = blockedNode = null;
    pointScrub.reset();
  }

  Offset? _nodeScreen(int node) => camera.projectToScreen(
    model.activePlane!.point(model.grid!.nodes[node], .008),
    viewport,
  );

  bool _pointGesture(Offset at, Duration time) {
    if (preview ||
        transition.isAnimating ||
        model.tool != CraftTool.scissors ||
        model.activePlane == null ||
        multi ||
        secondary ||
        pointers.length > 1) {
      _resetPointGestures();
      return false;
    }
    if (gestureDraftKey != model.draftKey) {
      _resetPointGestures();
      gestureDraftKey = model.draftKey;
    }
    if (blockedNode != null) {
      final screen = _nodeScreen(blockedNode!);
      if (screen != null && (screen - at).distance < 30) return true;
      blockedNode = null;
    }
    final path = model.draft.path;
    // Resolve the nearest actual dot first: a nearby past dot must never
    // steal a gesture aimed at the start/last/new dot on a dense grid.
    final nearest = _nodeAt(at);
    final previousNode =
        nearest != null &&
            path.length > 2 &&
            nearest != path.first &&
            nearest != path.last &&
            path.contains(nearest)
        ? nearest
        : null;
    final previousScreen = previousNode == null
        ? null
        : _nodeScreen(previousNode);
    if (previousScreen != null && (previousScreen - at).distance < 24) {
      if (heldNode != previousNode) {
        backtrackHold?.cancel();
        heldNode = previousNode;
        final key = model.draftKey, expected = List<int>.of(path);
        backtrackHold = Timer(const Duration(milliseconds: 500), () {
          if (!mounted ||
              preview ||
              model.draftKey != key ||
              model.tool != CraftTool.scissors ||
              !listEquals(model.draft.path, expected)) {
            return;
          }
          final removed = model.draft.path.last;
          if (model.rewindDraftTo(previousNode!, continuous: drawing)) {
            blockedNode = removed;
            moved = true;
            segmentGlow.value = 1;
          }
          heldNode = null;
        });
      }
      pointScrub.reset();
      return true;
    }
    backtrackHold?.cancel();
    backtrackHold = null;
    heldNode = null;
    if (path.isNotEmpty) {
      final screen = _nodeScreen(path.last);
      if (screen != null && pointScrub.update(at, screen, time)) {
        _eraseLastPoint();
        return true;
      }
    }
    return false;
  }

  void _eraseLastPoint() {
    final removed = model.draft.path.last;
    backtrackHold?.cancel();
    heldNode = null;
    pointScrub.reset();
    model.removeLastDraftNode(continuous: drawing);
    blockedNode = removed;
    moved = true;
    segmentGlow.value = 1;
  }

  Offset? _local(Offset at, [double depth = 0]) {
    final plane = model.activePlane;
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
    if (loading || loadFailed || transition.isAnimating) return;
    _resetPointGestures();
    controls.begin(e.kind, e.localPosition);
    pointers[e.pointer] = e.localPosition;
    if (pointers.length > 1) {
      _resetPointGestures();
      if (drawing || pulling) model.cancelGesture();
      drawing = false;
      livePointer = null;
      pulling = false;
      if (!multi) {
        planeSwipe.start(pointers.values);
      } else {
        planeSwipe.consumed = true;
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
    if (!controls.profile.canActivate(e.buttons)) return;
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
    } else if (!preview && model.tool == CraftTool.scissors && !secondary) {
      final node = _nodeAt(e.localPosition);
      if (node != null) {
        model.beginGesture();
        drawing = true;
        livePointer = controls.craftingAim(e.localPosition);
        if (!_pointGesture(e.localPosition, e.timeStamp) &&
            !model.draft.path.contains(node)) {
          model.appendNode(node);
        }
      }
    }
  }

  void _move(PointerMoveEvent e) {
    if (!pointers.containsKey(e.pointer)) return;
    controls.move(e.kind, e.localPosition);
    final oldPositions = pointers.values.toList();
    pointers[e.pointer] = e.localPosition;
    final delta = e.localPosition - (previous ?? e.localPosition);
    if (down != null && (e.localPosition - down!).distance > 6) moved = true;
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
        MediaQuery.sizeOf(context).shortestSide / 3,
      );
      if (swipe != null && model.activePlane != null) {
        _navigatePlane(swipe);
      } else if (!planeSwipe.consumed && !transition.isAnimating) {
        _navigateMulti(dx, ratio);
      } else if (model.activePlane == null && !transition.isAnimating) {
        _navigateMulti(dx, ratio);
      }
      lastSpan = span;
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
    } else if (drawing) {
      livePointer = controls.craftingAim(e.localPosition);
      if (_pointGesture(e.localPosition, e.timeStamp)) {
        previous = e.localPosition;
        setState(() {});
        return;
      }
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
        if (node == blockedNode ||
            (path.contains(node) && node != path.first)) {
          continue;
        }
        if (model.appendNode(node)) {
          pointScrub.reset();
          if (_completeDrawing()) break;
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
    autoCreating = true;
    final created = model.completeCraft(allowOpen: allowOpen);
    autoCreating = false;
    if (created) {
      completedTrace = trace;
      segmentGlow.forward(from: 0);
      drawing = false;
      livePointer = null;
      moved = true;
    }
    return created;
  }

  void _up(PointerUpEvent e) {
    _resetPointGestures();
    if (!pointers.containsKey(e.pointer)) return;
    controls.move(e.kind, e.localPosition);
    controls.end();
    pointers.remove(e.pointer);
    if (pointers.isNotEmpty) return;
    if (drawing && model.editId == null && devSettings.resetDrawingOnRelease) {
      _completeDrawing(allowOpen: true);
    }
    if (drawing || pulling) {
      model.finishGesture(
        resetDrawing:
            drawing && devSettings.resetDrawingOnRelease && model.error == null,
      );
    }
    if (!moved && !multi && !drawing && !pulling && !secondary) {
      _tap(e.localPosition);
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
    _resetPointGestures();
    pointers.clear();
    controls.cancel();
    if (drawing || pulling) model.cancelGesture();
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
    _resetPointGestures();
    if (loading || loadFailed || transition.isAnimating) return;
    if (drawing || pulling) model.cancelGesture();
    drawing = pulling = false;
    livePointer = null;
    controls.begin(event.kind, event.localPosition);
    trackpadScale = 1;
    pinch = 1;
  }

  void _trackpadUpdate(PointerPanZoomUpdateEvent event) {
    if (loading || loadFailed || transition.isAnimating) return;
    controls.move(event.kind, event.localPosition);
    _navigateMulti(event.panDelta.dx, event.scale / trackpadScale);
    trackpadScale = event.scale;
  }

  void _trackpadEnd(PointerPanZoomEndEvent event) {
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
    final now = DateTime.now();
    final local = _local(point);
    final objectHit =
        local != null &&
        model.objects.values.any(
          (o) => o.planeId == model.activePlaneId && o.region.contains(local),
        );
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
      final object = model.objects.values.firstWhere(
        (o) => o.planeId == model.activePlaneId && o.region.contains(local),
      );
      selectedObject = object.id;
      model.enter('surface-${object.id}');
    }
  }

  void _scroll(PointerSignalEvent e) {
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
    return Scaffold(
      backgroundColor: const Color(0xff0c1018),
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
          return Stack(
            children: [
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
                        model.activePlane == null && controls.hidesSystemCursor
                        ? SystemMouseCursors.none
                        : SystemMouseCursors.basic,
                    onEnter: (e) => controls.hover(e.kind, e.localPosition),
                    onExit: (_) {
                      controls.exit();
                      _resetPointGestures();
                    },
                    onHover: (e) {
                      controls.hover(e.kind, e.localPosition);
                      _pointGesture(e.localPosition, e.timeStamp);
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        SceneView(scene: scene),
                        FriendEyeOverlay(
                          friends: residents.friends,
                          camera: camera,
                          viewport: viewport,
                          tileSize: 1,
                          subtilesPerTile: BedroomResidents.subtiles,
                          listenable: scene,
                        ),
                        IgnorePointer(
                          child: CustomPaint(
                            painter: _GridPainter(
                              model,
                              camera,
                              preview: preview,
                              acetate: acetate.value,
                              outgoingGrid: outgoingGrid,
                              livePointer: drawing ? livePointer : null,
                              segmentPulse: 1 - segmentGlow.value,
                              completedTrace: completedTrace,
                              flashPoint: flashPoint,
                              pointPulse: 1 - pointGlow.value,
                              flashRemoved: flashRemoved,
                              showGridLines: devSettings.gridLines,
                              hover: hover?.id,
                              previousHover: previousHover,
                              hoverFade: glow.value,
                              focusFade: Curves.easeInOutSine.transform(
                                contextFade.value,
                              ),
                            ),
                          ),
                        ),
                      ],
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
                  child: Column(
                    children: [
                      Row(
                        children: [
                          DevToolsButton(
                            active: false,
                            onPressed: () => showProtoplaneDevTools(
                              context,
                              devSettings,
                              settingsStore,
                              _applyDevSettings,
                              initialError: settingsError,
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
                                            .objects[model.activePlane!.owner]
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
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          GameViewUndoRedoBar(
                            canUndo: model.canUndo && !loading && !loadFailed,
                            canRedo: model.canRedo && !loading && !loadFailed,
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
              if (model.activePlane != null && !loading && !loadFailed) ...[
                Positioned(
                  left: 10,
                  top: math.max(130, viewport.height * .35),
                  child: _tools(),
                ),
                Positioned(
                  right: 10,
                  top: math.max(130, viewport.height * .35),
                  child: _paperSelector(),
                ),
                Positioned(
                  bottom: 12 + MediaQuery.paddingOf(context).bottom,
                  left: 76,
                  right: 76,
                  child: _bottomControls(),
                ),
              ],
              if (loading) const Center(child: CircularProgressIndicator()),
            ],
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
          ? const Color(0xff675b92)
          : const Color(0xdd252c39),
      foregroundColor: Colors.white,
      minimumSize: const Size(44, 44),
    ),
    icon: Icon(icon, size: 21),
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

  Widget _tools() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _button(
        'Scissors',
        Icons.content_cut,
        () => model.selectTool(CraftTool.scissors),
        active: model.tool == CraftTool.scissors,
      ),
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
    ],
  );

  Widget _paperSelector() => GestureDetector(
    onVerticalDragEnd: (details) {
      final direction = (details.primaryVelocity ?? 0) < 0 ? 1 : -1;
      model.selectPaper(PaperColor.values[(model.paper.index + direction) % 3]);
    },
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final offset in [-1, 0, 1])
          Builder(
            builder: (context) {
              final color = PaperColor.values[(model.paper.index + offset) % 3];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: GestureDetector(
                  onTap: () => model.selectPaper(color),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: offset == 0 ? 48 : 34,
                    height: offset == 0 ? 60 : 35,
                    decoration: BoxDecoration(
                      color: paperColors[color]!.withValues(
                        alpha: offset == 0 ? 1 : .4,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: offset == 0
                          ? Border.all(color: Colors.white, width: 2)
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: offset == 0
                        ? Text(
                            '${model.balances[color]}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xff30303a),
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                ),
              );
            },
          ),
      ],
    ),
  );

  Widget _bottomControls() {
    final candidate = model.previewObject;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (candidate != null)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xe61b2230),
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
                          plane: model.activePlane!,
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
                        onPressed: model.applyEdit,
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
                      ? const Color(0xcc55506f)
                      : const Color(0x99252c39),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  model.activePlane!.grids[i].name,
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
  void dispose() {
    _disposed = true;
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
    pointGlow.dispose();
    _resetPointGestures();
    controls.dispose();
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
    this.completedTrace = const [],
    this.flashPoint,
    this.pointPulse = 0,
    this.flashRemoved = false,
    this.outgoingGrid,
    this.hover,
    this.previousHover,
    this.showGridLines = false,
    this.hoverFade = 1,
    this.focusFade = 1,
  });
  final ProtoplaneController model;
  final Camera camera;
  final bool preview;
  final double acetate;
  final Offset? livePointer;
  final double segmentPulse;
  final List<Offset> completedTrace;
  final Offset? flashPoint;
  final double pointPulse;
  final bool flashRemoved;
  final CraftGrid? outgoingGrid;
  final String? hover, previousHover;
  final double hoverFade, focusFade;
  final bool showGridLines;
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
        canvas.drawPath(
          projected(p, p.region.outer, close: true),
          Paint()
            ..color = p.id == hover
                ? const Color(0xffa39aed)
                : const Color(0x664a586f)
            ..style = PaintingStyle.stroke
            ..strokeWidth = p.id == hover ? 2 : 1,
        );
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
              ..color = const Color(0xffb8adff).withValues(alpha: .22 * opacity)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
          );
          drawDot(
            canvas,
            surface,
            node,
            size,
            .008,
            3.5,
            Paint()..color = Color.fromRGBO(186, 199, 221, opacity),
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
      Paint()..color = Color.fromRGBO(168, 181, 212, .045 * progress),
    );
    canvas.drawPath(
      outline,
      Paint()
        ..color = Color.fromRGBO(150, 165, 196, .24 * progress)
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
      final screen = camera.projectToScreen(plane.point(p, lift), size);
      if (screen == null) continue;
      drawDot(
        canvas,
        plane,
        p,
        size,
        lift,
        7,
        Paint()..color = const Color(0xff121824),
        grid.dotStyle(nodeIndex),
      );
      drawDot(
        canvas,
        plane,
        p,
        size,
        lift,
        3.5,
        Paint()..color = Color.fromRGBO(186, 199, 221, progress),
        grid.dotStyle(nodeIndex),
      );
    }
    final completion =
        model.trace.isEmpty && segmentPulse > 0 && completedTrace.isNotEmpty;
    final trace = completion ? completedTrace : model.trace;
    if (trace.length > 1) {
      final valid =
          completion || model.matches.isNotEmpty || model.cutObjects != null;
      final color = valid
          ? Colors.white
          : Color.lerp(paperColors[model.paper], Colors.white, .3)!;
      final path = projected(plane, trace, lift: lift + .001);
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white.withValues(alpha: valid ? .65 : .18)
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
            ..color = Colors.white.withValues(alpha: .4 * segmentPulse)
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
        final color = paperColors[model.paper]!;
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
    if (flashPoint != null && pointPulse > 0) {
      final point = camera.projectToScreen(
        plane.point(flashPoint!, lift + .003),
        size,
      );
      if (point != null) {
        final color = flashRemoved ? const Color(0xffff525e) : Colors.white;
        canvas.drawCircle(
          point,
          13,
          Paint()
            ..color = color.withValues(alpha: .8 * pointPulse)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
        );
        canvas.drawCircle(
          point,
          5,
          Paint()..color = color.withValues(alpha: pointPulse),
        );
      }
    }
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
