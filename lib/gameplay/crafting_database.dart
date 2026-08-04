import '../data/craft_tech_models.dart';
import '../data/crafts_tech_provider.dart';
import 'inventory.dart';

/// Represents a craftable item recipe
class CraftingRecipe {
  /// Global multiplier applied to all recipe ingredient requirements
  static const int ingredientScale = 3;

  final String id;
  final String name;
  final String resultType; // Asset type ID or special result identifier
  final Map<String, int> ingredients;
  final int turnsToComplete;
  final String? description;

  const CraftingRecipe({
    required this.id,
    required this.name,
    required this.resultType,
    required this.ingredients,
    this.turnsToComplete = 1,
    this.description,
  });

  /// Number of unique ingredient types required
  int get ingredientCount => ingredients.length;

  /// Ingredients after applying the global scale factor
  Map<String, int> get scaledIngredients =>
      ingredients.map((k, v) => MapEntry(k, v * ingredientScale));

  /// Total material units required (scaled)
  int get totalMaterialsRequired =>
      scaledIngredients.values.fold(0, (sum, amount) => sum + amount);

  /// Check if this recipe can be crafted with the given inventory (uses scaled ingredients)
  bool canCraftWith(Inventory inventory) =>
      inventory.hasEnough(scaledIngredients);

  /// Get a human-readable ingredient list (uses scaled ingredients)
  String get ingredientSummary {
    final parts = <String>[];
    for (final entry in scaledIngredients.entries) {
      parts.add('${entry.value} ${entry.key}');
    }
    return parts.join(' + ');
  }

  @override
  String toString() => 'CraftingRecipe($name: $ingredientSummary)';
}

/// Database of all known crafting recipes with search functionality
class CraftingDatabase {
  final List<CraftingRecipe> _recipes = [];

  CraftingDatabase();

  /// Replace all recipes with those derived from [provider]'s craft entries.
  /// Each craft entry whose graph has edges produces one recipe whose
  /// ingredients come from the edge costs pointing to the product node.
  void loadFromCraftsProvider(CraftsTechProvider provider) {
    _recipes.clear();

    for (final craft in provider.crafts) {
      final graph = craft.crafting;
      if (graph.edges.isEmpty) continue; // raw materials have no edges

      // Identify the product node: the node that appears as an edge target
      // but never as a source. Fall back to the last node in the list.
      final sourceIds = graph.edges.map((e) => e.source).toSet();
      final targetIds = graph.edges.map((e) => e.target).toSet();
      final productCandidates = targetIds.difference(sourceIds);

      String productNodeId;
      if (productCandidates.length == 1) {
        productNodeId = productCandidates.first;
      } else if (productCandidates.isNotEmpty) {
        productNodeId = productCandidates.first;
      } else {
        productNodeId = graph.nodes.last.id;
      }

      final productNode = graph.nodes.cast<GraphNode?>().firstWhere(
        (n) => n!.id == productNodeId,
        orElse: () => null,
      );
      final productName =
          productNode?.displayName ?? _titleFromId(craft.id);

      // Collect ingredients from edges targeting the product node.
      final ingredients = <String, int>{};
      for (final edge in graph.edges) {
        if (edge.target != productNodeId) continue;
        for (final cost in edge.costs) {
          if (cost.type == 'element' && cost.elementId != null) {
            final matId = cost.elementId!.startsWith('fm-')
                ? cost.elementId!
                : 'fm-${cost.elementId}';
            ingredients[matId] =
                (ingredients[matId] ?? 0) + (cost.amount ?? 1);
          }
        }
      }

      if (ingredients.isEmpty) continue;

      final turns = (ingredients.length).clamp(1, 5);
      _recipes.add(CraftingRecipe(
        id: craft.id,
        name: productName,
        resultType: 'crafted_${craft.id}',
        ingredients: ingredients,
        turnsToComplete: turns,
        description: '$productName blueprint',
      ));
    }
  }

  static String _titleFromId(String id) {
    var name = id.startsWith('fm-') ? id.substring(3) : id;
    name = name.replaceAll('-', ' ');
    return name.split(' ').map((w) {
      if (w.isEmpty) return w;
      return '${w[0].toUpperCase()}${w.substring(1)}';
    }).join(' ');
  }

  /// Get all recipes
  List<CraftingRecipe> get allRecipes => List.unmodifiable(_recipes);

  /// Get a recipe by ID
  CraftingRecipe? getRecipe(String id) {
    for (final recipe in _recipes) {
      if (recipe.id == id) return recipe;
    }
    return null;
  }

  /// Search recipes that use a specific material
  List<CraftingRecipe> searchByMaterial(String materialId) {
    return _recipes
        .where((recipe) => recipe.ingredients.containsKey(materialId))
        .toList();
  }

  /// Search recipes by number of unique ingredients
  List<CraftingRecipe> searchByIngredientCount(int count) {
    return _recipes.where((recipe) => recipe.ingredientCount == count).toList();
  }

  /// Search recipes that can be crafted with available inventory
  List<CraftingRecipe> searchCraftable(Inventory available) {
    return _recipes.where((recipe) => recipe.canCraftWith(available)).toList();
  }

  /// Search recipes by name (case-insensitive partial match)
  List<CraftingRecipe> searchByName(String query) {
    final lowerQuery = query.toLowerCase();
    return _recipes
        .where((recipe) => recipe.name.toLowerCase().contains(lowerQuery))
        .toList();
  }

  /// Combined search: by material AND ingredient count
  List<CraftingRecipe> search({String? materialId, int? ingredientCount}) {
    var results = _recipes.toList();

    if (materialId != null) {
      results = results
          .where((r) => r.ingredients.containsKey(materialId))
          .toList();
    }

    if (ingredientCount != null) {
      results = results
          .where((r) => r.ingredientCount == ingredientCount)
          .toList();
    }

    return results;
  }

  /// Add a custom recipe (for future recipe discovery mechanics)
  void addRecipe(CraftingRecipe recipe) {
    // Don't add duplicates
    if (getRecipe(recipe.id) != null) return;
    _recipes.add(recipe);
  }

  /// Remove a recipe by ID
  bool removeRecipe(String id) {
    final index = _recipes.indexWhere((r) => r.id == id);
    if (index >= 0) {
      _recipes.removeAt(index);
      return true;
    }
    return false;
  }
}
