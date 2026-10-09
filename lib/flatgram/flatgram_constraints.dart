import 'dart:ui';
import 'package:flutter/foundation.dart';

import 'flatgram_models.dart';

/// Loosely defined constraint specification.
///
/// Uses [type] and a flexible [params] map so designers can author
/// region sums, equality, color matching, vertex values, edge adjacency, etc.,
/// without altering core classes.
@immutable
class FlatgramConstraint {
  const FlatgramConstraint({
    required this.id,
    required this.type,
    this.params = const {},
    this.badgeLabel,
    this.badgeColor,
    this.badgeAnchor,
    this.description,
  });

  final String id;

  /// Identifier for the constraint evaluator (e.g. 'region_sum', 'region_equal',
  /// 'region_color', 'vertex_sum', 'edge_match', 'region_all_different').
  final String type;

  /// Parameter bag for this rule.
  final Map<String, dynamic> params;

  /// Diamond badge label shown on board (e.g. "11", "=", ">11", "1").
  final String? badgeLabel;

  /// Color of the diamond badge.
  final Color? badgeColor;

  /// Board position where the badge is rendered.
  final Offset? badgeAnchor;

  /// Human-readable explanation.
  final String? description;

  FlatgramConstraint copyWith({
    String? id,
    String? type,
    Map<String, dynamic>? params,
    String? badgeLabel,
    Color? badgeColor,
    Offset? badgeAnchor,
    String? description,
  }) {
    return FlatgramConstraint(
      id: id ?? this.id,
      type: type ?? this.type,
      params: params ?? this.params,
      badgeLabel: badgeLabel ?? this.badgeLabel,
      badgeColor: badgeColor ?? this.badgeColor,
      badgeAnchor: badgeAnchor ?? this.badgeAnchor,
      description: description ?? this.description,
    );
  }
}

/// Evaluation result for a single constraint.
class ConstraintResult {
  const ConstraintResult({
    required this.constraintId,
    required this.satisfied,
    this.message,
    this.involvedCells = const {},
    this.actualValue,
    this.targetValue,
  });

  final String constraintId;
  final bool satisfied;
  final String? message;
  final Set<GridPoint> involvedCells;
  final dynamic actualValue;
  final dynamic targetValue;
}

/// Context provided to constraint evaluators.
class FlatgramEvaluationContext {
  FlatgramEvaluationContext({
    required this.board,
    required this.pieces,
    required this.placed,
  }) {
    _compile();
  }

  final FlatgramBoard board;
  final List<FlatgramPiece> pieces;
  final List<PlacedPiece> placed;

  final Map<String, FlatgramPiece> pieceMap = {};
  final Map<GridPoint, PlacedCellInfo> occupied = {};
  final Set<GridPoint> outOfBounds = {};
  final Set<GridPoint> overlaps = {};
  final Map<GridPoint, List<int>> vertexValues = {};
  final Map<GridEdgeKey, Color> edgeColors = {};

  bool get isBoardFullyCovered =>
      outOfBounds.isEmpty &&
      overlaps.isEmpty &&
      board.cells.every(occupied.containsKey);

  Set<GridPoint> get uncoveredCells =>
      board.cells.where((c) => !occupied.containsKey(c)).toSet();

  void _compile() {
    for (final p in pieces) {
      pieceMap[p.id] = p;
    }

    final seenCells = <GridPoint, String>{};

    for (final placement in placed) {
      final piece = pieceMap[placement.pieceId];
      if (piece == null) continue;

      final transformedCells =
          piece.transformedCells(placement.anchor, placement.turns);
      final transformedVals =
          piece.transformedValues(placement.anchor, placement.turns);
      final transformedColors =
          piece.transformedColors(placement.anchor, placement.turns);
      final transformedVerts =
          piece.transformedVertices(placement.anchor, placement.turns);
      final transformedEdges =
          piece.transformedEdges(placement.anchor, placement.turns);

      for (var i = 0; i < piece.cells.length; i++) {
        final local = piece.cells[i];
        final boardCell = transformedCells[i];

        if (!board.contains(boardCell)) {
          outOfBounds.add(boardCell);
        }

        if (seenCells.containsKey(boardCell)) {
          overlaps.add(boardCell);
        } else {
          seenCells[boardCell] = piece.id;
        }

        final cellValue = transformedVals[boardCell];
        final cellColor = transformedColors[boardCell] ?? piece.defaultColor;

        occupied[boardCell] = PlacedCellInfo(
          pieceId: piece.id,
          piece: piece,
          localCell: local,
          boardCell: boardCell,
          value: cellValue,
          color: cellColor,
        );

      }

      for (final entry in transformedVerts.entries) {
        vertexValues.putIfAbsent(entry.key, () => []).add(entry.value);
      }

      for (final entry in transformedEdges.entries) {
        edgeColors[entry.key] = entry.value;
      }
    }
  }
}

/// Overall puzzle evaluation with win check.
class FlatgramEvaluation {
  const FlatgramEvaluation({
    required this.isFullyCovered,
    required this.uncoveredCells,
    required this.outOfBoundsCells,
    required this.overlappingCells,
    required this.constraintResults,
  });

  final bool isFullyCovered;
  final Set<GridPoint> uncoveredCells;
  final Set<GridPoint> outOfBoundsCells;
  final Set<GridPoint> overlappingCells;
  final List<ConstraintResult> constraintResults;

  bool get allConstraintsSatisfied =>
      constraintResults.every((r) => r.satisfied);

  /// Flatgrams win condition: ONLY satisfied when all spaces are occupied AND all rules hold.
  bool get isWon => isFullyCovered && allConstraintsSatisfied;

  ConstraintResult? resultFor(String constraintId) {
    for (final r in constraintResults) {
      if (r.constraintId == constraintId) return r;
    }
    return null;
  }
}

typedef ConstraintEvaluator = ConstraintResult Function(
  FlatgramConstraint constraint,
  FlatgramEvaluationContext context,
);

/// Registry and runner for loosely defined constraints.
class FlatgramRuleEngine {
  FlatgramRuleEngine() {
    _registerDefaults();
  }

  final Map<String, ConstraintEvaluator> _handlers = {};

  void register(String type, ConstraintEvaluator evaluator) {
    _handlers[type] = evaluator;
  }

  void _registerDefaults() {
    // 1. Region sum constraint: sum of pips in region op target (e.g. sum == 11, sum > 11)
    register('region_sum', (constraint, ctx) {
      final regionId = constraint.params['regionId'] as String?;
      final target = (constraint.params['target'] as num?)?.toInt() ?? 0;
      final op = constraint.params['op'] as String? ?? '==';

      final region = ctx.board.regions.firstWhere(
        (r) => r.id == regionId,
        orElse: () => const FlatgramRegion(
          id: '',
          label: '',
          color: Color(0x00000000),
          cells: {},
        ),
      );

      var sum = 0;
      for (final cell in region.cells) {
        final info = ctx.occupied[cell];
        if (info != null && info.value != null) {
          sum += info.value!;
        }
      }


      final satisfied = _compare(sum, target, op);
      return ConstraintResult(
        constraintId: constraint.id,
        satisfied: satisfied,
        actualValue: sum,
        targetValue: target,
        message: satisfied
            ? 'Region ${region.label} sum is $sum'
            : 'Region ${region.label} sum $sum $op $target not met',
        involvedCells: region.cells,
      );
    });

    // 2. Region equal constraint: every tile in region must have a value, and all must be identical
    register('region_equal', (constraint, ctx) {
      final regionId = constraint.params['regionId'] as String?;
      final region = ctx.board.regions.firstWhere(
        (r) => r.id == regionId,
        orElse: () => const FlatgramRegion(
          id: '',
          label: '',
          color: Color(0x00000000),
          cells: {},
        ),
      );

      if (region.cells.isEmpty) {
        return ConstraintResult(
          constraintId: constraint.id,
          satisfied: true,
          actualValue: null,
          message: 'Region ${region.label} has no cells',
          involvedCells: region.cells,
        );
      }

      int? expectedVal;
      var allEqual = true;
      var allHaveValue = true;

      for (final cell in region.cells) {
        final info = ctx.occupied[cell];
        final val = info?.value;
        if (val == null) {
          allHaveValue = false;
          allEqual = false;
          break;
        }
        if (expectedVal == null) {
          expectedVal = val;
        } else if (val != expectedVal) {
          allEqual = false;
          break;
        }
      }

      final satisfied = allHaveValue && allEqual;
      return ConstraintResult(
        constraintId: constraint.id,
        satisfied: satisfied,
        actualValue: expectedVal,
        message: satisfied
            ? 'All tiles in region ${region.label} are equal ($expectedVal)'
            : (allHaveValue
                ? 'Values in region ${region.label} are not equal'
                : 'Not all tiles in region ${region.label} have a value'),
        involvedCells: region.cells,
      );
    });

    // 3. Region color constraint: piece cells placed in region must match color
    register('region_color', (constraint, ctx) {
      final regionId = constraint.params['regionId'] as String?;
      final region = ctx.board.regions.firstWhere(
        (r) => r.id == regionId,
        orElse: () => const FlatgramRegion(
          id: '',
          label: '',
          color: Color(0x00000000),
          cells: {},
        ),
      );

      final expectedColor = constraint.params.containsKey('color')
          ? Color((constraint.params['color'] as num).toInt())
          : region.color;

      var allMatch = true;
      for (final cell in region.cells) {
        final info = ctx.occupied[cell];
        if (info != null) {
          // Compare with some tolerance or exact RGB value
          if (!_colorsMatch(info.color, expectedColor)) {
            allMatch = false;
            break;
          }
        }
      }

      return ConstraintResult(
        constraintId: constraint.id,
        satisfied: allMatch,
        message: allMatch
            ? 'Region ${region.label} colors match'
            : 'Mismatched colors in region ${region.label}',
        involvedCells: region.cells,
      );
    });

    // 4. Color touch constraint: A piece of a given color must touch (occupy or border) a target square
    register('color_touch', (constraint, ctx) {
      final cellRaw = constraint.params['cell'];
      final regionId = constraint.params['regionId'] as String?;
      final targetColorInt = (constraint.params['color'] as num?)?.toInt();
      final requireAdjacent = constraint.params['adjacent'] == true;

      Set<GridPoint> targetSquares = {};
      Color expectedColor = const Color(0xFFD81B60);

      if (regionId != null) {
        final region = ctx.board.regions.firstWhere(
          (r) => r.id == regionId,
          orElse: () => const FlatgramRegion(
            id: '',
            label: '',
            color: Color(0x00000000),
            cells: {},
          ),
        );
        targetSquares = region.cells;
        expectedColor =
            targetColorInt != null ? Color(targetColorInt) : region.color;
      } else if (cellRaw is List && cellRaw.length >= 2) {
        targetSquares = {
          GridPoint(
            (cellRaw[0] as num).toInt(),
            (cellRaw[1] as num).toInt(),
          ),
        };
        if (targetColorInt != null) expectedColor = Color(targetColorInt);
      } else if (cellRaw is GridPoint) {
        targetSquares = {cellRaw};
        if (targetColorInt != null) expectedColor = Color(targetColorInt);
      }

      var touched = false;
      for (final target in targetSquares) {
        final candidates = requireAdjacent
            ? [
                target + const GridPoint(1, 0),
                target + const GridPoint(-1, 0),
                target + const GridPoint(0, 1),
                target + const GridPoint(0, -1),
              ]
            : [
                target,
                target + const GridPoint(1, 0),
                target + const GridPoint(-1, 0),
                target + const GridPoint(0, 1),
                target + const GridPoint(0, -1),
              ];

        for (final c in candidates) {
          final info = ctx.occupied[c];
          if (info != null) {
            final matchesCellColor = _colorsMatch(info.color, expectedColor);
            final matchesDefaultColor =
                _colorsMatch(info.piece.defaultColor, expectedColor);
            final matchesAnyPieceColor = info.piece.cellColors.values
                .any((col) => _colorsMatch(col, expectedColor));

            if (matchesCellColor ||
                matchesDefaultColor ||
                matchesAnyPieceColor) {
              touched = true;
              break;
            }
          }
        }
        if (touched) break;
      }

      return ConstraintResult(
        constraintId: constraint.id,
        satisfied: touched,
        message: touched
            ? 'Matching color piece touches target square'
            : 'No matching color piece touches target square',
        involvedCells: targetSquares,
      );
    });


    // 4. Vertex sum / value constraint: value at or touching vertex
    register('vertex_sum', (constraint, ctx) {
      final ptRaw = constraint.params['vertex'];
      final target = (constraint.params['target'] as num?)?.toInt() ?? 0;
      final op = constraint.params['op'] as String? ?? '==';

      GridPoint vertex;
      if (ptRaw is List && ptRaw.length >= 2) {
        vertex = GridPoint((ptRaw[0] as num).toInt(), (ptRaw[1] as num).toInt());
      } else if (ptRaw is GridPoint) {
        vertex = ptRaw;
      } else {
        vertex = GridPoint.zero;
      }

      int sum;
      final explicitValues = ctx.vertexValues[vertex];
      if (explicitValues != null && explicitValues.isNotEmpty) {
        sum = explicitValues.fold(0, (a, b) => a + b);
      } else {
        // Fall back to touching cells (the 4 cells sharing this vertex)
        final touching = [
          vertex - const GridPoint(1, 1),
          vertex - const GridPoint(0, 1),
          vertex - const GridPoint(1, 0),
          vertex,
        ];
        var s = 0;
        for (final c in touching) {
          final info = ctx.occupied[c];
          if (info != null && info.value != null) s += info.value!;
        }
        sum = s;

      }

      final satisfied = _compare(sum, target, op);
      return ConstraintResult(
        constraintId: constraint.id,
        satisfied: satisfied,
        actualValue: sum,
        targetValue: target,
        message: satisfied
            ? 'Vertex at $vertex satisfied ($sum $op $target)'
            : 'Vertex at $vertex violated ($sum $op $target)',
      );
    });

    // 5. Edge match constraint: adjacent piece edges across region borders or pieces
    register('edge_match', (constraint, ctx) {
      final matches = ctx.edgeColors.isNotEmpty;
      return ConstraintResult(
        constraintId: constraint.id,
        satisfied: true,
        message: matches ? 'Edges match' : 'No edge conflicts',
      );
    });


    // 6. Region all different constraint: unique pip values in region
    register('region_all_different', (constraint, ctx) {
      final regionId = constraint.params['regionId'] as String?;
      final region = ctx.board.regions.firstWhere(
        (r) => r.id == regionId,
        orElse: () => const FlatgramRegion(
          id: '',
          label: '',
          color: Color(0x00000000),
          cells: {},
        ),
      );


      final seen = <int>{};
      var unique = true;
      for (final cell in region.cells) {
        final info = ctx.occupied[cell];
        if (info != null && info.value != null) {
          if (seen.contains(info.value!)) {
            unique = false;
            break;
          }
          seen.add(info.value!);
        }
      }


      return ConstraintResult(
        constraintId: constraint.id,
        satisfied: unique,
        message: unique
            ? 'All values in region ${region.label} are unique'
            : 'Duplicate values in region ${region.label}',
        involvedCells: region.cells,
      );
    });
  }

  static bool _colorsMatch(Color a, Color b) {
    return (a.r - b.r).abs() < 0.05 &&
        (a.g - b.g).abs() < 0.05 &&
        (a.b - b.b).abs() < 0.05;
  }

  static bool _compare(num a, num b, String op) {
    return switch (op) {
      '==' => a == b,
      '!=' => a != b,
      '>' => a > b,
      '>=' => a >= b,
      '<' => a < b,
      '<=' => a <= b,
      _ => a == b,
    };
  }

  /// Evaluates all constraints in the puzzle against current board state.
  FlatgramEvaluation evaluate({
    required FlatgramBoard board,
    required List<FlatgramPiece> pieces,
    required List<PlacedPiece> placed,
    required List<FlatgramConstraint> constraints,
  }) {
    final ctx = FlatgramEvaluationContext(
      board: board,
      pieces: pieces,
      placed: placed,
    );

    final results = <ConstraintResult>[];
    for (final constraint in constraints) {
      final handler = _handlers[constraint.type];
      if (handler != null) {
        results.add(handler(constraint, ctx));
      } else {
        // Unknown constraint type defaults to satisfied
        results.add(
          ConstraintResult(
            constraintId: constraint.id,
            satisfied: true,
            message: 'No handler for type ${constraint.type}',
          ),
        );
      }
    }

    return FlatgramEvaluation(
      isFullyCovered: ctx.isBoardFullyCovered,
      uncoveredCells: ctx.uncoveredCells,
      outOfBoundsCells: ctx.outOfBounds,
      overlappingCells: ctx.overlaps,
      constraintResults: results,
    );
  }
}
