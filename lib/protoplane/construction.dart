import 'dart:ui';
import 'drawing_graph.dart';
import 'models.dart';
import 'geometry.dart';

enum ConstructionTool { pencil, volume, paper, scissors, fold }

enum ConstructionPaper { building, cloth }

extension ConstructionPaperMaterial on ConstructionPaper {
  PaperMaterial get material => this == ConstructionPaper.building
      ? PaperMaterial.paperWhite
      : PaperMaterial.paperGreen;
}

class ConstructionTarget {
  const ConstructionTarget(
    this.planeId,
    this.surface,
    this.point,
    this.region,
    this.spacing, {
    this.context = MaterialContext.outdoor,
    this.roomId,
  });
  final MaterialContext context;
  final String? roomId;
  final String planeId;
  final DrawingSurface surface;
  final Offset point;
  final Region region;
  final double spacing;
}

class ConstructionEvaluation {
  const ConstructionEvaluation(
    this.tool,
    this.target, {
    this.object,
    this.frame,
    this.issue,
    this.replacementId,
    this.paper = ConstructionPaper.building,
    this.stroke,
  });
  final List<Offset>? stroke;
  final ConstructionTool tool;
  final ConstructionPaper paper;
  final String? replacementId;
  final ConstructionTarget? target;
  final CraftObject? object;
  final CraftPlane? frame;
  final String? issue;
  bool get valid => issue == null && target != null && object != null;
}
