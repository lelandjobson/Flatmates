import '../gridcraft/cube_blueprint.dart';
import '../gridcraft/cube_craft.dart';
import '../gridcraft/folded_model.dart';
import '../gridcraft/papercraft_net.dart';
import '../gridcraft/papercrafts.dart';
import '../papercut/craft_v1.dart';

/// The craft collection the craft room opens to.
const String kCraftRoomAsset = 'assets/craft_collections/craft_room.json';

/// Edge length of the craft room's cube. The shared cube stays [kCubeFace].
const double kRoomCubeFace = 3;

/// Puzzle id of the craft room's cube in [kCraftRoomAsset].
const String kRoomCubeId = 'cube-3x3';

/// The craft room's cube: [cubeBlueprint] and [cubeCraftJson] at
/// [kRoomCubeFace].
FoldedModel roomCubeModel() => foldedModelFromCraft(
  CraftV1.fromJson(
    cubeCraftJson(face: kRoomCubeFace),
    assetDirectory: kCubeCraftDirectory,
  ),
  1,
  cubeBlueprint(face: kRoomCubeFace).steps.first,
)!;

FoldedModel _boxStackModel() => foldedModelFromCraft(
  CraftV1.fromJson(
    boxStackCraftJson(),
    assetDirectory: kBoxStackCraftDirectory,
  ),
  1,
  boxStackBlueprint().steps.first,
)!;

FoldedModel? _papercraftModel(PapercraftDesign design) {
  final net = unfoldPapercraft(design);
  return foldedModelFromCraft(
    CraftV1.fromJson(
      net.craftJson(),
      assetDirectory: papercraftDirectory(design),
    ),
    1,
    net.level().steps.first,
  );
}

/// A craft the room can stand: its name and its model in its own space.
class RoomCraft {
  const RoomCraft({required this.id, required this.name, required this.model});

  final String id;
  final String name;
  final FoldedModel model;
}

/// The craft for [puzzleId], built in memory, or null for one the room does
/// not know.
RoomCraft? roomCraft(String puzzleId) {
  switch (puzzleId) {
    case kRoomCubeId:
      return RoomCraft(id: puzzleId, name: 'Cube', model: roomCubeModel());
    case kBoxStackId:
      return RoomCraft(
        id: puzzleId,
        name: 'Box Stack',
        model: _boxStackModel(),
      );
  }
  for (final design in papercraftDesigns()) {
    if (design.puzzleId != puzzleId) continue;
    final model = _papercraftModel(design);
    if (model == null) return null;
    return RoomCraft(id: puzzleId, name: design.name, model: model);
  }
  return null;
}
