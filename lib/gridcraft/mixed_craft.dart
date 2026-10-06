import 'dart:math' as math;
import 'dart:ui';

import '../geometry/polygon_union.dart';
import '../papercut/models.dart';
import '../papercut/paper.dart';
import '../papercut/split.dart';
import 'edit.dart';
import 'fold.dart';
import 'paper_stack.dart';
import 'scissor.dart';

/// Real size of a mixed-crafting sheet. At grid scale 4 it reads as 6×6.
const double kMixedPaperSize = 24;

/// Cell sizes, coarse to fine. Plus steps toward 1. Minus steps toward 12.
const List<int> kMixedGridScales = [12, 8, 6, 4, 3, 2, 1];

const int kMixedDefaultScale = 4;

/// A crafting-grid dot lattice fades across this long when the scale changes.
const Duration kGridScaleFade = Duration(milliseconds: 300);

const int kMixedHistoryDepth = 50;

/// How close an aim must be, in cells, before a cut or a fold locks onto an edge.
const double kMixedEdgeCells = 0.45;

/// One placed sheet. Hidden pieces live on the area, not here.
class MixedSheet {
  const MixedSheet({required this.id, required this.paper});

  final String id;
  final PapercutSheet paper;

  MixedSheet clone() => MixedSheet(id: id, paper: paper.clone());
}

/// Crafting-area state. The camera and the grid scale are not part of it.
class MixedCraftArea {
  const MixedCraftArea({
    required this.sheets,
    required this.hidden,
    required this.selected,
    required this.nextSheetId,
  });

  final List<MixedSheet> sheets;
  final Set<String> hidden;
  final Set<String> selected;
  final int nextSheetId;

  MixedCraftArea copy({
    List<MixedSheet>? sheets,
    Set<String>? hidden,
    Set<String>? selected,
    int? nextSheetId,
  }) {
    return MixedCraftArea(
      sheets: sheets ?? this.sheets,
      hidden: hidden ?? this.hidden,
      selected: selected ?? this.selected,
      nextSheetId: nextSheetId ?? this.nextSheetId,
    );
  }

  MixedCraftArea clone() {
    return MixedCraftArea(
      sheets: [for (final sheet in sheets) sheet.clone()],
      hidden: Set<String>.of(hidden),
      selected: Set<String>.of(selected),
      nextSheetId: nextSheetId,
    );
  }

  MixedSheet? sheetById(String id) {
    for (final sheet in sheets) {
      if (sheet.id == id) return sheet;
    }
    return null;
  }
}

/// Snapshot stack. Push the area from before a material change.
class MixedCraftHistory {
  final List<MixedCraftArea> _undo = [];
  final List<MixedCraftArea> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void push(MixedCraftArea before) {
    _undo.add(before.clone());
    if (_undo.length > kMixedHistoryDepth) _undo.removeAt(0);
    _redo.clear();
  }

  MixedCraftArea? undo(MixedCraftArea current) {
    if (_undo.isEmpty) return null;
    final previous = _undo.removeLast();
    _redo.add(current.clone());
    return previous;
  }

  MixedCraftArea? redo(MixedCraftArea current) {
    if (_redo.isEmpty) return null;
    _undo.add(current.clone());
    return _redo.removeLast();
  }
}

String mixedPieceKey(String sheetId, String pieceId) => '$sheetId/$pieceId';

/// The yellow sheet the view opens on, 24×24 and centered on the origin.
MixedCraftArea mixedOpeningArea() {
  final half = kMixedPaperSize / 2;
  return MixedCraftArea(
    sheets: [
      MixedSheet(
        id: 'sheet-1',
        paper: PapercutSheet(
          pieces: [
            PapercutPiece(
              id: 'paper',
              color: kPapercutYellow,
              vertices: [
                Offset(-half, -half),
                Offset(half, -half),
                Offset(half, half),
                Offset(-half, half),
              ],
            ),
          ],
        ),
      ),
    ],
    hidden: const {},
    selected: const {},
    nextSheetId: 2,
  );
}

/// How many cells the 24-unit sheet spans at [scale].
int gridCellsAcross(int scale) {
  if (scale <= 0) return 0;
  return kMixedPaperSize ~/ scale;
}

/// [finer] is the plus button: one step toward the smaller cell.
int stepGridScale(int scale, {required bool finer}) {
  final index = kMixedGridScales.indexOf(scale);
  if (index < 0) return kMixedDefaultScale;
  final next = finer ? index + 1 : index - 1;
  if (next < 0 || next >= kMixedGridScales.length) return scale;
  return kMixedGridScales[next];
}

/// Dot-lattice opacities while the crafting grid scale changes.
///
/// One step lasts [kGridScaleFade]. [opacities] lerps from the lattices that
/// were on screen at the step to the scale being stepped to. A step during a
/// fade samples those opacities first, so the texture retargets: nothing
/// clears to an empty grid, and a lattice already fading is not left behind.
class GridScaleCrossfade {
  GridScaleCrossfade({this.scale = kMixedDefaultScale}) : _from = {scale: 1.0};

  int scale;

  /// Opacities captured at the start of the current step.
  Map<int, double> _from;

  /// True before any step, and again once the latest step has finished.
  bool _idle = true;

  /// Lattice opacities at progress [t], where 0 is the step and 1 is 300ms.
  /// Entries that have faded out are omitted.
  Map<int, double> opacities(double t) {
    if (_idle) return {scale: 1.0};
    final u = t.clamp(0.0, 1.0);
    final painted = <int, double>{};
    for (final entry in _from.entries) {
      final target = entry.key == scale ? 1.0 : 0.0;
      final value = entry.value + (target - entry.value) * u;
      if (value > 0.001) painted[entry.key] = value;
    }
    return painted;
  }

  /// Start a fade toward [next]. [t] is the progress of a fade being
  /// interrupted. Returns false when [next] is already the scale.
  bool retarget(int next, {double t = 1}) {
    if (next == scale) return false;
    _from = Map<int, double>.of(opacities(t));
    _from.putIfAbsent(next, () => 0);
    scale = next;
    _idle = false;
    return true;
  }

  /// The fade has reached the scale. Later samples stay on that lattice.
  void settle() {
    _idle = true;
    _from = {scale: 1.0};
  }
}

/// Where a cut locks on. [point] is in the piece's model space.
class CutLock {
  const CutLock({
    required this.sheetId,
    required this.pieceId,
    required this.point,
  });

  final String sheetId;
  final String pieceId;
  final Offset point;
}

CutLock? lockCut(
  Offset aim,
  MixedCraftArea area,
  int scale, {
  double? maxCells = kMixedEdgeCells,
}) {
  final pieces = <PapercutPiece>[];
  final owners = <(String, String)>[];
  for (final sheet in area.sheets) {
    for (final piece in sheet.paper.pieces) {
      if (area.hidden.contains(mixedPieceKey(sheet.id, piece.id))) continue;
      pieces.add(piece);
      owners.add((sheet.id, piece.id));
    }
  }
  final edge = closestPieceEdge(
    aim: aim,
    pieces: pieces,
    spacing: scale.toDouble(),
  );
  if (edge == null) return null;
  final piece = pieces[edge.index];
  final drawn = edge.model + piece.separation;
  if (maxCells != null && (drawn - aim).distance > scale * maxCells) {
    return null;
  }
  if (placeOnRing(edge.model, piece.vertices) == null) return null;
  final owner = owners[edge.index];
  return CutLock(sheetId: owner.$1, pieceId: owner.$2, point: edge.model);
}

/// Fold start. Same edge snap as [lockCut]: an interior aim does not lock.
CutLock? lockFold(
  Offset aim,
  MixedCraftArea area,
  int scale, {
  double? maxCells = kMixedEdgeCells,
}) {
  return lockCut(aim, area, scale, maxCells: maxCells);
}

/// Far side of [ring] on the ray from [start] through [through].
///
/// [through] is the grid or crease point under the reticle, in model space.
/// The cut keeps going until it leaves the piece, so an interior aim still
/// splits the paper. Null when the ray does not leave the ring.
Offset? cutSpanEnd(Offset start, Offset through, List<Offset> ring) {
  final delta = through - start;
  if (delta.distance < 1e-4 || ring.length < 3) return null;
  return nextOutlineHit(from: start, direction: delta, closed: [ring]);
}

/// Splits [sheetId] along [start]–[end] in model space. Null when it does not
/// come out through another edge.
MixedCraftArea? commitCut(
  MixedCraftArea area,
  String sheetId,
  Offset start,
  Offset end,
) {
  final sheet = area.sheetById(sheetId);
  if (sheet == null) return null;
  if ((end - start).distance < 1e-3) return null;
  final next = applyPapercutCut(sheet.paper, [start, end]);
  if (next == null || next.pieces.length <= sheet.paper.pieces.length) {
    return null;
  }
  return _replace(area, sheetId, next);
}

MixedCraftArea? scoreSpan(
  MixedCraftArea area,
  String sheetId,
  Offset start,
  Offset end,
  Offset face,
) {
  final sheet = area.sheetById(sheetId);
  if (sheet == null) return null;
  final piece = _pieceUnder(sheet, face, area.hidden);
  if (piece == null) return null;
  final shift = piece.separation;
  final next = scoreCrease(sheet.paper, start - shift, end - shift);
  if (next.scores.length == sheet.paper.scores.length) return null;
  return _replace(area, sheetId, next);
}

MixedCraftArea? foldSpan(
  MixedCraftArea area,
  String sheetId,
  Offset start,
  Offset end,
  Offset face,
) {
  final sheet = area.sheetById(sheetId);
  if (sheet == null) return null;
  final piece = _pieceUnder(sheet, face, area.hidden);
  if (piece == null) return null;
  final shift = piece.separation;
  final next = foldSheet(
    sheet: sheet.paper,
    spanA: start - shift,
    spanB: end - shift,
    flapPoint: face - shift,
    facing: FoldFacing.toward,
    pieceId: piece.id,
  );
  if (next == null) return null;
  return _replace(area, sheetId, next);
}

/// Unfolds the latest crease when [aim] is on a visible piece of that sheet.
MixedCraftArea? unfoldUnder(MixedCraftArea area, Offset aim) {
  for (final sheet in area.sheets.reversed) {
    if (_pieceUnder(sheet, aim, area.hidden) == null) continue;
    final next = unfoldAt(sheet.paper, aim, reach: kMixedPaperSize);
    if (next == null) return null;
    return _replace(area, sheet.id, next);
  }
  return null;
}

MixedCraftArea? movePieces(MixedCraftArea area, Offset delta) {
  if (delta.distance < 1e-6 || area.selected.isEmpty) return null;
  var changed = false;
  final sheets = <MixedSheet>[];
  for (final sheet in area.sheets) {
    final pieces = <PapercutPiece>[];
    for (final piece in sheet.paper.pieces) {
      final key = mixedPieceKey(sheet.id, piece.id);
      if (!area.selected.contains(key)) {
        pieces.add(piece);
        continue;
      }
      changed = true;
      pieces.add(piece.copyWith(separation: piece.separation + delta));
    }
    sheets.add(
      MixedSheet(
        id: sheet.id,
        paper: sheet.paper.copyWith(pieces: pieces),
      ),
    );
  }
  if (!changed) return null;
  return area.copy(sheets: sheets);
}

MixedCraftArea? rotateSelection(MixedCraftArea area) {
  if (area.selected.isEmpty) return null;
  final cloud = <Offset>[];
  for (final sheet in area.sheets) {
    for (final piece in sheet.paper.pieces) {
      if (!area.selected.contains(mixedPieceKey(sheet.id, piece.id))) continue;
      cloud.addAll(
        shownRing(
          piece.vertices,
          piece.separation,
          sheet.paper.folds,
          pieceId: piece.id,
        ),
      );
    }
  }
  if (cloud.isEmpty) return null;
  var center = Offset.zero;
  for (final point in cloud) {
    center += point;
  }
  center = center / cloud.length.toDouble();

  final sheets = <MixedSheet>[];
  for (final sheet in area.sheets) {
    final selectedRings = <List<Offset>>[];
    final pieces = <PapercutPiece>[];
    for (final piece in sheet.paper.pieces) {
      final key = mixedPieceKey(sheet.id, piece.id);
      if (!area.selected.contains(key)) {
        pieces.add(piece);
        continue;
      }
      final ring = shownRing(
        piece.vertices,
        piece.separation,
        sheet.paper.folds,
        pieceId: piece.id,
      );
      selectedRings.add(ring);
      final holes = [
        for (final hole in piece.holes)
          [
            for (final point in shownRing(
              hole,
              piece.separation,
              sheet.paper.folds,
              pieceId: piece.id,
            ))
              _quarter(point, center),
          ],
      ];
      pieces.add(
        PapercutPiece(
          id: piece.id,
          color: piece.color,
          backColor: piece.backColor,
          vertices: [for (final point in ring) _quarter(point, center)],
          holes: holes,
        ),
      );
    }
    if (selectedRings.isEmpty) {
      sheets.add(sheet);
      continue;
    }
    Offset turn(Offset point) => _quarter(point, center);
    bool onSelection(Offset point) {
      for (final ring in selectedRings) {
        if (_onRing(point, ring)) return true;
      }
      return false;
    }

    final paper = sheet.paper;
    sheets.add(
      MixedSheet(
        id: sheet.id,
        paper: paper.copyWith(
          pieces: pieces,
          scores: [
            for (final score in paper.scores)
              onSelection(score.a) && onSelection(score.b)
                  ? ScoreLine(turn(score.a), turn(score.b))
                  : score,
          ],
          folds: [
            for (final joint in paper.folds)
              onSelection(joint.a) && onSelection(joint.b)
                  ? FoldJoint(
                      a: turn(joint.a),
                      b: turn(joint.b),
                      side: joint.side,
                      facing: joint.facing,
                      pieceIds: joint.pieceIds,
                    )
                  : joint,
          ],
          cutStrokes: [
            for (final stroke in paper.cutStrokes)
              stroke.isNotEmpty && stroke.every(onSelection)
                  ? [for (final point in stroke) turn(point)]
                  : stroke,
          ],
        ),
      ),
    );
  }
  return area.copy(sheets: sheets);
}

MixedCraftArea? hideSelection(MixedCraftArea area) {
  if (area.selected.isEmpty) return null;
  return area.copy(
    hidden: {...area.hidden, ...area.selected},
    selected: const {},
  );
}

MixedCraftArea? showPiece(MixedCraftArea area, String key) {
  if (!area.hidden.contains(key)) return null;
  final hidden = Set<String>.of(area.hidden)..remove(key);
  return area.copy(hidden: hidden);
}

/// Drops another 24×24 sheet. Occupied origins step one cell to the right.
MixedCraftArea placeSheet(MixedCraftArea area, Color color, int scale) {
  final half = kMixedPaperSize / 2;
  var center = Offset.zero;
  var guard = 0;
  while (_occupied(area, center, half) && guard < 24) {
    center += Offset(kMixedPaperSize + scale, 0);
    guard++;
  }
  final id = 'sheet-${area.nextSheetId}';
  final sheet = MixedSheet(
    id: id,
    paper: PapercutSheet(
      pieces: [
        PapercutPiece(
          id: 'paper',
          color: color,
          vertices: [
            Offset(center.dx - half, center.dy - half),
            Offset(center.dx + half, center.dy - half),
            Offset(center.dx + half, center.dy + half),
            Offset(center.dx - half, center.dy + half),
          ],
        ),
      ],
    ),
  );
  return area.copy(
    sheets: [...area.sheets, sheet],
    nextSheetId: area.nextSheetId + 1,
  );
}

/// Front to back, skipping hidden pieces.
List<String> piecesUnderAim(MixedCraftArea area, Offset aim) {
  final keys = <String>[];
  for (final sheet in area.sheets.reversed) {
    final indexes = piecesUnder(aim, sheet.paper);
    for (final index in indexes) {
      final piece = sheet.paper.pieces[index];
      final key = mixedPieceKey(sheet.id, piece.id);
      if (area.hidden.contains(key)) continue;
      keys.add(key);
    }
  }
  return keys;
}

Set<String> mixedMarqueeHits(MixedCraftArea area, Rect rect, MarqueePick pick) {
  final hits = <String>{};
  for (final sheet in area.sheets) {
    for (final piece in sheet.paper.pieces) {
      final key = mixedPieceKey(sheet.id, piece.id);
      if (area.hidden.contains(key)) continue;
      final ring = shownRing(
        piece.vertices,
        piece.separation,
        sheet.paper.folds,
        pieceId: piece.id,
      );
      if (polygonInMarquee(ring, rect, pick)) hits.add(key);
    }
  }
  return hits;
}

Offset snapCraft(Offset point, int scale, MixedCraftArea area) {
  final cell = scale.toDouble();
  final grid = Offset(
    (point.dx / cell).round() * cell,
    (point.dy / cell).round() * cell,
  );
  var best = grid;
  var bestDistance = (grid - point).distance;
  for (final segment in _creases(area)) {
    final on = _projectSegment(point, segment.$1, segment.$2);
    final distance = (on - point).distance;
    if (distance + 1e-6 < bestDistance) {
      best = on;
      bestDistance = distance;
    }
  }
  return best;
}

/// Piece under the reticle, front-most, for the cut and fold highlight.
String? pieceUnderAim(MixedCraftArea area, Offset aim) {
  final under = piecesUnderAim(area, aim);
  if (under.isEmpty) return null;
  return under.first;
}

Offset? selectionCenter(MixedCraftArea area) {
  final cloud = <Offset>[];
  for (final sheet in area.sheets) {
    for (final piece in sheet.paper.pieces) {
      if (!area.selected.contains(mixedPieceKey(sheet.id, piece.id))) continue;
      cloud.addAll(
        shownRing(
          piece.vertices,
          piece.separation,
          sheet.paper.folds,
          pieceId: piece.id,
        ),
      );
    }
  }
  if (cloud.isEmpty) return null;
  var center = Offset.zero;
  for (final point in cloud) {
    center += point;
  }
  return center / cloud.length.toDouble();
}

PapercutPiece? pieceForKey(MixedCraftArea area, String key) {
  for (final sheet in area.sheets) {
    for (final piece in sheet.paper.pieces) {
      if (mixedPieceKey(sheet.id, piece.id) == key) return piece;
    }
  }
  return null;
}

MixedCraftArea _replace(
  MixedCraftArea area,
  String sheetId,
  PapercutSheet paper,
) {
  final live = <String>{};
  for (final sheet in area.sheets) {
    final source = sheet.id == sheetId ? paper : sheet.paper;
    for (final piece in source.pieces) {
      live.add(mixedPieceKey(sheet.id, piece.id));
    }
  }
  return MixedCraftArea(
    sheets: [
      for (final sheet in area.sheets)
        sheet.id == sheetId ? MixedSheet(id: sheetId, paper: paper) : sheet,
    ],
    hidden: area.hidden.intersection(live),
    selected: area.selected.intersection(live),
    nextSheetId: area.nextSheetId,
  );
}

PapercutPiece? _pieceUnder(MixedSheet sheet, Offset point, Set<String> hidden) {
  final indexes = piecesUnder(point, sheet.paper);
  for (final index in indexes) {
    final piece = sheet.paper.pieces[index];
    if (hidden.contains(mixedPieceKey(sheet.id, piece.id))) continue;
    return piece;
  }
  return null;
}

bool _occupied(MixedCraftArea area, Offset center, double half) {
  final rect = Rect.fromCenter(
    center: center,
    width: half * 2,
    height: half * 2,
  );
  for (final sheet in area.sheets) {
    for (final piece in sheet.paper.pieces) {
      if (area.hidden.contains(mixedPieceKey(sheet.id, piece.id))) continue;
      final ring = shownRing(
        piece.vertices,
        piece.separation,
        sheet.paper.folds,
        pieceId: piece.id,
      );
      if (ring.isEmpty) continue;
      var minX = ring.first.dx;
      var minY = ring.first.dy;
      var maxX = ring.first.dx;
      var maxY = ring.first.dy;
      for (final point in ring) {
        minX = math.min(minX, point.dx);
        minY = math.min(minY, point.dy);
        maxX = math.max(maxX, point.dx);
        maxY = math.max(maxY, point.dy);
      }
      if (Rect.fromLTRB(minX, minY, maxX, maxY).overlaps(rect)) return true;
    }
  }
  return false;
}

List<(Offset, Offset)> _creases(MixedCraftArea area) {
  final lines = <(Offset, Offset)>[];
  for (final sheet in area.sheets) {
    for (final score in sheet.paper.scores) {
      lines.add((score.a, score.b));
    }
    for (final joint in sheet.paper.folds) {
      lines.add((
        displayPoint(joint.a, sheet.paper.folds),
        displayPoint(joint.b, sheet.paper.folds),
      ));
    }
  }
  return lines;
}

Offset _projectSegment(Offset point, Offset a, Offset b) {
  final d = b - a;
  final len2 = d.dx * d.dx + d.dy * d.dy;
  if (len2 < 1e-8) return a;
  final t = ((point.dx - a.dx) * d.dx + (point.dy - a.dy) * d.dy) / len2;
  final clamped = t.clamp(0.0, 1.0);
  return Offset(a.dx + d.dx * clamped, a.dy + d.dy * clamped);
}

Offset _quarter(Offset point, Offset center) {
  final rel = point - center;
  return center + Offset(-rel.dy, rel.dx);
}

bool _onRing(Offset point, List<Offset> ring) {
  if (ring.length < 3) return false;
  if (isInsidePolygon(point, ring)) return true;
  for (var i = 0; i < ring.length; i++) {
    final on = _projectSegment(point, ring[i], ring[(i + 1) % ring.length]);
    if ((on - point).distance <= 1e-2) return true;
  }
  return false;
}
