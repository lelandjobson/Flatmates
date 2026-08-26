import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color, Colors;

import '../../geometry/geometry.dart';
import '../lights.dart';
import '../mesh.dart';
import '../render_group.dart';
import 'camera.dart';

class Scene extends ChangeNotifier {
  Scene({double globalIllumination = 0.2})
    : globalIllumination = globalIllumination.clamp(0.0, 1.0);

  final List<Mesh> _meshes = [];
  final List<DirectionalLight> _lights = [];
  final List<SceneAnimatable> _animatables = [];
  final List<RenderGroup> _renderGroups = [];
  Camera? _camera;
  double globalIllumination;
  Mesh? _highlightedMesh;
  String? _highlightedMeshId;
  Color _activeHighlightColor = Colors.yellowAccent;

  List<Mesh> get meshes => List.unmodifiable(_meshes);
  List<DirectionalLight> get lights => List.unmodifiable(_lights);
  List<RenderGroup> get renderGroups => List.unmodifiable(_renderGroups);
  Camera? get camera => _camera;

  set camera(Camera? value) {
    _camera = value;
    notifyListeners();
  }

  void addMesh(Mesh mesh) {
    _meshes.add(mesh);
    notifyListeners();
  }

  void addMeshes(Iterable<Mesh> meshes) {
    final newMeshes = meshes.toList(growable: false);
    if (newMeshes.isEmpty) {
      return;
    }
    _meshes.addAll(newMeshes);
    notifyListeners();
  }

  void setMeshes(Iterable<Mesh> meshes) {
    _meshes
      ..clear()
      ..addAll(meshes);
    _highlightedMesh = null;
    _applyHighlightToCurrentMesh(notify: false);
    notifyListeners();
  }

  Mesh? meshById(String meshId) {
    for (final m in _meshes) {
      if (m.id == meshId) return m;
    }
    return null;
  }

  bool removeMeshById(String meshId) {
    final index = _meshes.indexWhere((mesh) => mesh.id == meshId);
    if (index == -1) {
      return false;
    }
    final removed = _meshes.removeAt(index);
    if (_highlightedMeshId == removed.id) {
      removed.setHighlight(null);
      _highlightedMesh = null;
      _highlightedMeshId = null;
    }
    notifyListeners();
    return true;
  }

  void clearMeshes() {
    if (_meshes.isEmpty) {
      return;
    }
    _meshes.clear();
    _highlightedMesh = null;
    _highlightedMeshId = null;
    notifyListeners();
  }

  void addAnimatable(SceneAnimatable animatable) {
    _animatables.add(animatable);
    animatable.attach(this);
  }

  void addLight(DirectionalLight light) {
    _lights.add(light);
    notifyListeners();
  }

  void setLights(Iterable<DirectionalLight> lights) {
    _lights
      ..clear()
      ..addAll(lights);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Render groups
  // ---------------------------------------------------------------------------

  /// Create a render group from the given mesh IDs.
  /// Meshes in a render group are tessellated adaptively for correct depth
  /// sorting when they overlap.
  RenderGroup createRenderGroup(String id, List<String> meshIds) {
    removeRenderGroup(id);
    final group = RenderGroup(id: id)..meshIds.addAll(meshIds);
    _renderGroups.add(group);
    notifyListeners();
    return group;
  }

  /// Remove a render group by ID. Returns true if it existed.
  bool removeRenderGroup(String id) {
    final idx = _renderGroups.indexWhere((g) => g.id == id);
    if (idx == -1) return false;
    _renderGroups.removeAt(idx);
    notifyListeners();
    return true;
  }

  /// Look up a render group by ID.
  RenderGroup? getRenderGroup(String id) {
    for (final g in _renderGroups) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// Find the render group that contains [meshId], if any.
  RenderGroup? renderGroupForMesh(String meshId) {
    for (final g in _renderGroups) {
      if (g.meshIds.contains(meshId)) return g;
    }
    return null;
  }

  void markNeedsPaint() => notifyListeners();

  void handleClick(String? meshId, {Color? highlightColor}) {
    if (meshId == null) {
      _clearHighlightedMesh();
      return;
    }
    final resolvedColor = highlightColor ?? _activeHighlightColor;
    if (_highlightedMeshId == meshId && _highlightedMesh != null) {
      return;
    }
    _highlightedMesh?.setHighlight(null);
    _highlightedMesh = null;
    _highlightedMeshId = meshId;
    _activeHighlightColor = resolvedColor;
    _applyHighlightToCurrentMesh();
  }

  String? get highlightedMeshId => _highlightedMeshId;

  void _applyHighlightToCurrentMesh({bool notify = true}) {
    if (_highlightedMeshId == null) {
      if (notify) {
        markNeedsPaint();
      }
      return;
    }
    final mesh = _findMeshById(_highlightedMeshId!);
    if (mesh == null || !mesh.highlightOnClick) {
      _highlightedMeshId = null;
      _highlightedMesh = null;
      if (notify) {
        markNeedsPaint();
      }
      return;
    }
    mesh.setHighlight(_activeHighlightColor);
    _highlightedMesh = mesh;
    if (notify) {
      markNeedsPaint();
    }
  }

  void _clearHighlightedMesh() {
    var didChange = false;
    if (_highlightedMesh != null) {
      _highlightedMesh!.setHighlight(null);
      _highlightedMesh = null;
      didChange = true;
    }
    if (_highlightedMeshId != null) {
      _highlightedMeshId = null;
      didChange = true;
    }
    if (didChange) {
      markNeedsPaint();
    }
  }

  Mesh? _findMeshById(String meshId) {
    for (final mesh in _meshes) {
      if (mesh.id == meshId) {
        return mesh;
      }
    }
    return null;
  }

  @override
  void dispose() {
    for (final animatable in _animatables) {
      animatable.dispose();
    }
    _animatables.clear();
    super.dispose();
  }
}

abstract class SceneAnimatable {
  Mesh get mesh;
  Geometry? get unfoldedGeometry;
  bool get isUnfolded;

  void attach(Scene scene);
  void toggleUnfolded();
  void setUnfolded(bool value);
  void jumpTo(bool unfolded);
  void dispose();
}
