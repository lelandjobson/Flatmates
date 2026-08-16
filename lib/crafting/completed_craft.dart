import 'dart:ui' as ui;

import '../crafting/crafting_blueprint.dart';
import '../data/crafting_state.dart';
import '../rendering/iso/iso_sprite.dart';

/// A craft that has been fully completed (all blueprint regions locked).
/// Can be placed in the world as an iso asset.
class CompletedCraft {
  CompletedCraft({
    required this.id,
    required this.blueprintName,
    required this.papers,
    required this.canvasSize,
    this.blueprint,
  });

  final String id;
  final String blueprintName;
  final List<CraftingPaperState> papers;
  final double canvasSize;

  /// The blueprint used to fold this craft (needed for sprite regeneration).
  final CraftingBlueprint? blueprint;

  /// Generated raster iso sprites for each view direction index.
  Map<int, ui.Image>? isoSprites;

  /// Generated vector iso sprites for each view direction index.
  Map<int, VectorIsoSprite>? vectorSprites;

  /// Whether iso sprites have been generated.
  bool get hasSprites =>
      (isoSprites != null && isoSprites!.isNotEmpty) ||
      (vectorSprites != null && vectorSprites!.isNotEmpty);

  /// Asset type id used when placing this craft in the world.
  String get objTypeId => 'obj_${blueprintName.toLowerCase()}';

  @override
  String toString() => 'CompletedCraft($blueprintName, ${papers.length} papers)';
}

/// Stored in structure inventory alongside raw materials.
/// The structure inventory key uses a 'craft:' prefix to distinguish from
/// material IDs.
class CraftInventoryEntry {
  CraftInventoryEntry({required this.craft});

  final CompletedCraft craft;

  String get inventoryKey => 'craft:${craft.id}';
}
