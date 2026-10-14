import '../flatgram/flatgram_models.dart';
import '../flatgram/flatgram_puzzles.dart';
import 'tilewalk_models.dart';

/// Easy, medium, and hard Tilewalk boards.
///
/// Each [TilewalkPuzzle.solution] is a winning line: swipes, tray rotations,
/// and placements. The cube only walks on tiles, so a gap has to be filled
/// before a later pickup can be reached.
final List<TilewalkPuzzle> kTilewalkPuzzles = [
  easyTilewalkPuzzle(),
  mediumTilewalkPuzzle(),
  hardTilewalkPuzzle(),
];

/// 3×2 floor. A domino is already down. Step onto it to pick up a square,
/// then turn the L twice and close the board. The door is the far end of the L.
TilewalkPuzzle easyTilewalkPuzzle() {
  const exit = GridPoint(2, 0);
  return TilewalkPuzzle(
    id: 'tilewalk_easy',
    title: 'First Steps',
    difficulty: 'easy',
    description: 'Step onto the mark, then fill the rest of the floor.',
    cells: {
      const GridPoint(0, 0),
      const GridPoint(1, 0),
      const GridPoint(2, 0),
      const GridPoint(0, 1),
      const GridPoint(1, 1),
      const GridPoint(2, 1),
    },
    exitCell: exit,
    startCell: const GridPoint(0, 0),
    pieces: [
      makeDomino(id: 'easy_start', color: FlatgramPalette.pastelTeal),
      makeLTromino(id: 'easy_l', color: FlatgramPalette.pastelAmber),
      makeMonomino(id: 'easy_dot', color: FlatgramPalette.pastelMint),
    ],
    initialPlaced: const [
      PlacedPiece(pieceId: 'easy_start', anchor: GridPoint(0, 0)),
    ],
    initialTray: const ['easy_l'],
    pickups: const [
      TilewalkPickup(pieceId: 'easy_dot', cell: GridPoint(1, 0)),
    ],
    solution: const [
      TilewalkSwipeCommand(TilewalkStep.right),
      TilewalkRotateCommand('easy_l'),
      TilewalkRotateCommand('easy_l'),
      TilewalkPlaceCommand('easy_l', GridPoint(2, 1)),
      TilewalkPlaceCommand('easy_dot', GridPoint(0, 1)),
      TilewalkSwipeCommand(TilewalkStep.right),
    ],
  );
}

/// A notch floor. The L only bridges the gap after one quarter turn.
/// The monomino on the far tile is collected afterwards and caps the end.
TilewalkPuzzle mediumTilewalkPuzzle() {
  return TilewalkPuzzle(
    id: 'tilewalk_medium',
    title: 'The Gap',
    difficulty: 'medium',
    description: 'Turn the piece so it reaches the mark across the gap.',
    cells: {
      const GridPoint(0, 0),
      const GridPoint(1, 0),
      const GridPoint(2, 0),
      const GridPoint(3, 0),
      const GridPoint(2, 1),
      const GridPoint(3, 1),
    },
    exitCell: const GridPoint(3, 0),
    startCell: const GridPoint(0, 0),
    pieces: [
      makeMonomino(id: 'med_start', color: FlatgramPalette.pastelTeal),
      makeMonomino(id: 'med_island', color: FlatgramPalette.pastelCoral),
      makeLTromino(id: 'med_l', color: FlatgramPalette.pastelAmber),
      makeMonomino(id: 'med_cap', color: FlatgramPalette.pastelMint),
    ],
    initialPlaced: const [
      PlacedPiece(pieceId: 'med_start', anchor: GridPoint(0, 0)),
      PlacedPiece(pieceId: 'med_island', anchor: GridPoint(3, 1)),
    ],
    initialTray: const ['med_l'],
    pickups: const [
      TilewalkPickup(pieceId: 'med_cap', cell: GridPoint(3, 1)),
    ],
    solution: const [
      TilewalkRotateCommand('med_l'),
      TilewalkPlaceCommand('med_l', GridPoint(2, 0)),
      TilewalkSwipeCommand(TilewalkStep.right),
      TilewalkSwipeCommand(TilewalkStep.right),
      TilewalkSwipeCommand(TilewalkStep.down),
      TilewalkSwipeCommand(TilewalkStep.right),
      TilewalkPlaceCommand('med_cap', GridPoint(3, 0)),
      TilewalkSwipeCommand(TilewalkStep.up),
    ],
  );
}

/// 3×3 floor. The cube begins on a tile that cannot be moved. The L on the
/// road has to be collected and placed before the domino on the far corner
/// can be reached.
TilewalkPuzzle hardTilewalkPuzzle() {
  return TilewalkPuzzle(
    id: 'tilewalk_hard',
    title: 'Two Marks',
    difficulty: 'hard',
    description: 'Gather the pieces in path order. The tile under you stays.',
    cells: {
      const GridPoint(0, 0),
      const GridPoint(1, 0),
      const GridPoint(2, 0),
      const GridPoint(0, 1),
      const GridPoint(1, 1),
      const GridPoint(2, 1),
      const GridPoint(0, 2),
      const GridPoint(1, 2),
      const GridPoint(2, 2),
    },
    exitCell: const GridPoint(0, 2),
    startCell: const GridPoint(0, 0),
    pieces: [
      makeMonomino(id: 'hard_start', color: FlatgramPalette.pastelTeal),
      makeDomino(id: 'hard_road', color: FlatgramPalette.pastelBlue),
      makeMonomino(id: 'hard_island', color: FlatgramPalette.pastelCoral),
      makeLTromino(id: 'hard_l', color: FlatgramPalette.pastelAmber),
      makeDomino(id: 'hard_d', color: FlatgramPalette.pastelPurple),
    ],
    initialPlaced: const [
      PlacedPiece(pieceId: 'hard_start', anchor: GridPoint(0, 0)),
      PlacedPiece(pieceId: 'hard_road', anchor: GridPoint(1, 0)),
      PlacedPiece(pieceId: 'hard_island', anchor: GridPoint(2, 2)),
    ],
    initialTray: const [],
    pickups: const [
      TilewalkPickup(pieceId: 'hard_l', cell: GridPoint(2, 0)),
      TilewalkPickup(pieceId: 'hard_d', cell: GridPoint(2, 2)),
    ],
    solution: const [
      TilewalkSwipeCommand(TilewalkStep.right),
      TilewalkSwipeCommand(TilewalkStep.right),
      TilewalkPlaceCommand('hard_l', GridPoint(1, 1)),
      TilewalkSwipeCommand(TilewalkStep.down),
      TilewalkSwipeCommand(TilewalkStep.down),
      TilewalkRotateCommand('hard_d'),
      TilewalkPlaceCommand('hard_d', GridPoint(0, 1)),
      TilewalkSwipeCommand(TilewalkStep.left),
      TilewalkSwipeCommand(TilewalkStep.left),
    ],
  );
}
