import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../crafting/craft_manifest.dart';
import '../geometry/geometry.dart';
import '../geometry/obj_parser.dart';
import '../rendering/lights.dart';
import '../rendering/mesh.dart';
import '../rendering/scene/camera.dart';
import '../rendering/scene/camera_controller.dart';
import '../rendering/scene/scene.dart';
import '../rendering/scene_view.dart';
import '../ui/fm_dev_back_button.dart';
import '../ui/fm_safe_area.dart';
import '../ui/fm_screen.dart';

/// Orbit preview of a v9 craft's composed step OBJ meshes.
class CraftModelPreviewView extends StatefulWidget {
  const CraftModelPreviewView({super.key, this.craftName = 'house_foo'});

  final String craftName;

  @override
  State<CraftModelPreviewView> createState() => _CraftModelPreviewViewState();
}

class _StepMeshes {
  _StepMeshes({
    required this.step,
    required this.parts,
    required this.appliques,
  });

  final CraftStep step;
  final Mesh? parts;
  final Mesh? appliques;

  Iterable<Mesh> get meshes sync* {
    if (parts != null) yield parts!;
    if (appliques != null) yield appliques!;
  }
}

class _CraftModelPreviewViewState extends State<CraftModelPreviewView> {
  static const _appliqueColor = Color(0xFFFF66AA);

  late final Scene _scene;
  late final OrbitCameraController _orbit;
  int _mouseButtons = 0;
  Offset? _lastTouchFocalPoint;
  double _lastTouchScale = 1.0;
  int _lastTouchPointerCount = 0;

  CraftManifest? _manifest;
  final List<_StepMeshes> _steps = [];
  int _stepIndex = 0;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final camera = Camera(
      name: 'craft-preview-cam',
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

  void _onCameraChanged() {
    _scene.markNeedsPaint();
    setState(() {});
  }

  void _onSceneChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _orbit
      ..removeListener(_onCameraChanged)
      ..dispose();
    _scene.removeListener(_onSceneChanged);
    super.dispose();
  }

  Future<void> _loadCraft() async {
    try {
      final manifests = await CraftManifest.loadAll();
      final manifest = manifests
          .where((m) => m.craft.toLowerCase() == widget.craftName.toLowerCase())
          .firstOrNull;
      if (manifest == null) {
        setState(() {
          _loading = false;
          _error = 'Craft "${widget.craftName}" not found.';
        });
        return;
      }

      final loaded = <_StepMeshes>[];
      for (var i = 0; i < manifest.steps.length; i++) {
        final step = manifest.steps[i];
        final path = 'assets/models/${manifest.craft}/${step.model}';
        String source;
        try {
          source = await rootBundle.loadString(path);
        } catch (_) {
          loaded.add(_StepMeshes(step: step, parts: null, appliques: null));
          continue;
        }
        final groups = ObjParser.parseGroups(
          id: '${manifest.craft}_step_${step.index}',
          source: source,
        );
        Mesh? parts;
        Mesh? appliques;
        final hue = (i * 137.5) % 360;
        final partColor = HSLColor.fromAHSL(1, hue, 0.55, 0.5).toColor();
        for (final entry in groups.entries) {
          final name = entry.key.toLowerCase();
          final isApplique = name.contains('applique');
          final mesh = Mesh(
            id: '${manifest.craft}_${step.index}_${entry.key}',
            name: entry.key,
            geometry: entry.value,
            material: MaterialModel(
              color: isApplique ? _appliqueColor : partColor,
              doubleSided: true,
            ),
          );
          if (isApplique) {
            appliques = mesh;
          } else {
            parts = mesh;
          }
        }
        loaded.add(
          _StepMeshes(step: step, parts: parts, appliques: appliques),
        );
      }

      _centerAssembly(loaded);

      _scene.setMeshes([
        for (final step in loaded) ...step.meshes,
      ]);
      _fitCamera(loaded);

      if (!mounted) return;
      setState(() {
        _manifest = manifest;
        _steps
          ..clear()
          ..addAll(loaded);
        _loading = false;
        _stepIndex = 0;
      });
      _applyIsolation();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _centerAssembly(List<_StepMeshes> steps) {
    final verts = <Vector3>[
      for (final step in steps)
        for (final mesh in step.meshes)
          ...mesh.geometry.vertices,
    ];
    if (verts.isEmpty) return;
    var minX = verts.first.x, maxX = verts.first.x;
    var minY = verts.first.y, maxY = verts.first.y;
    var minZ = verts.first.z, maxZ = verts.first.z;
    for (final v in verts) {
      minX = math.min(minX, v.x);
      maxX = math.max(maxX, v.x);
      minY = math.min(minY, v.y);
      maxY = math.max(maxY, v.y);
      minZ = math.min(minZ, v.z);
      maxZ = math.max(maxZ, v.z);
    }
    final cx = (minX + maxX) / 2;
    final cy = (minY + maxY) / 2;
    final cz = (minZ + maxZ) / 2;
    for (final step in steps) {
      for (final mesh in step.meshes) {
        for (final v in mesh.geometry.vertices) {
          v.x -= cx;
          v.y -= cy;
          v.z -= cz;
        }
      }
    }
  }

  void _fitCamera(List<_StepMeshes> steps) {
    final verts = <Vector3>[
      for (final step in steps)
        for (final mesh in step.meshes)
          ...mesh.geometry.vertices,
    ];
    if (verts.isEmpty) return;
    var maxAbs = 1.0;
    for (final v in verts) {
      maxAbs = math.max(maxAbs, v.length);
    }
    final dist = (maxAbs * 2.4).clamp(8.0, 250.0);
    _orbit.jumpTo(
      position: Vector3(dist * 0.85, dist * 0.65, dist * 0.85),
      target: Vector3.zero(),
    );
  }

  void _applyIsolation() {
    if (_steps.isEmpty) return;
    final current = _steps[_stepIndex].step;
    final currentGroup = current.isolationGroup;
    for (var i = 0; i < _steps.length; i++) {
      final step = _steps[i];
      final sameGroup =
          currentGroup != null && step.step.isolationGroup == currentGroup;
      final MaterialModel Function(Color base) mode;
      if (i == _stepIndex || sameGroup) {
        mode = (c) => MaterialModel(color: c, doubleSided: true, opacity: 1);
      } else if (currentGroup != null) {
        mode = (c) => MaterialModel(
              color: c,
              doubleSided: true,
              wireframe: true,
              opacity: 0.3,
            );
      } else {
        mode = (c) => MaterialModel(color: c, doubleSided: true, opacity: 0.55);
      }
      final hue = (i * 137.5) % 360;
      final partColor = HSLColor.fromAHSL(1, hue, 0.55, 0.5).toColor();
      if (step.parts != null) {
        step.parts!.material = mode(partColor);
      }
      if (step.appliques != null) {
        step.appliques!.material = mode(_appliqueColor);
      }
    }
    _scene.markNeedsPaint();
  }

  void _go(int delta) {
    if (_steps.isEmpty) return;
    final next = (_stepIndex + delta).clamp(0, _steps.length - 1);
    if (next == _stepIndex) return;
    setState(() => _stepIndex = next);
    _applyIsolation();
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps.isEmpty ? null : _steps[_stepIndex].step;
    return FmScreen(
      backgroundColor: const Color(0xFF12121A),
      overlays: [
        const FmDevBackButton(),
        if (step != null)
          FmSafePositioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: _StepHud(
                label: '${_manifest?.craft ?? widget.craftName}  ·  '
                    'Step ${step.index} (${_stepIndex + 1}/${_steps.length})'
                    '${step.isolationGroup != null ? '  [${step.isolationGroup}]' : ''}',
                onPrev: _stepIndex > 0 ? () => _go(-1) : null,
                onNext: _stepIndex < _steps.length - 1 ? () => _go(1) : null,
              ),
            ),
          ),
      ],
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
            _orbit.pan(event.delta);
          } else if ((_mouseButtons & kPrimaryButton) != 0) {
            _orbit.orbit(event.delta);
          }
        }
      },
      onPointerUp: (_) => _mouseButtons = 0,
      onPointerCancel: (_) => _mouseButtons = 0,
      onPointerSignal: (signal) {
        if (signal is PointerScrollEvent) {
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
              _orbit.orbit(delta);
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
        child: SceneView(scene: _scene),
      ),
    );
  }
}

class _StepHud extends StatelessWidget {
  const _StepHud({
    required this.label,
    required this.onPrev,
    required this.onNext,
  });

  final String label;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white24),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: onPrev,
              icon: const Icon(Icons.chevron_left),
              color: Colors.white,
              disabledColor: Colors.white24,
            ),
            Text(label, style: const TextStyle(color: Colors.white)),
            IconButton(
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
              color: Colors.white,
              disabledColor: Colors.white24,
            ),
          ],
        ),
      ),
    );
  }
}
