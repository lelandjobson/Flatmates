import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

enum PaperColor {
  pink(Color(0xFFFFB3BA), 'Pink'),
  yellow(Color(0xFFFFF3B0), 'Yellow'),
  green(Color(0xFFBAFFC9), 'Green');

  const PaperColor(this.color, this.label);
  final Color color;
  final String label;
}

class PlacedPaper {
  PlacedPaper({
    required this.id,
    required this.paperColor,
    required this.position,
    this.rotationDeg = 0,
    this.sizeLevel = 1,
    this.localVertices,
    this.localHoles = const [],
    this.groupId,
    this.materialId,
  });

  final String id;
  final PaperColor paperColor;
  Vector3 position;
  double rotationDeg;
  /// 1 = 8x8 cells (one paper). Locked once cut.
  int sizeLevel;
  final List<Offset>? localVertices;
  final List<List<Offset>> localHoles;
  String? groupId;
  final List<(Offset, Offset)> cutSegments = [];
  bool locked = false;
  int? lockedBlueprintIndex;

  /// True when this piece is matched to a blueprint slot (in craft position).
  bool get isBlueprintMatched => lockedBlueprintIndex != null;

  /// Material ID from the inventory system. When set, the display color is
  /// derived from the CraftingMaterialRegistry rather than the PaperColor enum.
  final String? materialId;
}
