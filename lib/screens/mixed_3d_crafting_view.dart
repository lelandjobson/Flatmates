import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../animation/scene_animatables.dart';
import '../crafting/crafting_blueprint.dart';
import '../crafting/folded_geometry_blueprint.dart';
import '../data/crafting_state.dart';
import '../geometry/folded_geometry.dart';
import '../geometry/geometries.dart';
import '../geometry/geometry.dart';
import '../rendering/lights.dart';
import '../rendering/mesh.dart';
import '../rendering/scene/camera.dart';
import '../rendering/scene/camera_controller.dart';
import '../rendering/scene/face_focus_picker.dart';
import '../rendering/scene/object_focus_picker.dart';
import '../rendering/scene/scene.dart';
import '../rendering/scene/scene_hit_tester.dart';
import '../rendering/scene_view.dart';
import '../ui/crafting_workstation.dart';
import '../ui/fm_dev_back_button.dart';
import '../ui/fm_safe_area.dart';
import '../ui/fm_screen.dart';
import '../theme/world_theme.dart';
import '../ui/fm_theme.dart';
import '../utils/math_utils.dart';

enum MixedCraftSelectMode { face, object }

enum _CameraTool { orbit, pan, zoom }

enum _FocusPhase { free, focusing, focused, returning }

/// Default craft canvas / ortho stubs (face.extent / object bounds wired later).
double craftCanvasSizeForFace(FocusedFace face) {
  // ignore: unused_local_variable
  final _ = face.extent;
  return 400.0;
}

double craftOrthoForFace(FocusedFace face) {
  final _ = face.extent;
  return 440.0;
}

double craftCanvasSizeForObject({required double objectExtent}) {
  final _ = objectExtent;
  return 400.0;
}

double craftOrthoForObject({required double objectExtent}) {
  final _ = objectExtent;
  return 440.0;
}

class Mixed3dCraftingView extends StatefulWidget {
  const Mixed3dCraftingView({super.key});

  @override
  State<Mixed3dCraftingView> createState() => _Mixed3dCraftingViewState();
}

class _Mixed3dCraftingViewState extends State<Mixed3dCraftingView>
    with TickerProviderStateMixin {
  static const String _cubeMeshId = 'mixed-cube';
  /// Matches cube blueprint edge (8 grid units × minorGridSpacing 12.5 @ canvas 400).
  static const double _cubeSize = 100;

  late final Scene _scene;
  late final OrbitCameraController _orbit;
  late final FoldedGeometry _foldedCube;
  late final Mesh _cubeMesh;
  late final MeshUnfoldAnimatable _unfoldAnimatable;

  late final AnimationController _highlightController;
  late final AnimationController _focusController;
  late final AnimationController _morphController;
  late final AnimationController _craftFadeController;

  final FaceFocusPicker _facePicker = const FaceFocusPicker();
  final ObjectFocusPicker _objectPicker = const ObjectFocusPicker();
  final CraftingStateStore _craftState = CraftingStateStore();
  final GlobalKey<CraftingTestViewState> _craftKey =
      GlobalKey<CraftingTestViewState>();

  MixedCraftSelectMode _mode = MixedCraftSelectMode.face;
  _FocusPhase _phase = _FocusPhase.free;
  _CameraTool _cameraTool = _CameraTool.orbit;

  /// Host-drawn unfold wireframe; hidden after handoff to craft blueprint.
  bool _showObjectWireframe = false;

  FocusedFace? _faceContender;
  FocusedFace? _pendingFaceContender;
  String? _objectContenderId;
  String? _pendingObjectContenderId;
  FocusedFace? _focusedFace;

  Timer? _contenderDebounce;
  Timer? _contenderSwitchTimer;

  Size _viewportSize = Size.zero;

  // Saved free-orbit camera
  Vector3? _savedPosition;
  Vector3? _savedTarget;
  Vector3? _savedUp;
  ProjectionType? _savedProjection;
  double? _savedOrthoScale;
  double? _savedFov;

  // Focus camera lerp
  Vector3? _camFromPos;
  Vector3? _camToPos;
  Vector3? _camFromTarget;
  Vector3? _camToTarget;
  Vector3? _camFromUp;
  Vector3? _camToUp;
  double? _camFromOrtho;
  double? _camToOrtho;
  ProjectionType? _camToProjection;

  // Face morph: fill fade + outline color/width
  double _meshFillOpacity = 1.0;
  double _outlineMix = 0; // 0 = yellow thick, 1 = white thin

  // Object focus: mesh rotation to align flat net (XZ/Y-up) → craft XY/Z-up
  double _objectAlignRx = 0;
  double _objectAlignRxFrom = 0;
  double _objectAlignRxTo = 0;
  Vector3? _meshPosFrom;
  Vector3? _meshPosTo;
  bool _recenterMeshDuringFocus = false;

  // Craft overlay params
  double _craftCanvasSize = 400;
  double _craftOrtho = 440;
  // Reserved for future object↔craft scale lock.
  // ignore: unused_field
  double _objectWorldToCraftScale = 1.0;
  bool _showCraft = false;
  bool _craftInteractive = false;

  // Gesture state (from SceneWidget)
  Offset? _lastTouchFocalPoint;
  double _lastTouchScale = 1.0;
  int _mouseButtons = 0;
  int _lastTouchPointerCount = 0;

  MaterialModel _baseMaterial = const MaterialModel.ghost();
  final MaterialModel _wireMaterial = const MaterialModel(
    color: Color(0xFFFFFFFF),
    wireframe: true,
    doubleSided: true,
    opacity: 0.15,
  );

  /// Per-face colors from the last completed craft; null = still a ghost.
  List<Color>? _craftedFaceColors;

  @override
  void initState() {
    super.initState();

    _highlightController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() => setState(() {}));

    _focusController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    )
      ..addListener(_onFocusTick)
      ..addStatusListener(_onFocusStatus);

    _morphController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    )..addListener(_onMorphTick);

    _craftFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..addListener(() => setState(() {}));

    _scene = Scene(globalIllumination: 0.28);
    const d = 380.0;
    final camera = Camera(
      name: 'Mixed3dCamera',
      position: Vector3(d * 0.75, d * 0.65, d * 0.75),
      target: Vector3.zero(),
      projection: ProjectionType.perspective,
      fovDegrees: 55,
      near: 1,
      far: d * 6,
      orthographicScale: 220,
    );
    _orbit = OrbitCameraController(camera: camera, target: Vector3.zero())
      ..addListener(_onCameraChanged);

    _scene
      ..addLight(
        DirectionalLight(
          color: Colors.white,
          intensity: 0.9,
          direction: Vector3(-0.6, -1, -0.4),
        ),
      )
      ..camera = camera;

    _foldedCube = GeodesicFoldFactories.cube(_cubeSize);
    final foldedGeom = ensureOutwardFacingGeometry(
      _foldedCube.toGeometry(foldValue: 1),
    );
    final unfoldedGeom = ensureOutwardFacingGeometry(
      _foldedCube.toGeometry(foldValue: 0),
    );
    _cubeMesh = Mesh(
      id: _cubeMeshId,
      name: 'Mixed Cube',
      geometry: foldedGeom,
      material: _baseMaterial,
    );
    _unfoldAnimatable = MeshUnfoldAnimatable(
      vsync: this,
      mesh: _cubeMesh,
      foldedGeometry: _foldedCube,
      unfoldedGeometry: unfoldedGeom,
      duration: const Duration(milliseconds: 900),
      initiallyUnfolded: false,
      onFoldAnimationCompleted: _onFoldAnimationCompleted,
    );
    _scene.addAnimatable(_unfoldAnimatable);
    _scene.addListener(_onSceneChanged);
  }

  void _onFoldAnimationCompleted() {
    if (!mounted) return;
    if (_mode != MixedCraftSelectMode.object) return;
    if (_phase != _FocusPhase.focusing && _phase != _FocusPhase.focused) {
      return;
    }
    if (_unfoldAnimatable.isUnfolded) {
      _handoffUnfoldedNetToCraft();
    }
  }

  /// Transfer the live unfolded net into the craft view as the fill blueprint,
  /// matching craft camera to the host ortho view, then hide the host outline.
  void _handoffUnfoldedNetToCraft() {
    // Ensure mesh pose is settled at the centered flat net.
    _recenterMeshDuringFocus = false;
    _centerUnfoldedMesh();

    final world = Matrix4.copy(_cubeMesh.transformMatrix);
    final blueprint = craftingBlueprintFromFoldedGeometry(
      folded: _foldedCube,
      worldFromLocal: world,
      craft: 'cube',
      foldedGeometryId: _foldedCube.id,
    );

    void tryApply() {
      if (!mounted) return;
      final craftState = _craftKey.currentState;
      if (craftState == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => tryApply());
        return;
      }
      craftState.applyBlueprint(
        blueprint,
        panOffset: Offset.zero,
        orthoScale: _craftOrtho,
        viewRotation: 0,
      );
      setState(() {
        _showObjectWireframe = false;
        _craftInteractive = true;
        if (_phase == _FocusPhase.focusing) {
          _phase = _FocusPhase.focused;
        }
      });
    }

    tryApply();
  }

  void _onSceneChanged() {
    if (!mounted) return;
    // Keep object-focus wireframe overlay in sync with fold animation frames.
    if (_mode == MixedCraftSelectMode.object &&
        _phase != _FocusPhase.free) {
      if (_recenterMeshDuringFocus) {
        _centerUnfoldedMesh();
      }
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Keep uncrafted cube in theme ghost material.
    if (_craftedFaceColors == null && _phase == _FocusPhase.free) {
      final ghost = FmThemeData.of(context).ghostMaterial;
      if (_cubeMesh.material.color != ghost.color ||
          _cubeMesh.material.opacity != ghost.opacity) {
        _baseMaterial = ghost;
        _cubeMesh.material = ghost;
        _scene.markNeedsPaint();
      }
    }
  }

  @override
  void dispose() {
    _contenderDebounce?.cancel();
    _contenderSwitchTimer?.cancel();
    _orbit
      ..removeListener(_onCameraChanged)
      ..dispose();
    _scene.removeListener(_onSceneChanged);
    _highlightController.dispose();
    _focusController.dispose();
    _morphController.dispose();
    _craftFadeController.dispose();
    _scene.dispose();
    super.dispose();
  }

  void _onCameraChanged() {
    _scene.markNeedsPaint();
    if (_phase != _FocusPhase.free) return;
    // Always repaint so the candidate outline reprojects with the camera.
    // Contender identity changes are applied with a short settle delay so we
    // keep the current outline until the next pick is stable.
    setState(() {});
    _scheduleContenderUpdate();
  }

  void _scheduleContenderUpdate() {
    _contenderDebounce?.cancel();
    _contenderDebounce = Timer(const Duration(milliseconds: 50), () {
      if (!mounted || _phase != _FocusPhase.free) return;
      _updateContender();
    });
  }

  void _updateContender() {
    if (_viewportSize == Size.zero || _scene.camera == null) return;

    if (_mode == MixedCraftSelectMode.face) {
      final next = _facePicker.pick(
        scene: _scene,
        camera: _scene.camera!,
        viewportSize: _viewportSize,
      );
      final changed = next?.meshId != _faceContender?.meshId ||
          next?.faceIndex != _faceContender?.faceIndex;
      if (!changed) {
        // Same face — ensure highlight is visible if we have a contender.
        if (next != null && _highlightController.value < 1) {
          _highlightController.forward();
        }
        return;
      }

      // Switching or clearing: fade out old, then apply after a short hold.
      _pendingFaceContender = next;
      if (_faceContender != null && next == null) {
        // Losing a candidate — reverse highlight, clear after fade.
        _highlightController.reverse().whenComplete(() {
          if (!mounted || _pendingFaceContender != null) return;
          setState(() => _faceContender = null);
        });
        return;
      }
      if (_faceContender != null && next != null) {
        // Switch: keep old outline until settled, then swap.
        _contenderSwitchTimer?.cancel();
        _contenderSwitchTimer = Timer(const Duration(milliseconds: 80), () {
          if (!mounted || _phase != _FocusPhase.free) return;
          if (_pendingFaceContender?.meshId != next.meshId ||
              _pendingFaceContender?.faceIndex != next.faceIndex) {
            return;
          }
          setState(() => _faceContender = next);
          _highlightController.forward(from: 0);
        });
        return;
      }
      // Gaining first candidate
      setState(() => _faceContender = next);
      _highlightController.forward(from: 0);
      if (_objectContenderId != null) {
        setState(() => _objectContenderId = null);
      }
    } else {
      final meshId = _objectPicker.pickMeshId(
        scene: _scene,
        camera: _scene.camera!,
        viewportSize: _viewportSize,
      );
      if (meshId == _objectContenderId) {
        if (meshId != null && _highlightController.value < 1) {
          _highlightController.forward();
        }
        return;
      }

      _pendingObjectContenderId = meshId;
      if (_objectContenderId != null && meshId == null) {
        _highlightController.reverse().whenComplete(() {
          if (!mounted || _pendingObjectContenderId != null) return;
          setState(() => _objectContenderId = null);
        });
        return;
      }
      if (_objectContenderId != null && meshId != null) {
        _contenderSwitchTimer?.cancel();
        _contenderSwitchTimer = Timer(const Duration(milliseconds: 80), () {
          if (!mounted || _phase != _FocusPhase.free) return;
          if (_pendingObjectContenderId != meshId) return;
          setState(() => _objectContenderId = meshId);
          _highlightController.forward(from: 0);
        });
        return;
      }
      setState(() => _objectContenderId = meshId);
      _highlightController.forward(from: 0);
      if (_faceContender != null) {
        setState(() => _faceContender = null);
      }
    }
  }

  bool get _hasContender =>
      _mode == MixedCraftSelectMode.face
          ? _faceContender != null
          : _objectContenderId != null;

  bool get _orbitLocked => _phase != _FocusPhase.free;

  void _setMode(MixedCraftSelectMode mode) {
    if (_mode == mode || _phase != _FocusPhase.free) return;
    _contenderDebounce?.cancel();
    _contenderSwitchTimer?.cancel();
    setState(() {
      _mode = mode;
      _faceContender = null;
      _pendingFaceContender = null;
      _objectContenderId = null;
      _pendingObjectContenderId = null;
    });
    _highlightController.value = 0;
    _updateContender();
  }

  // ---------------------------------------------------------------------------
  // Focus / Return
  // ---------------------------------------------------------------------------

  void _onFocusPressed() {
    if (_phase == _FocusPhase.free && _hasContender) {
      if (_mode == MixedCraftSelectMode.face) {
        _beginFaceFocus();
      } else {
        _beginObjectFocus();
      }
    } else if (_phase == _FocusPhase.focused) {
      _beginReturn();
    }
  }

  void _snapshotCamera() {
    final cam = _orbit.camera;
    _savedPosition = Vector3.copy(cam.position);
    _savedTarget = cam.target;
    _savedUp = cam.up;
    _savedProjection = cam.projection;
    _savedOrthoScale = cam.orthographicScale;
    _savedFov = cam.fovDegrees;
  }

  void _beginFaceFocus() {
    final face = _faceContender;
    if (face == null) return;

    _snapshotCamera();
    _focusedFace = face;
    _craftCanvasSize = craftCanvasSizeForFace(face);
    _craftOrtho = craftOrthoForFace(face);

    final distance = face.extent * 3.2;
    final dir = Vector3.copy(face.normal)..normalize();
    final endPos = Vector3.copy(face.center)..add(dir * distance);
    final up = _stableUp(face.normal);
    final ortho = (face.extent * 1.35).clamp(
      _orbit.minOrthographicScale,
      _orbit.maxOrthographicScale,
    );

    _camFromPos = Vector3.copy(_orbit.camera.position);
    _camToPos = endPos;
    _camFromTarget = _orbit.camera.target;
    _camToTarget = Vector3.copy(face.center);
    _camFromUp = _orbit.camera.up;
    _camToUp = up;
    _camFromOrtho = _orbit.camera.orthographicScale;
    _camToOrtho = ortho;
    _camToProjection = ProjectionType.orthographic;

    _orbit.allowOrbiting = false;
    setState(() {
      _phase = _FocusPhase.focusing;
      _showCraft = true;
      _craftInteractive = false;
      _meshFillOpacity = 1;
      _outlineMix = 0;
    });

    _orbit.camera.projection = ProjectionType.orthographic;
    _morphController.forward(from: 0);
    _focusController.forward(from: 0);
    _craftFadeController.forward(from: 0);
  }

  void _beginObjectFocus() {
    if (_objectContenderId == null) return;

    _snapshotCamera();
    final extent = _objectExtent();
    _craftCanvasSize = craftCanvasSizeForObject(objectExtent: extent);
    _craftOrtho = craftOrthoForObject(objectExtent: extent);
    _objectWorldToCraftScale = _craftCanvasSize / math.max(extent, 1e-3);

    // Craft-like camera: look down +Z onto XY.
    _camFromPos = Vector3.copy(_orbit.camera.position);
    _camToPos = Vector3(0, 0, 500);
    _camFromTarget = _orbit.camera.target;
    _camToTarget = Vector3.zero();
    _camFromUp = _orbit.camera.up;
    _camToUp = Vector3(0, 1, 0);
    _camFromOrtho = _orbit.camera.orthographicScale;
    _camToOrtho = _craftOrtho;
    _camToProjection = ProjectionType.orthographic;

    _objectAlignRxFrom = _cubeMesh.rotation.x;
    _objectAlignRxTo = math.pi / 2; // XZ/Y-up flat net → XY/Z-up craft plane
    _meshPosFrom = Vector3.copy(_cubeMesh.position);
    _meshPosTo = null; // position driven by recenter while focusing
    _recenterMeshDuringFocus = true;

    _orbit.allowOrbiting = false;
    _cubeMesh.material = _wireMaterial;
    _scene.markNeedsPaint();

    setState(() {
      _phase = _FocusPhase.focusing;
      _showCraft = true;
      _craftInteractive = false;
      _meshFillOpacity = 0.15;
      _outlineMix = 0;
      _showObjectWireframe = true;
    });

    _orbit.camera.projection = ProjectionType.orthographic;
    _morphController.forward(from: 0);
    _focusController.forward(from: 0);
    _craftFadeController.forward(from: 0);
    // Unfold folded → flat after a short beat so wireframe is visible first.
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (!mounted || _phase == _FocusPhase.returning) return;
      _unfoldAnimatable.setUnfolded(true);
    });
  }

  double _objectExtent() {
    final geom = _cubeMesh.geometry;
    if (geom.vertices.isEmpty) return _cubeSize;
    var minV = Vector3.copy(geom.vertices.first);
    var maxV = Vector3.copy(geom.vertices.first);
    final world = _cubeMesh.transformMatrix;
    for (final v in geom.vertices) {
      final wp = Vector3.copy(v);
      world.transform3(wp);
      minV = Vector3(
        math.min(minV.x, wp.x),
        math.min(minV.y, wp.y),
        math.min(minV.z, wp.z),
      );
      maxV = Vector3(
        math.max(maxV.x, wp.x),
        math.max(maxV.y, wp.y),
        math.max(maxV.z, wp.z),
      );
    }
    return (maxV - minV).length;
  }

  void _beginReturn() {
    if (_phase == _FocusPhase.returning || _phase == _FocusPhase.focusing) {
      return;
    }
    if (_savedPosition == null || _savedTarget == null) {
      _finishReturn();
      return;
    }

    setState(() {
      _phase = _FocusPhase.returning;
      _craftInteractive = false;
    });

    // Fade craft chrome immediately; fold/camera reverse in parallel.
    _craftFadeController.reverse();

    // Restore free-camera projection up front so the reverse lerp stays in
    // perspective — avoids an ortho→perspective pop at the end.
    final cam = _orbit.camera;
    if (_savedProjection != null) {
      cam.projection = _savedProjection!;
    }
    if (_savedFov != null) {
      cam.fovDegrees = _savedFov!;
    }

    if (_mode == MixedCraftSelectMode.object) {
      _recenterMeshDuringFocus = false;
      _craftKey.currentState?.clearBlueprint();
      // Painted cube folds back solid; uncrafted stays wire→ghost.
      _showObjectWireframe = _craftedFaceColors == null;
      _applyCubeSurfaceMaterial(wireframe: _craftedFaceColors == null);
      _unfoldAnimatable.setUnfolded(false);
      _objectAlignRxFrom = _cubeMesh.rotation.x;
      _objectAlignRxTo = 0;
      _meshPosFrom = Vector3.copy(_cubeMesh.position);
      _meshPosTo = Vector3.zero();
    } else {
      _applyCubeSurfaceMaterial();
    }

    _camFromPos = Vector3.copy(cam.position);
    _camToPos = Vector3.copy(_savedPosition!);
    _camFromTarget = cam.target;
    _camToTarget = Vector3.copy(_savedTarget!);
    _camFromUp = cam.up;
    _camToUp = Vector3.copy(_savedUp ?? Vector3(0, 1, 0));
    _camFromOrtho = cam.orthographicScale;
    _camToOrtho = _savedOrthoScale;
    _camToProjection = _savedProjection ?? ProjectionType.perspective;

    _morphController.reverse();
    _focusController.forward(from: 0);
  }

  void _finishReturn() {
    final cam = _orbit.camera;
    // Animation already lerped to the saved pose — only sync the orbit
    // controller to the current camera. Do not re-jump/recenter.
    if (_savedProjection != null) {
      cam.projection = _savedProjection!;
    }
    if (_savedFov != null) {
      cam.fovDegrees = _savedFov!;
    }
    if (_savedOrthoScale != null &&
        cam.projection == ProjectionType.orthographic) {
      cam.orthographicScale = _savedOrthoScale!;
    }
    if (_savedUp != null) {
      cam.setUp(_savedUp!);
    }
    _orbit.jumpTo(position: cam.position, target: cam.target);

    _applyCubeSurfaceMaterial();
    // Settle mesh without a visible jump (already at end of lerp).
    _cubeMesh.setRotation(Vector3(_objectAlignRxTo, 0, 0));
    if (_meshPosTo != null) {
      _cubeMesh.setPosition(Vector3.copy(_meshPosTo!));
    }
    if (!_unfoldAnimatable.isUnfolded) {
      // Already folded by animation; avoid a redundant geometry snap.
    } else {
      _unfoldAnimatable.jumpTo(false);
    }
    _objectAlignRx = _objectAlignRxTo;
    _recenterMeshDuringFocus = false;
    _meshPosFrom = null;
    _meshPosTo = null;
    _orbit.allowOrbiting = true;

    setState(() {
      _phase = _FocusPhase.free;
      _showCraft = false;
      _craftInteractive = false;
      _focusedFace = null;
      _meshFillOpacity = 1;
      _outlineMix = 0;
      _showObjectWireframe = false;
    });
    _scene.markNeedsPaint();
    _updateContender();
  }

  void _onFocusTick() {
    final t = Curves.easeOutCubic.transform(_focusController.value);
    if (_camFromPos != null && _camToPos != null) {
      final pos = MathUtils.lerpVector(_camFromPos!, _camToPos!, t);
      final target = MathUtils.lerpVector(
        _camFromTarget!,
        _camToTarget!,
        t,
      );
      final up = MathUtils.lerpVector(_camFromUp!, _camToUp!, t);
      if (up.length2 > 1e-8) {
        up.normalize();
      }
      _orbit.camera.setPosition(pos);
      _orbit.camera.setTarget(target);
      _orbit.camera.setUp(up);
      if (_camFromOrtho != null &&
          _camToOrtho != null &&
          _orbit.camera.projection == ProjectionType.orthographic) {
        _orbit.camera.orthographicScale =
            _camFromOrtho! + (_camToOrtho! - _camFromOrtho!) * t;
      }
      // Keep orbit spherical in sync (no extra motion beyond the lerp).
      _orbit.jumpTo(position: pos, target: target);
      _orbit.camera.setUp(up);
    }

    if (_mode == MixedCraftSelectMode.object) {
      _objectAlignRx =
          _objectAlignRxFrom + (_objectAlignRxTo - _objectAlignRxFrom) * t;
      _cubeMesh.setRotation(Vector3(_objectAlignRx, 0, 0));
      if (_phase == _FocusPhase.returning &&
          _meshPosFrom != null &&
          _meshPosTo != null) {
        _cubeMesh.setPosition(
          MathUtils.lerpVector(_meshPosFrom!, _meshPosTo!, t),
        );
      } else if (_recenterMeshDuringFocus) {
        _centerUnfoldedMesh();
      }
    }

    _scene.markNeedsPaint();
    setState(() {});
  }

  void _centerUnfoldedMesh() {
    // Keep the mesh centroid near the craft origin while unfolding.
    final geom = _cubeMesh.geometry;
    if (geom.vertices.isEmpty) return;
    final c = Vector3.zero();
    for (final v in geom.vertices) {
      c.add(v);
    }
    c.scale(1.0 / geom.vertices.length);
    // After Rx, transform centroid and cancel XY drift.
    final rot = Matrix4.rotationX(_objectAlignRx);
    final wc = Vector3.copy(c);
    rot.transform3(wc);
    _cubeMesh.setPosition(Vector3(-wc.x, -wc.y, -wc.z));
  }

  MaterialModel _materialFromCraftedFaces() {
    final colors = _craftedFaceColors;
    if (colors == null || colors.isEmpty) {
      return const MaterialModel.ghost();
    }
    return MaterialModel(
      color: colors.first,
      doubleSided: true,
      opacity: 1,
      perFaceColors: colors,
      exactPerFaceColors: true,
    );
  }

  void _applyCubeSurfaceMaterial({bool wireframe = false}) {
    if (wireframe) {
      _cubeMesh.material = _wireMaterial;
    } else if (_craftedFaceColors != null) {
      _baseMaterial = _materialFromCraftedFaces();
      _cubeMesh.material = _baseMaterial;
    } else {
      _baseMaterial = const MaterialModel.ghost();
      _cubeMesh.material = _baseMaterial;
    }
    _scene.markNeedsPaint();
  }

  /// Map locked craft papers onto cube faces (handoff blueprint poly order
  /// matches FoldedGeometry face traversal / mesh face indices).
  void _onCraftCompleted(
    List<CraftingPaperState> papers,
    String craftName,
    CraftingBlueprint blueprint,
  ) {
    final faceCount = _cubeMesh.geometry.faces.length;
    if (faceCount <= 0) return;

    final ghost = MaterialModel.kGhostMaterialColor;
    final colors = List<Color>.filled(faceCount, ghost);

    var polyI = 0;
    final polyToMeshFace = <int, int>{};
    for (final node in blueprint.transformTree.nodes) {
      if (node.unfoldedPolygon2D.length < 3) continue;
      final meshFace = node.id < faceCount ? node.id : polyI;
      polyToMeshFace[polyI] = meshFace.clamp(0, faceCount - 1);
      polyI++;
    }

    for (final paper in papers) {
      final polyIdx = paper.lockedBlueprintIndex;
      if (polyIdx == null) continue;
      final meshFace = polyToMeshFace[polyIdx] ?? polyIdx;
      if (meshFace < 0 || meshFace >= faceCount) continue;
      colors[meshFace] = paper.paperColor.resolve();
    }

    _craftedFaceColors = colors;
    // Swap wire → painted once craft is done so return shows the made object.
    if (_phase == _FocusPhase.focused || _phase == _FocusPhase.free) {
      _showObjectWireframe = false;
      _applyCubeSurfaceMaterial();
    }
    setState(() {});
  }

  void _onMorphTick() {
    final t = _morphController.value;
    if (_mode == MixedCraftSelectMode.face ||
        (_phase == _FocusPhase.returning && _focusedFace != null)) {
      _meshFillOpacity = 1.0 - t;
      _outlineMix = t;
      final base = _craftedFaceColors != null
          ? _materialFromCraftedFaces()
          : const MaterialModel.ghost();
      _cubeMesh.material = MaterialModel(
        color: base.color,
        doubleSided: true,
        opacity: (_meshFillOpacity * (base.opacity)).clamp(0.0, 1.0),
        perFaceColors: base.perFaceColors,
        exactPerFaceColors: base.exactPerFaceColors,
      );
      _scene.markNeedsPaint();
      setState(() {});
    }
  }

  void _onFocusStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;

    if (_phase == _FocusPhase.focusing) {
      if (_camToProjection != null) {
        _orbit.camera.projection = _camToProjection!;
      }
      setState(() {
        _phase = _FocusPhase.focused;
        // Face: interactive once morph done.
        // Object: wait for unfold → blueprint handoff.
        if (_mode == MixedCraftSelectMode.face) {
          _craftInteractive = true;
        }
      });
    } else if (_phase == _FocusPhase.returning) {
      _finishReturn();
    }
  }

  Vector3 _stableUp(Vector3 normal) {
    final worldUp = Vector3(0, 1, 0);
    final alignment = normal.normalized().dot(worldUp).abs();
    if (alignment > 0.95) {
      return Vector3(0, 0, normal.y >= 0 ? 1 : -1);
    }
    return worldUp;
  }

  // ---------------------------------------------------------------------------
  // Overlay edge projection
  // ---------------------------------------------------------------------------

  List<(Offset, Offset)> _projectedEdges(List<(Vector3, Vector3)> worldEdges) {
    final cam = _scene.camera;
    if (cam == null || _viewportSize == Size.zero) return const [];
    final aspect = _viewportSize.width / _viewportSize.height;
    final mvp = cam.projectionMatrix(aspect) * cam.viewMatrix;
    final out = <(Offset, Offset)>[];
    for (final edge in worldEdges) {
      final a = _project(edge.$1, mvp, _viewportSize);
      final b = _project(edge.$2, mvp, _viewportSize);
      if (a != null && b != null) out.add((a, b));
    }
    return out;
  }

  Offset? _project(Vector3 worldPos, Matrix4 mvp, Size size) {
    final clip = Vector4(worldPos.x, worldPos.y, worldPos.z, 1);
    mvp.transform(clip);
    if (clip.w < 1e-3) return null;
    final ndcX = clip.x / clip.w;
    final ndcY = clip.y / clip.w;
    if (!ndcX.isFinite || !ndcY.isFinite) return null;
    return Offset(
      (ndcX * 0.5 + 0.5) * size.width,
      (1 - (ndcY * 0.5 + 0.5)) * size.height,
    );
  }

  List<(Offset, Offset)> _contenderScreenEdges() {
    if (_mode == MixedCraftSelectMode.face) {
      final face = _phase == _FocusPhase.free
          ? _faceContender
          : (_focusedFace ?? _faceContender);
      if (face == null) return const [];
      final mesh = _scene.meshById(face.meshId);
      if (mesh == null) return const [];
      return _projectedEdges(
        FaceFocusPicker.faceWorldEdges(mesh, face.faceIndex),
      );
    }

    // Free / pre-focus object contender highlight.
    if (_phase != _FocusPhase.free) return const [];
    final id = _objectContenderId ?? _cubeMeshId;
    final mesh = _scene.meshById(id);
    if (mesh == null || _scene.camera == null) return const [];
    return _projectedEdges(
      ObjectFocusPicker.meshOutlineEdges(mesh, _scene.camera!.position),
    );
  }

  /// All unique mesh edges in screen space (object focus wireframe overlay).
  List<(Offset, Offset)> _objectWireframeScreenEdges() {
    final mesh = _cubeMesh;
    final geometry = mesh.geometry;
    final world = mesh.transformMatrix;
    final seen = <_UndirectedEdgeKey>{};
    final worldEdges = <(Vector3, Vector3)>[];
    for (final face in geometry.faces) {
      for (var i = 0; i < face.length; i++) {
        final a = face[i];
        final b = face[(i + 1) % face.length];
        final key = _UndirectedEdgeKey(a, b);
        if (!seen.add(key)) continue;
        final wa = Vector3.copy(geometry.vertices[a]);
        final wb = Vector3.copy(geometry.vertices[b]);
        world.transform3(wa);
        world.transform3(wb);
        worldEdges.add((wa, wb));
      }
    }
    return _projectedEdges(worldEdges);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final highlightT = _highlightController.value;
    final craftOpacity = _craftFadeController.value;
    final showFocusButton =
        (_phase == _FocusPhase.free && _hasContender) ||
        _phase == _FocusPhase.focused;
    final focusLabel = _phase == _FocusPhase.focused ? 'Return' : 'Focus';

    // Face morph outline style
    final outlineColor = Color.lerp(
      const Color(0xFFFFEB3B),
      Colors.white,
      _outlineMix,
    )!;
    final outlineWidth = 5.0 + (0.8 - 5.0) * _outlineMix;
    final edgeOpacity = switch (_phase) {
      _FocusPhase.free => highlightT,
      _FocusPhase.focused when _mode == MixedCraftSelectMode.face => 0.9,
      _ => (1.0 - craftOpacity * 0.55).clamp(0.2, 1.0),
    };

    return FmScreen(
      backgroundColor: const Color(0xFF12121C),
      background: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          if (size != _viewportSize) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() => _viewportSize = size);
              _updateContender();
            });
          }

          return Stack(
            fit: StackFit.expand,
            children: [
              Opacity(
                opacity: _mode == MixedCraftSelectMode.object && _showCraft
                    ? (1.0 - craftOpacity * 0.95).clamp(0.0, 1.0)
                    : 1.0,
                child: _buildSceneGestures(
                  child: SceneView(scene: _scene),
                ),
              ),
              // Contender highlight (free orbit only — focus morphs draw above craft).
              if (edgeOpacity > 0.01 && _phase == _FocusPhase.free)
                IgnorePointer(
                  child: CustomPaint(
                    painter: _EdgeOverlayPainter(
                      edges: _contenderScreenEdges(),
                      color: outlineColor.withValues(alpha: edgeOpacity),
                      strokeWidth: 4.5,
                    ),
                  ),
                ),
              // Center crosshair / zone hint
              if (_phase == _FocusPhase.free)
                IgnorePointer(
                  child: CustomPaint(
                    painter: _CenterGuidePainter(
                      mode: _mode,
                      zoneInset: kFaceCenterZoneInset,
                    ),
                  ),
                ),
              // Crafting overlay
              if (_showCraft && craftOpacity > 0)
                Opacity(
                  opacity: craftOpacity.clamp(0.0, 1.0),
                  child: IgnorePointer(
                    ignoring: !_craftInteractive,
                    child: CraftingTestView(
                      key: _craftKey,
                      structureId: 'mixed-3d-craft',
                      stateStore: _craftState,
                      canvasSize: _craftCanvasSize,
                      initialOrthoScale: _craftOrtho,
                      hideDrawingPlane: true,
                      showDotWipe: false,
                      onDismiss: _beginReturn,
                      onCraftCompleted: _onCraftCompleted,
                      // Hide dots until applyBlueprint reveals them after the
                      // dominant-edge grid frame is already installed.
                      initialCanvasDisplayMode:
                          _mode == MixedCraftSelectMode.object
                              ? CanvasDisplayMode.none
                              : CanvasDisplayMode.dot,
                      initialBlueprintSet: null,
                    ),
                  ),
                ),
              // Face Focus morph outline → craft drawing-plane frame (above craft).
              if (_mode == MixedCraftSelectMode.face &&
                  (_phase == _FocusPhase.focusing ||
                      _phase == _FocusPhase.focused ||
                      _phase == _FocusPhase.returning) &&
                  edgeOpacity > 0.01)
                IgnorePointer(
                  child: CustomPaint(
                    painter: _EdgeOverlayPainter(
                      edges: _contenderScreenEdges(),
                      color: outlineColor.withValues(alpha: edgeOpacity),
                      strokeWidth: outlineWidth,
                    ),
                  ),
                ),
              // Object-mode unfold wireframe sits above craft until handoff.
              if (_mode == MixedCraftSelectMode.object &&
                  _showObjectWireframe &&
                  (_phase == _FocusPhase.focusing ||
                      _phase == _FocusPhase.focused ||
                      _phase == _FocusPhase.returning))
                IgnorePointer(
                  child: CustomPaint(
                    painter: _EdgeOverlayPainter(
                      edges: _objectWireframeScreenEdges(),
                      color: Colors.white.withValues(alpha: 0.92),
                      strokeWidth: 1.6,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      overlays: [
        const FmDevBackButton(),
        FmSafePositioned(
          top: 12,
          right: 12,
          child: _ModeToggle(
            mode: _mode,
            enabled: _phase == _FocusPhase.free,
            onChanged: _setMode,
          ),
        ),
        if (_phase == _FocusPhase.free)
          FmSafePositioned(
            left: 12,
            top: 48,
            child: _CameraToolBar(
              tool: _cameraTool,
              onChanged: (tool) => setState(() => _cameraTool = tool),
            ),
          ),
        if (showFocusButton)
          FmSafePositioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: _FocusButton(
                label: focusLabel,
                onPressed: _phase == _FocusPhase.focusing ||
                        _phase == _FocusPhase.returning
                    ? null
                    : _onFocusPressed,
              ),
            ),
          ),
      ],
    );
  }

  void _applySingleFingerDrag(Offset delta) {
    switch (_cameraTool) {
      case _CameraTool.orbit:
        _orbit.orbit(delta);
      case _CameraTool.pan:
        _orbit.pan(delta);
      case _CameraTool.zoom:
        // Up (negative dy) = zoom in; down = zoom out.
        _orbit.zoomByScroll(delta.dy);
    }
  }

  Widget _buildSceneGestures({required Widget child}) {
    return Listener(
      onPointerDown: (event) {
        if (_orbitLocked) return;
        if (event.kind == PointerDeviceKind.mouse) {
          _mouseButtons = event.buttons;
        }
      },
      onPointerMove: (event) {
        if (_orbitLocked) return;
        if (event.kind == PointerDeviceKind.mouse) {
          _mouseButtons = event.buttons;
          if ((_mouseButtons & kSecondaryButton) != 0) {
            _orbit.pan(event.delta);
          } else if ((_mouseButtons & kPrimaryButton) != 0) {
            _applySingleFingerDrag(event.delta);
          }
        }
      },
      onPointerUp: (_) => _mouseButtons = 0,
      onPointerCancel: (_) => _mouseButtons = 0,
      onPointerSignal: (signal) {
        if (_orbitLocked) return;
        if (signal is PointerScrollEvent) {
          _orbit.zoomByScroll(signal.scrollDelta.dy);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: (details) {
          if (_orbitLocked) return;
          _lastTouchFocalPoint = details.focalPoint;
          _lastTouchScale = 1.0;
          _lastTouchPointerCount = details.pointerCount;
        },
        onScaleUpdate: (details) {
          if (_orbitLocked) return;
          if (details.pointerCount != _lastTouchPointerCount) {
            _lastTouchFocalPoint = details.focalPoint;
            _lastTouchScale = details.scale;
            _lastTouchPointerCount = details.pointerCount;
          }
          final focalPoint = details.focalPoint;
          if (_lastTouchFocalPoint != null) {
            final delta = focalPoint - _lastTouchFocalPoint!;
            if (details.pointerCount == 1) {
              _applySingleFingerDrag(delta);
            } else if (details.pointerCount >= 2) {
              _orbit.pan(delta);
              final scaleChange = details.scale / _lastTouchScale;
              if (scaleChange > 0 && scaleChange != 1.0) {
                _orbit.zoomByScale(scaleChange);
              }
            }
          }
          _lastTouchFocalPoint = focalPoint;
          _lastTouchScale = details.scale;
        },
        onScaleEnd: (_) {
          _lastTouchFocalPoint = null;
          _lastTouchScale = 1.0;
          _lastTouchPointerCount = 0;
        },
        child: child,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// HUD widgets / painters
// -----------------------------------------------------------------------------

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({
    required this.mode,
    required this.enabled,
    required this.onChanged,
  });

  final MixedCraftSelectMode mode;
  final bool enabled;
  final ValueChanged<MixedCraftSelectMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xCC1E1E2E),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _seg('Face', MixedCraftSelectMode.face),
            _seg('Object', MixedCraftSelectMode.object),
          ],
        ),
      ),
    );
  }

  Widget _seg(String label, MixedCraftSelectMode value) {
    final selected = mode == value;
    return GestureDetector(
      onTap: enabled ? () => onChanged(value) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white24 : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

class _CameraToolBar extends StatelessWidget {
  const _CameraToolBar({required this.tool, required this.onChanged});

  final _CameraTool tool;
  final ValueChanged<_CameraTool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _camBtn(Icons.threed_rotation, 'Orbit', _CameraTool.orbit),
          const SizedBox(height: 2),
          _camBtn(Icons.pan_tool, 'Pan', _CameraTool.pan),
          const SizedBox(height: 2),
          _camBtn(Icons.zoom_in, 'Zoom', _CameraTool.zoom),
        ],
      ),
    );
  }

  Widget _camBtn(IconData icon, String tooltip, _CameraTool value) {
    final active = tool == value;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? Colors.white.withValues(alpha: 0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => onChanged(value),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(
              icon,
              color: active ? Colors.white : Colors.white70,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusButton extends StatelessWidget {
  const _FocusButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
          decoration: BoxDecoration(
            color: onPressed == null
                ? const Color(0x66404050)
                : const Color(0xEE2A2A3A),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white38),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}

class _EdgeOverlayPainter extends CustomPainter {
  _EdgeOverlayPainter({
    required this.edges,
    required this.color,
    required this.strokeWidth,
  });

  final List<(Offset, Offset)> edges;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (edges.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final e in edges) {
      canvas.drawLine(e.$1, e.$2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EdgeOverlayPainter oldDelegate) =>
      oldDelegate.edges != edges ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}

class _CenterGuidePainter extends CustomPainter {
  _CenterGuidePainter({required this.mode, required this.zoneInset});

  final MixedCraftSelectMode mode;
  final double zoneInset;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final cross = Paint()
      ..color = Colors.white30
      ..strokeWidth = 1;
    const arm = 10.0;
    canvas.drawLine(Offset(c.dx - arm, c.dy), Offset(c.dx + arm, c.dy), cross);
    canvas.drawLine(Offset(c.dx, c.dy - arm), Offset(c.dx, c.dy + arm), cross);

    if (mode == MixedCraftSelectMode.face) {
      final inset = zoneInset.clamp(0.0, 0.49);
      final rect = Rect.fromLTRB(
        size.width * inset,
        size.height * inset,
        size.width * (1 - inset),
        size.height * (1 - inset),
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = Colors.white12
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CenterGuidePainter oldDelegate) =>
      oldDelegate.mode != mode || oldDelegate.zoneInset != zoneInset;
}

class _UndirectedEdgeKey {
  _UndirectedEdgeKey(int a, int b)
      : a = a < b ? a : b,
        b = a < b ? b : a;

  final int a;
  final int b;

  @override
  bool operator ==(Object other) =>
      other is _UndirectedEdgeKey && other.a == a && other.b == b;

  @override
  int get hashCode => Object.hash(a, b);
}
