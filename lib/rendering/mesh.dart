import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart';

import '../geometry/geometry.dart';
import '../geometry/transformable.dart';
import 'ground_occlusion.dart';
import 'scene/planar_texture.dart';
import 'scene/surface_texture.dart';
import 'surface_edge_shading.dart';

class Mesh extends Transformable {
  Mesh({
    required this.id,
    required this.name,
    required Geometry geometry,
    required MaterialModel material,
    Vector3? position,
    Vector3? rotation,
    Vector3? scale,
    bool yawThenPitch = false,
    double travelYaw = 0,
    this.highlightOnClick = false,
    this.visible = true,
    this.groundPlane = false,
    this.groundOcclusion,
    this.planarTexture,
    this.surfaceTexture,
    this.textureUp,
    this.shadeEdges = false,
  }) : _geometry = geometry,
       _material = material,
       _highlightColor = null,
       super(
         position: position,
         rotation: rotation,
         scale: scale,
         yawThenPitch: yawThenPitch,
         travelYaw: travelYaw,
       );

  ColorFilter? appearanceFilter;
  final String id;
  final String name;
  final bool highlightOnClick;
  bool visible;

  /// Ground-plane paper: paint under volumes / structures / friends.
  bool groundPlane;

  /// When set, faces are clipped so solid ground hides underground parts.
  GroundOcclusion? groundOcclusion;

  /// Optional atlas sprite for flat ground surfaces.
  final PlanarTexture? planarTexture;
  final SurfaceTexture? surfaceTexture;
  final Vector3? textureUp;

  /// Opt-in shading prepared outside the renderer's paint loop.
  final bool shadeEdges;
  Map<int, SurfaceEdgeShade> edgeShades = const {};
  Map<int, List<SurfaceEdgeShade>> pencilShades = const {};
  double pencilOpacity = .35;

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
