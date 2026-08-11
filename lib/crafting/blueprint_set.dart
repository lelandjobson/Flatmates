import 'crafting_blueprint.dart';

/// A step within a blueprint set, referencing a specific blueprint by its
/// asset path components (craft name + island index).
class BlueprintStep {
  const BlueprintStep({
    required this.craft,
    required this.island,
    this.label,
    this.iconCodePoint = 0xe87e, // default: build icon
  });

  final String craft;
  final int island;
  final String? label;
  final int iconCodePoint;

  String get assetKey => island == 0 ? craft : '$craft#$island';
}

/// An ordered collection of blueprints to be completed in sequence.
class BlueprintSet {
  const BlueprintSet({
    required this.name,
    required this.steps,
  });

  final String name;
  final List<BlueprintStep> steps;

  /// Creates a single-step set from an existing blueprint.
  factory BlueprintSet.single(CraftingBlueprint blueprint) {
    return BlueprintSet(
      name: blueprint.displayName,
      steps: [
        BlueprintStep(
          craft: blueprint.craft,
          island: blueprint.island,
          label: blueprint.displayName,
        ),
      ],
    );
  }
}
