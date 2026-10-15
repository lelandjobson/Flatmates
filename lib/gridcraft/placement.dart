import 'dart:ui';

import '../geometry/polygon_union.dart';
import '../papercut/paper.dart';
import 'blueprint.dart';
import 'folded_model.dart';
import 'rules.dart';
import 'scissor.dart' show ownsPoint;

/// A paper piece laid on a model face. The piece's level coordinates turn by
/// [quarterTurns] counter-clockwise about the level origin, then move by
/// [offset]. Both stay on whole grid cells. The identity is the one placement
/// that puts every blueprint face on its model face.
class PiecePlacement {
  const PiecePlacement({
    required this.pieceId,
    required this.face,
    this.offset = Offset.zero,
    this.quarterTurns = 0,
  });

  final String pieceId;
  final int face;
  final Offset offset;
  final int quarterTurns;

  int get turns => quarterTurns % 4;

  Offset apply(Offset point) => turn(point, quarterTurns) + offset;

  /// Slid by [delta], snapped to [spacing].
  PiecePlacement movedTo(Offset offset, double spacing) => PiecePlacement(
    pieceId: pieceId,
    face: face,
    offset: snapToGrid(offset, spacing),
    quarterTurns: quarterTurns,
  );

  /// A quarter turn about [pivot]. Positive [direction] is counter-clockwise.
  PiecePlacement turned(int direction, Offset pivot, double spacing) {
    final step = direction >= 0 ? 1 : 3;
    return PiecePlacement(
      pieceId: pieceId,
      face: face,
      offset: snapToGrid(turn(offset - pivot, step) + pivot, spacing),
      quarterTurns: (quarterTurns + step) % 4,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PiecePlacement &&
      other.pieceId == pieceId &&
      other.face == face &&
      other.offset == offset &&
      other.turns == turns;

  @override
  int get hashCode => Object.hash(pieceId, face, offset, turns);
}

Offset turn(Offset point, int quarterTurns) {
  switch (quarterTurns % 4) {
    case 1:
      return Offset(-point.dy, point.dx);
    case 2:
      return Offset(-point.dx, -point.dy);
    case 3:
      return Offset(point.dy, -point.dx);
    default:
      return point;
  }
}

Offset snapToGrid(Offset point, double spacing) {
  if (spacing <= 0) return point;
  return Offset(
    (point.dx / spacing).roundToDouble() * spacing + 0.0,
    (point.dy / spacing).roundToDouble() * spacing + 0.0,
  );
}

/// First placement when a piece is picked for [face]: its middle over the
/// face's middle, unturned.
PiecePlacement startPlacement(
  PapercutPiece piece,
  int face,
  FoldedModel model,
  double spacing,
) {
  final middle = pointBounds(piece.vertices).center;
  return PiecePlacement(
    pieceId: piece.id,
    face: face,
    offset: snapToGrid(model.faces[face].centroid - middle, spacing),
  );
}

/// True when [piece] is exactly the cut-out of [face]'s island and sits at the
/// identity, so its blueprint faces land on their model faces.
bool placementMatches(
  PiecePlacement placement,
  PapercutPiece piece,
  FoldedModel model,
  GridStep step,
) {
  if (placement.pieceId != piece.id) return false;
  if (placement.face < 0 || placement.face >= model.faces.length) return false;
  if (placement.turns != 0 || placement.offset.distance > 1e-6) return false;
  return isIslandCutout(piece, model, model.faces[placement.face].island, step);
}

/// The paper covers the island's blueprint pieces and nothing more.
bool isIslandCutout(
  PapercutPiece piece,
  FoldedModel model,
  int island,
  GridStep step,
) {
  final rings = {
    for (final face in model.islands[island])
      if (model.faces[face].ring >= 0) model.faces[face].ring,
  };
  if (rings.isEmpty || piece.vertices.length < 3) return false;
  var paperArea = polygonSignedArea(piece.vertices).abs();
  for (final hole in piece.holes) {
    paperArea -= polygonSignedArea(hole).abs();
  }
  var blueprintArea = 0.0;
  for (final ring in rings) {
    final polygon = step.polygons[ring];
    blueprintArea += polygonSignedArea(polygon).abs();
    for (final point in polygon) {
      if (!ownsPoint(piece.vertices, point)) return false;
    }
    final middle = polygonCentroid(polygon);
    for (final hole in piece.holes) {
      if (isInsidePolygon(middle, hole)) return false;
    }
  }
  final cell = step.gridSpacing * step.gridSpacing;
  return (paperArea - blueprintArea).abs() < 1e-3 * cell;
}

/// [piece] where [placement] lays it, with no display nudge.
PapercutPiece placedPiece(PapercutPiece piece, PiecePlacement placement) {
  return PapercutPiece(
    id: piece.id,
    color: piece.color,
    backColor: piece.backColor,
    vertices: [for (final point in piece.vertices) placement.apply(point)],
    holes: [
      for (final hole in piece.holes)
        [for (final point in hole) placement.apply(point)],
    ],
  );
}

/// The blueprint ink carried along with a placed piece.
GridStep placedStep(GridStep step, PiecePlacement placement) {
  return step.copyWith(
    polygons: [
      for (final ring in step.polygons)
        [for (final point in ring) placement.apply(point)],
    ],
    rules: const GridRules(),
    permutation: const LevelPermutation(),
  );
}

/// [decals] carried along with a placed piece.
List<Decal> placedDecals(List<Decal> decals, PiecePlacement placement) {
  return [
    for (final decal in decals)
      Decal(
        label: decal.label,
        center: placement.apply(decal.center),
        up: turn(decal.up, placement.quarterTurns),
        size: decal.size,
        face: decal.face,
      ),
  ];
}
