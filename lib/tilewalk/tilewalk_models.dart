import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../flatgram/flatgram_models.dart';

/// One cell of a swipe. Grid Y grows downward, matching the tangram board.
enum TilewalkStep {
  left(GridPoint(-1, 0)),
  right(GridPoint(1, 0)),
  up(GridPoint(0, -1)),
  down(GridPoint(0, 1));

  const TilewalkStep(this.delta);
  final GridPoint delta;
}

/// A piece waiting on the board. The cube collects it by stepping on [cell].
@immutable
class TilewalkPickup {
  const TilewalkPickup({required this.pieceId, required this.cell});

  final String pieceId;
  final GridPoint cell;

  @override
  String toString() => 'Pickup($pieceId @ $cell)';
}

/// A full Tilewalk puzzle: the floor to fill, the pieces, and a known solution.
@immutable
class TilewalkPuzzle {
  TilewalkPuzzle({
    required this.id,
    required this.title,
    required this.difficulty,
    required this.cells,
    required this.exitCell,
    required this.startCell,
    required this.pieces,
    required this.initialPlaced,
    required this.initialTray,
    required this.pickups,
    required this.solution,
    this.description = '',
  }) : byId = {for (final piece in pieces) piece.id: piece};

  final String id;
  final String title;
  final String difficulty;
  final Set<GridPoint> cells;
  final GridPoint exitCell;
  final GridPoint startCell;
  final List<FlatgramPiece> pieces;
  final Map<String, FlatgramPiece> byId;
  final List<PlacedPiece> initialPlaced;
  final List<String> initialTray;
  final List<TilewalkPickup> pickups;
  final List<TilewalkCommand> solution;
  final String description;

  Rect get bounds {
    if (cells.isEmpty) return Rect.zero;
    var minX = cells.first.x;
    var maxX = minX;
    var minY = cells.first.y;
    var maxY = minY;
    for (final cell in cells) {
      if (cell.x < minX) minX = cell.x;
      if (cell.x > maxX) maxX = cell.x;
      if (cell.y < minY) minY = cell.y;
      if (cell.y > maxY) maxY = cell.y;
    }
    return Rect.fromLTRB(
      minX.toDouble(),
      minY.toDouble(),
      (maxX + 1).toDouble(),
      (maxY + 1).toDouble(),
    );
  }
}

/// Live play state. Rules return a new session instead of mutating this one.
@immutable
class TilewalkSession {
  const TilewalkSession({
    required this.puzzle,
    required this.placed,
    required this.tray,
    required this.trayTurns,
    required this.pickups,
    required this.cube,
    required this.won,
  });

  factory TilewalkSession.start(TilewalkPuzzle puzzle) {
    return TilewalkSession(
      puzzle: puzzle,
      placed: List<PlacedPiece>.of(puzzle.initialPlaced),
      tray: List<String>.of(puzzle.initialTray),
      trayTurns: {for (final id in puzzle.initialTray) id: 0},
      pickups: List<TilewalkPickup>.of(puzzle.pickups),
      cube: puzzle.startCell,
      won: false,
    );
  }

  final TilewalkPuzzle puzzle;
  final List<PlacedPiece> placed;
  final List<String> tray;
  final Map<String, int> trayTurns;
  final List<TilewalkPickup> pickups;
  final GridPoint cube;
  final bool won;

  FlatgramPiece piece(String id) => puzzle.byId[id]!;

  PlacedPiece? placementOf(String pieceId) {
    for (final placed in this.placed) {
      if (placed.pieceId == pieceId) return placed;
    }
    return null;
  }

  /// Quarter turns currently shown for a tray piece or a placed piece.
  int orientation(String pieceId) {
    final trayTurn = trayTurns[pieceId];
    if (trayTurn != null) return trayTurn;
    return placementOf(pieceId)?.turns ?? 0;
  }

  TilewalkSession copyWith({
    List<PlacedPiece>? placed,
    List<String>? tray,
    Map<String, int>? trayTurns,
    List<TilewalkPickup>? pickups,
    GridPoint? cube,
    bool? won,
  }) {
    return TilewalkSession(
      puzzle: puzzle,
      placed: placed ?? this.placed,
      tray: tray ?? this.tray,
      trayTurns: trayTurns ?? this.trayTurns,
      pickups: pickups ?? this.pickups,
      cube: cube ?? this.cube,
      won: won ?? this.won,
    );
  }
}

/// One move in a scripted solution.
sealed class TilewalkCommand {
  const TilewalkCommand();
}

class TilewalkSwipeCommand extends TilewalkCommand {
  const TilewalkSwipeCommand(this.step);
  final TilewalkStep step;

  @override
  String toString() => 'Swipe(${step.name})';
}

class TilewalkRotateCommand extends TilewalkCommand {
  const TilewalkRotateCommand(this.pieceId);
  final String pieceId;

  @override
  String toString() => 'Rotate($pieceId)';
}

class TilewalkPlaceCommand extends TilewalkCommand {
  const TilewalkPlaceCommand(this.pieceId, this.anchor);
  final String pieceId;
  final GridPoint anchor;

  @override
  String toString() => 'Place($pieceId @ $anchor)';
}
