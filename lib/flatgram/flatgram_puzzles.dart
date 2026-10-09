import 'dart:ui';

import 'flatgram_constraints.dart';
import 'flatgram_models.dart';

/// Palette with distinct, vibrant colors for tangram tiles and markers.
class FlatgramPalette {
  /// Default uniform material color for continuous tangram pieces (matte porcelain/bone).
  static const Color tangramPiece = Color(0xFFE2E8F0);
  static const Color tangramPieceNumber = Color(0xFF0F121A);

  // Vibrant pastel palette for subregions & indicators that pop against dark backgrounds:
  static const Color pastelBlue = Color(0xFF93C5FD); // Soft luminous sky blue
  static const Color pastelPurple = Color(0xFFD8B4FE); // Soft luminous lavender
  static const Color pastelMint = Color(0xFF86EFAC); // Soft luminous mint green
  static const Color pastelCoral = Color(0xFFFCA5A5); // Soft luminous coral rose
  static const Color pastelAmber = Color(0xFFFDE047); // Soft luminous warm yellow
  static const Color pastelTeal = Color(0xFF5EEAD4); // Soft luminous seafoam/teal
  static const Color pastelOrange = Color(0xFFFDBA74); // Soft luminous peach / apricot
  static const Color pastelPink = Color(0xFFF9A8D4); // Soft luminous rose pink

  static const Color rose = Color(0xFFE91E63);
  static const Color teal = Color(0xFF00ACC1);
  static const Color amber = Color(0xFFFFB300);
  static const Color purple = Color(0xFF8E24AA);
  static const Color emerald = Color(0xFF43A047);
  static const Color sky = Color(0xFF29B6F6);
  static const Color orange = Color(0xFFFB8C00);
  static const Color ruby = Color(0xFFD32F2F);
  static const Color indigo = Color(0xFF3949AB);
  static const Color gold = Color(0xFFFFD54F);

  // Backward compatibility
  static const Color pink = rose;
  static const Color olive = emerald;
  static const Color navy = indigo;

  static const Color dominoBone = Color(0xFFF9F7F1);
  static const Color dominoLine = Color(0xFF333333);
}

// ---------------------------------------------------------------------------
// Standard Piece Shape Constructors
// ---------------------------------------------------------------------------

/// 1-cell Monomino square.
FlatgramPiece makeMonomino({
  required String id,
  int? value,
  Color? color,
}) {
  final tileColor = color ?? FlatgramPalette.tangramPiece;
  return FlatgramPiece(
    id: id,
    cells: const [GridPoint(0, 0)],
    cellValues: {
      const GridPoint(0, 0): ?value,
    },
    cellColors: {const GridPoint(0, 0): tileColor},
    defaultColor: tileColor,
  );
}

/// 2-cell Domino tile (1x2). Values are optional per cell.
FlatgramPiece makeDomino({
  required String id,
  int? valA,
  int? valB,
  Color? color,
  Map<GridPoint, int> vertexValues = const {},
}) {
  final tileColor = color ?? FlatgramPalette.tangramPiece;
  return FlatgramPiece(
    id: id,
    cells: const [GridPoint(0, 0), GridPoint(1, 0)],
    cellValues: {
      const GridPoint(0, 0): ?valA,
      const GridPoint(1, 0): ?valB,
    },
    cellColors: {
      const GridPoint(0, 0): tileColor,
      const GridPoint(1, 0): tileColor,
    },
    defaultColor: tileColor,
    vertexValues: vertexValues,
  );
}

/// 3-cell L-Tromino: corner at (0,0), arm along X to (1,0), arm along Y to (0,1).
FlatgramPiece makeLTromino({
  required String id,
  int? cornerVal,
  int? armXVal,
  int? armYVal,
  Color? color,
}) {
  final tileColor = color ?? FlatgramPalette.tangramPiece;
  return FlatgramPiece(
    id: id,
    cells: const [GridPoint(0, 0), GridPoint(1, 0), GridPoint(0, 1)],
    cellValues: {
      const GridPoint(0, 0): ?cornerVal,
      const GridPoint(1, 0): ?armXVal,
      const GridPoint(0, 1): ?armYVal,
    },
    cellColors: {
      const GridPoint(0, 0): tileColor,
      const GridPoint(1, 0): tileColor,
      const GridPoint(0, 1): tileColor,
    },
    defaultColor: tileColor,
  );
}

/// 3-cell Straight Triomino: (0,0), (1,0), (2,0).
FlatgramPiece makeStraightTriomino({
  required String id,
  int? valA,
  int? valB,
  int? valC,
  Color? color,
}) {
  final tileColor = color ?? FlatgramPalette.tangramPiece;
  return FlatgramPiece(
    id: id,
    cells: const [GridPoint(0, 0), GridPoint(1, 0), GridPoint(2, 0)],
    cellValues: {
      const GridPoint(0, 0): ?valA,
      const GridPoint(1, 0): ?valB,
      const GridPoint(2, 0): ?valC,
    },
    cellColors: {
      const GridPoint(0, 0): tileColor,
      const GridPoint(1, 0): tileColor,
      const GridPoint(2, 0): tileColor,
    },
    defaultColor: tileColor,
  );
}

/// 4-cell Square / O-Tetromino: 2x2 square.
FlatgramPiece makeSquareTetromino({
  required String id,
  int? valTL,
  int? valTR,
  int? valBL,
  int? valBR,
  Color? color,
}) {
  final tileColor = color ?? FlatgramPalette.tangramPiece;
  return FlatgramPiece(
    id: id,
    cells: const [
      GridPoint(0, 0),
      GridPoint(1, 0),
      GridPoint(0, 1),
      GridPoint(1, 1),
    ],
    cellValues: {
      const GridPoint(0, 0): ?valTL,
      const GridPoint(1, 0): ?valTR,
      const GridPoint(0, 1): ?valBL,
      const GridPoint(1, 1): ?valBR,
    },
    cellColors: {
      const GridPoint(0, 0): tileColor,
      const GridPoint(1, 0): tileColor,
      const GridPoint(0, 1): tileColor,
      const GridPoint(1, 1): tileColor,
    },
    defaultColor: tileColor,
  );
}

/// 4-cell T-Tetromino: bar at (0,0), (1,0), (2,0) with center stem down at (1,1).
FlatgramPiece makeTTetromino({
  required String id,
  int? barLeftVal,
  int? barCenterVal,
  int? barRightVal,
  int? stemVal,
  Color? color,
}) {
  final tileColor = color ?? FlatgramPalette.tangramPiece;
  return FlatgramPiece(
    id: id,
    cells: const [
      GridPoint(0, 0),
      GridPoint(1, 0),
      GridPoint(2, 0),
      GridPoint(1, 1),
    ],
    cellValues: {
      const GridPoint(0, 0): ?barLeftVal,
      const GridPoint(1, 0): ?barCenterVal,
      const GridPoint(2, 0): ?barRightVal,
      const GridPoint(1, 1): ?stemVal,
    },
    cellColors: {
      const GridPoint(0, 0): tileColor,
      const GridPoint(1, 0): tileColor,
      const GridPoint(2, 0): tileColor,
      const GridPoint(1, 1): tileColor,
    },
    defaultColor: tileColor,
  );
}

/// 4-cell L-Tetromino: (0,0), (1,0), (1,1), (1,2).
FlatgramPiece makeLTetromino({
  required String id,
  int? shortEndVal,
  int? cornerVal,
  int? midLongVal,
  int? endLongVal,
  Color? color,
}) {
  final tileColor = color ?? FlatgramPalette.tangramPiece;
  return FlatgramPiece(
    id: id,
    cells: const [
      GridPoint(0, 0),
      GridPoint(1, 0),
      GridPoint(1, 1),
      GridPoint(1, 2),
    ],
    cellValues: {
      const GridPoint(0, 0): ?shortEndVal,
      const GridPoint(1, 0): ?cornerVal,
      const GridPoint(1, 1): ?midLongVal,
      const GridPoint(1, 2): ?endLongVal,
    },
    cellColors: {
      const GridPoint(0, 0): tileColor,
      const GridPoint(1, 0): tileColor,
      const GridPoint(1, 1): tileColor,
      const GridPoint(1, 2): tileColor,
    },
    defaultColor: tileColor,
  );
}

// ---------------------------------------------------------------------------
// 1. Easy Puzzle: "Tetra & Duo"
// ---------------------------------------------------------------------------

/// Easy puzzle: 8 cells (2x4 rectangle).
/// Continuous tangram pieces: Straight-3, L-tromino, Domino.
/// Notice: Pieces only have values on selective cells!
FlatgramPuzzle easyFlatgramPuzzle() {
  final leftCells = {
    const GridPoint(0, 0),
    const GridPoint(1, 0),
    const GridPoint(2, 0),
    const GridPoint(0, 1),
    const GridPoint(1, 1),
  };

  final rightCells = {
    const GridPoint(3, 0),
    const GridPoint(2, 1),
    const GridPoint(3, 1),
  };

  final allCells = {...leftCells, ...rightCells};

  final board = FlatgramBoard(
    cells: allCells,
    regions: [
      FlatgramRegion(
        id: 'left',
        label: 'West',
        color: FlatgramPalette.pastelBlue,
        cells: leftCells,
        badgeLabel: '7',
        badgeColor: FlatgramPalette.pastelBlue,
        badgePosition: const GridPoint(1, -1),
      ),
      FlatgramRegion(
        id: 'right',
        label: 'East',
        color: FlatgramPalette.pastelPurple,
        cells: rightCells,
        badgeLabel: '=',
        badgeColor: FlatgramPalette.pastelPurple,
        badgePosition: const GridPoint(3, -1),
      ),
    ],
  );

  final pieces = [
    // P1: Straight Triomino - only center has value 5
    makeStraightTriomino(
      id: 'easy_p1',
      valB: 5,
    ),
    // P2: L-Tromino - all 3 tiles have value 3 (satisfies East '=' equality)
    makeLTromino(
      id: 'easy_p2',
      cornerVal: 3,
      armXVal: 3,
      armYVal: 3,
    ),
    // P3: Domino - one cell has 2, other cell is clean
    makeDomino(
      id: 'easy_p3',
      valA: 2,
    ),
  ];

  final constraints = [
    const FlatgramConstraint(
      id: 'easy_left_sum',
      type: 'region_sum',
      params: {'regionId': 'left', 'target': 7, 'op': '=='},
      badgeLabel: '7',
      badgeColor: FlatgramPalette.pastelBlue,
      badgeAnchor: Offset(0.5, -0.3),
      description: 'Sum of numbers in West region must equal 7',
    ),
    const FlatgramConstraint(
      id: 'easy_right_equal',
      type: 'region_equal',
      params: {'regionId': 'right'},
      badgeLabel: '=',
      badgeColor: FlatgramPalette.pastelPurple,
      badgeAnchor: Offset(2.5, -0.3),
      description: 'All tiles in East region must have equal values',
    ),
  ];

  return FlatgramPuzzle(
    id: 'easy_twin_regions',
    title: 'Tetra & Duo',
    difficulty: 'easy',
    board: board,
    pieces: pieces,
    constraints: constraints,
    description:
        'Fit the Straight-3, L-tromino, and Domino into the grid to satisfy the West sum (7) and East equality.',
  );
}

// ---------------------------------------------------------------------------
// 2. Medium Puzzle: "Polyomino Step"
// ---------------------------------------------------------------------------

/// Medium puzzle: 12 cells (3x4 rectangle).
/// Shapes: T-tetromino, Straight-3, L-tromino, Domino.
FlatgramPuzzle mediumFlatgramPuzzle() {
  final topBandCells = {
    const GridPoint(0, 0),
    const GridPoint(1, 0),
    const GridPoint(2, 0),
    const GridPoint(3, 0),
  };

  final bottomLeftCells = {
    const GridPoint(0, 1),
    const GridPoint(1, 1),
    const GridPoint(0, 2),
    const GridPoint(1, 2),
  };

  final bottomRightCells = {
    const GridPoint(2, 1),
    const GridPoint(3, 1),
    const GridPoint(2, 2),
    const GridPoint(3, 2),
  };

  final allCells = {...topBandCells, ...bottomLeftCells, ...bottomRightCells};

  final board = FlatgramBoard(
    cells: allCells,
    regions: [
      FlatgramRegion(
        id: 'top_band',
        label: 'Top Row',
        color: FlatgramPalette.pastelAmber,
        cells: topBandCells,
        badgeLabel: '11',
        badgeColor: FlatgramPalette.pastelAmber,
      ),
      FlatgramRegion(
        id: 'bottom_left',
        label: 'South-West',
        color: FlatgramPalette.pastelBlue,
        cells: bottomLeftCells,
        badgeLabel: '5',
        badgeColor: FlatgramPalette.pastelBlue,
      ),
      FlatgramRegion(
        id: 'bottom_right',
        label: 'South-East',
        color: FlatgramPalette.pastelMint,
        cells: bottomRightCells,
        badgeLabel: '=',
        badgeColor: FlatgramPalette.pastelMint,
      ),
    ],
  );

  final pieces = [
    // P1: Straight Triomino - one end has 5
    makeStraightTriomino(
      id: 'med_p1',
      valC: 5,
    ),
    // P2: L-Tromino - corner and arm have 4
    makeLTromino(
      id: 'med_p2',
      cornerVal: 4,
      armXVal: 4,
    ),
    // P3: T-Tetromino - barLeft, center and stem have 4
    makeTTetromino(
      id: 'med_p3',
      barLeftVal: 4,
      barCenterVal: 4,
      stemVal: 4,
    ),
    // P4: Domino - valA is 3, valB is 4
    makeDomino(
      id: 'med_p4',
      valA: 3,
      valB: 4,
    ),
  ];

  final constraints = [
    const FlatgramConstraint(
      id: 'med_top_sum',
      type: 'region_sum',
      params: {'regionId': 'top_band', 'target': 11, 'op': '=='},
      badgeLabel: '11',
      badgeColor: FlatgramPalette.pastelAmber,
      badgeAnchor: Offset(1.5, -0.3),
      description: 'Sum of numbers in top row must equal 11',
    ),
    const FlatgramConstraint(
      id: 'med_bottom_left_sum',
      type: 'region_sum',
      params: {'regionId': 'bottom_left', 'target': 5, 'op': '=='},
      badgeLabel: '5',
      badgeColor: FlatgramPalette.pastelBlue,
      badgeAnchor: Offset(0.5, 2.8),
      description: 'Sum of numbers in South-West must equal 5',
    ),
    const FlatgramConstraint(
      id: 'med_bottom_right_equal',
      type: 'region_equal',
      params: {'regionId': 'bottom_right'},
      badgeLabel: '=',
      badgeColor: FlatgramPalette.pastelMint,
      badgeAnchor: Offset(2.5, 2.8),
      description: 'All numbers in South-East must be equal',
    ),
    const FlatgramConstraint(
      id: 'med_vertex_center',
      type: 'vertex_sum',
      params: {'vertex': [2, 2], 'target': 8, 'op': '=='},
      badgeLabel: '8',
      badgeColor: FlatgramPalette.pastelPurple,
      badgeAnchor: Offset(2.0, 2.0),
      description: 'Touching numbers at intersection (2, 2) must sum to 8',
    ),
  ];

  return FlatgramPuzzle(
    id: 'medium_staircase_ring',
    title: 'Polyomino Step',
    difficulty: 'medium',
    board: board,
    pieces: pieces,
    constraints: constraints,
    description:
        'Tile the 3x4 board with T-tetromino, Straight-3, L-tromino, and Domino while matching sums, equality, and vertex value.',
  );
}

// ---------------------------------------------------------------------------
// 3. Hard Puzzle: "The Tangram Monolith"
// ---------------------------------------------------------------------------

/// Hard puzzle: 16 cells (4x4 square).
/// Continuous shapes: Square, L-tetromino, T-tetromino, L-tromino, Monomino.
FlatgramPuzzle hardFlatgramPuzzle() {
  final topBandCells = {
    const GridPoint(0, 0),
    const GridPoint(1, 0),
    const GridPoint(2, 0),
    const GridPoint(3, 0),
    const GridPoint(0, 1),
    const GridPoint(3, 1),
  };

  final bottomQuadCells = {
    const GridPoint(0, 3),
    const GridPoint(1, 3),
    const GridPoint(2, 3),
    const GridPoint(3, 3),
  };

  final centerCoreCells = {
    const GridPoint(1, 1),
    const GridPoint(2, 1),
    const GridPoint(1, 2),
    const GridPoint(2, 2),
  };

  final flankCells = {
    const GridPoint(0, 2),
    const GridPoint(3, 2),
  };

  final allCells = {
    ...topBandCells,
    ...bottomQuadCells,
    ...centerCoreCells,
    ...flankCells,
  };

  final board = FlatgramBoard(
    cells: allCells,
    regions: [
      FlatgramRegion(
        id: 'top_band',
        label: 'Crown',
        color: FlatgramPalette.pastelCoral,
        cells: topBandCells,
        badgeLabel: '12',
        badgeColor: FlatgramPalette.pastelCoral,
      ),
      FlatgramRegion(
        id: 'bottom_quad',
        label: 'Base',
        color: FlatgramPalette.pastelPurple,
        cells: bottomQuadCells,
        badgeLabel: '5',
        badgeColor: FlatgramPalette.pastelPurple,
      ),
      FlatgramRegion(
        id: 'center_core',
        label: 'Core',
        color: FlatgramPalette.pastelTeal,
        cells: centerCoreCells,
        badgeLabel: '4',
        badgeColor: FlatgramPalette.pastelTeal,
      ),
    ],
  );

  final pieces = [
    // P1: 2x2 Square Tetromino - TL has 5, TR has 4
    makeSquareTetromino(
      id: 'hard_p1',
      valTL: 5,
      valTR: 4,
    ),
    // P2: L-Tetromino - corner has 3, end has 2
    makeLTetromino(
      id: 'hard_p2',
      cornerVal: 3,
      endLongVal: 2,
    ),
    // P3: T-Tetromino - center has 5, stem has 1
    makeTTetromino(
      id: 'hard_p3',
      barCenterVal: 5,
      stemVal: 1,
    ),
    // P4: L-Tromino - corner has 4
    makeLTromino(
      id: 'hard_p4',
      cornerVal: 4,
    ),
    // P5: Monomino - value 3
    makeMonomino(
      id: 'hard_p5',
      value: 3,
    ),
  ];

  final constraints = [
    const FlatgramConstraint(
      id: 'hard_top_sum',
      type: 'region_sum',
      params: {'regionId': 'top_band', 'target': 12, 'op': '=='},
      badgeLabel: '12',
      badgeColor: FlatgramPalette.pastelCoral,
      badgeAnchor: Offset(1.5, -0.3),
      description: 'Sum of numbers in Crown must equal 12',
    ),
    const FlatgramConstraint(
      id: 'hard_bottom_sum',
      type: 'region_sum',
      params: {'regionId': 'bottom_quad', 'target': 5, 'op': '=='},
      badgeLabel: '5',
      badgeColor: FlatgramPalette.pastelPurple,
      badgeAnchor: Offset(1.5, 3.8),
      description: 'Sum of numbers in Base must equal 5',
    ),
    const FlatgramConstraint(
      id: 'hard_center_sum',
      type: 'region_sum',
      params: {'regionId': 'center_core', 'target': 4, 'op': '=='},
      badgeLabel: '4',
      badgeColor: FlatgramPalette.pastelTeal,
      badgeAnchor: Offset(1.5, 1.5),
      description: 'Sum of numbers in Core must equal 4',
    ),
    const FlatgramConstraint(
      id: 'hard_vertex_center',
      type: 'vertex_sum',
      params: {'vertex': [2, 2], 'target': 4, 'op': '=='},
      badgeLabel: '4',
      badgeColor: FlatgramPalette.pastelAmber,
      badgeAnchor: Offset(2.0, 2.0),
      description: 'Touching numbers at intersection (2, 2) must sum to 4',
    ),
  ];

  return FlatgramPuzzle(
    id: 'hard_hollow_monolith',
    title: 'Tangram Monolith',
    difficulty: 'hard',
    board: board,
    pieces: pieces,
    constraints: constraints,
    description:
        'Pack 5 distinct continuous tangram shapes (Square, L-tetromino, T-tetromino, L-tromino, and Monomino) into the 4x4 board.',
  );
}

/// Catalog of all playable flatgram puzzles.
final List<FlatgramPuzzle> kFlatgramPuzzles = [
  easyFlatgramPuzzle(),
  mediumFlatgramPuzzle(),
  hardFlatgramPuzzle(),
];
