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
    required this.stackOrder,
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

  /// Higher draws and hit-tests in front.
  /// New pieces use the next integer; split fragments keep the parent and
  /// append a decimal digit (2 → 2 and 2.1, then 2.1 → 2.1 and 2.11).
  double stackOrder;
  double rotationDeg;
  /// 1 = 8x8 cells (one paper). Locked once cut.
  int sizeLevel;
  final List<Offset>? localVertices;
  final List<List<Offset>> localHoles;
  String? groupId;
  final List<(Offset, Offset)> cutSegments = [];
  bool locked = false;
  int? lockedBlueprintIndex;

  /// Protected from punch / paint / cut, but still selectable.
  /// Distinct from [locked], which is a previous-step / applique commit.
  bool opsLocked = false;

  /// True when this piece is matched to a blueprint slot (in craft position).
  bool get isBlueprintMatched => lockedBlueprintIndex != null;

  /// Current-step lock used for tools and the 75% / grey-dot treatment.
  bool get isOpsLocked => opsLocked && !locked;

  /// Material ID from the inventory system. When set, the display color is
  /// derived from the CraftingMaterialRegistry rather than the PaperColor enum.
  final String? materialId;
}
