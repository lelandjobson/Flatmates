import 'package:flutter/scheduler.dart';

import '../geometry/folded_geometry.dart';
import '../geometry/geometry.dart';
import '../rendering/mesh.dart';
import '../rendering/scene/scene.dart';
import 'fold_animator.dart';

class MeshUnfoldAnimatable implements SceneAnimatable {
  MeshUnfoldAnimatable({
    required Mesh mesh,
    required this.foldedGeometry,
    required Geometry unfoldedGeometry,
    required Duration duration,
    required TickerProvider vsync,
    Geometry Function(Geometry geometry)? geometryMapper,
    bool ensureOutwardNormals = true,
    bool initiallyUnfolded = false,
  })  : _unfoldedGeometry = unfoldedGeometry,
        _duration = duration,
        _vsync = vsync,
        _geometryMapper = geometryMapper,
        _ensureOutwardNormals = ensureOutwardNormals,
        _initiallyUnfolded = initiallyUnfolded,
        _mesh = mesh;

  final Mesh _mesh;
  final FoldedGeometry foldedGeometry;
  final Geometry _unfoldedGeometry;
  final Duration _duration;
  final TickerProvider _vsync;
  final Geometry Function(Geometry geometry)? _geometryMapper;
  final bool _ensureOutwardNormals;
  final bool _initiallyUnfolded;

  FoldAnimator? _foldAnimator;
  bool _isUnfolded = false;
  bool _isAttached = false;

  @override
  Geometry get unfoldedGeometry => _unfoldedGeometry;

  @override
  bool get isUnfolded => _isUnfolded;

  @override
  void attach(Scene scene) {
    if (_isAttached) {
      return;
    }
    _isAttached = true;
    scene.addMesh(_mesh);
    _foldAnimator = FoldAnimator(
      vsync: _vsync,
      foldedGeometry: foldedGeometry,
      mesh: _mesh,
      duration: _duration,
      ensureOutwardNormals: _ensureOutwardNormals,
      geometryMapper: _geometryMapper,
      onChanged: scene.markNeedsPaint,
    )..jumpTo(_initiallyUnfolded);
    _isUnfolded = _initiallyUnfolded;
  }

  @override
  void dispose() {
    _foldAnimator?.dispose();
    _foldAnimator = null;
    _isAttached = false;
  }

  @override
  void jumpTo(bool unfolded) {
    _isUnfolded = unfolded;
    _foldAnimator?.jumpTo(unfolded);
  }

  @override
  Mesh get mesh => _mesh;

  @override
  void setUnfolded(bool value) {
    if (_isUnfolded == value) {
      return;
    }
    _isUnfolded = value;
    _foldAnimator?.setUnfolded(value);
  }

  @override
  void toggleUnfolded() => setUnfolded(!_isUnfolded);
}

