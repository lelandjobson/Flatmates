import 'package:flutter/material.dart';

import 'crafting_database.dart';
import 'inventory.dart';
import 'structure_task.dart';

/// A [StructureTask] that tracks crafting progress for a [CraftingRecipe].
///
/// Evaluates the structure's inventory against the recipe's scaled ingredient
/// requirements and returns [StructureTaskStatus.ready] when all ingredients
/// are present.
class BlueprintTask extends StructureTask {
  BlueprintTask({required this.recipe, Color? color}) : _color = color;

  final CraftingRecipe recipe;
  final Color? _color;
  bool _completed = false;

  @override
  String get id => 'blueprint_${recipe.id}';

  @override
  String get displayName => recipe.name;

  @override
  Color? get iconColor => _color;

  bool get isCompleted => _completed;

  /// Fraction of ingredient requirements satisfied (0.0–1.0).
  double ingredientProgress(Inventory structureInventory) {
    final scaled = recipe.scaledIngredients;
    if (scaled.isEmpty) return 1.0;
    double filled = 0;
    double total = 0;
    for (final entry in scaled.entries) {
      final have = structureInventory.get(entry.key);
      total += entry.value;
      filled += have.clamp(0, entry.value);
    }
    return total > 0 ? filled / total : 0.0;
  }

  @override
  StructureTaskResult evaluate(Inventory structureInventory) {
    if (_completed) {
      return const StructureTaskResult(
        status: StructureTaskStatus.complete,
        progress: 1.0,
      );
    }

    final progress = ingredientProgress(structureInventory);
    final canCraft = recipe.canCraftWith(structureInventory);

    if (canCraft) {
      return StructureTaskResult(
        status: StructureTaskStatus.ready,
        progress: 1.0,
      );
    }

    return StructureTaskResult(
      status: StructureTaskStatus.awaiting,
      progress: progress,
    );
  }

  @override
  void execute(Inventory structureInventory, Inventory playerInventory) {
    if (!recipe.canCraftWith(structureInventory)) return;
    structureInventory.consume(recipe.scaledIngredients);

    if (!structureInventory.add(recipe.resultType, 1)) {
      playerInventory.add(recipe.resultType, 1);
    }
    _completed = true;
  }
}
