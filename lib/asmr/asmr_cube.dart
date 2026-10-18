import '../gridcraft/cube_blueprint.dart';
import '../gridcraft/cube_craft.dart';
import '../gridcraft/folded_model.dart';
import '../papercut/craft_v1.dart';

/// The 5x5x5 cube the ASMR view crafts, folded from its generated craft.
FoldedModel asmrCubeModel() => foldedModelFromCraft(
  CraftV1.fromJson(cubeCraftJson(), assetDirectory: kCubeCraftDirectory),
  1,
  cubeBlueprint().steps.first,
)!;
