import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart';

import '../tiles/tiles.dart';

class ConnectSelection {
  const ConnectSelection({
    required this.coordinate,
    required this.color,
    required this.world,
    required this.meshId,
    required this.highlightable,
  });

  final TileCoordinate coordinate;
  final Color color;
  final Vector3 world;
  final String meshId;
  final bool highlightable;
}

class StructureSelection {
  const StructureSelection({
    required this.instance,
    required this.structureId,
    required this.world,
    required this.highlightable,
  });

  final GeometryInstance instance;
  final String structureId;
  final Vector3 world;
  final bool highlightable;
}

class TileSurfaceHandle {
  const TileSurfaceHandle({
    required this.layerId,
    required this.feature,
    required this.color,
  });

  final String layerId;
  final VectorTileFeature feature;
  final Color color;
}

