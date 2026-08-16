import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../crafting/crafting_blueprint.dart';
import '../crafting/craft_step_meshes.dart';
import '../data/crafting_state.dart';
import '../geometry/geometry.dart';
import '../rendering/lights.dart';
import '../rendering/mesh.dart';
import '../rendering/scene/camera.dart';
import '../rendering/scene/camera_controller.dart';
import '../rendering/scene/object_focus_picker.dart';
import '../rendering/scene/scene.dart';
import '../rendering/scene_view.dart';
import '../ui/crafting_workstation.dart';
import '../ui/fm_dev_back_button.dart';
import '../ui/fm_safe_area.dart';
import '../ui/fm_screen.dart';

/// Combined 3D assembly viewer + crafting workstation, linked by a vertical peek pager.
class CraftAssemblyView extends StatefulWidget {
  const CraftAssemblyView({
    super.key,
    this.craftName = 'house_foo',
    this.futureStepWindow = 4,
    this.showDrawingPlane = false,
  });

  final String craftName;
  final int futureStepWindow;

  /// When true, shows the large grey drawing-plane square on the craft page.
  final bool showDrawingPlane;

  @override
  State<CraftAssemblyView> createState() => _CraftAssemblyViewState();
}

class _CraftAssemblyViewState extends State<CraftAssemblyView>
    with TickerProviderStateMixin {
  static const _flashGreen = Color(0xFF66BB6A);
  static const _currentStepBlue = Color(0xFF6495ED);
  static const _pageDuration = Duration(milliseconds: 380);
  static const _fadeDuration = Duration(milliseconds: 450);
  static const _fitAllDuration = Duration(milliseconds: 1400);
  static const _fitStepDuration = Duration(milliseconds: 1000);
  static const _turntableDuration = Duration(seconds: 24);
  static const _kStepOutlineWidth = 2.4;
  static const _kAppliqueOutlineWidth = 2.0;
  static const _kSilhouetteWidth = 1.4;

  late final Scene _scene;
  late final OrbitCameraController _orbit;
  late final AnimationController _pageAnim;
  late final AnimationController _flashAnim;
  late final AnimationController _fadeAnim;
  late final AnimationController _panSpringAnim;
  late final AnimationController _fitAllAnim;
  late final AnimationController _turntableAnim;

  final CraftingStateStore _stateStore = CraftingStateStore();
  final GlobalKey<CraftingTestViewState> _craftKey =
      GlobalKey<CraftingTestViewState>();

  int _mouseButtons = 0;
  Offset? _lastTouchFocalPoint;
  double _lastTouchScale = 1.0;
  int _lastTouchPointerCount = 0;

  CraftStepAssembly? _assembly;
  List<CraftingBlueprint> _fills = const [];
  int _fillIndex = 0;
  String? _error;
  bool _loading = true;
  int _stepIndex = 0;
  late int _futureStepWindow;
  Size _viewportSize = Size.zero;
  bool _sequenceRunning = false;
  bool _craftComplete = false;
  bool _panSpringEnabled = true;
  bool _showWorldXyPlane = false;
  bool _orbitPanning = false;
  Vector3 _panSpringFrom = Vector3.zero();
  Vector3 _fitAllFromTarget = Vector3.zero();
  Vector3 _fitAllToTarget = Vector3.zero();
  double _fitAllFromRadius = 1;
  double _fitAllToRadius = 1;
  double _lastTurntableValue = 0;

  @override
  void initState() {
    super.initState();
    _futureStepWindow = widget.futureStepWindow.clamp(0, 16);

    _pageAnim = AnimationController(vsync: this, duration: _pageDuration)
      ..addListener(() => setState(() {}));
    _flashAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..addListener(_applyStepMaterials);
    _fadeAnim = AnimationController(vsync: this, duration: _fadeDuration)
      ..value = 1
      ..addListener(_applyStepMaterials);
    _panSpringAnim = AnimationController.unbounded(vsync: this)
      ..addListener(_onPanSpringTick);
    _fitAllAnim = AnimationController(vsync: this, duration: _fitAllDuration)
      ..addListener(_onFitAllTick);
    _turntableAnim = AnimationController(
      vsync: this,
      duration: _turntableDuration,
    )..addListener(_onTurntableTick);

    final camera = Camera(
      name: 'craft-assembly-cam',
      position: Vector3(40, 30, 40),
      target: Vector3.zero(),
      projection: ProjectionType.perspective,
      fovDegrees: 50,
      near: 0.1,
      far: 5000,
    );
    _orbit = OrbitCameraController(
      camera: camera,
      target: Vector3.zero(),
      minDistance: 4,
      maxDistance: 400,
      constrainPan: true,
    )..addListener(_onCameraChanged);

    _scene = Scene(globalIllumination: 0.25)
      ..camera = camera
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

    _loadCraft();
  }

  @override
  void dispose() {
    _pageAnim.dispose();
    _flashAnim.dispose();
    _fadeAnim.dispose();
    _panSpringAnim.dispose();
    _fitAllAnim.dispose();
    _turntableAnim.dispose();
    _orbit
      ..removeListener(_onCameraChanged)
      ..dispose();
    _scene.removeListener(_onSceneChanged);
    super.dispose();
  }

  void _onCameraChanged() {
    _scene.markNeedsPaint();
    if (mounted) setState(() {});
  }

  void _onSceneChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadCraft() async {
    try {
      final assembly = await CraftStepAssembly.load(widget.craftName);
      if (!mounted) return;
      setState(() {
        _assembly = assembly;
        _fills = assembly.manifest.toFillBlueprints();
        _fillIndex = 0;
        _loading = false;
        _stepIndex = 0;
      });
      _applyStepMaterials();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _fitCurrentStep();
        _loadCraftFill(0);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Step styling
  // ---------------------------------------------------------------------------

  double _futureOpacity(int distance) {
    if (distance <= 0 || distance > _futureStepWindow) return 0;
    return (_futureStepWindow + 1 - distance) / (_futureStepWindow + 1);
  }

  /// Per-step grey so adjacent assembly steps stay distinguishable.
  Color _stepGrey(int index) {
    final t = (index * 0.17) % 1.0;
    final lightness = 0.38 + 0.36 * t;
    return HSLColor.fromAHSL(1, 0, 0, lightness).toColor();
  }

  void _applyStepMaterials() {
    final assembly = _assembly;
    if (assembly == null) return;

    final flashT = math.sin(math.pi * _flashAnim.value);
    final currentOpacity = _fadeAnim.value.clamp(0.0, 1.0);
    final visible = <Mesh>[];

    for (var i = 0; i < assembly.steps.length; i++) {
      final step = assembly.steps[i];
      final delta = i - _stepIndex;
      if (delta > 0) continue;

      final opacity = _craftComplete
          ? 1.0
          : (delta < 0 ? 0.5 : currentOpacity);
      if (opacity <= 0) continue;

      Color color = (delta == 0 && !_craftComplete)
          ? _currentStepBlue
          : _stepGrey(i);
      if (delta == 0 && flashT > 0) {
        color = Color.lerp(color, _flashGreen, flashT)!;
      }

      if (step.parts != null) {
        step.parts!.material = MaterialModel(
          color: color,
          doubleSided: true,
          opacity: opacity,
          strokeEdges: false,
        );
        visible.add(step.parts!);
      }
      if (step.appliques != null) {
        step.appliques!.material = MaterialModel(
          color: color,
          doubleSided: true,
          opacity: opacity,
          strokeEdges: false,
        );
        visible.add(step.appliques!);
      }
    }

    _scene.setMeshes(visible);
    _scene.markNeedsPaint();
  }

  _FitPose? _fitPoseForVertices(Iterable<Vector3> verts) {
    final list = verts.toList();
    if (list.isEmpty) return null;

    var minX = list.first.x, maxX = list.first.x;
    var minY = list.first.y, maxY = list.first.y;
    var minZ = list.first.z, maxZ = list.first.z;
    for (final v in list) {
      minX = math.min(minX, v.x);
      maxX = math.max(maxX, v.x);
      minY = math.min(minY, v.y);
      maxY = math.max(maxY, v.y);
      minZ = math.min(minZ, v.z);
      maxZ = math.max(maxZ, v.z);
    }
    final target = Vector3(
      (minX + maxX) / 2,
      (minY + maxY) / 2,
      (minZ + maxZ) / 2,
    );
    final hx = (maxX - minX) / 2;
    final hy = (maxY - minY) / 2;
    final hz = (maxZ - minZ) / 2;

    const padding = 1.35;
    final usableH = _viewportSize.height > 1
        ? _viewportSize.height * 0.88
        : 400.0;
    final usableW = _viewportSize.width > 1 ? _viewportSize.width : 400.0;
    final aspect = usableW / usableH;
    final fovY = _orbit.camera.fovDegrees * math.pi / 180;
    final halfFovY = fovY / 2;
    final halfFovX = math.atan(math.tan(halfFovY) * aspect);
    final distY = (hy * padding) / math.max(math.tan(halfFovY), 1e-4);
    final distX = (hx * padding) / math.max(math.tan(halfFovX), 1e-4);
    final distZ = (hz * padding) / math.max(math.tan(halfFovY), 1e-4);
    final dist =
        math.max(distX, math.max(distY, distZ)).clamp(8.0, 350.0) * 1.25;
    final extent = math.max(hx, math.max(hy, hz));
    final diagonal = math.sqrt(
      (maxX - minX) * (maxX - minX) +
          (maxY - minY) * (maxY - minY) +
          (maxZ - minZ) * (maxZ - minZ),
    );
    return _FitPose(
      target: target,
      dist: dist,
      extent: extent,
      diagonal: diagonal,
    );
  }

  Iterable<Vector3> _allAssemblyVertices() sync* {
    final assembly = _assembly;
    if (assembly == null) return;
    for (final step in assembly.steps) {
      yield* step.vertices;
    }
  }

  void _applyFitPose(_FitPose pose, {bool jump = true}) {
    _orbit.setFocusAnchor(
      pose.target,
      extent: pose.extent,
      diagonal: pose.diagonal,
    );
    _orbit.setDistanceLimits(
      math.max(pose.dist * 0.3, pose.diagonal * 0.2),
      pose.dist * 2.5,
    );
    if (jump) {
      var dir = _orbit.camera.position - _orbit.camera.target;
      if (dir.length2 < 1e-8) {
        dir = Vector3(0.85, 0.65, 0.85);
      }
      dir.normalize();
      _orbit.jumpTo(
        position: pose.target + dir * pose.dist,
        target: pose.target,
        focusExtent: pose.extent,
      );
    }
    _panSpringAnim.stop();
  }

  void _fitCurrentStep({bool animate = false}) {
    final assembly = _assembly;
    if (assembly == null || assembly.steps.isEmpty) return;
    final pose = _fitPoseForVertices(assembly.steps[_stepIndex].vertices);
    if (pose == null) return;
    if (animate) {
      _animateFitTo(pose, duration: _fitStepDuration);
    } else {
      _applyFitPose(pose);
    }
  }

  Future<void> _animateFitTo(
    _FitPose pose, {
    required Duration duration,
  }) async {
    _fitAllFromTarget = _orbit.target;
    _fitAllFromRadius = _orbit.radius;
    _fitAllToTarget = pose.target;
    _fitAllToRadius = pose.dist;
    _orbit.setFocusAnchor(
      pose.target,
      extent: pose.extent,
      diagonal: pose.diagonal,
    );
    _orbit.setDistanceLimits(
      math.min(
        _fitAllFromRadius,
        math.max(pose.dist * 0.3, pose.diagonal * 0.2),
      ),
      math.max(pose.dist * 2.5, _fitAllFromRadius),
    );
    _panSpringAnim.stop();
    _fitAllAnim.duration = duration;
    await _fitAllAnim.forward(from: 0);
    if (!mounted) return;
    _applyFitPose(pose, jump: false);
    _orbit.setPose(target: pose.target, radius: pose.dist);
  }

  void _onFitAllTick() {
    final t = Curves.easeInOutCubic.transform(_fitAllAnim.value);
    _orbit.setPose(
      target: _fitAllFromTarget + (_fitAllToTarget - _fitAllFromTarget) * t,
      radius: _fitAllFromRadius + (_fitAllToRadius - _fitAllFromRadius) * t,
    );
  }

  void _onTurntableTick() {
    if (!_turntableAnim.isAnimating) return;
    final value = _turntableAnim.value;
    var delta = value - _lastTurntableValue;
    if (delta < -0.5) delta += 1;
    _lastTurntableValue = value;
    if (delta.abs() < 1e-6) return;
    _orbit.addYaw(delta * 2 * math.pi);
  }

  void _stopCinematicCamera() {
    _fitAllAnim.stop();
    _turntableAnim.stop();
  }

  Future<void> _playCompletedReveal() async {
    setState(() => _craftComplete = true);
    _applyStepMaterials();

    final pose = _fitPoseForVertices(_allAssemblyVertices());
    if (pose != null) {
      await _animateFitTo(pose, duration: _fitAllDuration);
      if (!mounted) return;
    }

    _lastTurntableValue = 0;
    _turntableAnim.repeat();
  }

  void _onPanSpringTick() {
    final t = _panSpringAnim.value.clamp(0.0, 1.0);
    final home = _orbit.focusAnchor;
    _orbit.setTargetKeepingOrbit(
      _panSpringFrom + (home - _panSpringFrom) * t,
    );
  }

  void _beginOrbitPan() {
    if (_panSpringAnim.isAnimating) _panSpringAnim.stop();
    _orbitPanning = true;
  }

  void _endOrbitPan() {
    if (!_orbitPanning) return;
    _orbitPanning = false;
    if (!_panSpringEnabled) return;
    final home = _orbit.focusAnchor;
    final offset = _orbit.target - home;
    if (offset.length2 < 1e-6) return;
    _panSpringFrom = _orbit.target;
    _panSpringAnim.animateWith(
      SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 90, damping: 14),
        0,
        1,
        0,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Pager
  // ---------------------------------------------------------------------------

  double get _page => _pageAnim.value;
  bool get _showingCraft => _page >= 0.5;

  Future<void> _animateToPage(double target) async {
    await _pageAnim.animateTo(
      target.clamp(0.0, 1.0),
      duration: _pageDuration,
      curve: Curves.easeOutCubic,
    );
    if (!mounted) return;
  }

  void _onPeekDragUpdate(DragUpdateDetails details, double travel) {
    if (travel < 1) return;
    final delta = -details.delta.dy / travel;
    _pageAnim.value = (_pageAnim.value + delta).clamp(0.0, 1.0);
  }

  void _onPeekDragEnd(DragEndDetails details) {
    final v = details.velocity.pixelsPerSecond.dy;
    var target = _page >= 0.5 ? 1.0 : 0.0;
    if (v < -280) target = 1;
    if (v > 280) target = 0;
    _animateToPage(target);
  }

  // ---------------------------------------------------------------------------
  // Assembly-step completion
  // ---------------------------------------------------------------------------

  CraftingBlueprint? get _currentFill {
    if (_fillIndex < 0 || _fillIndex >= _fills.length) return null;
    return _fills[_fillIndex];
  }

  void _loadCraftFill(int fillIndex, {bool keepCanvas = false}) {
    if (fillIndex < 0 || fillIndex >= _fills.length) return;
    setState(() => _fillIndex = fillIndex);
    _craftKey.currentState?.applyBlueprint(
      _fills[fillIndex],
      keepCanvas: keepCanvas,
    );
  }

  int _firstFillForAssemblyStep(int assemblyIndex) {
    return _fills.indexWhere((f) => f.stepIndex == assemblyIndex);
  }

  void _onCraftFillCompleted(
    List<CraftingPaperState> papers,
    String blueprintName,
    CraftingBlueprint blueprint,
  ) {
    final next = _fillIndex + 1;
    if (next < _fills.length &&
        _fills[next].stepIndex == _fills[_fillIndex].stepIndex) {
      _loadCraftFill(next, keepCanvas: true);
      return;
    }
    _onAssemblyStepCompleted();
  }

  Future<void> _onAssemblyStepCompleted() async {
    if (_sequenceRunning) return;
    _sequenceRunning = true;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      await _animateToPage(0);
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;

      final assembly = _assembly;
      final isLastStep =
          assembly == null || _stepIndex >= assembly.steps.length - 1;
      if (!isLastStep) {
        setState(() => _stepIndex += 1);
        _fitCurrentStep(animate: true);
        _loadCraftFill(_firstFillForAssemblyStep(_stepIndex));
        _fadeAnim.forward(from: 0);
      }
      await _flashAnim.forward(from: 0);
      if (!mounted) return;
      _flashAnim.value = 0;
      _applyStepMaterials();
      if (isLastStep) {
        await _playCompletedReveal();
      }
    } finally {
      _sequenceRunning = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Silhouette overlay
  // ---------------------------------------------------------------------------

  List<_OutlineEdge> _stepSilhouetteEdges(Size size) {
    final assembly = _assembly;
    final camera = _scene.camera;
    if (assembly == null || camera == null || size.width < 1) {
      return const [];
    }
    if (_craftComplete) return const [];
    final aspect = size.width / size.height;
    final mvp = camera.projectionMatrix(aspect) * camera.viewMatrix;
    final out = <_OutlineEdge>[];
    final currentOpacity = _fadeAnim.value.clamp(0.0, 1.0);
    final currentFill = _currentFill;
    final highlightApplique = currentFill?.isApplique == true;
    final highlightParts = currentFill != null && !currentFill.isApplique;

    for (var i = 0; i < assembly.steps.length; i++) {
      final delta = i - _stepIndex;
      final opacity = delta < 0
          ? 0.5
          : (delta == 0 ? currentOpacity : _futureOpacity(delta));
      if (opacity <= 0) continue;

      if (delta == 0) {
        // White highlight for whichever fill is on the crafting canvas —
        // parts and applique are never outlined together.
        if (highlightParts && assembly.steps[i].parts != null) {
          _appendProjectedEdges(
            out,
            assembly.steps[i].parts!,
            camera.position,
            mvp,
            size,
            Colors.white.withValues(alpha: opacity * 0.75),
            _kStepOutlineWidth,
          );
        } else if (highlightApplique && assembly.steps[i].appliques != null) {
          _appendProjectedEdges(
            out,
            assembly.steps[i].appliques!,
            camera.position,
            mvp,
            size,
            Colors.white.withValues(alpha: opacity),
            _kAppliqueOutlineWidth,
          );
        }
        continue;
      }

      final mesh = assembly.steps[i].parts;
      if (mesh == null) continue;
      _appendProjectedEdges(
        out,
        mesh,
        camera.position,
        mvp,
        size,
        _stepGrey(i).withValues(alpha: opacity),
        _kSilhouetteWidth,
      );
    }
    return out;
  }

  void _appendProjectedEdges(
    List<_OutlineEdge> out,
    Mesh mesh,
    Vector3 cameraPosition,
    Matrix4 mvp,
    Size size,
    Color color,
    double width,
  ) {
    final worldEdges = ObjectFocusPicker.meshOutlineEdges(mesh, cameraPosition);
    for (final edge in worldEdges) {
      final a = _project(edge.$1, mvp, size);
      final b = _project(edge.$2, mvp, size);
      if (a != null && b != null) {
        out.add(_OutlineEdge(a, b, color, width));
      }
    }
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

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return FmScreen(
      backgroundColor: const Color(0xFF12121A),
      overlays: const [FmDevBackButton()],
      background: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: Colors.white70)),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size != _viewportSize && size.width > 1 && size.height > 1) {
          _viewportSize = size;
          _orbit.setViewportSize(size);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _fitCurrentStep();
          });
        }
        final peek = size.height * 0.12;
        final travel = size.height - peek;
        final ty = -_page * travel;

        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                top: ty,
                left: 0,
                right: 0,
                height: size.height,
                child: IgnorePointer(
                  ignoring: _page > 0.5,
                  child: _build3dPage(size),
                ),
              ),
              Positioned(
                top: ty + travel,
                left: 0,
                right: 0,
                height: size.height,
                child: IgnorePointer(
                  ignoring: _page < 0.5,
                  child: _buildCraftPage(),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                height: peek,
                top: _showingCraft ? 0 : size.height - peek,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _animateToPage(_showingCraft ? 0 : 1),
                  onVerticalDragUpdate: (d) => _onPeekDragUpdate(d, travel),
                  onVerticalDragEnd: _onPeekDragEnd,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _build3dPage(Size size) {
    final step = _assembly?.steps.isEmpty == false
        ? _assembly!.steps[_stepIndex].step
        : null;
    final edges = _stepSilhouetteEdges(size);
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: const Color(0xFF12121A),
          child: _buildOrbitScene(),
        ),
        if (edges.isNotEmpty)
          IgnorePointer(
            child: CustomPaint(painter: _SilhouetteOverlayPainter(edges: edges)),
          ),
        if (step != null)
          FmSafePositioned(
            top: 12,
            right: 12,
            child: _StepCornerHud(stepNumber: step.index),
          ),
      ],
    );
  }

  Widget _buildOrbitScene() {
    return Listener(
      onPointerDown: (event) {
        if (event.kind == PointerDeviceKind.mouse) {
          _mouseButtons = event.buttons;
        }
      },
      onPointerMove: (event) {
        if (event.kind == PointerDeviceKind.mouse) {
          _mouseButtons = event.buttons;
          if ((_mouseButtons & kSecondaryButton) != 0) {
            _stopCinematicCamera();
            _beginOrbitPan();
            _orbit.pan(event.delta);
          } else if ((_mouseButtons & kPrimaryButton) != 0) {
            _stopCinematicCamera();
            _orbit.orbit(event.delta);
          }
        }
      },
      onPointerUp: (_) {
        _mouseButtons = 0;
        _endOrbitPan();
      },
      onPointerCancel: (_) {
        _mouseButtons = 0;
        _endOrbitPan();
      },
      onPointerSignal: (signal) {
        if (signal is PointerScrollEvent) {
          _stopCinematicCamera();
          _orbit.zoomByScroll(signal.scrollDelta.dy);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: (details) {
          _lastTouchFocalPoint = details.focalPoint;
          _lastTouchScale = 1.0;
          _lastTouchPointerCount = details.pointerCount;
        },
        onScaleUpdate: (details) {
          if (details.pointerCount != _lastTouchPointerCount) {
            _lastTouchFocalPoint = details.focalPoint;
            _lastTouchScale = details.scale;
            _lastTouchPointerCount = details.pointerCount;
          }
          final focalPoint = details.focalPoint;
          if (_lastTouchFocalPoint != null) {
            final delta = focalPoint - _lastTouchFocalPoint!;
            if (details.pointerCount == 1) {
              _stopCinematicCamera();
              _orbit.orbit(delta);
            } else if (details.pointerCount >= 2) {
              _stopCinematicCamera();
              _beginOrbitPan();
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
          _endOrbitPan();
        },
        child: SceneView(
          scene: _scene,
          debugOptions: SceneDebugOptions(showWorldXyPlane: _showWorldXyPlane),
        ),
      ),
    );
  }

  Widget _buildCraftPage() {
    return ColoredBox(
      color: const Color(0xFF1A1A2E),
      child: CraftingTestView(
        key: _craftKey,
        structureId: 'craft-assembly-${widget.craftName}',
        stateStore: _stateStore,
        canvasSize: 400.0,
        hideDrawingPlane: !widget.showDrawingPlane,
        showDotWipe: false,
        onCraftCompleted: _onCraftFillCompleted,
      ),
    );
  }
}

class _StepCornerHud extends StatelessWidget {
  const _StepCornerHud({required this.stepNumber});

  final int stepNumber;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Text(
          'Step $stepNumber',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

class _FitPose {
  const _FitPose({
    required this.target,
    required this.dist,
    required this.extent,
    required this.diagonal,
  });

  final Vector3 target;
  final double dist;
  final double extent;
  final double diagonal;
}

class _OutlineEdge {
  const _OutlineEdge(this.a, this.b, this.color, this.width);

  final Offset a;
  final Offset b;
  final Color color;
  final double width;
}

class _SilhouetteOverlayPainter extends CustomPainter {
  _SilhouetteOverlayPainter({required this.edges});

  final List<_OutlineEdge> edges;

  @override
  void paint(Canvas canvas, Size size) {
    if (edges.isEmpty) return;
    for (final e in edges) {
      canvas.drawLine(
        e.a,
        e.b,
        Paint()
          ..color = e.color
          ..strokeWidth = e.width
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SilhouetteOverlayPainter oldDelegate) =>
      oldDelegate.edges != edges;
}
