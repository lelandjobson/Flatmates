import 'dart:math' as math;
import 'dart:ui';

import '../geometry/polygon_union.dart';
import '../gestures/gesture_system.dart';
import '../papercut/models.dart';
import '../papercut/paper.dart';
import 'blueprint.dart';
import 'dimension_measure.dart';
import 'edit.dart';
import 'fold.dart';
import 'mixed_craft.dart';

/// Screen pixels inside which a blueprint-board vertex catches a target.
const double kBoardSnapPixels = 12;

/// A paper piece parked on a blueprint step. Vertices are in step space.
class BoardPiece {
  const BoardPiece({
    required this.id,
    required this.color,
    required this.vertices,
    this.backColor = kPapercutPink,
    this.holes = const [],
  });

  final String id;
  final Color color;
  final Color backColor;
  final List<Offset> vertices;
  final List<List<Offset>> holes;

  BoardPiece copyWith({List<Offset>? vertices, List<List<Offset>>? holes}) {
    return BoardPiece(
      id: id,
      color: color,
      backColor: backColor,
      vertices: vertices ?? this.vertices,
      holes: holes ?? this.holes,
    );
  }

  BoardPiece clone() {
    return BoardPiece(
      id: id,
      color: color,
      backColor: backColor,
      vertices: List<Offset>.from(vertices),
      holes: [for (final hole in holes) List<Offset>.from(hole)],
    );
  }
}

/// One blueprint step's pieces, rulers, and locked dimensions.
///
/// The rulers stay here so leaving the dimension tool, or the page, keeps
/// the last measurement.
class StepBoard {
  final List<BoardPiece> pieces = [];
  final Set<String> selected = {};
  final DimensionRuler horizontal = DimensionRuler(DimensionAxis.horizontal);
  final DimensionRuler vertical = DimensionRuler(DimensionAxis.vertical);
  final List<LockedDimension> locked = [];
  bool rulersPlaced = false;
  int nextId = 1;

  void removeIds(Iterable<String> ids) {
    final drop = ids.toSet();
    if (drop.isEmpty) return;
    pieces.removeWhere((piece) => drop.contains(piece.id));
    selected.removeAll(drop);
  }

  void addPieces(Iterable<BoardPiece> adding) {
    pieces.addAll(adding.map((piece) => piece.clone()));
  }
}

/// A piece move between the craft bench and a step board, for undo.
class BoardTransfer {
  const BoardTransfer({
    required this.stepKey,
    required this.pieces,
    required this.addedToBoard,
  });

  final String stepKey;
  final List<BoardPiece> pieces;

  /// True when the edit put [pieces] onto the board. False when it took them off.
  final bool addedToBoard;

  void undo(Map<String, StepBoard> boards) =>
      _apply(boards, added: !addedToBoard);

  void redo(Map<String, StepBoard> boards) =>
      _apply(boards, added: addedToBoard);

  void _apply(Map<String, StepBoard> boards, {required bool added}) {
    final board = boards[stepKey];
    if (board == null) return;
    if (added) {
      board.addPieces(pieces);
      return;
    }
    board.removeIds(pieces.map((piece) => piece.id));
  }
}

/// A blueprint step the paired view can open.
class BoardStepChoice {
  const BoardStepChoice({required this.blueprint, required this.stepIndex});

  final GridBlueprint blueprint;
  final int stepIndex;

  String get key => boardStepKey(blueprint.id, stepIndex);

  String get label => blueprint.steps[stepIndex].label;
}

String boardStepKey(String blueprintId, int stepIndex) =>
    '$blueprintId/$stepIndex';

List<BoardStepChoice> choicesForBlueprint(GridBlueprint blueprint) {
  return [
    for (var i = 0; i < blueprint.steps.length; i++)
      BoardStepChoice(blueprint: blueprint, stepIndex: i),
  ];
}

enum BoardTool { dimension, select }

/// Select is a tool only while the step has something to pick.
bool selectToolShown(int pieceCount) => pieceCount > 0;

/// Live rulers, grabs, and snap guides.
bool dimensionWidgetsShown(BoardTool tool) => tool == BoardTool.dimension;

/// Locked dimensions. Always on the dimension tool. On select, only by choice.
bool placedDimensionsShown(BoardTool tool, {required bool showInSelect}) {
  if (tool == BoardTool.dimension) return true;
  return showInSelect;
}

/// Select disappears with the last piece, and the dimension tool takes over.
BoardTool boardToolWithPieces(BoardTool tool, int pieceCount) {
  if (tool == BoardTool.select && !selectToolShown(pieceCount)) {
    return BoardTool.dimension;
  }
  return tool;
}

/// Pieces lifted off the craft bench, already sitting on [center].
class TakenCraft {
  const TakenCraft({
    required this.craft,
    required this.pieces,
    required this.nextId,
  });

  final MixedCraftArea craft;
  final List<BoardPiece> pieces;
  final int nextId;
}

/// Pulls the selection off the bench. The ring is unchanged, then shifted so
/// its centroid lands on [center].
TakenCraft? takeCraftSelection(
  MixedCraftArea area, {
  required Offset center,
  int nextId = 1,
}) {
  if (area.selected.isEmpty) return null;
  final raw = <BoardPiece>[];
  var id = nextId;
  for (final sheet in area.sheets) {
    for (final piece in sheet.paper.pieces) {
      final key = mixedPieceKey(sheet.id, piece.id);
      if (!area.selected.contains(key)) continue;
      final ring = shownRing(
        piece.vertices,
        piece.separation,
        sheet.paper.folds,
        pieceId: piece.id,
      );
      if (ring.length < 3) continue;
      raw.add(
        BoardPiece(
          id: 'board-$id',
          color: piece.color,
          backColor: piece.backColor,
          vertices: ring,
          holes: [
            for (final hole in piece.holes)
              shownRing(
                hole,
                piece.separation,
                sheet.paper.folds,
                pieceId: piece.id,
              ),
          ],
        ),
      );
      id++;
    }
  }
  if (raw.isEmpty) return null;
  final centroid = cloudCentroid([for (final piece in raw) ...piece.vertices]);
  return TakenCraft(
    craft: dropCraftKeys(area, area.selected),
    pieces: shiftPieces(raw, center - centroid),
    nextId: id,
  );
}

/// Drops [pieces] on the bench, shifted so their centroid is [center].
MixedCraftArea placePiecesOnCraft(
  MixedCraftArea area,
  List<BoardPiece> pieces, {
  required Offset center,
}) {
  if (pieces.isEmpty) return area;
  final centroid = cloudCentroid([
    for (final piece in pieces) ...piece.vertices,
  ]);
  final shifted = shiftPieces(pieces, center - centroid);
  final sheetId = 'sheet-${area.nextSheetId}';
  return area.copy(
    sheets: [
      ...area.sheets,
      MixedSheet(
        id: sheetId,
        paper: PapercutSheet(
          pieces: [
            for (final piece in shifted)
              PapercutPiece(
                id: piece.id,
                color: piece.color,
                backColor: piece.backColor,
                vertices: List<Offset>.from(piece.vertices),
                holes: [
                  for (final hole in piece.holes) List<Offset>.from(hole),
                ],
              ),
          ],
        ),
      ),
    ],
    selected: {for (final piece in shifted) mixedPieceKey(sheetId, piece.id)},
    nextSheetId: area.nextSheetId + 1,
  );
}

MixedCraftArea dropCraftKeys(MixedCraftArea area, Set<String> keys) {
  if (keys.isEmpty) return area;
  final sheets = <MixedSheet>[];
  for (final sheet in area.sheets) {
    final pieces = [
      for (final piece in sheet.paper.pieces)
        if (!keys.contains(mixedPieceKey(sheet.id, piece.id))) piece,
    ];
    if (pieces.isEmpty) continue;
    sheets.add(
      MixedSheet(
        id: sheet.id,
        paper: sheet.paper.copyWith(pieces: pieces),
      ),
    );
  }
  return area.copy(
    sheets: sheets,
    hidden: area.hidden.difference(keys),
    selected: area.selected.difference(keys),
  );
}

Offset cloudCentroid(Iterable<Offset> points) {
  var sum = Offset.zero;
  var count = 0;
  for (final point in points) {
    sum += point;
    count++;
  }
  if (count == 0) return Offset.zero;
  return sum / count.toDouble();
}

List<BoardPiece> shiftPieces(List<BoardPiece> pieces, Offset delta) {
  if (delta.distance < 1e-9) {
    return [for (final piece in pieces) piece.clone()];
  }
  return [
    for (final piece in pieces) mapPiece(piece, (point) => point + delta),
  ];
}

List<BoardPiece> shiftSelected(
  List<BoardPiece> pieces,
  Set<String> ids,
  Offset delta,
) {
  if (ids.isEmpty || delta.distance < 1e-9) {
    return [for (final piece in pieces) piece.clone()];
  }
  return [
    for (final piece in pieces)
      ids.contains(piece.id)
          ? mapPiece(piece, (point) => point + delta)
          : piece.clone(),
  ];
}

BoardPiece mapPiece(BoardPiece piece, Offset Function(Offset point) map) {
  return piece.copyWith(
    vertices: [for (final point in piece.vertices) map(point)],
    holes: [
      for (final hole in piece.holes) [for (final point in hole) map(point)],
    ],
  );
}

Iterable<Offset> piecePoints(BoardPiece piece) sync* {
  yield* piece.vertices;
  for (final hole in piece.holes) {
    yield* hole;
  }
}

/// Front to back.
List<String> boardPiecesUnder(List<BoardPiece> pieces, Offset aim) {
  final hits = <String>[];
  for (final piece in pieces.reversed) {
    if (_contains(piece, aim)) hits.add(piece.id);
  }
  return hits;
}

bool _contains(BoardPiece piece, Offset aim) {
  if (piece.vertices.length < 3) return false;
  if (!isInsidePolygon(aim, piece.vertices)) return false;
  for (final hole in piece.holes) {
    if (hole.length >= 3 && isInsidePolygon(aim, hole)) return false;
  }
  return true;
}

Set<String> boardMarqueeHits(
  List<BoardPiece> pieces,
  Rect rect,
  MarqueePick pick,
) {
  return {
    for (final piece in pieces)
      if (polygonInMarquee(piece.vertices, rect, pick)) piece.id,
  };
}

Rect? selectionBounds(List<BoardPiece> pieces, Set<String> ids) {
  return vertexBounds([
    for (final piece in pieces)
      if (ids.contains(piece.id)) ...piece.vertices,
  ]);
}

Offset? selectionCentroid(List<BoardPiece> pieces, Set<String> ids) {
  final points = [
    for (final piece in pieces)
      if (ids.contains(piece.id)) ...piece.vertices,
  ];
  if (points.isEmpty) return null;
  return cloudCentroid(points);
}

/// Translation that lands a moving vertex on a target.
///
/// Blueprint vertices win over other paper, which wins over the grid. When
/// nothing is inside [radius], the nearest grid point still wins.
Offset blueprintMoveSnap({
  required List<Offset> moving,
  required List<Offset> blueprintVertices,
  required List<Offset> otherPaper,
  required double spacing,
  required double radius,
}) {
  if (moving.isEmpty || spacing <= 0) return Offset.zero;
  var bestDistance = double.infinity;
  var best = Offset.zero;
  var bestPriority = -1;

  void consider(Offset delta, double distance, int priority) {
    if (priority > bestPriority ||
        (priority == bestPriority && distance < bestDistance)) {
      bestPriority = priority;
      bestDistance = distance;
      best = delta;
    }
  }

  for (final vertex in moving) {
    for (final target in blueprintVertices) {
      final delta = target - vertex;
      final distance = delta.distance;
      if (distance <= radius) consider(delta, distance, 3);
    }
    for (final target in otherPaper) {
      final delta = target - vertex;
      final distance = delta.distance;
      if (distance <= radius) consider(delta, distance, 2);
    }
    final grid = _gridPoint(vertex, spacing);
    final delta = grid - vertex;
    final distance = delta.distance;
    if (distance <= radius) consider(delta, distance, 0);
  }

  if (bestPriority >= 0) return best;

  var fallback = Offset.zero;
  var fallbackDistance = double.infinity;
  for (final vertex in moving) {
    final delta = _gridPoint(vertex, spacing) - vertex;
    final distance = delta.distance;
    if (distance < fallbackDistance) {
      fallbackDistance = distance;
      fallback = delta;
    }
  }
  return fallback;
}

Offset _gridPoint(Offset point, double spacing) {
  return Offset(
    (point.dx / spacing).round() * spacing,
    (point.dy / spacing).round() * spacing,
  );
}

/// Closest vertex inside [radius], or null.
Offset? nearestSnapVertex(Offset aim, List<Offset> vertices, double radius) {
  if (radius <= 0) return null;
  Offset? best;
  var bestDistance = radius;
  for (final vertex in vertices) {
    final distance = (vertex - aim).distance;
    if (distance > bestDistance) continue;
    bestDistance = distance;
    best = vertex;
  }
  return best;
}

/// What the selection box is allowed to do.
///
/// [stretch] turns on the side grabs, which scale one axis. With it off,
/// only the corners move, and they scale both axes together. [rotation]
/// draws the ring that turns the selection.
class TransformBox {
  const TransformBox({this.stretch = false, this.rotation = false});

  final bool stretch;
  final bool rotation;
}

/// Uniform corners and a rotation ring. Side grabs stay off.
const TransformBox kCombinedTransform = TransformBox(rotation: true);

/// Rotation ring steps, matching the crafting gizmo.
const double kRotationSnapDegrees = 5;

/// Signed degrees in (-180, 180], on the nearest [kRotationSnapDegrees] step.
double snapRotationDelta(double degrees) {
  var wrapped = degrees % 360;
  if (wrapped > 180) wrapped -= 360;
  if (wrapped < -180) wrapped += 360;
  return (wrapped / kRotationSnapDegrees).round() * kRotationSnapDegrees;
}

/// Screen-space ring around a transform box.
class RotationWidget {
  const RotationWidget({
    required this.center,
    required this.radius,
    required this.degrees,
  });

  final Offset center;
  final double radius;
  final double degrees;

  static const double hitSlop = 18;
  static const double handleRadius = 11;

  /// Screen atan2 grows clockwise. World rotation grows the other way.
  static const double rotationSign = -1;

  static RotationWidget layout({
    required Offset center,
    required double halfDiagonal,
    double degrees = 0,
  }) {
    return RotationWidget(
      center: center,
      radius: math.max(halfDiagonal + 28, 64),
      degrees: degrees,
    );
  }

  double get _angle => rotationSign * degrees * math.pi / 180;

  Offset get handle =>
      center + Offset(math.cos(_angle), math.sin(_angle)) * radius;

  bool hits(Offset screen) {
    if ((screen - handle).distance <= handleRadius + 8) return true;
    return ((screen - center).distance - radius).abs() <= hitSlop;
  }

  static double degreesFromScreen({
    required double startAngle,
    required double currentAngle,
  }) {
    final delta = wrapRadians(currentAngle - startAngle);
    return snapRotationDelta(rotationSign * delta * 180 / math.pi);
  }
}

/// Edge and corner grabs. Index 0 is the max-Y edge, then max-X, min-Y, min-X,
/// then the four corners from min-X/max-Y clockwise.
enum TransformHandle {
  maxY,
  maxX,
  minY,
  minX,
  minXMaxY,
  maxXMaxY,
  maxXMinY,
  minXMinY,
}

bool transformHandleScalesX(TransformHandle handle) {
  return switch (handle) {
    TransformHandle.maxY || TransformHandle.minY => false,
    _ => true,
  };
}

bool transformHandleScalesY(TransformHandle handle) {
  return switch (handle) {
    TransformHandle.maxX || TransformHandle.minX => false,
    _ => true,
  };
}

bool transformHandleIsCorner(TransformHandle handle) {
  return switch (handle) {
    TransformHandle.minXMaxY ||
    TransformHandle.maxXMaxY ||
    TransformHandle.maxXMinY ||
    TransformHandle.minXMinY => true,
    _ => false,
  };
}

List<Offset> transformHandlePoints(Rect bounds) {
  final midX = bounds.center.dx;
  final midY = bounds.center.dy;
  return [
    Offset(midX, bounds.bottom),
    Offset(bounds.right, midY),
    Offset(midX, bounds.top),
    Offset(bounds.left, midY),
    Offset(bounds.left, bounds.bottom),
    Offset(bounds.right, bounds.bottom),
    Offset(bounds.right, bounds.top),
    Offset(bounds.left, bounds.top),
  ];
}

/// The point that stays put while [handle] moves.
Offset stretchAnchor(TransformHandle handle, Rect bounds) {
  final midX = bounds.center.dx;
  final midY = bounds.center.dy;
  return switch (handle) {
    TransformHandle.maxY => Offset(midX, bounds.top),
    TransformHandle.maxX => Offset(bounds.left, midY),
    TransformHandle.minY => Offset(midX, bounds.bottom),
    TransformHandle.minX => Offset(bounds.right, midY),
    TransformHandle.minXMaxY => bounds.topRight,
    TransformHandle.maxXMaxY => bounds.topLeft,
    TransformHandle.maxXMinY => bounds.bottomLeft,
    TransformHandle.minXMinY => bounds.bottomRight,
  };
}

TransformHandle? hitTransformHandle(
  Offset world,
  Rect bounds,
  double radius, {
  TransformBox box = const TransformBox(stretch: true),
}) {
  if (radius <= 0) return null;
  final points = transformHandlePoints(bounds);
  TransformHandle? best;
  var bestDistance = radius;
  for (var i = 0; i < points.length; i++) {
    final handle = TransformHandle.values[i];
    if (!box.stretch && !transformHandleIsCorner(handle)) continue;
    final distance = (points[i] - world).distance;
    if (distance > bestDistance) continue;
    bestDistance = distance;
    best = handle;
  }
  return best;
}

class PieceStretch {
  const PieceStretch({
    required this.scaleX,
    required this.scaleY,
    required this.anchor,
  });

  final double scaleX;
  final double scaleY;
  final Offset anchor;
}

/// Scale that pulls [handle] toward [pointer], then snaps the moving edge.
///
/// A blueprint vertex on that edge wins when it is inside [radius]. Otherwise
/// the edge lands on the nearest grid line.
PieceStretch stretchToPointer({
  required TransformHandle handle,
  required Rect bounds,
  required Offset pointer,
  required List<Offset> blueprintVertices,
  required double spacing,
  required double radius,
  bool uniform = false,
}) {
  final anchor = stretchAnchor(handle, bounds);
  final origin = transformHandlePoints(bounds)[handle.index];
  if (uniform && transformHandleIsCorner(handle)) {
    final snapped = _snapCorner(pointer, blueprintVertices, spacing, radius);
    final base = (origin - anchor).distance;
    var scale = base < 1e-6 ? 1.0 : (snapped - anchor).distance / base;
    if (scale < 0.05) scale = 0.05;
    return PieceStretch(scaleX: scale, scaleY: scale, anchor: anchor);
  }
  if (transformHandleIsCorner(handle)) {
    final snapped = _snapCorner(pointer, blueprintVertices, spacing, radius);
    return PieceStretch(
      scaleX: _axisScale(origin.dx, anchor.dx, snapped.dx),
      scaleY: _axisScale(origin.dy, anchor.dy, snapped.dy),
      anchor: anchor,
    );
  }
  if (transformHandleScalesX(handle)) {
    final snapped = snapAxisCoordinate(
      pointer.dx,
      [for (final vertex in blueprintVertices) vertex.dx],
      spacing,
      radius,
    );
    return PieceStretch(
      scaleX: _axisScale(origin.dx, anchor.dx, snapped),
      scaleY: 1,
      anchor: anchor,
    );
  }
  final snapped = snapAxisCoordinate(
    pointer.dy,
    [for (final vertex in blueprintVertices) vertex.dy],
    spacing,
    radius,
  );
  return PieceStretch(
    scaleX: 1,
    scaleY: _axisScale(origin.dy, anchor.dy, snapped),
    anchor: anchor,
  );
}

double snapAxisCoordinate(
  double value,
  List<double> coordinates,
  double spacing,
  double radius,
) {
  double? best;
  var bestDistance = radius;
  for (final coordinate in coordinates) {
    final distance = (coordinate - value).abs();
    if (distance > bestDistance) continue;
    bestDistance = distance;
    best = coordinate;
  }
  if (best != null) return best;
  if (spacing <= 0) return value;
  return (value / spacing).round() * spacing;
}

Offset _snapCorner(
  Offset point,
  List<Offset> vertices,
  double spacing,
  double radius,
) {
  final vertex = nearestSnapVertex(point, vertices, radius);
  if (vertex != null) return vertex;
  if (spacing <= 0) return point;
  return _gridPoint(point, spacing);
}

double _axisScale(double origin, double anchor, double snapped) {
  final span = origin - anchor;
  if (span.abs() < 1e-6) return 1;
  final scale = (snapped - anchor) / span;
  if (scale < 0.05) return 0.05;
  return scale;
}

Offset applyStretchPoint(Offset point, PieceStretch stretch) {
  return Offset(
    point.dx * stretch.scaleX + stretch.anchor.dx * (1 - stretch.scaleX),
    point.dy * stretch.scaleY + stretch.anchor.dy * (1 - stretch.scaleY),
  );
}

List<BoardPiece> stretchPieces(
  List<BoardPiece> pieces,
  Set<String> ids,
  PieceStretch stretch,
) {
  return [
    for (final piece in pieces)
      ids.contains(piece.id)
          ? mapPiece(piece, (point) => applyStretchPoint(point, stretch))
          : piece.clone(),
  ];
}

Offset rotateAround(Offset point, Offset pivot, double radians) {
  final delta = point - pivot;
  final cosine = math.cos(radians);
  final sine = math.sin(radians);
  return Offset(
    pivot.dx + delta.dx * cosine - delta.dy * sine,
    pivot.dy + delta.dx * sine + delta.dy * cosine,
  );
}

List<BoardPiece> rotatePieces(
  List<BoardPiece> pieces,
  Set<String> ids,
  Offset pivot,
  double radians,
) {
  if (radians.abs() < 1e-9) {
    return [for (final piece in pieces) piece.clone()];
  }
  return [
    for (final piece in pieces)
      ids.contains(piece.id)
          ? mapPiece(piece, (point) => rotateAround(point, pivot, radians))
          : piece.clone(),
  ];
}

/// [radians] around [pivot], corrected so a moving vertex lands on a target
/// when the free turn already brings it inside [radius].
double snapTurn({
  required List<Offset> moving,
  required Offset pivot,
  required double radians,
  required List<Offset> targets,
  required double radius,
}) {
  if (radius <= 0 || moving.isEmpty || targets.isEmpty) return radians;
  var bestCorrection = 0.0;
  var bestAbs = double.infinity;
  var found = false;
  for (final vertex in moving) {
    final arm = vertex - pivot;
    if (arm.distance < 1e-6) continue;
    final preview = rotateAround(vertex, pivot, radians);
    for (final target in targets) {
      if ((target - vertex).distance < 1e-6) continue;
      if ((preview - target).distance > radius) continue;
      if ((arm.distance - (target - pivot).distance).abs() > radius) continue;
      final want =
          math.atan2(target.dy - pivot.dy, target.dx - pivot.dx) -
          math.atan2(arm.dy, arm.dx);
      final correction = wrapRadians(want - radians);
      final landed = rotateAround(vertex, pivot, radians + correction);
      if ((landed - target).distance > 1e-3) continue;
      if (correction.abs() >= bestAbs) continue;
      bestAbs = correction.abs();
      bestCorrection = correction;
      found = true;
    }
  }
  if (!found) return radians;
  return wrapRadians(radians + bestCorrection);
}
