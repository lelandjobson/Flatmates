import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../animation/scene_animatables.dart';
import '../geometry/folded_geometry.dart';
import '../geometry/geometry.dart';
import '../rendering/lights.dart';
import '../rendering/mesh.dart';
import '../rendering/scene/camera.dart';
import '../rendering/scene/camera_controller.dart';
import '../rendering/scene/scene.dart';
import '../rendering/scene_view.dart';

/// Reusable 3D scene viewer with orbit camera, lighting, and optional
/// fold/unfold animation support.
///
/// Accepts a list of [SceneObjectSpec]s that describe the meshes to render
/// (geometry, material, position, optional fold geometry). All objects are
/// collectively centered at the origin.
class SceneWidget extends StatefulWidget {
  const SceneWidget({
    super.key,
    required this.objects,
    this.initiallyUnfolded = true,
    this.cameraDistance = 400,
    this.fovDegrees = 55,
    this.globalIllumination = 0.25,
    this.onFoldComplete,
  });

  final List<SceneObjectSpec> objects;
  final bool initiallyUnfolded;
  final double cameraDistance;
  final double fovDegrees;
  final double globalIllumination;

  /// Called when a fold animation finishes (folded → complete).
  final VoidCallback? onFoldComplete;

  @override
  State<SceneWidget> createState() => SceneWidgetState();
}

class SceneWidgetState extends State<SceneWidget>
    with TickerProviderStateMixin {
  late Scene _scene;
  late OrbitCameraController _orbitController;
  final List<MeshUnfoldAnimatable> _animatables = [];

  Offset? _lastTouchFocalPoint;
  double _lastTouchScale = 1.0;
  int _mouseButtons = 0;
  int _lastTouchPointerCount = 0;

  @override
  void initState() {
    super.initState();
    _scene = Scene(globalIllumination: widget.globalIllumination);

    final d = widget.cameraDistance;
    final camera = Camera(
      name: 'SceneWidgetCamera',
      position: Vector3(d * 0.75, d * 0.75, d * 0.75),
      target: Vector3.zero(),
      projection: ProjectionType.perspective,
      fovDegrees: widget.fovDegrees,
      near: 1,
      far: d * 5,
    );

    _orbitController = OrbitCameraController(
      camera: camera,
      target: Vector3.zero(),
    );

    _scene
      ..addLight(DirectionalLight(
        color: Colors.white,
        intensity: 0.9,
        direction: Vector3(-0.6, -1, -0.4),
      ))
      ..camera = camera;

    _buildMeshes();
  }

  void _buildMeshes() {
    for (final spec in widget.objects) {
      final mesh = Mesh(
        id: spec.id,
        name: spec.name,
        geometry: spec.foldedGeometry != null
            ? ensureOutwardFacingGeometry(
                spec.foldedGeometry!.toGeometry(foldValue: 1),
              )
            : spec.geometry!,
        material: spec.material,
      );
      if (spec.position != null) {
        mesh.setPosition(spec.position!);
      }

      if (spec.foldedGeometry != null) {
        final unfoldedGeom = ensureOutwardFacingGeometry(
          spec.foldedGeometry!.toGeometry(foldValue: 0),
        );
        final animatable = MeshUnfoldAnimatable(
          vsync: this,
          mesh: mesh,
          foldedGeometry: spec.foldedGeometry!,
          unfoldedGeometry: unfoldedGeom,
          duration: const Duration(milliseconds: 800),
          initiallyUnfolded: widget.initiallyUnfolded,
        );
        _scene.addAnimatable(animatable);
        _animatables.add(animatable);
      } else {
        _scene.addMesh(mesh);
      }
    }
  }

  /// Trigger fold animation on all meshes. Calls [onFoldComplete] when done.
  void foldAll() {
    if (_animatables.isEmpty) {
      widget.onFoldComplete?.call();
      return;
    }
    for (final a in _animatables) {
      a.setUnfolded(false);
    }
    Future.delayed(const Duration(milliseconds: 850), () {
      widget.onFoldComplete?.call();
    });
  }

  /// Update materials on existing meshes by matching spec IDs.
  void updateMaterials(List<SceneObjectSpec> specs) {
    for (final spec in specs) {
      final mesh = _scene.meshById(spec.id);
      if (mesh != null) {
        mesh.material = spec.material;
      }
    }
  }

  /// Trigger unfold animation on all meshes.
  void unfoldAll() {
    for (final a in _animatables) {
      a.setUnfolded(true);
    }
  }

  @override
  void didUpdateWidget(SceneWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.objects.length == oldWidget.objects.length) {
      for (var i = 0; i < widget.objects.length; i++) {
        final newSpec = widget.objects[i];
        final oldSpec = oldWidget.objects[i];
        if (newSpec.id == oldSpec.id &&
            !_materialEquals(newSpec.material, oldSpec.material)) {
          final mesh = _scene.meshById(newSpec.id);
          if (mesh != null) {
            mesh.material = newSpec.material;
          }
        }
      }
    }
  }

  bool _materialEquals(MaterialModel a, MaterialModel b) {
    if (a.color != b.color || a.opacity != b.opacity) return false;
    final aFace = a.perFaceColors;
    final bFace = b.perFaceColors;
    if (aFace == null && bFace == null) return true;
    if (aFace == null || bFace == null) return false;
    if (aFace.length != bFace.length) return false;
    for (var i = 0; i < aFace.length; i++) {
      if (aFace[i] != bFace[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _orbitController.dispose();
    _scene.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
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
                _orbitController.pan(event.delta);
              } else if ((_mouseButtons & kPrimaryButton) != 0) {
                _orbitController.orbit(event.delta);
              }
            }
          },
          onPointerUp: (_) => _mouseButtons = 0,
          onPointerCancel: (_) => _mouseButtons = 0,
          onPointerSignal: (signal) {
            if (signal is PointerScrollEvent) {
              _orbitController.zoomByScroll(signal.scrollDelta.dy);
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
                  _orbitController.orbit(delta);
                } else if (details.pointerCount >= 2) {
                  _orbitController.pan(delta);
                  final scaleChange = details.scale / _lastTouchScale;
                  if (scaleChange > 0 && scaleChange != 1.0) {
                    _orbitController.zoomByScale(scaleChange);
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
      },
    );
  }
}

/// Describes a 3D object to place in a [SceneWidget].
class SceneObjectSpec {
  const SceneObjectSpec({
    required this.id,
    this.name = '',
    this.geometry,
    this.foldedGeometry,
    required this.material,
    this.position,
  }) : assert(
         geometry != null || foldedGeometry != null,
         'Provide either geometry or foldedGeometry',
       );

  final String id;
  final String name;
  final Geometry? geometry;
  final FoldedGeometry? foldedGeometry;
  final MaterialModel material;
  final Vector3? position;
}
