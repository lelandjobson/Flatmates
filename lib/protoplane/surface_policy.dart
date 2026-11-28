import 'construction.dart';
import 'models.dart';

/// Physical surface capabilities, independent of camera and hover state.
Set<ConstructionTool> surfaceTools(
  CraftPlane plane,
  CraftObject? owner, {
  required bool landscape,
}) {
  if (landscape) return const {ConstructionTool.volume};
  if (owner?.kind == CraftKind.paperSheet &&
      owner?.material == PaperMaterial.paperGreen) {
    return const {ConstructionTool.fold};
  }
  if (owner?.kind != CraftKind.room) return const {};
  if (plane.roomFace == 'floor' && plane.interior) {
    return const {ConstructionTool.pencil, ConstructionTool.paper};
  }
  if (plane.roomFace?.startsWith('wall-') == true) {
    return const {
      ConstructionTool.pencil,
      ConstructionTool.scissors,
      ConstructionTool.fold,
    };
  }
  return const {};
}
