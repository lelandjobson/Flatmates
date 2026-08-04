import 'package:flutter/animation.dart';

import '../geometry/folded_geometry.dart';
import '../geometry/geometry.dart';
import '../rendering/mesh.dart';

class FoldAnimator {
  FoldAnimator({
    required this.foldedGeometry,
    required this.mesh,
    required Duration duration,
    required TickerProvider vsync,
    required VoidCallback onChanged,
    this.ensureOutwardNormals = false,
    Geometry Function(Geometry geometry)? geometryMapper,
  })  : _duration = duration,
        _onChanged = onChanged,
        _geometryMapper = geometryMapper {
    _controller = AnimationController(
      vsync: vsync,
      duration: _duration,
      value: 1,
    )..addListener(_applyFrame);
    _applyFrame();
  }

  final FoldedGeometry foldedGeometry;
  final Mesh mesh;
  final VoidCallback _onChanged;
  final bool ensureOutwardNormals;
  final Geometry Function(Geometry geometry)? _geometryMapper;
  late final AnimationController _controller;
  Duration _duration;

  Duration get duration => _duration;
  set duration(Duration value) {
    _duration = value;
    _controller.duration = value;
  }

  bool get isUnfolded => _controller.value <= 1e-3;

  void jumpTo(bool unfolded) {
    _controller.value = unfolded ? 0 : 1;
    _applyFrame();
  }

  void setUnfolded(bool unfolded) {
    final target = unfolded ? 0.0 : 1.0;
    if ((target - _controller.value).abs() <= 1e-4) {
      return;
    }
    _controller.animateTo(
      target,
      duration: _duration,
      curve: Curves.easeOutCubic,
    );
  }

  void dispose() {
    _controller.dispose();
  }

  void _applyFrame() {
    final clamped = _controller.value.clamp(0.0, 1.0);
    var geometry = foldedGeometry.toGeometry(foldValue: clamped);
    if (ensureOutwardNormals) {
      geometry = ensureOutwardFacingGeometry(geometry);
    }
    final geometryMapper = _geometryMapper;
    if (geometryMapper != null) {
      geometry = geometryMapper(geometry);
    }
    mesh.geometry = geometry;
    _onChanged();
  }
}

