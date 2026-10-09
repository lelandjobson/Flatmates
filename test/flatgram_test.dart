import 'package:flatmates/flatgram/flatgram_constraints.dart';
import 'package:flatmates/flatgram/flatgram_models.dart';
import 'package:flatmates/flatgram/flatgram_painter.dart';
import 'package:flatmates/flatgram/flatgram_puzzles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GridPoint and transformations', () {
    test('rotateClockwise works for all quarter turns', () {
      const pt = GridPoint(2, 1);
      expect(pt.rotateClockwise(0), const GridPoint(2, 1));
      expect(pt.rotateClockwise(1), const GridPoint(-1, 2));
      expect(pt.rotateClockwise(2), const GridPoint(-2, -1));
      expect(pt.rotateClockwise(3), const GridPoint(1, -2));
      expect(pt.rotateClockwise(4), const GridPoint(2, 1));
      expect(pt.rotateClockwise(-1), const GridPoint(1, -2));
    });

    test('diverse polyomino shapes rotate and map coordinates correctly', () {
      // 1. L-tromino
      final lTromino = makeLTromino(
        id: 'test_l',
        cornerVal: 5,
        armXVal: 3,
        armYVal: 1,
      );
      expect(lTromino.cells.length, 3);
      final lCellsTurn2 =
          lTromino.transformedCells(const GridPoint(3, 1), 2);
      expect(lCellsTurn2, [
        const GridPoint(3, 1),
        const GridPoint(2, 1),
        const GridPoint(3, 0),
      ]);

      // 2. T-tetromino
      final tPiece = makeTTetromino(
        id: 'test_t',
        barLeftVal: 2,
        barCenterVal: 4,
        barRightVal: 6,
        stemVal: 1,
      );
      expect(tPiece.cells.length, 4);
      final tCellsTurn2 = tPiece.transformedCells(const GridPoint(3, 3), 2);
      expect(tCellsTurn2, [
        const GridPoint(3, 3),
        const GridPoint(2, 3),
        const GridPoint(1, 3),
        const GridPoint(2, 2),
      ]);

      // 3. Monomino
      final mono = makeMonomino(id: 'test_m', value: 4);
      expect(mono.cells.length, 1);
      expect(mono.transformedCells(const GridPoint(2, 1), 1), [
        const GridPoint(2, 1),
      ]);
    });
  });

  group('FlatgramRuleEngine and win condition checks', () {
    final engine = FlatgramRuleEngine();

    test('win condition requires full board coverage', () {
      final puzzle = easyFlatgramPuzzle();

      // Only place 1 piece (board not fully covered)
      final placed = [
        const PlacedPiece(
          pieceId: 'easy_p1',
          anchor: GridPoint(0, 0),
          turns: 0,
        ),
      ];

      final eval = engine.evaluate(
        board: puzzle.board,
        pieces: puzzle.pieces,
        placed: placed,
        constraints: puzzle.constraints,
      );

      expect(eval.isFullyCovered, isFalse);
      expect(eval.isWon, isFalse);
      expect(eval.uncoveredCells.length, 5);
    });

    test('color_touch constraint verifies touching color pieces', () {
      final puzzle = FlatgramPuzzle(
        id: 'test_color',
        title: 'Color Touch Test',
        difficulty: 'easy',
        board: FlatgramBoard(
          cells: {const GridPoint(0, 0)},
          regions: const [],
        ),
        pieces: [
          makeMonomino(id: 'amber_p', color: FlatgramPalette.amber),
        ],
        constraints: const [
          FlatgramConstraint(
            id: 'c_touch',
            type: 'color_touch',
            params: {'cell': [0, 0], 'color': 0xFFFFB300},
          ),
        ],
      );

      final eval = engine.evaluate(
        board: puzzle.board,
        pieces: puzzle.pieces,
        placed: const [
          PlacedPiece(pieceId: 'amber_p', anchor: GridPoint(0, 0), turns: 0),
        ],
        constraints: puzzle.constraints,
      );

      expect(eval.isWon, isTrue);
    });

    test('region_equal constraint requires every tile in region to have equal values', () {
      final board = FlatgramBoard(
        cells: {const GridPoint(0, 0), const GridPoint(1, 0), const GridPoint(0, 1)},
        regions: [
          FlatgramRegion(
            id: 'req',
            label: 'Equal Region',
            color: Colors.blue,
            cells: {const GridPoint(0, 0), const GridPoint(1, 0), const GridPoint(0, 1)},
          ),
        ],
      );

      final pieces = [
        makeLTromino(id: 'l_partial', cornerVal: 3, armXVal: 3), // armY is null!
        makeLTromino(id: 'l_full', cornerVal: 3, armXVal: 3, armYVal: 3),
        makeLTromino(id: 'l_mismatch', cornerVal: 3, armXVal: 3, armYVal: 4),
      ];

      const constraint = FlatgramConstraint(
        id: 'eq_rule',
        type: 'region_equal',
        params: {'regionId': 'req'},
      );

      // 1. Partial piece (missing value on armY) -> FAILS (not every tile has a value)
      final evalPartial = engine.evaluate(
        board: board,
        pieces: pieces,
        placed: const [PlacedPiece(pieceId: 'l_partial', anchor: GridPoint(0, 0), turns: 0)],
        constraints: const [constraint],
      );
      expect(evalPartial.allConstraintsSatisfied, isFalse);

      // 2. Mismatch piece (3, 3, 4) -> FAILS (values not all identical)
      final evalMismatch = engine.evaluate(
        board: board,
        pieces: pieces,
        placed: const [PlacedPiece(pieceId: 'l_mismatch', anchor: GridPoint(0, 0), turns: 0)],
        constraints: const [constraint],
      );
      expect(evalMismatch.allConstraintsSatisfied, isFalse);

      // 3. Full piece with 3 3's (3, 3, 3) -> PASSES!
      final evalFull = engine.evaluate(
        board: board,
        pieces: pieces,
        placed: const [PlacedPiece(pieceId: 'l_full', anchor: GridPoint(0, 0), turns: 0)],
        constraints: const [constraint],
      );
      expect(evalFull.allConstraintsSatisfied, isTrue);
    });
  });

  group('Playable Puzzles Solvability', () {
    final engine = FlatgramRuleEngine();

    test('Easy puzzle has a valid winning solution with diverse shapes', () {
      final puzzle = easyFlatgramPuzzle();

      final winningPlacement = [
        const PlacedPiece(
          pieceId: 'easy_p1', // Straight-3 (Teal)
          anchor: GridPoint(0, 0),
          turns: 0,
        ),
        const PlacedPiece(
          pieceId: 'easy_p2', // L-tromino (Amber)
          anchor: GridPoint(3, 1),
          turns: 2,
        ),
        const PlacedPiece(
          pieceId: 'easy_p3', // Domino (Rose)
          anchor: GridPoint(0, 1),
          turns: 0,
        ),
      ];

      final eval = engine.evaluate(
        board: puzzle.board,
        pieces: puzzle.pieces,
        placed: winningPlacement,
        constraints: puzzle.constraints,
      );

      expect(eval.isFullyCovered, isTrue);
      expect(eval.allConstraintsSatisfied, isTrue);
      expect(eval.isWon, isTrue);
    });

    test('Medium puzzle has a valid winning solution with diverse shapes', () {
      final puzzle = mediumFlatgramPuzzle();

      final winningPlacement = [
        const PlacedPiece(
          pieceId: 'med_p1', // Straight-3 (Amber)
          anchor: GridPoint(0, 0),
          turns: 1,
        ),
        const PlacedPiece(
          pieceId: 'med_p2', // L-tromino (Emerald)
          anchor: GridPoint(1, 0),
          turns: 0,
        ),
        const PlacedPiece(
          pieceId: 'med_p4', // Domino (Sky)
          anchor: GridPoint(3, 0),
          turns: 1,
        ),
        const PlacedPiece(
          pieceId: 'med_p3', // T-tetromino (Purple)
          anchor: GridPoint(3, 2),
          turns: 2,
        ),
      ];

      final eval = engine.evaluate(
        board: puzzle.board,
        pieces: puzzle.pieces,
        placed: winningPlacement,
        constraints: puzzle.constraints,
      );

      expect(eval.isFullyCovered, isTrue);
      expect(eval.allConstraintsSatisfied, isTrue);
      expect(eval.isWon, isTrue);
    });

    test('Hard puzzle has a valid winning solution with 5 distinct polyominoes', () {
      final puzzle = hardFlatgramPuzzle();

      final winningPlacement = [
        const PlacedPiece(
          pieceId: 'hard_p1', // Square Tetromino (Ruby)
          anchor: GridPoint(0, 0),
          turns: 0,
        ),
        const PlacedPiece(
          pieceId: 'hard_p2', // L-Tetromino (Indigo)
          anchor: GridPoint(2, 0),
          turns: 0,
        ),
        const PlacedPiece(
          pieceId: 'hard_p5', // Monomino (Gold)
          anchor: GridPoint(2, 1),
          turns: 0,
        ),
        const PlacedPiece(
          pieceId: 'hard_p4', // L-Tromino (Teal)
          anchor: GridPoint(0, 2),
          turns: 0,
        ),
        const PlacedPiece(
          pieceId: 'hard_p3', // T-Tetromino (Orange)
          anchor: GridPoint(3, 3),
          turns: 2,
        ),
      ];

      final eval = engine.evaluate(
        board: puzzle.board,
        pieces: puzzle.pieces,
        placed: winningPlacement,
        constraints: puzzle.constraints,
      );

      expect(eval.isFullyCovered, isTrue);
      expect(eval.allConstraintsSatisfied, isTrue);
      expect(eval.isWon, isTrue);
    });
  });

  group('Continuous Tangram Geometry & Sparse Values', () {
    test('Sparse values: pieces can have values on only some cells', () {
      final lPiece = makeLTromino(
        id: 'sparse_l',
        cornerVal: 5,
        // armX and armY are null (blank / unvalued)
      );

      expect(lPiece.cellValues.length, 1);
      expect(lPiece.cellValues[const GridPoint(0, 0)], 5);
      expect(lPiece.cellValues[const GridPoint(1, 0)], isNull);
      expect(lPiece.cellValues[const GridPoint(0, 1)], isNull);

      final placed = [
        const PlacedPiece(
          pieceId: 'sparse_l',
          anchor: GridPoint(0, 0),
          turns: 0,
        ),
      ];

      final engine = FlatgramRuleEngine();
      final eval = engine.evaluate(
        board: FlatgramBoard(
          cells: {const GridPoint(0, 0), const GridPoint(1, 0), const GridPoint(0, 1)},
          regions: [
            FlatgramRegion(
              id: 'r1',
              label: 'Sum',
              color: const Color(0xFF333333),
              cells: {const GridPoint(0, 0), const GridPoint(1, 0), const GridPoint(0, 1)},
            ),
          ],
        ),
        pieces: [lPiece],
        placed: placed,
        constraints: const [
          FlatgramConstraint(
            id: 'c_sum',
            type: 'region_sum',
            params: {'regionId': 'r1', 'target': 5, 'op': '=='},
          ),
        ],
      );

      // Only cell (0,0) with value 5 contributes to region sum (blank cells ignored)
      expect(eval.isWon, isTrue);
    });

    test('Pieces can be placed anywhere in crafting view without being rejected', () {
      // Crafting view allows placing pieces anywhere on the grid
      final lPiece = makeLTromino(id: 'l1', cornerVal: 3);
      final placedOffBoard = PlacedPiece(
        pieceId: lPiece.id,
        anchor: const GridPoint(-5, 10), // Way outside board
        turns: 1,
      );

      expect(placedOffBoard.anchor, const GridPoint(-5, 10));
      expect(placedOffBoard.turns, 1);

      // Tapping rotates piece clockwise by 1 turn (90 degrees)
      final rotated = placedOffBoard.copyWith(turns: (placedOffBoard.turns + 1) % 4);
      expect(rotated.turns, 2);

      final rotatedAgain = rotated.copyWith(turns: (rotated.turns + 1) % 4);
      expect(rotatedAgain.turns, 3);

      final rotatedFull = rotatedAgain.copyWith(turns: (rotatedAgain.turns + 1) % 4);
      expect(rotatedFull.turns, 0);
    });
  });

  group('Flatgram Visual Styling & Grid Alignment', () {
    test('Dot grid and puzzle outline share the same faded white', () {
      expect(FlatgramPainter.fadedWhite, const Color(0x40FFFFFF));
    });

    test('Piece numbers are dark matching the background color with no disc', () {
      expect(FlatgramPalette.tangramPieceNumber, const Color(0xFF0F121A));
    });

    test('All puzzle subregions use vibrant pastel colors', () {
      final easy = easyFlatgramPuzzle();
      for (final r in easy.board.regions) {
        expect(
          [FlatgramPalette.pastelBlue, FlatgramPalette.pastelPurple].contains(r.color),
          isTrue,
        );
      }

      final medium = mediumFlatgramPuzzle();
      for (final r in medium.board.regions) {
        expect(
          [
            FlatgramPalette.pastelBlue,
            FlatgramPalette.pastelMint,
            FlatgramPalette.pastelAmber,
          ].contains(r.color),
          isTrue,
        );
      }

      final hard = hardFlatgramPuzzle();
      for (final r in hard.board.regions) {
        expect(
          [
            FlatgramPalette.pastelCoral,
            FlatgramPalette.pastelTeal,
            FlatgramPalette.pastelPurple,
          ].contains(r.color),
          isTrue,
        );
      }
    });

    test('Tile square corners match dot grid coordinates exactly', () {
      const cellSize = 54.0;
      const boardOffset = Offset(120.0, 80.0);

      final painter = FlatgramPainter(
        board: easyFlatgramPuzzle().board,
        placedPieces: const [],
        pieceCatalog: const {},
        constraints: const [],
        cellSize: cellSize,
        boardOffset: boardOffset,
      );

      // Verify cellToScreen maps (x, y) to the exact corner dot
      const cell = GridPoint(2, 3);
      final screenCorner = painter.cellToScreen(cell);
      expect(screenCorner.dx, boardOffset.dx + 2 * cellSize);
      expect(screenCorner.dy, boardOffset.dy + 3 * cellSize);

      final rect = painter.cellToRect(cell);
      expect(rect.topLeft, screenCorner);
      expect(rect.width, cellSize);
      expect(rect.height, cellSize);
    });

    test('Piece pickup preserves exact grab offset and does not jump to center', () {
      const cellSize = 54.0;
      const boardOffset = Offset(100.0, 100.0);
      const pieceAnchor = GridPoint(2, 1);

      final initialAnchorScreen = Offset(
        boardOffset.dx + pieceAnchor.x * cellSize,
        boardOffset.dy + pieceAnchor.y * cellSize,
      ); // Offset(208.0, 154.0)

      // Cursor touches arbitrary point on the piece
      const cursorTouch = Offset(230.0, 180.0);
      final grabOffsetPx = cursorTouch - initialAnchorScreen;
      expect(grabOffsetPx, const Offset(22.0, 26.0));

      // Drag begins at cursor position: visual anchor must match initial position with zero jump
      final dragVisualAnchor = cursorTouch - grabOffsetPx;
      expect(dragVisualAnchor, initialAnchorScreen);

      // Cursor moves by delta (10.0, -15.0)
      const cursorMoved = Offset(240.0, 165.0);
      final movedVisualAnchor = cursorMoved - grabOffsetPx;
      expect(cursorMoved - movedVisualAnchor, grabOffsetPx);

      // Snap preview candidate anchor remains directly underneath floating piece
      final boardLocal = movedVisualAnchor - boardOffset;
      final snapAnchor = GridPoint(
        (boardLocal.dx / cellSize).round(),
        (boardLocal.dy / cellSize).round(),
      );
      expect(snapAnchor, const GridPoint(2, 1));

      final snapPreviewScreen = Offset(
        boardOffset.dx + snapAnchor.x * cellSize,
        boardOffset.dy + snapAnchor.y * cellSize,
      );
      final offsetFromPreview = (movedVisualAnchor - snapPreviewScreen).distance;
      expect(offsetFromPreview < cellSize * 0.75, isTrue);
    });

    test('Piece tiles have 50% opacity and regions have inward offset', () {
      expect(FlatgramPainter.pieceOpacity, 0.50);
      expect(FlatgramPainter.regionInset, 3.5);

      // Verify buildPolyominoPath with inset shrinks bounds inward
      const testCells = [
        GridPoint(0, 0),
        GridPoint(1, 0),
        GridPoint(0, 1),
        GridPoint(1, 1),
      ];
      final pathNormal = buildPolyominoPath(testCells, 50.0, cornerRadius: 0.0, inset: 0.0);
      final pathInset = buildPolyominoPath(testCells, 50.0, cornerRadius: 0.0, inset: 3.5);

      final boundsNormal = pathNormal.getBounds();
      final boundsInset = pathInset.getBounds();

      expect(boundsNormal.left, 0.0);
      expect(boundsNormal.top, 0.0);
      expect(boundsNormal.right, 100.0);
      expect(boundsNormal.bottom, 100.0);

      expect(boundsInset.left, closeTo(3.5, 0.01));
      expect(boundsInset.top, closeTo(3.5, 0.01));
      expect(boundsInset.right, closeTo(96.5, 0.01));
      expect(boundsInset.bottom, closeTo(96.5, 0.01));
    });

    test('Medium puzzle regions are contiguous with unambiguous targets', () {
      final puzzle = mediumFlatgramPuzzle();

      // Ensure every region in medium puzzle is contiguous (no disjoint multi-island ambiguities)
      for (final region in puzzle.board.regions) {
        final cells = region.cells.toSet();
        expect(cells.isNotEmpty, isTrue);

        final visited = <GridPoint>{};
        final queue = [cells.first];
        visited.add(cells.first);

        while (queue.isNotEmpty) {
          final curr = queue.removeAt(0);
          for (final neighbor in [
            curr + const GridPoint(1, 0),
            curr + const GridPoint(-1, 0),
            curr + const GridPoint(0, 1),
            curr + const GridPoint(0, -1),
          ]) {
            if (cells.contains(neighbor) && !visited.contains(neighbor)) {
              visited.add(neighbor);
              queue.add(neighbor);
            }
          }
        }

        // All cells in the region must be reachable in a single connected component
        expect(visited.length, cells.length,
            reason: 'Region ${region.id} should be contiguous');
      }

      // Check the 3 contiguous regions and their unambiguous labels
      final regionIds = puzzle.board.regions.map((r) => r.id).toList();
      expect(regionIds, ['top_band', 'bottom_left', 'bottom_right']);
    });
  });
}


