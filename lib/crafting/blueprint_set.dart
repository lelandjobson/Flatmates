import 'crafting_blueprint.dart';

/// A step within a blueprint set: either an assembly step's parts or a qLayer.
class BlueprintStep {
  const BlueprintStep({
    required this.craft,
    required this.stepIndex,
    required this.logicalIndex,
    required this.kind,
    this.qLayer,
    this.label,
    this.iconCodePoint = 0xe87e,
  });

  final String craft;

  /// Index into the parent craft's `steps` array.
  final int stepIndex;

  /// Logical step number from the source layer.
  final int logicalIndex;

  final BlueprintStepKind kind;
  final int? qLayer;
  final String? label;
  final int iconCodePoint;

  String get fillKey => '$craft#$stepIndex#${kind.name}#${qLayer ?? -1}';

  bool get isApplique => kind == BlueprintStepKind.applique;
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
          stepIndex: blueprint.stepIndex,
          logicalIndex: blueprint.logicalIndex,
          kind: blueprint.kind,
          qLayer: blueprint.qLayer,
          label: blueprint.displayName,
        ),
      ],
    );
  }
}
