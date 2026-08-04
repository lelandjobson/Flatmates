import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

import '../crafting/placed_paper.dart';

/// Snapshot of a single placed paper for persistence across mode switches.
class CraftingPaperState {
  CraftingPaperState({
    required this.id,
    required this.paperColor,
    required this.positionX,
    required this.positionY,
    required this.positionZ,
    required this.rotationDeg,
    required this.sizeLevel,
    this.localVertices,
    this.localHoles = const [],
    this.cutSegments = const [],
    this.locked = false,
    this.lockedBlueprintIndex,
    this.materialId,
  });

  final String id;
  final PaperColor paperColor;
  final double positionX;
  final double positionY;
  final double positionZ;
  final double rotationDeg;
  final int sizeLevel;
  final List<Offset>? localVertices;
  final List<List<Offset>> localHoles;
  final List<(Offset, Offset)> cutSegments;
  final bool locked;
  final int? lockedBlueprintIndex;
  final String? materialId;

  factory CraftingPaperState.fromPaper(PlacedPaper paper) {
    return CraftingPaperState(
      id: paper.id,
      paperColor: paper.paperColor,
      positionX: paper.position.x,
      positionY: paper.position.y,
      positionZ: paper.position.z,
      rotationDeg: paper.rotationDeg,
      sizeLevel: paper.sizeLevel,
      localVertices: paper.localVertices != null
          ? List<Offset>.from(paper.localVertices!)
          : null,
      localHoles: paper.localHoles
          .map((h) => List<Offset>.from(h))
          .toList(),
      cutSegments: List<(Offset, Offset)>.from(paper.cutSegments),
      locked: paper.locked,
      lockedBlueprintIndex: paper.lockedBlueprintIndex,
      materialId: paper.materialId,
    );
  }

  PlacedPaper toPaper() {
    final p = PlacedPaper(
      id: id,
      paperColor: paperColor,
      position: Vector3(positionX, positionY, positionZ),
      rotationDeg: rotationDeg,
      sizeLevel: sizeLevel,
      localVertices: localVertices,
      localHoles: localHoles,
      materialId: materialId,
    );
    p.cutSegments.addAll(cutSegments);
    p.locked = locked;
    p.lockedBlueprintIndex = lockedBlueprintIndex;
    return p;
  }
}

/// Per-structure crafting state.
class StructureCraftingState {
  StructureCraftingState({
    this.papers = const [],
    this.nextPaperId = 0,
  });

  final List<CraftingPaperState> papers;
  final int nextPaperId;
}

/// In-memory store of crafting state keyed by structure ID.
class CraftingStateStore {
  final Map<String, StructureCraftingState> _states = {};

  StructureCraftingState? getState(String structureId) =>
      _states[structureId];

  bool hasState(String structureId) => _states.containsKey(structureId);

  void saveState(String structureId, StructureCraftingState state) {
    _states[structureId] = state;
  }

  void savePapers(String structureId, List<PlacedPaper> papers, int nextId) {
    _states[structureId] = StructureCraftingState(
      papers: papers.map(CraftingPaperState.fromPaper).toList(),
      nextPaperId: nextId,
    );
  }
}
