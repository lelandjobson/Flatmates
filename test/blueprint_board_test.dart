import 'dart:math' as math;

import 'package:flatmates/gestures/gesture_system.dart';
import 'package:flatmates/gridcraft/blueprint_board.dart';
import 'package:flatmates/gridcraft/mixed_craft.dart';
import 'package:flatmates/papercut/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('piece transfer', () {
    test('a sent ring keeps its shape and lands on the step center', () {
      final area = mixedOpeningArea().copy(selected: {'sheet-1/paper'});
      final taken = takeCraftSelection(area, center: const Offset(3.5, 1));
      expect(taken, isNotNull);
      expect(taken!.craft.sheets, isEmpty);
      expect(taken.pieces, hasLength(1));
      expect(taken.pieces.single.vertices.first, const Offset(-8.5, -11));
      expect(
        taken.pieces.single.vertices[1].dx - taken.pieces.single.vertices[0].dx,
        24,
      );

      final back = placePiecesOnCraft(
        taken.craft,
        taken.pieces,
        center: Offset.zero,
      );
      final piece = back.sheets.single.paper.pieces.single;
      expect(piece.vertices.first, const Offset(-12, -12));
      expect(piece.vertices[1].dx - piece.vertices[0].dx, 24);
      expect(back.selected, {'sheet-2/board-1'});
    });

    test('undo puts a sent piece back on the bench and off the board', () {
      final boards = {'twin-ls/0': StepBoard()};
      final piece = BoardPiece(
        id: 'board-1',
        color: kPapercutYellow,
        vertices: const [Offset.zero, Offset(1, 0), Offset(0, 1)],
      );
      final transfer = BoardTransfer(
        stepKey: 'twin-ls/0',
        pieces: [piece],
        addedToBoard: true,
      );
      boards['twin-ls/0']!.addPieces([piece]);
      expect(boards['twin-ls/0']!.pieces, hasLength(1));

      transfer.undo(boards);
      expect(boards['twin-ls/0']!.pieces, isEmpty);

      transfer.redo(boards);
      expect(boards['twin-ls/0']!.pieces, hasLength(1));
      expect(boards['twin-ls/0']!.pieces.single.id, 'board-1');
    });
  });

  group('blueprint snap', () {
    test('blueprint vertices beat paper, and paper beats the grid', () {
      final blueprint = blueprintMoveSnap(
        moving: const [Offset(0.2, 0.2)],
        blueprintVertices: const [Offset.zero],
        otherPaper: const [Offset(0.15, 0.2)],
        spacing: 1,
        radius: 0.5,
      );
      expect(blueprint.dx, closeTo(-0.2, 1e-9));
      expect(blueprint.dy, closeTo(-0.2, 1e-9));

      final paper = blueprintMoveSnap(
        moving: const [Offset(0.2, 0)],
        blueprintVertices: const [],
        otherPaper: const [Offset(0.4, 0)],
        spacing: 1,
        radius: 0.5,
      );
      expect(paper, const Offset(0.2, 0));
    });

    test('a far drag still settles on the nearest grid point', () {
      final delta = blueprintMoveSnap(
        moving: const [Offset(5.2, 0)],
        blueprintVertices: const [],
        otherPaper: const [],
        spacing: 1,
        radius: 0.05,
      );
      expect(delta.dx, closeTo(-0.2, 1e-9));
      expect(delta.dy, closeTo(0, 1e-9));
    });
  });

  group('transform', () {
    test('the outer edge snaps to a blueprint vertex, else a grid line', () {
      const bounds = Rect.fromLTRB(0, 0, 2, 2);
      final square = [
        BoardPiece(
          id: 'board-1',
          color: kPapercutYellow,
          vertices: const [
            Offset(0, 0),
            Offset(2, 0),
            Offset(2, 2),
            Offset(0, 2),
          ],
        ),
      ];

      final toVertex = stretchToPointer(
        handle: TransformHandle.maxX,
        bounds: bounds,
        pointer: const Offset(3.2, 1),
        blueprintVertices: const [Offset(3, 5)],
        spacing: 1,
        radius: 0.5,
      );
      final snapped = stretchPieces(square, {'board-1'}, toVertex);
      expect(snapped.single.vertices[1].dx, closeTo(3, 1e-9));
      expect(snapped.single.vertices[0].dx, closeTo(0, 1e-9));

      final toGrid = stretchToPointer(
        handle: TransformHandle.maxX,
        bounds: bounds,
        pointer: const Offset(4.2, 1),
        blueprintVertices: const [],
        spacing: 1,
        radius: 0.1,
      );
      final gridded = stretchPieces(square, {'board-1'}, toGrid);
      expect(gridded.single.vertices[1].dx, closeTo(4, 1e-9));
      expect(gridded.single.vertices[0], const Offset(0, 0));
    });

    test('stretch off keeps side grabs quiet and corners uniform', () {
      const bounds = Rect.fromLTRB(0, 0, 2, 2);
      expect(
        hitTransformHandle(
          const Offset(2, 1),
          bounds,
          0.3,
          box: kCombinedTransform,
        ),
        isNull,
      );
      expect(
        hitTransformHandle(
          const Offset(2, 2),
          bounds,
          0.3,
          box: kCombinedTransform,
        ),
        TransformHandle.maxXMaxY,
      );
      expect(kCombinedTransform.stretch, isFalse);
      expect(kCombinedTransform.rotation, isTrue);

      final uniform = stretchToPointer(
        handle: TransformHandle.maxXMaxY,
        bounds: bounds,
        pointer: const Offset(4, 4),
        blueprintVertices: const [],
        spacing: 1,
        radius: 0.1,
        uniform: true,
      );
      expect(uniform.scaleX, closeTo(2, 1e-9));
      expect(uniform.scaleY, closeTo(uniform.scaleX, 1e-9));
    });

    test('the rotation ring steps by five degrees', () {
      expect(snapRotationDelta(7), 5);
      expect(snapRotationDelta(8), 10);
      expect(snapRotationDelta(-3), -5);
      expect(kRotationSnapDegrees, 5);
      final ring = RotationWidget.layout(
        center: const Offset(100, 100),
        halfDiagonal: 20,
      );
      expect(ring.hits(ring.handle), isTrue);
      expect(ring.hits(const Offset(0, 0)), isFalse);
    });

    test('a rotate-from-point settles a vertex onto its target', () {
      const pivot = Offset.zero;
      const moving = [Offset(1, 0)];
      final radians = snapTurn(
        moving: moving,
        pivot: pivot,
        radians: math.pi / 2 - 0.05,
        targets: const [Offset(0, 1)],
        radius: 0.2,
      );
      final landed = rotateAround(moving.single, pivot, radians);
      expect(landed.dx, closeTo(0, 1e-6));
      expect(landed.dy, closeTo(1, 1e-6));
    });
  });

  group('dimension board tools', () {
    test(
      'select hides with the last piece, and dimensions follow the tool',
      () {
        expect(selectToolShown(0), isFalse);
        expect(selectToolShown(2), isTrue);
        expect(boardToolWithPieces(BoardTool.select, 0), BoardTool.dimension);
        expect(boardToolWithPieces(BoardTool.select, 1), BoardTool.select);

        expect(dimensionWidgetsShown(BoardTool.dimension), isTrue);
        expect(dimensionWidgetsShown(BoardTool.select), isFalse);
        expect(
          placedDimensionsShown(BoardTool.select, showInSelect: false),
          isFalse,
        );
        expect(
          placedDimensionsShown(BoardTool.select, showInSelect: true),
          isTrue,
        );
        expect(
          placedDimensionsShown(BoardTool.dimension, showInSelect: false),
          isTrue,
        );
      },
    );
  });

  group('pinch rotation', () {
    test('two contacts report the angle between them', () {
      expect(
        pointerPairAngle(Offset.zero, const Offset(0, 1)),
        closeTo(math.pi / 2, 1e-9),
      );
      expect(wrapRadians(0), 0);
      expect(wrapRadians(math.pi + 0.1), closeTo(-math.pi + 0.1, 1e-9));
    });
  });
}
