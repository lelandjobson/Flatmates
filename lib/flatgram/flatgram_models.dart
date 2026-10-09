import 'dart:ui';
import 'package:flutter/foundation.dart';

import 'flatgram_constraints.dart';

/// 2D integer coordinate representing a cell or a vertex on the grid.
@immutable
class GridPoint implements Comparable<GridPoint> {
  const GridPoint(this.x, this.y);

  final int x;
  final int y;

  static const zero = GridPoint(0, 0);

  GridPoint operator +(GridPoint other) => GridPoint(x + other.x, y + other.y);
  GridPoint operator -(GridPoint other) => GridPoint(x - other.x, y - other.y);

  /// Rotates clockwise in screen space (X right, Y down).
  /// [turns] is quarter turns (0, 1, 2, 3).
  GridPoint rotateClockwise(int turns) {
    final t = ((turns % 4) + 4) % 4;
    return switch (t) {
      0 => this,
      1 => GridPoint(-y, x),
      2 => GridPoint(-x, -y),
      3 => GridPoint(y, -x),
      _ => this,
    };
  }

  Offset toOffset([double scale = 1.0]) => Offset(x * scale, y * scale);

  @override
  int compareTo(GridPoint other) {
    if (x != other.x) return x.compareTo(other.x);
    return y.compareTo(other.y);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GridPoint &&
          runtimeType == other.runtimeType &&
          x == other.x &&
          y == other.y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x, $y)';

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  factory GridPoint.fromJson(Map<String, dynamic> json) =>
      GridPoint((json['x'] as num).toInt(), (json['y'] as num).toInt());
}

/// Canonical undirected grid edge between two grid vertices.
@immutable
class GridEdgeKey {
  GridEdgeKey(GridPoint p1, GridPoint p2)
      : a = p1.compareTo(p2) <= 0 ? p1 : p2,
        b = p1.compareTo(p2) <= 0 ? p2 : p1;

  final GridPoint a;
  final GridPoint b;

  GridEdgeKey transformed(GridPoint anchor, int turns) {
    final tA = anchor + a.rotateClockwise(turns);
    final tB = anchor + b.rotateClockwise(turns);
    return GridEdgeKey(tA, tB);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GridEdgeKey &&
          runtimeType == other.runtimeType &&
          a == other.a &&
          b == other.b;

  @override
  int get hashCode => Object.hash(a, b);

  @override
  String toString() => 'Edge($a <-> $b)';
}

/// A subregion of the puzzle board with its own tint and constraints.
class FlatgramRegion {
  const FlatgramRegion({
    required this.id,
    required this.label,
    required this.color,
    required this.cells,
    this.badgeLabel,
    this.badgeColor,
    this.badgePosition,
  });

  final String id;
  final String label;
  final Color color;
  final Set<GridPoint> cells;

  /// Optional display badge label (e.g. "11", "=", ">10")
  final String? badgeLabel;
  final Color? badgeColor;
  final GridPoint? badgePosition;

  bool contains(GridPoint cell) => cells.contains(cell);
}

/// The outer shape of the puzzle and its subregions.
class FlatgramBoard {
  const FlatgramBoard({
    required this.cells,
    required this.regions,
  });

  final Set<GridPoint> cells;
  final List<FlatgramRegion> regions;

  int get cellCount => cells.length;

  bool contains(GridPoint cell) => cells.contains(cell);

  FlatgramRegion? regionForCell(GridPoint cell) {
    for (final region in regions) {
      if (region.contains(cell)) return region;
    }
    return null;
  }

  /// Bounding box of board cells in grid coordinates.
  Rect computeBounds() {
    if (cells.isEmpty) return Rect.zero;
    var minX = cells.first.x;
    var maxX = cells.first.x;
    var minY = cells.first.y;
    var maxY = cells.first.y;
    for (final c in cells) {
      if (c.x < minX) minX = c.x;
      if (c.x > maxX) maxX = c.x;
      if (c.y < minY) minY = c.y;
      if (c.y > maxY) maxY = c.y;
    }
    return Rect.fromLTRB(
      minX.toDouble(),
      minY.toDouble(),
      (maxX + 1).toDouble(),
      (maxY + 1).toDouble(),
    );
  }
}

/// A tangram / domino piece that can be placed on the board.
class FlatgramPiece {
  const FlatgramPiece({
    required this.id,
    required this.cells,
    this.cellValues = const {},
    this.cellColors = const {},
    this.vertexValues = const {},
    this.edgeColors = const {},
    this.turns = 0,
    this.defaultColor = const Color(0xFFE2D9C8),
  });

  final String id;

  /// Local cell coordinates relative to the piece's anchor (0,0).
  final List<GridPoint> cells;

  /// Pip value (0 to 6) per local cell.
  final Map<GridPoint, int> cellValues;

  /// Optional color per local cell (for multicolored pieces).
  final Map<GridPoint, Color> cellColors;

  /// Optional values placed on local vertex corners.
  final Map<GridPoint, int> vertexValues;

  /// Optional colored outer edges.
  final Map<GridEdgeKey, Color> edgeColors;

  /// Default background color of the piece if cellColors is not specified.
  final Color defaultColor;

  /// Quarter turns clockwise (0..3).
  final int turns;

  FlatgramPiece copyWith({
    String? id,
    List<GridPoint>? cells,
    Map<GridPoint, int>? cellValues,
    Map<GridPoint, Color>? cellColors,
    Map<GridPoint, int>? vertexValues,
    Map<GridEdgeKey, Color>? edgeColors,
    Color? defaultColor,
    int? turns,
  }) {
    return FlatgramPiece(
      id: id ?? this.id,
      cells: cells ?? this.cells,
      cellValues: cellValues ?? this.cellValues,
      cellColors: cellColors ?? this.cellColors,
      vertexValues: vertexValues ?? this.vertexValues,
      edgeColors: edgeColors ?? this.edgeColors,
      defaultColor: defaultColor ?? this.defaultColor,
      turns: turns ?? this.turns,
    );
  }

  /// Calculates transformed cell locations when placed at [anchor] with [appliedTurns].
  List<GridPoint> transformedCells(GridPoint anchor, int appliedTurns) {
    return [
      for (final cell in cells) anchor + cell.rotateClockwise(appliedTurns),
    ];
  }

  /// Maps transformed board grid cell -> pip value.
  Map<GridPoint, int> transformedValues(GridPoint anchor, int appliedTurns) {
    final result = <GridPoint, int>{};
    for (final entry in cellValues.entries) {
      final t = anchor + entry.key.rotateClockwise(appliedTurns);
      result[t] = entry.value;
    }
    return result;
  }

  /// Maps transformed board grid cell -> cell color.
  Map<GridPoint, Color> transformedColors(GridPoint anchor, int appliedTurns) {
    final result = <GridPoint, Color>{};
    for (final cell in cells) {
      final t = anchor + cell.rotateClockwise(appliedTurns);
      result[t] = cellColors[cell] ?? defaultColor;
    }
    return result;
  }

  /// Maps transformed board vertex -> vertex value.
  Map<GridPoint, int> transformedVertices(GridPoint anchor, int appliedTurns) {
    final result = <GridPoint, int>{};
    for (final entry in vertexValues.entries) {
      final t = anchor + entry.key.rotateClockwise(appliedTurns);
      result[t] = entry.value;
    }
    return result;
  }

  /// Maps transformed board edge -> edge color.
  Map<GridEdgeKey, Color> transformedEdges(GridPoint anchor, int appliedTurns) {
    final result = <GridEdgeKey, Color>{};
    for (final entry in edgeColors.entries) {
      final tKey = entry.key.transformed(anchor, appliedTurns);
      result[tKey] = entry.value;
    }
    return result;
  }

  /// Bounding box of the piece in local space (cells) given [appliedTurns].
  Rect localBounds([int appliedTurns = 0]) {
    if (cells.isEmpty) return Rect.zero;
    final rotated = [for (final c in cells) c.rotateClockwise(appliedTurns)];
    var minX = rotated.first.x;
    var maxX = rotated.first.x;
    var minY = rotated.first.y;
    var maxY = rotated.first.y;
    for (final c in rotated) {
      if (c.x < minX) minX = c.x;
      if (c.x > maxX) maxX = c.x;
      if (c.y < minY) minY = c.y;
      if (c.y > maxY) maxY = c.y;
    }
    return Rect.fromLTRB(
      minX.toDouble(),
      minY.toDouble(),
      (maxX + 1).toDouble(),
      (maxY + 1).toDouble(),
    );
  }
}

/// Record of a placed piece on the board.
class PlacedPiece {
  const PlacedPiece({
    required this.pieceId,
    required this.anchor,
    this.turns = 0,
  });

  final String pieceId;
  final GridPoint anchor;
  final int turns;

  PlacedPiece copyWith({GridPoint? anchor, int? turns}) {
    return PlacedPiece(
      pieceId: pieceId,
      anchor: anchor ?? this.anchor,
      turns: turns ?? this.turns,
    );
  }
}

/// Runtime info about a board cell occupied by a placed piece.
class PlacedCellInfo {
  const PlacedCellInfo({
    required this.pieceId,
    required this.piece,
    required this.localCell,
    required this.boardCell,
    this.value,
    required this.color,
  });

  final String pieceId;
  final FlatgramPiece piece;
  final GridPoint localCell;
  final GridPoint boardCell;
  final int? value;
  final Color color;
}


/// A complete Flatgram puzzle definition.
class FlatgramPuzzle {
  const FlatgramPuzzle({
    required this.id,
    required this.title,
    required this.difficulty,
    required this.board,
    required this.pieces,
    required this.constraints,
    this.initialPlaced = const [],
    this.description = '',
  });

  final String id;
  final String title;
  final String difficulty; // 'easy', 'medium', 'hard'
  final FlatgramBoard board;
  final List<FlatgramPiece> pieces;
  final List<FlatgramConstraint> constraints;
  final List<PlacedPiece> initialPlaced;
  final String description;
}

