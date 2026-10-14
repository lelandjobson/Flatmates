import '../flatgram/flatgram_models.dart';
import 'tilewalk_models.dart';

const _neighbors = <GridPoint>[
  GridPoint(1, 0),
  GridPoint(-1, 0),
  GridPoint(0, 1),
  GridPoint(0, -1),
];

/// Cells covered by placed pieces, optionally ignoring one piece being moved.
Set<GridPoint> coveredCells(TilewalkSession session, {String? ignorePieceId}) {
  final covered = <GridPoint>{};
  for (final placed in session.placed) {
    if (placed.pieceId == ignorePieceId) continue;
    covered.addAll(
      session.piece(placed.pieceId).transformedCells(placed.anchor, placed.turns),
    );
  }
  return covered;
}

/// Floor the cube can reach, not counting [ignorePieceId].
Set<GridPoint> cubeComponent(TilewalkSession session, {String? ignorePieceId}) {
  final covered = coveredCells(session, ignorePieceId: ignorePieceId);
  final reached = <GridPoint>{};
  if (!covered.contains(session.cube)) return reached;
  final queue = <GridPoint>[session.cube];
  while (queue.isNotEmpty) {
    final cell = queue.removeLast();
    if (!reached.add(cell)) continue;
    for (final delta in _neighbors) {
      final next = cell + delta;
      if (covered.contains(next)) queue.add(next);
    }
  }
  return reached;
}

bool isWalkable(TilewalkSession session, GridPoint cell) {
  if (!session.puzzle.cells.contains(cell)) return false;
  return coveredCells(session).contains(cell);
}

bool isBoardComplete(TilewalkSession session) {
  final covered = coveredCells(session);
  if (covered.length != session.puzzle.cells.length) return false;
  for (final cell in session.puzzle.cells) {
    if (!covered.contains(cell)) return false;
  }
  return true;
}

bool showDoor(TilewalkSession session) => isBoardComplete(session);

/// Tray pieces can be placed. A placed piece the cube is standing on cannot.
bool canMoveTile(TilewalkSession session, String pieceId) {
  if (session.won) return false;
  if (session.tray.contains(pieceId)) return true;
  final placed = session.placementOf(pieceId);
  if (placed == null) return false;
  final cells = session
      .piece(pieceId)
      .transformedCells(placed.anchor, placed.turns);
  return !cells.contains(session.cube);
}

/// The piece must lie on the board, avoid other pieces, and touch floor the
/// cube can already reach so a drop cannot strand a tile across a gap.
bool placementFits(
  TilewalkSession session,
  String pieceId,
  GridPoint anchor,
  int turns,
) {
  final cells = session.piece(pieceId).transformedCells(anchor, turns);
  if (cells.isEmpty) return false;
  final unique = cells.toSet();
  if (unique.length != cells.length) return false;

  final occupied = coveredCells(session, ignorePieceId: pieceId);
  for (final cell in cells) {
    if (!session.puzzle.cells.contains(cell)) return false;
    if (occupied.contains(cell)) return false;
  }

  final ground = cubeComponent(session, ignorePieceId: pieceId);
  for (final cell in cells) {
    for (final delta in _neighbors) {
      if (ground.contains(cell + delta)) return true;
    }
  }
  return false;
}

TilewalkSession applyTilewalkCommand(
  TilewalkSession session,
  TilewalkCommand command,
) {
  return switch (command) {
    TilewalkSwipeCommand(:final step) => stepCube(session, step),
    TilewalkRotateCommand(:final pieceId) => rotateTile(session, pieceId),
    TilewalkPlaceCommand(:final pieceId, :final anchor) =>
      placeTile(session, pieceId, anchor),
  };
}

TilewalkSession stepCube(TilewalkSession session, TilewalkStep step) {
  if (session.won) return session;
  final dest = session.cube + step.delta;
  if (!isWalkable(session, dest)) return session;

  var pickups = session.pickups;
  var tray = session.tray;
  var trayTurns = session.trayTurns;
  TilewalkPickup? found;
  for (final pickup in pickups) {
    if (pickup.cell == dest) {
      found = pickup;
      break;
    }
  }
  if (found != null) {
    pickups = [
      for (final pickup in pickups)
        if (pickup.pieceId != found.pieceId) pickup,
    ];
    tray = [...tray, found.pieceId];
    trayTurns = {...trayTurns, found.pieceId: 0};
  }

  return _resolveWin(
    session.copyWith(
      cube: dest,
      pickups: pickups,
      tray: tray,
      trayTurns: trayTurns,
    ),
  );
}

TilewalkSession rotateTile(TilewalkSession session, String pieceId) {
  if (session.won) return session;
  if (session.tray.contains(pieceId)) {
    final turns = (session.orientation(pieceId) + 1) % 4;
    return session.copyWith(
      trayTurns: {...session.trayTurns, pieceId: turns},
    );
  }
  if (!canMoveTile(session, pieceId)) return session;
  final placed = session.placementOf(pieceId);
  if (placed == null) return session;
  final turns = (placed.turns + 1) % 4;
  if (!placementFits(session, pieceId, placed.anchor, turns)) return session;
  return _resolveWin(
    session.copyWith(
      placed: [
        for (final item in session.placed)
          if (item.pieceId == pieceId) item.copyWith(turns: turns) else item,
      ],
    ),
  );
}

TilewalkSession placeTile(
  TilewalkSession session,
  String pieceId,
  GridPoint anchor,
) {
  if (!canMoveTile(session, pieceId)) return session;
  final turns = session.orientation(pieceId);
  if (!placementFits(session, pieceId, anchor, turns)) return session;
  return _resolveWin(
    session.copyWith(
      placed: [
        for (final item in session.placed)
          if (item.pieceId != pieceId) item,
        PlacedPiece(pieceId: pieceId, anchor: anchor, turns: turns),
      ],
      tray: [for (final id in session.tray) if (id != pieceId) id],
      trayTurns: {
        for (final entry in session.trayTurns.entries)
          if (entry.key != pieceId) entry.key: entry.value,
      },
    ),
  );
}

TilewalkSession _resolveWin(TilewalkSession session) {
  if (session.won) return session;
  if (isBoardComplete(session) && session.cube == session.puzzle.exitCell) {
    return session.copyWith(won: true);
  }
  return session;
}
