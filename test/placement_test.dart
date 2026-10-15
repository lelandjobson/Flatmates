import 'dart:convert';
import 'dart:io';

import 'package:flatmates/gridcraft/blueprint.dart';
import 'package:flatmates/gridcraft/cube_blueprint.dart';
import 'package:flatmates/gridcraft/cube_craft.dart';
import 'package:flatmates/gridcraft/folded_model.dart';
import 'package:flatmates/gridcraft/placement.dart';
import 'package:flatmates/papercut/craft_v1.dart';
import 'package:flatmates/papercut/models.dart';
import 'package:flatmates/papercut/paper.dart';
import 'package:flutter_test/flutter_test.dart';

/// Outline of the cube's Latin cross, as a scissor cut-out would leave it.
const List<Offset> _cross = [
  Offset(5, 0),
  Offset(10, 0),
  Offset(10, 5),
  Offset(20, 5),
  Offset(20, 10),
  Offset(10, 10),
  Offset(10, 15),
  Offset(5, 15),
  Offset(5, 10),
  Offset(0, 10),
  Offset(0, 5),
  Offset(5, 5),
];

void main() {
  final level = GridBlueprint.fromJson(
    jsonDecode(File('levels/cube/cube.json').readAsStringSync())
        as Map<String, dynamic>,
  ).steps.single;
  final model = foldedModelFromCraft(
    CraftV1.fromJson(
      jsonDecode(File('$kCubeCraftDirectory/craft.json').readAsStringSync())
          as Map<String, dynamic>,
    ),
    1,
    level,
  )!;
  const cross = PapercutPiece(
    id: 'cross',
    color: kPapercutYellow,
    vertices: _cross,
    separation: Offset(3, -2),
  );
  final back = model.faceOfRing(3)!;
  final hub = model.faceOfRing(0)!;

  test('the exact cut-out at the identity matches on any of its faces', () {
    for (final face in [hub, back]) {
      expect(
        placementMatches(
          PiecePlacement(pieceId: 'cross', face: face),
          cross,
          model,
          level,
        ),
        isTrue,
      );
    }
  });

  test('a turn, an offset, or the wrong piece does not match', () {
    bool matches(PiecePlacement placement, [PapercutPiece piece = cross]) =>
        placementMatches(placement, piece, model, level);

    expect(
      matches(PiecePlacement(pieceId: 'cross', face: back, quarterTurns: 1)),
      isFalse,
    );
    expect(
      matches(
        PiecePlacement(
          pieceId: 'cross',
          face: back,
          offset: const Offset(1, 0),
        ),
      ),
      isFalse,
    );
    expect(matches(PiecePlacement(pieceId: 'other', face: back)), isFalse);
    expect(
      matches(PiecePlacement(pieceId: 'cross', face: model.faces.length)),
      isFalse,
    );
    const sheet = PapercutPiece(
      id: 'sheet',
      color: kPapercutYellow,
      vertices: [
        Offset(-2, -2),
        Offset(22, -2),
        Offset(22, 17),
        Offset(-2, 17),
      ],
    );
    expect(
      matches(PiecePlacement(pieceId: 'sheet', face: back), sheet),
      isFalse,
    );
    const arm = PapercutPiece(
      id: 'arm',
      color: kPapercutYellow,
      vertices: [Offset(15, 5), Offset(20, 5), Offset(20, 10), Offset(15, 10)],
    );
    expect(matches(PiecePlacement(pieceId: 'arm', face: back), arm), isFalse);
  });

  test('four quarter turns about the face come back to a match', () {
    final pivot = model.faces[back].centroid;
    var placement = PiecePlacement(pieceId: 'cross', face: back);
    for (var i = 0; i < 4; i++) {
      placement = placement.turned(1, pivot, level.gridSpacing);
      expect(placementMatches(placement, cross, model, level), i == 3);
    }
  });

  test('dragging snaps to whole cells and back onto the match', () {
    final start = startPlacement(cross, back, model, level.gridSpacing);
    expect(start.offset.dx % 1, 0);
    expect(start.offset.dy % 1, 0);
    expect(placementMatches(start, cross, model, level), isFalse);
    final moved = start.movedTo(const Offset(0.3, -0.4), level.gridSpacing);
    expect(moved.offset, Offset.zero);
    expect(placementMatches(moved, cross, model, level), isTrue);
  });

  test('each box of the stack takes only its own cross', () {
    final stack = GridBlueprint.fromJson(
      jsonDecode(File(kBoxStackLevelPath).readAsStringSync())
          as Map<String, dynamic>,
    ).steps.single;
    final stackModel = foldedModelFromCraft(
      CraftV1.fromJson(
        jsonDecode(
              File('$kBoxStackCraftDirectory/craft.json').readAsStringSync(),
            )
            as Map<String, dynamic>,
      ),
      1,
      stack,
    )!;
    final top = PapercutPiece(
      id: 'top',
      color: kPapercutYellow,
      vertices: [for (final point in _cross) point + kBoxStackSecondNet],
    );
    for (final face in [stackModel.faceOfRing(0)!, stackModel.faceOfRing(3)!]) {
      final placement = PiecePlacement(pieceId: 'cross', face: face);
      expect(placementMatches(placement, cross, stackModel, stack), isTrue);
      final wrong = PiecePlacement(pieceId: 'top', face: face);
      expect(placementMatches(wrong, top, stackModel, stack), isFalse);
    }
    for (final face in [stackModel.faceOfRing(6)!, stackModel.faceOfRing(9)!]) {
      final placement = PiecePlacement(pieceId: 'top', face: face);
      expect(placementMatches(placement, top, stackModel, stack), isTrue);
      final wrong = PiecePlacement(pieceId: 'cross', face: face);
      expect(placementMatches(wrong, cross, stackModel, stack), isFalse);
    }
  });

  test('placed geometry and decals follow the placement', () {
    const placement = PiecePlacement(
      pieceId: 'cross',
      face: 0,
      offset: Offset(2, 1),
      quarterTurns: 1,
    );
    expect(placement.apply(const Offset(1, 0)), const Offset(2, 2));
    final piece = placedPiece(cross, placement);
    expect(piece.separation, Offset.zero);
    expect(piece.vertices.first, placement.apply(_cross.first));
    final step = placedStep(level, placement);
    expect(step.polygons[0][0], placement.apply(level.polygons[0][0]));
    final decals = placedDecals(faceDecals(model), placement);
    expect(decals.first.up, const Offset(-1, 0));
    expect(
      decals.first.center,
      placement.apply(faceDecals(model).first.center),
    );
  });
}
