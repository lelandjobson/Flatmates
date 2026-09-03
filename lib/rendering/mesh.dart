import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart';

import '../geometry/geometry.dart';
import '../geometry/transformable.dart';

class Mesh extends Transformable {
  Mesh({
    required this.id,
    required this.name,
    required Geometry geometry,
    required MaterialModel material,
    Vector3? position,
    Vector3? rotation,
    Vector3? scale,
    this.highlightOnClick = false,
    this.visible = true,
    this.groundPlane = false,
  })  : _geometry = geometry,
        _material = material,
        _highlightColor = null,
        super(position: position, rotation: rotation, scale: scale);

  final String id;
  final String name;
  final bool highlightOnClick;
  bool visible;

  /// Ground-plane paper: paint under volumes / structures / friends.
  bool groundPlane;

  Geometry _geometry;
  Geometry get geometry => _geometry;
  set geometry(Geometry value) => _geometry = value;

  MaterialModel _material;
  MaterialModel get material => _material;
  set material(MaterialModel value) => _material = value;

  Color? _highlightColor;
  bool get isHighlighted => _highlightColor != null;
  Color? get highlightColor => _highlightColor;

  void setHighlight(Color? color) {
    _highlightColor = color;
  }
}
