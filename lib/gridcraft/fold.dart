import 'dart:math' as math;
import 'dart:ui';

import '../crafting/paper_splitting.dart';
import '../geometry/geometry_algorithms.dart';
import '../geometry/polygon_union.dart';
import '../papercut/paper.dart';
import '../papercut/split.dart';
import 'blueprint.dart';

const _eps = 1e-4;

/// Fixed flashlight cone, measured from the facing axis to each side.
const double flashlightHalfAngle = 25 * math.pi / 180;

/// On and off fractions of one grid cell. The phase is the distance from the
/// world origin along the line, so every collinear mark shares one pattern.
const double foldDashFraction = 0.62;
const double foldGapFraction = 0.38;

/// Fold dashes use half a grid cell, so each dash and gap is half as long.
const double foldDashScale = 0.5;

/// How far a scored crease swings, as a fraction of a full fold.
const double creaseBendFraction = 0.1;

/// Share of the twitch spent lifting. The rest eases back to flat.
const double creaseLiftFraction = 0.32;

/// Bend at the end of the fold bar: 135°, three quarters of a fold.
const double foldPreviewEnd = 0.75;

/// Bend where the flap passes through edge-on. Past this, a release commits.
const double foldCommitBend = 0.5;

/// Where the 90° marks sit, as a fraction of the way from the center to an end.
const double foldCommitMark = foldCommitBend / foldPreviewEnd;

/// Signed position on the fold bar. [drag] is the finger offset along the bar
/// and [halfLength] is the distance from the center to either end.
double foldBarSigned(double drag, double halfLength) {
  if (halfLength.abs() < 1e-6) return 0;
  return (drag / halfLength).clamp(-1.0, 1.0);
}

/// Preview bend for a signed bar position. The ends are [foldPreviewEnd].
double foldPreviewBend(double signed) {
  return signed.abs().clamp(0.0, 1.0) * foldPreviewEnd;
}

/// True once the bubble has passed an edge-on mark.
bool foldPreviewCommits(double signed) {
  return signed.abs() > foldCommitMark;
}

double _easeOutCubic(double t) {
  final remaining = 1 - t.clamp(0.0, 1.0);
  return 1 - remaining * remaining * remaining;
}

/// Bend for a crease twitch. [t] is 0 at the press and 1 when it has settled.
///
/// The paper lifts quickly to [creaseBendFraction], then eases back to flat.
double creaseFoldBend(double t) {
  final u = t.clamp(0.0, 1.0);
  if (u <= creaseLiftFraction) {
    return creaseBendFraction * _easeOutCubic(u / creaseLiftFraction);
  }
  final back = (u - creaseLiftFraction) / (1 - creaseLiftFraction);
  return creaseBendFraction * (1 - _easeOutCubic(back));
}

/// Axis-aligned direction perpendicular to edge [a]–[b], pointing into [ring].
///
/// Horizontal when the edge is closer to vertical, vertical when it is closer
/// to horizontal. The scissors use the same snap for a cut into the paper.
Offset? axisPerpendicular(Offset a, Offset b, List<Offset> ring) {
  if (ring.length < 3) return null;
  final area = polygonSignedArea(ring);
  if (area.abs() < 1e-8) return null;
  final sign = area > 0 ? 1.0 : -1.0;
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  final nx = -dy * sign;
  final ny = dx * sign;
  if (nx.abs() < 1e-8 && ny.abs() < 1e-8) return null;
  return nx.abs() >= ny.abs() ? Offset(nx.sign, 0) : Offset(0, ny.sign);
}

/// Dashed pieces of [a]–[b]. A dash does not restart at the segment.
List<(Offset, Offset)> globalDashSegments(
  Offset a,
  Offset b, {
  double spacing = 1,
}) {
  final delta = b - a;
  final length = delta.distance;
  if (length < 1e-8) return const [];
  var direction = delta / length;
  if (direction.dx < -1e-9 ||
      (direction.dx.abs() <= 1e-9 && direction.dy < 0)) {
    direction = -direction;
  }
  final period = spacing <= 1e-8 ? 1.0 : spacing;
  final dash = period * foldDashFraction;
  double phase(Offset point) =>
      point.dx * direction.dx + point.dy * direction.dy;
  final alongA = phase(a);
  final alongB = phase(b);
  final lo = math.min(alongA, alongB);
  final hi = math.max(alongA, alongB);
  var cursor = lo - _floorMod(lo, period);
  final marks = <(Offset, Offset)>[];
  while (cursor < hi - 1e-9) {
    final start = math.max(cursor, lo);
    final end = math.min(cursor + dash, hi);
    if (end - start > 1e-4) {
      marks.add((
        a + direction * (start - alongA),
        a + direction * (end - alongA),
      ));
    }
    cursor += period;
  }
  return marks;
}

double _floorMod(double value, double period) {
  final remainder = value % period;
  return remainder < 0 ? remainder + period : remainder;
}

double sideOfLine(Offset point, Offset a, Offset b) {
  final ab = b - a;
  final ap = point - a;
  return ab.dx * ap.dy - ab.dy * ap.dx;
}

Offset reflectAcrossLine(Offset point, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 < _eps) return point;
  final t = ((point.dx - a.dx) * ab.dx + (point.dy - a.dy) * ab.dy) / len2;
  final foot = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
  return foot * 2 - point;
}

/// True when [joint] was scored on [pieceId] or on a piece it was cut from.
///
/// An empty [FoldJoint.pieceIds] set still applies to every piece.
bool foldJointOwnsPiece(FoldJoint joint, String pieceId) {
  if (joint.pieceIds.isEmpty) return true;
  if (joint.pieceIds.contains(pieceId)) return true;
  for (final id in joint.pieceIds) {
    if (pieceId.startsWith('$id-')) return true;
  }
  return false;
}

bool foldApplies(Offset point, FoldJoint joint, {String? pieceId}) {
  if (joint.facing == FoldFacing.unfolded) return false;
  if (pieceId != null && !foldJointOwnsPiece(joint, pieceId)) return false;
  final side = sideOfLine(point, joint.a, joint.b);
  if (side.abs() < _eps) return false;
  return side.sign == joint.side.sign;
}

/// Unfolded [point] moved onto the face the player sees.
///
/// [bend] is a joint still swinging onto the sheet. [bendT] 0 is flat,
/// 1 has landed on its reflection. The flap closes onto the crease at the
/// halfway point, which is the paper rotating through the edge-on pose.
Offset displayPoint(
  Offset point,
  List<FoldJoint> joints, {
  String? pieceId,
  int? bend,
  double bendT = 1,
}) {
  var current = point;
  for (var i = 0; i < joints.length; i++) {
    final joint = joints[i];
    if (!foldApplies(current, joint, pieceId: pieceId)) continue;
    if (i == bend && bendT < 1) {
      current = bendAcrossLine(current, joint.a, joint.b, bendT);
    } else {
      current = reflectAcrossLine(current, joint.a, joint.b);
    }
  }
  return current;
}

/// Moves [point] toward its reflection. [t] 0 stays put, 0.5 sits on the
/// crease, and 1 is the full reflection.
Offset bendAcrossLine(Offset point, Offset a, Offset b, double t) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 < _eps) return point;
  final along = ((point.dx - a.dx) * ab.dx + (point.dy - a.dy) * ab.dy) / len2;
  final foot = Offset(a.dx + ab.dx * along, a.dy + ab.dy * along);
  final scale = math.cos(t.clamp(0.0, 1.0) * math.pi);
  return foot + (point - foot) * scale;
}

List<Offset> displayRing(
  List<Offset> ring,
  List<FoldJoint> joints, {
  String? pieceId,
  int? bend,
  double bendT = 1,
}) {
  return [
    for (final point in ring)
      displayPoint(point, joints, pieceId: pieceId, bend: bend, bendT: bendT),
  ];
}

/// Positive draws above the sheet. Negative draws underneath.
int foldDepth(Offset point, List<FoldJoint> joints, {String? pieceId}) {
  var depth = 0;
  var current = point;
  for (final joint in joints) {
    if (!foldApplies(current, joint, pieceId: pieceId)) continue;
    depth += joint.facing == FoldFacing.toward ? 1 : -1;
    current = reflectAcrossLine(current, joint.a, joint.b);
  }
  return depth;
}

/// True when [point] has been turned an odd number of times.
///
/// [bend] is a joint still swinging. The back faces the player only after
/// that swing passes halfway, when the flap has come through edge-on.
bool showingBack(
  Offset point,
  List<FoldJoint> joints, {
  String? pieceId,
  int? bend,
  double bendT = 1,
}) {
  var flips = 0;
  var current = point;
  for (var i = 0; i < joints.length; i++) {
    final joint = joints[i];
    if (!foldApplies(current, joint, pieceId: pieceId)) continue;
    final swinging = i == bend && bendT < 1 - 1e-9;
    if (!swinging || bendT >= 0.5) flips++;
    current = swinging
        ? bendAcrossLine(current, joint.a, joint.b, bendT)
        : reflectAcrossLine(current, joint.a, joint.b);
  }
  return flips.isOdd;
}

/// One face of a piece while a joint is still swinging.
///
/// [ring] and [holes] are already in display space, before separation.
/// [back] is the pink side, and only a flap past edge-on sets it.
class SwingFace {
  const SwingFace({
    required this.ring,
    this.holes = const [],
    required this.back,
  });

  final List<Offset> ring;
  final List<List<Offset>> holes;
  final bool back;
}

/// Splits [ring] along the swinging joint, then bends only the flap.
///
/// Stationary faces come first. A flap that has collapsed onto the crease
/// (edge-on) is left out. [bend] indexes [joints].
List<SwingFace> swingFaces({
  required List<Offset> ring,
  List<List<Offset>> holes = const [],
  required List<FoldJoint> joints,
  required int bend,
  required double bendT,
  String? pieceId,
}) {
  if (ring.length < 3 || bend < 0 || bend >= joints.length) return const [];
  final joint = joints[bend];
  if (joint.facing == FoldFacing.unfolded) return const [];
  final posedRing = [
    for (final point in ring)
      _posedPoint(point, joints, pieceId: pieceId, end: bend),
  ];
  final posedHoles = [
    for (final hole in holes)
      [
        for (final point in hole)
          _posedPoint(point, joints, pieceId: pieceId, end: bend),
      ],
  ];
  final chords = _chordsOfLine(joint.a, joint.b, posedRing, posedHoles);
  final parts = splitPaperByCuts(posedRing, chords, holes: posedHoles);
  final stationary = <SwingFace>[];
  final flaps = <SwingFace>[];
  final showBack = bendT >= 0.5;
  for (final part in parts) {
    if (part.$1.length < 3) continue;
    final sample = _sampleInside(part.$1);
    final side = sideOfLine(sample, joint.a, joint.b);
    final flap = side.abs() >= _eps && side.sign == joint.side.sign;
    final shownRing = _swingRing(
      part.$1,
      joints,
      bend: bend,
      bendT: bendT,
      pieceId: pieceId,
      flap: flap,
    );
    if (polygonSignedArea(shownRing).abs() <= 1e-8) continue;
    final shownHoles = [
      for (final hole in part.$2)
        if (hole.length >= 3)
          _swingRing(
            hole,
            joints,
            bend: bend,
            bendT: bendT,
            pieceId: pieceId,
            flap: flap,
          ),
    ];
    final face = SwingFace(
      ring: shownRing,
      holes: shownHoles,
      back: flap && showBack,
    );
    if (flap) {
      flaps.add(face);
    } else {
      stationary.add(face);
    }
  }
  return [...stationary, ...flaps];
}

/// Grid segments of a swinging piece. A segment that crosses the crease is
/// cut there, and only the flap side is bent.
List<(Offset, Offset)> swingGridSegments({
  required List<(Offset, Offset)> segments,
  required List<FoldJoint> joints,
  required int bend,
  required double bendT,
  String? pieceId,
}) {
  if (bend < 0 || bend >= joints.length) return segments;
  final joint = joints[bend];
  final shown = <(Offset, Offset)>[];
  for (final segment in segments) {
    final a = _posedPoint(segment.$1, joints, pieceId: pieceId, end: bend);
    final b = _posedPoint(segment.$2, joints, pieceId: pieceId, end: bend);
    final sa = sideOfLine(a, joint.a, joint.b);
    final sb = sideOfLine(b, joint.a, joint.b);
    final crosses = sa.abs() >= _eps && sb.abs() >= _eps && sa.sign != sb.sign;
    if (!crosses) {
      _addSwingSegment(
        shown,
        a,
        b,
        joints,
        joint: joint,
        bend: bend,
        bendT: bendT,
        pieceId: pieceId,
      );
      continue;
    }
    final t = sa / (sa - sb);
    if (t <= 1e-6 || t >= 1 - 1e-6) {
      _addSwingSegment(
        shown,
        a,
        b,
        joints,
        joint: joint,
        bend: bend,
        bendT: bendT,
        pieceId: pieceId,
      );
      continue;
    }
    final hit = Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
    _addSwingSegment(
      shown,
      a,
      hit,
      joints,
      joint: joint,
      bend: bend,
      bendT: bendT,
      pieceId: pieceId,
    );
    _addSwingSegment(
      shown,
      hit,
      b,
      joints,
      joint: joint,
      bend: bend,
      bendT: bendT,
      pieceId: pieceId,
    );
  }
  return shown;
}

void _addSwingSegment(
  List<(Offset, Offset)> shown,
  Offset a,
  Offset b,
  List<FoldJoint> joints, {
  required FoldJoint joint,
  required int bend,
  required double bendT,
  required String? pieceId,
}) {
  Offset place(Offset point) {
    final side = sideOfLine(point, joint.a, joint.b);
    final flap = side.abs() >= _eps && side.sign == joint.side.sign;
    final bent = flap ? bendAcrossLine(point, joint.a, joint.b, bendT) : point;
    return _posedPoint(bent, joints, pieceId: pieceId, start: bend + 1);
  }

  final start = place(a);
  final end = place(b);
  if ((start - end).distance < 1e-6) return;
  shown.add((start, end));
}

List<Offset> _swingRing(
  List<Offset> ring,
  List<FoldJoint> joints, {
  required int bend,
  required double bendT,
  required String? pieceId,
  required bool flap,
}) {
  final joint = joints[bend];
  return [
    for (final point in ring)
      _posedPoint(
        flap ? bendAcrossLine(point, joint.a, joint.b, bendT) : point,
        joints,
        pieceId: pieceId,
        start: bend + 1,
      ),
  ];
}

Offset _posedPoint(
  Offset point,
  List<FoldJoint> joints, {
  String? pieceId,
  int start = 0,
  int? end,
}) {
  final last = end ?? joints.length;
  var current = point;
  for (var i = start; i < last; i++) {
    final joint = joints[i];
    if (!foldApplies(current, joint, pieceId: pieceId)) continue;
    current = reflectAcrossLine(current, joint.a, joint.b);
  }
  return current;
}

List<(Offset, Offset)> _chordsOfLine(
  Offset a,
  Offset b,
  List<Offset> ring,
  List<List<Offset>> holes,
) {
  final ab = b - a;
  final length = ab.distance;
  if (length < _eps || ring.length < 3) return const [];
  final bounds = _ringBounds(ring);
  if (bounds == null) return const [];
  final unit = ab / length;
  final reach = bounds.width + bounds.height + length + 1;
  return _clipSpanToSolid(a - unit * reach, a + unit * reach, ring, holes);
}

Offset _sampleInside(List<Offset> ring) {
  if (ring.length < 3) return ring.isEmpty ? Offset.zero : ring.first;
  final centroid = polygonCentroid(ring);
  if (isInsidePolygon(centroid, ring)) return centroid;
  const offset = 1e-4;
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    final edge = b - a;
    final len = edge.distance;
    if (len < 1e-8) continue;
    final normal = Offset(-edge.dy / len, edge.dx / len);
    final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    final left = mid + normal * offset;
    if (isInsidePolygon(left, ring)) return left;
    final right = mid - normal * offset;
    if (isInsidePolygon(right, ring)) return right;
  }
  return centroid;
}

/// Maps a point on the displayed sheet back to unfolded coordinates.
Offset localPoint(Offset visual, List<FoldJoint> joints, {String? pieceId}) {
  var current = visual;
  for (final joint in joints.reversed) {
    if (joint.facing == FoldFacing.unfolded) continue;
    final reflected = reflectAcrossLine(current, joint.a, joint.b);
    if (foldApplies(reflected, joint, pieceId: pieceId)) current = reflected;
  }
  return current;
}

int topPieceIndex(Offset visual, PapercutSheet sheet) {
  var best = -1;
  var bestDepth = -1 << 30;
  for (var i = 0; i < sheet.pieces.length; i++) {
    final piece = sheet.pieces[i];
    final local = localPoint(visual, sheet.folds, pieceId: piece.id);
    if (!isInsidePolygon(local, piece.vertices)) continue;
    var inHole = false;
    for (final hole in piece.holes) {
      if (isInsidePolygon(local, hole)) inHole = true;
    }
    if (inHole) continue;
    final depth = foldDepth(
      polygonCentroid(piece.vertices),
      sheet.folds,
      pieceId: piece.id,
    );
    if (depth >= bestDepth) {
      bestDepth = depth;
      best = i;
    }
  }
  return best;
}

PapercutSheet addPaperMark(PapercutSheet sheet, List<Offset> visualStroke) {
  if (visualStroke.length < 2) return sheet;
  final index = topPieceIndex(visualStroke.first, sheet);
  if (index < 0) return sheet;
  final local = [
    for (final point in visualStroke)
      localPoint(point, sheet.folds, pieceId: sheet.pieces[index].id),
  ];
  if (!isInsidePolygon(local.first, sheet.pieces[index].vertices)) return sheet;
  return sheet.copyWith(
    marks: [
      ...sheet.marks,
      PaperMark(points: local),
    ],
  );
}

/// Folds the side of [span] indicated by [flapPoint].
///
/// Returns null when the fold meets a no-fold zone or a blueprint piece that
/// overlaps one. [record] is false so the crease is a joint, not a cut.
PapercutSheet? foldSheet({
  required PapercutSheet sheet,
  required Offset spanA,
  required Offset spanB,
  required Offset flapPoint,
  required FoldFacing facing,
  List<List<Offset>> noFold = const [],
  List<List<Offset>> blueprintPieces = const [],
  Offset cutShift = Offset.zero,
  String? pieceId,
}) {
  if (facing == FoldFacing.unfolded) return null;
  final side = sideOfLine(flapPoint, spanA, spanB);
  if (side.abs() < _eps) return null;
  if (_creaseBlocked(
    sheet,
    spanA,
    spanB,
    flapPoint,
    noFold: noFold,
    blueprintPieces: blueprintPieces,
    pieceId: pieceId,
  )) {
    return null;
  }
  // [span] is the crease with separation removed. The cut is where the paper
  // is drawn, so the dragged sheet and anything under it are both split
  // unless [pieceId] names the only sheet that should fold.
  final shift = cutShift == Offset.zero
      ? _sharedSeparation(sheet, spanA, spanB)
      : cutShift;
  final split = cutThroughFolds(
    sheet,
    [spanA + shift, spanB + shift],
    recordStroke: false,
    onlyPieceId: pieceId,
  );
  if (split == null) return null;
  final next = split;
  return next.copyWith(
    folds: [
      ...next.folds,
      FoldJoint(
        a: spanA,
        b: spanB,
        side: side,
        facing: facing,
        pieceIds: _flapPieceIds(
          before: sheet,
          after: next,
          onlyPieceId: pieceId,
          a: spanA,
          b: spanB,
          side: side,
        ),
      ),
    ],
  );
}

/// Pieces produced from the folded sheet that lie on the flap side of [a]–[b].
Set<String> _flapPieceIds({
  required PapercutSheet before,
  required PapercutSheet after,
  required String? onlyPieceId,
  required Offset a,
  required Offset b,
  required double side,
}) {
  final beforeIds = {for (final piece in before.pieces) piece.id};
  final sources = onlyPieceId == null
      ? beforeIds.where((id) => !after.pieces.any((piece) => piece.id == id))
      : {onlyPieceId};
  final ids = <String>{};
  for (final piece in after.pieces) {
    final fromSource = sources.any(
      (source) => piece.id == source || piece.id.startsWith('$source-'),
    );
    if (!fromSource) continue;
    final signed = sideOfLine(polygonCentroid(piece.vertices), a, b);
    if (signed.abs() < _eps || signed.sign != side.sign) continue;
    ids.add(piece.id);
  }
  if (ids.isEmpty && onlyPieceId != null) ids.add(onlyPieceId);
  return ids;
}

bool _creaseBlocked(
  PapercutSheet sheet,
  Offset a,
  Offset b,
  Offset flapPoint, {
  required List<List<Offset>> noFold,
  required List<List<Offset>> blueprintPieces,
  String? pieceId,
}) {
  final localA = localPoint(a, sheet.folds, pieceId: pieceId);
  final localB = localPoint(b, sheet.folds, pieceId: pieceId);
  final localFlap = localPoint(flapPoint, sheet.folds, pieceId: pieceId);
  final layers = <(Offset, Offset, Offset)>[(localA, localB, localFlap)];
  for (final joint in sheet.folds) {
    if (joint.facing == FoldFacing.unfolded) continue;
    layers.add((
      reflectAcrossLine(localA, joint.a, joint.b),
      reflectAcrossLine(localB, joint.a, joint.b),
      reflectAcrossLine(localFlap, joint.a, joint.b),
    ));
  }
  for (final layer in layers) {
    final layerSide = sideOfLine(layer.$3, layer.$1, layer.$2);
    if (layerSide.abs() < _eps) continue;
    if (_foldBlocked(
      sheet: sheet,
      a: layer.$1,
      b: layer.$2,
      side: layerSide,
      noFold: noFold,
      blueprintPieces: blueprintPieces,
    )) {
      return true;
    }
  }
  return false;
}

/// Where the folder hinge will land, and the side that folds.
class FolderGuide {
  const FolderGuide({
    required this.line,
    required this.flap,
    required this.separation,
    required this.pieceId,
  });

  /// Crease in display space, with [separation] removed, for [foldSheet].
  ///
  /// The segment under the reticle, bounded by cuts and paper edges. The
  /// crease runs perpendicular to the nearest edge.
  final (Offset, Offset) line;

  /// A point on the side that folds. Null when the cursor sits on the crease.
  ///
  /// The cursor's side stays flat.
  final Offset? flap;

  /// Drawn shift of the paper the crease belongs to.
  final Offset separation;

  /// Topmost paper piece the crease segment belongs to.
  final String pieceId;

  /// [line] where the player sees it, including [separation].
  (Offset, Offset) get drawn => (line.$1 + separation, line.$2 + separation);
}

/// Crease on the paper under the reticle, perpendicular to the nearest edge.
///
/// The grid line is split by every paper edge, hole, and cut. The segment
/// that contains the reticle is the one that folds. Returns null when [aim]
/// is more than one grid cell from every paper piece. The cursor's side of
/// the crease stays flat.
FolderGuide? folderGuide(Offset aim, PapercutSheet sheet, double spacing) {
  if (spacing <= 0 || sheet.pieces.isEmpty) return null;
  var bestIndex = -1;
  var bestDistance = double.infinity;
  var bestDepth = -1 << 30;
  for (var i = 0; i < sheet.pieces.length; i++) {
    final piece = sheet.pieces[i];
    final ring = _drawnRing(
      piece.vertices,
      piece.separation,
      sheet.folds,
      pieceId: piece.id,
    );
    final holes = [
      for (final hole in piece.holes)
        _drawnRing(hole, piece.separation, sheet.folds, pieceId: piece.id),
    ];
    final distance = _distanceToSolid(aim, ring, holes);
    final depth = foldDepth(
      polygonCentroid(piece.vertices),
      sheet.folds,
      pieceId: piece.id,
    );
    final closer = distance < bestDistance - 1e-6;
    final tied = (distance - bestDistance).abs() <= 1e-6 && depth > bestDepth;
    if (!closer && !tied) continue;
    bestIndex = i;
    bestDistance = distance;
    bestDepth = depth;
  }
  if (bestIndex < 0 || bestDistance > spacing) return null;
  final piece = sheet.pieces[bestIndex];
  final ring = _drawnRing(
    piece.vertices,
    piece.separation,
    sheet.folds,
    pieceId: piece.id,
  );
  final edge = _nearestEdge(aim, ring);
  if (edge == null) return null;
  final direction = axisPerpendicular(edge.$1, edge.$2, ring);
  if (direction == null) return null;
  final span = _gridCrease(
    aim: aim,
    direction: direction,
    ring: ring,
    sheet: sheet,
    spacing: spacing,
  );
  if (span == null) return null;
  final mid = Offset.lerp(span.$1, span.$2, 0.5)!;
  final owner = _topPieceAt(aim, sheet) ?? _topPieceAt(mid, sheet);
  if (owner == null) return null;
  final shift = owner.separation;
  final flapDrawn = _oppositeFlap(aim, span.$1, span.$2, spacing);
  return FolderGuide(
    line: (span.$1 - shift, span.$2 - shift),
    flap: flapDrawn == null ? null : flapDrawn - shift,
    separation: shift,
    pieceId: owner.id,
  );
}

/// Drawn crease within [reach] of [point], or null when none can unfold.
///
/// The latest fold wins. Distance is measured where the crease is drawn.
(Offset, Offset)? unfoldCue(
  PapercutSheet sheet,
  Offset point, {
  double reach = 0.45,
}) {
  return _unfoldHit(sheet, point, reach: reach)?.drawn;
}

PapercutSheet? unfoldAt(
  PapercutSheet sheet,
  Offset point, {
  double reach = 0.45,
}) {
  final hit = _unfoldHit(sheet, point, reach: reach);
  if (hit == null) return null;
  final folds = [...sheet.folds];
  final joint = folds[hit.index];
  final layers = _creaseLayers(joint, sheet.folds.sublist(0, hit.index));
  folds[hit.index] = joint.copyWith(facing: FoldFacing.unfolded);
  final scored = sheet.scores.any((score) => _sameLine(score, joint));
  return _rejoinAcross(
    sheet.copyWith(
      folds: folds,
      scores: scored
          ? sheet.scores
          : [...sheet.scores, ScoreLine(joint.a, joint.b)],
    ),
    layers,
  );
}

bool _sameLine(ScoreLine score, FoldJoint joint) {
  bool near(Offset p, Offset q) => (p - q).distance < 1e-3;
  return (near(score.a, joint.a) && near(score.b, joint.b)) ||
      (near(score.a, joint.b) && near(score.b, joint.a));
}

/// Where [joint] split the paper, in unfolded coordinates.
///
/// [foldSheet] cuts the crease through every layer showing at the time, the
/// same way [cutThroughFolds] does, so each layer's copy is listed.
List<(Offset, Offset)> _creaseLayers(FoldJoint joint, List<FoldJoint> earlier) {
  final a = localPoint(joint.a, earlier);
  final b = localPoint(joint.b, earlier);
  return [
    (a, b),
    for (final other in earlier)
      if (other.facing != FoldFacing.unfolded)
        (
          reflectAcrossLine(a, other.a, other.b),
          reflectAcrossLine(b, other.a, other.b),
        ),
  ];
}

/// Joins paper pieces that meet along one of [lines] back into one piece.
///
/// A fold splits the paper on its crease without recording a cut. Once it
/// opens, the two sides are one sheet again, so the crease can fold again.
/// An edge that lies on a recorded cut stroke stays apart.
PapercutSheet _rejoinAcross(PapercutSheet sheet, List<(Offset, Offset)> lines) {
  var pieces = [...sheet.pieces];
  var joined = true;
  while (joined) {
    joined = false;
    for (var i = 0; i < pieces.length && !joined; i++) {
      for (var j = i + 1; j < pieces.length; j++) {
        final merged = _joinPieces(
          pieces[i],
          pieces[j],
          lines,
          sheet.cutStrokes,
        );
        if (merged == null) continue;
        pieces = [
          for (var k = 0; k < pieces.length; k++)
            if (k == i) merged else if (k != j) pieces[k],
        ];
        joined = true;
        break;
      }
    }
  }
  return sheet.copyWith(pieces: pieces);
}

PapercutPiece? _joinPieces(
  PapercutPiece p,
  PapercutPiece q,
  List<(Offset, Offset)> lines,
  List<List<Offset>> cuts,
) {
  if (p.color != q.color) return null;
  if ((p.separation - q.separation).distance > 1e-6) return null;
  if (!_shareCrease(p.vertices, q.vertices, lines, cuts)) return null;
  final union = unionPolygons([p.vertices, q.vertices]);
  final joined = _pieceFromLoops(union, p, q);
  if (joined != null) return joined;
  // Collinear crease edges do not always split into one shared run, so the
  // union keeps the two notches apart. Drop the shared crease and trace what
  // remains: the sheet, and the hole where a cut crossed the fold.
  return _pieceFromLoops(_stitchRings(p.vertices, q.vertices), p, q);
}

PapercutPiece? _pieceFromLoops(
  List<List<Offset>> loops,
  PapercutPiece p,
  PapercutPiece q,
) {
  if (loops.isEmpty) return null;
  var outer = 0;
  for (var i = 1; i < loops.length; i++) {
    if (polygonSignedArea(loops[i]).abs() >
        polygonSignedArea(loops[outer]).abs()) {
      outer = i;
    }
  }
  final sign = polygonSignedArea(loops[outer]).sign;
  final gaps = <List<Offset>>[];
  for (var i = 0; i < loops.length; i++) {
    if (i == outer) continue;
    var loop = loops[i];
    if (polygonSignedArea(loop).sign == sign) {
      if (!isInsidePolygon(polygonCentroid(loop), loops[outer])) return null;
      loop = loop.reversed.toList();
    }
    gaps.add(loop);
  }
  return PapercutPiece(
    id: p.id,
    color: p.color,
    backColor: p.backColor,
    vertices: _dropCollinear(loops[outer]),
    holes: [...p.holes, ...q.holes, ...gaps],
    separation: p.separation,
  );
}

/// Boundary left after cancelling edges the two rings share.
///
/// Shared crease runs drop out. A cut that met the crease on both layers
/// leaves those arcs as their own loop.
List<List<Offset>> _stitchRings(List<Offset> p, List<Offset> q) {
  final counts = <String, int>{};
  final directed = <String, (Offset, Offset)>{};
  void add(List<Offset> ring) {
    for (var i = 0; i < ring.length; i++) {
      final a = ring[i];
      final b = ring[(i + 1) % ring.length];
      if ((a - b).distance < 1e-8) continue;
      final id = _edgeKey(a, b);
      counts[id] = (counts[id] ?? 0) + 1;
      directed[id] = (a, b);
    }
  }

  add(p);
  add(q);
  final kept = <(Offset, Offset)>[
    for (final entry in counts.entries)
      if (entry.value == 1) directed[entry.key]!,
  ];
  return _traceLoops(kept);
}

String _edgeKey(Offset a, Offset b) {
  String key(Offset point) =>
      '${(point.dx * 1e3).round()},${(point.dy * 1e3).round()}';
  final ka = key(a);
  final kb = key(b);
  return ka.compareTo(kb) <= 0 ? '$ka|$kb' : '$kb|$ka';
}

List<List<Offset>> _traceLoops(List<(Offset, Offset)> segments) {
  if (segments.isEmpty) return const [];
  String key(Offset point) =>
      '${(point.dx * 1e3).round()},${(point.dy * 1e3).round()}';
  final next = <String, List<int>>{};
  for (var i = 0; i < segments.length; i++) {
    next.putIfAbsent(key(segments[i].$1), () => []).add(i);
  }
  final used = List<bool>.filled(segments.length, false);
  final loops = <List<Offset>>[];
  for (var start = 0; start < segments.length; start++) {
    if (used[start]) continue;
    final loop = <Offset>[];
    var current = start;
    while (!used[current]) {
      used[current] = true;
      loop.add(segments[current].$1);
      final options = next[key(segments[current].$2)];
      int? follow;
      if (options != null) {
        for (final candidate in options) {
          if (!used[candidate]) {
            follow = candidate;
            break;
          }
        }
      }
      if (follow == null) break;
      current = follow;
    }
    if (loop.length >= 3) loops.add(loop);
  }
  return loops;
}

/// True when [p] and [q] have overlapping edges on one of [lines] that no
/// cut stroke covers.
bool _shareCrease(
  List<Offset> p,
  List<Offset> q,
  List<(Offset, Offset)> lines,
  List<List<Offset>> cuts,
) {
  for (final line in lines) {
    final axis = line.$2 - line.$1;
    final length = axis.distance;
    if (length < _eps) continue;
    final unit = axis / length;
    bool onLine(Offset point) =>
        sideOfLine(point, line.$1, line.$2).abs() / length <= 1e-3;
    double along(Offset point) =>
        (point.dx - line.$1.dx) * unit.dx + (point.dy - line.$1.dy) * unit.dy;
    for (var i = 0; i < p.length; i++) {
      final a = p[i];
      final b = p[(i + 1) % p.length];
      if (!onLine(a) || !onLine(b)) continue;
      for (var k = 0; k < q.length; k++) {
        final c = q[k];
        final d = q[(k + 1) % q.length];
        if (!onLine(c) || !onLine(d)) continue;
        final lo = math.max(
          math.min(along(a), along(b)),
          math.min(along(c), along(d)),
        );
        final hi = math.min(
          math.max(along(a), along(b)),
          math.max(along(c), along(d)),
        );
        if (hi - lo <= 1e-3) continue;
        final mid = line.$1 + unit * ((lo + hi) / 2);
        if (_onStroke(mid, cuts)) continue;
        return true;
      }
    }
  }
  return false;
}

bool _onStroke(Offset point, List<List<Offset>> strokes) {
  for (final stroke in strokes) {
    for (var i = 0; i < stroke.length - 1; i++) {
      if (_distanceToSegment(point, stroke[i], stroke[i + 1]) <= 1e-3) {
        return true;
      }
    }
  }
  return false;
}

List<Offset> _dropCollinear(List<Offset> ring) {
  if (ring.length <= 3) return ring;
  final kept = <Offset>[];
  for (var i = 0; i < ring.length; i++) {
    final prev = ring[(i - 1 + ring.length) % ring.length];
    final here = ring[i];
    final next = ring[(i + 1) % ring.length];
    final into = here - prev;
    final out = next - here;
    final cross = into.dx * out.dy - into.dy * out.dx;
    final dot = into.dx * out.dx + into.dy * out.dy;
    final scale = into.distance * out.distance;
    if (scale > 1e-12 && cross.abs() / scale < 1e-6 && dot > 0) continue;
    kept.add(here);
  }
  return kept.length >= 3 ? kept : ring;
}

class _UnfoldHit {
  const _UnfoldHit({required this.index, required this.drawn});

  final int index;
  final (Offset, Offset) drawn;
}

_UnfoldHit? _unfoldHit(
  PapercutSheet sheet,
  Offset point, {
  required double reach,
}) {
  for (var i = sheet.folds.length - 1; i >= 0; i--) {
    final joint = sheet.folds[i];
    if (joint.facing == FoldFacing.unfolded) continue;
    (Offset, Offset)? closest;
    var closestDistance = reach;
    for (final part in _drawnCrease(joint, sheet)) {
      final distance = _distanceToSegment(point, part.$1, part.$2);
      if (distance > closestDistance) continue;
      closest = part;
      closestDistance = distance;
    }
    if (closest != null) return _UnfoldHit(index: i, drawn: closest);
  }
  return null;
}

List<(Offset, Offset)> _drawnCrease(FoldJoint joint, PapercutSheet sheet) {
  final drawn = <(Offset, Offset)>[];
  for (final piece in sheet.pieces) {
    if (joint.pieceIds.isNotEmpty && !foldJointOwnsPiece(joint, piece.id)) {
      continue;
    }
    final parts = _clipSpanToSolid(
      joint.a,
      joint.b,
      piece.vertices,
      piece.holes,
    );
    for (final part in parts) {
      drawn.add((
        displayPoint(part.$1, sheet.folds, pieceId: piece.id) +
            piece.separation,
        displayPoint(part.$2, sheet.folds, pieceId: piece.id) +
            piece.separation,
      ));
    }
  }
  if (drawn.isEmpty) {
    drawn.add((
      displayPoint(joint.a, sheet.folds),
      displayPoint(joint.b, sheet.folds),
    ));
  }
  return drawn;
}

/// [ring] where the player sees it: folded, then shifted by [separation].
List<Offset> shownRing(
  List<Offset> ring,
  Offset separation,
  List<FoldJoint> folds, {
  String? pieceId,
  int? bend,
  double bendT = 1,
}) {
  return [
    for (final point in ring)
      displayPoint(point, folds, pieceId: pieceId, bend: bend, bendT: bendT) +
          separation,
  ];
}

List<Offset> _drawnRing(
  List<Offset> ring,
  Offset separation,
  List<FoldJoint> folds, {
  String? pieceId,
}) {
  return shownRing(ring, separation, folds, pieceId: pieceId);
}

double _distanceToSolid(
  Offset aim,
  List<Offset> ring,
  List<List<Offset>> holes,
) {
  if (ring.length < 3) return double.infinity;
  if (isInsidePolygon(aim, ring)) {
    for (final hole in holes) {
      if (hole.length < 3) continue;
      if (isInsidePolygon(aim, hole) && _distanceToRing(aim, hole) > 1e-3) {
        return _distanceToRing(aim, hole);
      }
    }
    return 0;
  }
  return _distanceToRing(aim, ring);
}

double _distanceToRing(Offset point, List<Offset> ring) {
  if (ring.isEmpty) return double.infinity;
  var best = double.infinity;
  for (var i = 0; i < ring.length; i++) {
    final next = ring[(i + 1) % ring.length];
    final distance = _distanceToSegment(point, ring[i], next);
    if (distance < best) best = distance;
  }
  return best;
}

(Offset, Offset)? _nearestEdge(Offset aim, List<Offset> ring) {
  if (ring.length < 2) return null;
  (Offset, Offset)? best;
  var bestDistance = double.infinity;
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    final distance = _distanceToSegment(aim, a, b);
    if (distance >= bestDistance) continue;
    best = (a, b);
    bestDistance = distance;
  }
  return best;
}

(Offset, Offset)? _gridCrease({
  required Offset aim,
  required Offset direction,
  required List<Offset> ring,
  required PapercutSheet sheet,
  required double spacing,
}) {
  final bounds = _ringBounds(ring);
  final all = _drawnBounds(sheet) ?? bounds;
  if (bounds == null || all == null) return null;
  final horizontal = direction.dx.abs() >= direction.dy.abs();
  final values = horizontal
      ? _interiorGrid(bounds.top, bounds.bottom, spacing)
      : _interiorGrid(bounds.left, bounds.right, spacing);
  values.sort((a, b) {
    final origin = horizontal ? aim.dy : aim.dx;
    return (a - origin).abs().compareTo((b - origin).abs());
  });
  for (final value in values) {
    final a = horizontal
        ? Offset(all.left - spacing, value)
        : Offset(value, all.top - spacing);
    final b = horizontal
        ? Offset(all.right + spacing, value)
        : Offset(value, all.bottom + spacing);
    final span = _spanUnderAim(aim, _spansAlongLine(a, b, sheet));
    if (span == null) continue;
    if ((span.$2 - span.$1).distance <= _eps) continue;
    return span;
  }
  return null;
}

/// Cell edges of [ring], clipped to the paper and kept out of [holes].
List<(Offset, Offset)> paperGridSegments({
  required List<Offset> ring,
  required List<List<Offset>> holes,
  required double spacing,
}) {
  if (spacing <= 0) return const [];
  final bounds = _ringBounds(ring);
  if (bounds == null) return const [];
  final spans = <(Offset, Offset)>[];
  for (final y in _interiorGrid(bounds.top, bounds.bottom, spacing)) {
    spans.addAll(
      _clipSpanToSolid(
        Offset(bounds.left - spacing, y),
        Offset(bounds.right + spacing, y),
        ring,
        holes,
      ),
    );
  }
  for (final x in _interiorGrid(bounds.left, bounds.right, spacing)) {
    spans.addAll(
      _clipSpanToSolid(
        Offset(x, bounds.top - spacing),
        Offset(x, bounds.bottom + spacing),
        ring,
        holes,
      ),
    );
  }
  return spans;
}

/// Scores [a]–[b] without splitting the paper or leaving a fold.
PapercutSheet scoreCrease(PapercutSheet sheet, Offset a, Offset b) {
  if ((a - b).distance <= _eps) return sheet;
  return sheet.copyWith(scores: [...sheet.scores, ScoreLine(a, b)]);
}

/// Unit normal to the left of the directed crease [a] → [b].
Offset? creaseLeftNormal(Offset a, Offset b) {
  final ab = b - a;
  final length = ab.distance;
  if (length < _eps) return null;
  return Offset(-ab.dy, ab.dx) / length;
}

/// Point on the side of [creaseA]–[creaseB] that [drag] leaves behind.
///
/// A drag toward +x folds the −x side over it. [origin] is a point on the
/// crease, in the same space as [drag].
Offset? flapForPerpendicularDrag({
  required Offset drag,
  required Offset creaseA,
  required Offset creaseB,
  required Offset origin,
}) {
  final normal = creaseLeftNormal(creaseA, creaseB);
  if (normal == null || drag.distance < _eps) return null;
  final along = drag.dx * normal.dx + drag.dy * normal.dy;
  if (along.abs() < _eps) return null;
  final trailing = along > 0 ? -normal : normal;
  final length = (creaseB - creaseA).distance;
  return origin + trailing * (length * 0.25 + 0.25);
}

Rect? _drawnBounds(PapercutSheet sheet) {
  Offset? min;
  Offset? max;
  void grow(Offset point) {
    final lo = min;
    final hi = max;
    if (lo == null || hi == null) {
      min = point;
      max = point;
      return;
    }
    min = Offset(math.min(lo.dx, point.dx), math.min(lo.dy, point.dy));
    max = Offset(math.max(hi.dx, point.dx), math.max(hi.dy, point.dy));
  }

  for (final piece in sheet.pieces) {
    final ring = _drawnRing(
      piece.vertices,
      piece.separation,
      sheet.folds,
      pieceId: piece.id,
    );
    for (final point in ring) {
      grow(point);
    }
  }
  final lo = min;
  final hi = max;
  if (lo == null || hi == null) return null;
  if ((hi.dx - lo.dx).abs() < _eps && (hi.dy - lo.dy).abs() < _eps) return null;
  return Rect.fromLTRB(lo.dx, lo.dy, hi.dx, hi.dy);
}

/// Spans of [a]–[b] that sit on paper, split by piece edges and cuts.
List<(Offset, Offset)> _spansAlongLine(
  Offset a,
  Offset b,
  PapercutSheet sheet,
) {
  final delta = b - a;
  final length = delta.distance;
  if (length < 1e-8 || sheet.pieces.isEmpty) return const [];
  final parameters = <double>[0, 1];
  void addPoint(Offset point) {
    parameters.add(parameterOnSegment(a, b, point).clamp(0.0, 1.0));
  }

  void addSegment(Offset c, Offset d) {
    final hit = segmentIntersection(a, b, c, d);
    if (hit.isPoint && hit.point != null) {
      addPoint(hit.point!);
    } else if (hit.isCollinear) {
      final start = hit.segmentStart;
      final end = hit.segmentEnd;
      if (start != null) addPoint(start);
      if (end != null) addPoint(end);
    }
  }

  void addRing(List<Offset> edges) {
    if (edges.length < 2) return;
    for (var i = 0; i < edges.length; i++) {
      addSegment(edges[i], edges[(i + 1) % edges.length]);
    }
  }

  for (final piece in sheet.pieces) {
    addRing(
      _drawnRing(
        piece.vertices,
        piece.separation,
        sheet.folds,
        pieceId: piece.id,
      ),
    );
    for (final hole in piece.holes) {
      addRing(
        _drawnRing(hole, piece.separation, sheet.folds, pieceId: piece.id),
      );
    }
    for (final stroke in sheet.cutStrokes) {
      for (final chain in clipStrokePolylines(stroke, piece)) {
        final shown = [
          for (final point in chain)
            displayPoint(point, sheet.folds, pieceId: piece.id) +
                piece.separation,
        ];
        for (var i = 0; i < shown.length - 1; i++) {
          addSegment(shown[i], shown[i + 1]);
        }
      }
    }
  }
  parameters.sort();
  Offset at(double t) => Offset(a.dx + delta.dx * t, a.dy + delta.dy * t);
  final kept = <(Offset, Offset)>[];
  for (var i = 0; i < parameters.length - 1; i++) {
    final t0 = parameters[i];
    final t1 = parameters[i + 1];
    if ((t1 - t0) * length < 1e-4) continue;
    final mid = at((t0 + t1) / 2);
    if (_topPieceAt(mid, sheet) == null) continue;
    kept.add((at(t0), at(t1)));
  }
  return kept;
}

/// Segment of [parts] whose projection contains [aim], preferring the
/// midpoint nearest [aim] when the reticle sits on a boundary.
(Offset, Offset)? _spanUnderAim(Offset aim, List<(Offset, Offset)> parts) {
  (Offset, Offset)? best;
  var bestDistance = double.infinity;
  for (final part in parts) {
    final ab = part.$2 - part.$1;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 < 1e-12) continue;
    final t =
        ((aim.dx - part.$1.dx) * ab.dx + (aim.dy - part.$1.dy) * ab.dy) / len2;
    if (t < -1e-4 || t > 1 + 1e-4) continue;
    final mid = Offset.lerp(part.$1, part.$2, 0.5)!;
    final distance = (mid - aim).distance;
    if (distance >= bestDistance) continue;
    best = part;
    bestDistance = distance;
  }
  return best;
}

/// Highest paper under [point], later pieces winning a depth tie.
PapercutPiece? _topPieceAt(Offset point, PapercutSheet sheet) {
  PapercutPiece? best;
  var bestDepth = -1 << 30;
  var bestIndex = -1;
  for (var i = 0; i < sheet.pieces.length; i++) {
    final piece = sheet.pieces[i];
    final ring = _drawnRing(
      piece.vertices,
      piece.separation,
      sheet.folds,
      pieceId: piece.id,
    );
    final holes = [
      for (final hole in piece.holes)
        _drawnRing(hole, piece.separation, sheet.folds, pieceId: piece.id),
    ];
    if (_distanceToSolid(point, ring, holes) > 1e-3) continue;
    final depth = foldDepth(
      polygonCentroid(piece.vertices),
      sheet.folds,
      pieceId: piece.id,
    );
    if (depth < bestDepth || (depth == bestDepth && i < bestIndex)) continue;
    best = piece;
    bestDepth = depth;
    bestIndex = i;
  }
  return best;
}

List<double> _interiorGrid(double min, double max, double spacing) {
  final lines = <double>[];
  var value = (min / spacing).ceil() * spacing;
  if ((value - min).abs() < 1e-3) value += spacing;
  for (; value < max - 1e-3; value += spacing) {
    lines.add(value);
  }
  return lines;
}

Rect? _ringBounds(List<Offset> ring) {
  if (ring.isEmpty) return null;
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
  if (maxX - minX < _eps || maxY - minY < _eps) return null;
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

/// Point on the side of [a]–[b] opposite [aim]. Null when [aim] is on the line.
Offset? _oppositeFlap(Offset aim, Offset a, Offset b, double spacing) {
  final side = sideOfLine(aim, a, b);
  if (side.abs() < 1e-3) return null;
  final ab = b - a;
  final length = ab.distance;
  if (length < _eps) return null;
  final positive = Offset(-ab.dy, ab.dx) / length;
  final toward = side > 0 ? -positive : positive;
  final across = _distanceToSegment(aim, a, b) * 2 + spacing * 0.25;
  return aim + toward * across;
}

List<(Offset, Offset)> _clipSpanToSolid(
  Offset a,
  Offset b,
  List<Offset> ring,
  List<List<Offset>> holes,
) {
  final delta = b - a;
  if (delta.distance < 1e-8 || ring.length < 3) return const [];
  final parameters = <double>[0, 1];
  void addRing(List<Offset> edges) {
    for (var i = 0; i < edges.length; i++) {
      final hit = segmentIntersection(
        a,
        b,
        edges[i],
        edges[(i + 1) % edges.length],
      );
      if (hit.isPoint && hit.point != null) {
        parameters.add(parameterOnSegment(a, b, hit.point!).clamp(0.0, 1.0));
      } else if (hit.isCollinear) {
        final start = hit.segmentStart;
        final end = hit.segmentEnd;
        if (start != null) {
          parameters.add(parameterOnSegment(a, b, start).clamp(0.0, 1.0));
        }
        if (end != null) {
          parameters.add(parameterOnSegment(a, b, end).clamp(0.0, 1.0));
        }
      }
    }
  }

  addRing(ring);
  for (final hole in holes) {
    addRing(hole);
  }
  parameters.sort();
  Offset at(double t) => Offset(a.dx + delta.dx * t, a.dy + delta.dy * t);
  bool owns(Offset point) {
    if (!isInsidePolygon(point, ring) && _distanceToRing(point, ring) > 1e-3) {
      return false;
    }
    for (final hole in holes) {
      if (hole.length < 3) continue;
      if (isInsidePolygon(point, hole) && _distanceToRing(point, hole) > 1e-3) {
        return false;
      }
    }
    return true;
  }

  final kept = <(Offset, Offset)>[];
  for (var i = 0; i < parameters.length - 1; i++) {
    final t0 = parameters[i];
    final t1 = parameters[i + 1];
    if (t1 - t0 < 1e-5) continue;
    if (!owns(at((t0 + t1) / 2))) continue;
    kept.add((at(t0), at(t1)));
  }
  return kept;
}

bool _foldBlocked({
  required PapercutSheet sheet,
  required Offset a,
  required Offset b,
  required double side,
  required List<List<Offset>> noFold,
  required List<List<Offset>> blueprintPieces,
}) {
  if (sheet.pieces.isEmpty) return false;
  for (final zone in noFold) {
    if (zone.length < 3) continue;
    if (_segmentHitsRing(a, b, zone)) return true;
    for (final point in zone) {
      final signed = sideOfLine(point, a, b);
      if (signed.abs() > _eps && signed.sign == side.sign) return true;
    }
    for (final ring in blueprintPieces) {
      if (ring.length < 3) continue;
      if (!_ringsOverlap(ring, zone)) continue;
      if (sideOfLine(polygonCentroid(ring), a, b).sign == side.sign) {
        return true;
      }
    }
  }
  return false;
}

bool _ringsOverlap(List<Offset> a, List<Offset> b) {
  if (isInsidePolygon(polygonCentroid(a), b)) return true;
  if (isInsidePolygon(polygonCentroid(b), a)) return true;
  for (final point in a) {
    if (isInsidePolygon(point, b)) return true;
  }
  return _segmentHitsRing(a.first, a[1], b);
}

bool _segmentHitsRing(Offset a, Offset b, List<Offset> ring) {
  if (isInsidePolygon(a, ring) || isInsidePolygon(b, ring)) return true;
  for (var i = 0; i < ring.length; i++) {
    final c = ring[i];
    final d = ring[(i + 1) % ring.length];
    if (_segmentsCross(a, b, c, d)) return true;
  }
  return false;
}

bool _segmentsCross(Offset a, Offset b, Offset c, Offset d) {
  final ab = b - a;
  final cd = d - c;
  final denom = ab.dx * cd.dy - ab.dy * cd.dx;
  if (denom.abs() < 1e-10) return false;
  final ac = c - a;
  final t = (ac.dx * cd.dy - ac.dy * cd.dx) / denom;
  final u = (ac.dx * ab.dy - ac.dy * ab.dx) / denom;
  return t > _eps && t < 1 - _eps && u > _eps && u < 1 - _eps;
}

double _distanceToSegment(Offset point, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 < 1e-12) return (point - a).distance;
  final t = ((point.dx - a.dx) * ab.dx + (point.dy - a.dy) * ab.dy) / len2;
  final clamped = t.clamp(0.0, 1.0);
  final closest = Offset(a.dx + ab.dx * clamped, a.dy + ab.dy * clamped);
  return (point - closest).distance;
}

/// Cuts [visualStroke] through every drawn piece it overlaps.
///
/// [visualStroke] is where the paper is drawn: folded, then shifted by each
/// piece's separation. A piece is cut in its own unfolded coordinates, and
/// only along the part of the stroke that lies on that piece.
PapercutSheet? cutThroughFolds(
  PapercutSheet sheet,
  List<Offset> visualStroke, {
  double thickCut = 0,
  List<List<Offset>> blueprintPieces = const [],
  bool recordStroke = true,
  String? onlyPieceId,
}) {
  if (visualStroke.length < 2) return null;
  final targets = <String>[
    for (final piece in sheet.pieces)
      if (onlyPieceId == null || piece.id == onlyPieceId)
        if (_modelChains(visualStroke, piece, sheet.folds).isNotEmpty) piece.id,
  ];
  if (targets.isEmpty) return null;
  var current = sheet;
  var any = false;
  final recorded = <List<Offset>>[];
  for (final id in targets) {
    final index = current.pieces.indexWhere((piece) => piece.id == id);
    if (index < 0) continue;
    final piece = current.pieces[index];
    final chains = _modelChains(visualStroke, piece, current.folds);
    for (final chain in chains) {
      final next = thickCut > 0
          ? _thickCutOne(current, id, chain, thickCut, blueprintPieces)
          : _cutOne(current, id, chain);
      if (next == null) continue;
      any = true;
      current = next;
      if (recordStroke && thickCut <= 0) recorded.add(chain);
    }
  }
  if (!any) return null;
  if (recordStroke && recorded.isNotEmpty) {
    final chords = <List<Offset>>[
      for (final chain in recorded) ?_foldChord(chain, sheet.folds),
    ];
    current = current.copyWith(
      cutStrokes: [...current.cutStrokes, ...recorded, ...chords],
    );
  }
  return current;
}

/// Straight close across a fold when both ends of [chain] lie on it.
///
/// The arc and its mirror are the two halves of a disk. The chord keeps the
/// cut-offs from rejoining along the crease, and the sheet still can.
List<Offset>? _foldChord(List<Offset> chain, List<FoldJoint> folds) {
  if (chain.length < 3) return null;
  final a = chain.first;
  final b = chain.last;
  if ((a - b).distance < 1e-3) return null;
  for (final joint in folds) {
    if (joint.facing == FoldFacing.unfolded) continue;
    if (_distanceToSegment(a, joint.a, joint.b) > 1e-2) continue;
    if (_distanceToSegment(b, joint.a, joint.b) > 1e-2) continue;
    return [a, b];
  }
  return null;
}

/// Reflections [displayPoint] applies to [piece], in fold order.
///
/// A fold splits along its crease first, so the whole piece stays on one side.
List<FoldJoint> _appliedFolds(PapercutPiece piece, List<FoldJoint> joints) {
  if (piece.vertices.length < 3) return const [];
  var current = polygonCentroid(piece.vertices);
  final applied = <FoldJoint>[];
  for (final joint in joints) {
    if (!foldApplies(current, joint, pieceId: piece.id)) continue;
    applied.add(joint);
    current = reflectAcrossLine(current, joint.a, joint.b);
  }
  return applied;
}

/// Separation shared by every piece the unshifted crease crosses.
///
/// A dragged sheet stores the crease without that shift. One shared shift
/// puts the cut back where the sheet is drawn. Stacked sheets with no shift
/// stay put.
Offset _sharedSeparation(PapercutSheet sheet, Offset a, Offset b) {
  final shifts = <Offset>{};
  for (final piece in sheet.pieces) {
    if (piece.vertices.length < 3) continue;
    final drawn = PapercutPiece(
      id: piece.id,
      color: piece.color,
      vertices: shownRing(
        piece.vertices,
        Offset.zero,
        sheet.folds,
        pieceId: piece.id,
      ),
      holes: [
        for (final hole in piece.holes)
          shownRing(hole, Offset.zero, sheet.folds, pieceId: piece.id),
      ],
    );
    if (clipStrokePolylines([a, b], drawn).isEmpty) continue;
    shifts.add(piece.separation);
  }
  if (shifts.length != 1) return Offset.zero;
  return shifts.single;
}

Offset _undoDisplay(Offset drawn, List<FoldJoint> applied, Offset separation) {
  var current = drawn - separation;
  for (final joint in applied.reversed) {
    current = reflectAcrossLine(current, joint.a, joint.b);
  }
  return current;
}

PapercutPiece _asDrawn(PapercutPiece piece, List<FoldJoint> folds) {
  return PapercutPiece(
    id: piece.id,
    color: piece.color,
    vertices: shownRing(
      piece.vertices,
      piece.separation,
      folds,
      pieceId: piece.id,
    ),
    holes: [
      for (final hole in piece.holes)
        shownRing(hole, piece.separation, folds, pieceId: piece.id),
    ],
  );
}

List<List<Offset>> _modelChains(
  List<Offset> visualStroke,
  PapercutPiece piece,
  List<FoldJoint> folds,
) {
  if (piece.vertices.length < 3) return const [];
  final drawn = _asDrawn(piece, folds);
  if (drawn.vertices.length < 3) return const [];
  final applied = _appliedFolds(piece, folds);
  final chains = clipStrokePolylines(visualStroke, drawn);
  return [
    for (final chain in chains)
      [
        for (final point in chain)
          _undoDisplay(point, applied, piece.separation),
      ],
  ];
}

/// Cuts [id] along [modelStroke]. Null when the stroke misses that piece.
///
/// A stroke that has entered the paper but not yet split it still counts, so
/// the blade can keep marching.
PapercutSheet? _cutOne(
  PapercutSheet sheet,
  String id,
  List<Offset> modelStroke,
) {
  final index = sheet.pieces.indexWhere((piece) => piece.id == id);
  if (index < 0) return null;
  final piece = sheet.pieces[index];
  final alone = PapercutSheet(pieces: [piece], nextPieceId: sheet.nextPieceId);
  final cut = applyPapercutCut(alone, modelStroke, recordStroke: false);
  if (cut == null) return null;
  if (cut.pieces.length == 1 && cut.pieces.single.id == piece.id) return sheet;
  final pieces = [...sheet.pieces]..removeAt(index);
  pieces.insertAll(index, cut.pieces);
  return sheet.copyWith(pieces: pieces, nextPieceId: cut.nextPieceId);
}

PapercutSheet? _thickCutOne(
  PapercutSheet sheet,
  String id,
  List<Offset> modelStroke,
  double halfWidth,
  List<List<Offset>> blueprintPieces,
) {
  final index = sheet.pieces.indexWhere((piece) => piece.id == id);
  if (index < 0) return null;
  final piece = sheet.pieces[index];
  final alone = PapercutSheet(pieces: [piece], nextPieceId: sheet.nextPieceId);
  final cut = applyThickCut(
    alone,
    modelStroke,
    halfWidth,
    blueprintPieces: blueprintPieces,
  );
  if (cut == null) return null;
  final pieces = [...sheet.pieces]..removeAt(index);
  pieces.insertAll(index, cut.pieces);
  return sheet.copyWith(pieces: pieces, nextPieceId: cut.nextPieceId);
}

List<Offset> capsule(Offset a, Offset b, double radius) {
  if (radius <= 0) return const [];
  final delta = b - a;
  final len = delta.distance;
  if (len < _eps) return _circle(a, radius);
  final dir = delta / len;
  const steps = 8;
  final points = <Offset>[];
  for (var i = 0; i <= steps; i++) {
    final angle = -math.pi / 2 + math.pi * i / steps;
    points.add(b + _rotate(dir, angle) * radius);
  }
  for (var i = 0; i <= steps; i++) {
    final angle = math.pi / 2 + math.pi * i / steps;
    points.add(a + _rotate(dir, angle) * radius);
  }
  return points;
}

List<Offset> _circle(Offset center, double radius) {
  const steps = 16;
  return [
    for (var i = 0; i < steps; i++)
      center +
          Offset(
                math.cos(2 * math.pi * i / steps),
                math.sin(2 * math.pi * i / steps),
              ) *
              radius,
  ];
}

Offset _rotate(Offset vector, double angle) {
  final c = math.cos(angle);
  final s = math.sin(angle);
  return Offset(vector.dx * c - vector.dy * s, vector.dx * s + vector.dy * c);
}

PapercutSheet? applyThickCut(
  PapercutSheet sheet,
  List<Offset> centerline,
  double halfWidth, {
  List<List<Offset>> blueprintPieces = const [],
}) {
  if (halfWidth <= 0 || centerline.length < 2) return null;
  PapercutSheet? current = sheet;
  var any = false;
  for (var i = 0; i < centerline.length - 1; i++) {
    final a = centerline[i];
    final b = centerline[i + 1];
    final regions = _stripRegions(a, b, halfWidth, blueprintPieces);
    for (final region in regions) {
      final next = subtractRegion(current!, region);
      if (next == null) continue;
      any = true;
      current = next;
    }
  }
  return any ? current : null;
}

List<List<Offset>> _stripRegions(
  Offset a,
  Offset b,
  double halfWidth,
  List<List<Offset>> blueprintPieces,
) {
  final strip = capsule(a, b, halfWidth);
  if (strip.length < 3) return const [];
  var sheet = PapercutSheet(
    pieces: [
      PapercutPiece(
        id: 'strip',
        color: const Color(0x00000000),
        vertices: strip,
      ),
    ],
  );
  for (final ring in blueprintPieces) {
    if (ring.length < 3) continue;
    if (_rides(a, b, ring)) continue;
    final next = subtractRegion(sheet, ring);
    if (next != null) sheet = next;
  }
  return [for (final piece in sheet.pieces) piece.vertices];
}

bool _rides(Offset a, Offset b, List<Offset> ring) {
  for (var i = 0; i < ring.length; i++) {
    final c = ring[i];
    final d = ring[(i + 1) % ring.length];
    if (_distanceToSegment(a, c, d) > 1e-2) continue;
    if (_distanceToSegment(b, c, d) > 1e-2) continue;
    return true;
  }
  return false;
}

enum PunchShape { circle, square, triangle }

const List<double> punchSizes = [0.5, 1, 2];

/// Nearest grid point to [aim]. A punch is centered on that point.
Offset snapPunchCenter(Offset aim, double spacing) {
  if (spacing <= 1e-9) return aim;
  return Offset(
    (aim.dx / spacing).roundToDouble() * spacing,
    (aim.dy / spacing).roundToDouble() * spacing,
  );
}

List<Offset> punchOutline(Offset center, PunchShape shape, double size) {
  final half = size / 2;
  return switch (shape) {
    PunchShape.circle => _circle(center, half),
    PunchShape.square => [
      center + Offset(-half, -half),
      center + Offset(half, -half),
      center + Offset(half, half),
      center + Offset(-half, half),
    ],
    PunchShape.triangle => [
      center + Offset(0, -half),
      center + Offset(half, half),
      center + Offset(-half, half),
    ],
  };
}

bool punchCrossesBlueprint(List<Offset> punch, List<List<Offset>> pieces) {
  for (final ring in pieces) {
    if (ring.length < 3) continue;
    for (final point in punch) {
      if (isInsidePolygon(point, ring)) return true;
    }
    if (punch.isNotEmpty && isInsidePolygon(polygonCentroid(punch), ring)) {
      return true;
    }
    for (final vertex in ring) {
      if (isInsidePolygon(vertex, punch)) return true;
    }
  }
  return false;
}

Offset reflectPoint(
  Offset point,
  Offset center, {
  required bool acrossX,
  required bool acrossY,
}) {
  var x = point.dx;
  var y = point.dy;
  if (acrossX) x = center.dx * 2 - x;
  if (acrossY) y = center.dy * 2 - y;
  return Offset(x, y);
}

List<List<Offset>> mirroredPolylines(
  List<Offset> path,
  Offset center, {
  required bool mirrorX,
  required bool mirrorY,
}) {
  final images = <List<Offset>>[];
  void add({required bool acrossX, required bool acrossY}) {
    images.add([
      for (final point in path)
        reflectPoint(point, center, acrossX: acrossX, acrossY: acrossY),
    ]);
  }

  if (mirrorX) add(acrossX: true, acrossY: false);
  if (mirrorY) add(acrossX: false, acrossY: true);
  if (mirrorX && mirrorY) add(acrossX: true, acrossY: true);
  return images;
}

/// Unit-cell center inside [ring] closest to the piece centroid.
Offset collisionAnchor(List<Offset> ring) {
  if (ring.length < 3) return ring.isEmpty ? Offset.zero : ring.first;
  final centroid = polygonCentroid(ring);
  var minX = ring.first.dx;
  var maxX = ring.first.dx;
  var minY = ring.first.dy;
  var maxY = ring.first.dy;
  for (final point in ring) {
    minX = math.min(minX, point.dx);
    maxX = math.max(maxX, point.dx);
    minY = math.min(minY, point.dy);
    maxY = math.max(maxY, point.dy);
  }
  Offset? best;
  var bestDistance = double.infinity;
  for (var x = minX.floor(); x <= maxX.ceil(); x++) {
    for (var y = minY.floor(); y <= maxY.ceil(); y++) {
      final center = Offset(x + 0.5, y + 0.5);
      if (!isInsidePolygon(center, ring)) continue;
      final distance = (center - centroid).distance;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = center;
      }
    }
  }
  return best ?? centroid;
}

/// The paper under a hits piece may leave only when [hitsLeft] is already 0.
/// A positive count means that paper was removed too soon.
bool paperRemovedEarly(int? hitsLeft, {required bool cutOut}) {
  if (hitsLeft == null || hitsLeft <= 0) return false;
  return cutOut;
}

/// The paper piece whose outline matches [ring], if the cut has freed it.
PapercutPiece? paperMatchingRing(List<Offset> ring, PapercutSheet sheet) {
  if (ring.length < 3) return null;
  final target = polygonSignedArea(ring).abs();
  if (target < 1e-6) return null;
  final center = polygonCentroid(ring);
  for (final piece in sheet.pieces) {
    if (!isInsidePolygon(center, piece.vertices)) continue;
    var buried = false;
    for (final hole in piece.holes) {
      if (isInsidePolygon(center, hole)) buried = true;
    }
    if (buried) continue;
    final area = polygonSignedArea(piece.vertices).abs();
    if ((area - target).abs() <= target * 0.25 + 0.35) return piece;
  }
  return null;
}

bool blueprintPieceCutOut(List<Offset> ring, PapercutSheet sheet) {
  return paperMatchingRing(ring, sheet) != null;
}

/// Closed blueprint pieces whose paper is already free on [sheet].
Set<int> liberatedPieceIndexes(GridStep step, PapercutSheet sheet) {
  final found = <int>{};
  for (var i = 0; i < step.polygons.length; i++) {
    if (!step.isRingClosed(i)) continue;
    if (step.polygons[i].length < 3) continue;
    if (blueprintPieceCutOut(step.polygons[i], sheet)) found.add(i);
  }
  return found;
}

/// True when the level has at least one closed blueprint piece and every one
/// of them is in [liberated].
bool piecesLiberated(GridStep step, Set<int> liberated) {
  var any = false;
  for (var i = 0; i < step.polygons.length; i++) {
    if (!step.isRingClosed(i)) continue;
    if (step.polygons[i].length < 3) continue;
    any = true;
    if (!liberated.contains(i)) return false;
  }
  return any;
}

/// Blueprint piece indexes whose perimeter the segment meets.
List<int> piecesTouched(
  List<List<Offset>> pieces,
  Offset a,
  Offset b, {
  List<bool> closed = const [],
}) {
  final hits = <int>[];
  for (var i = 0; i < pieces.length; i++) {
    if (i < closed.length && !closed[i]) continue;
    final ring = pieces[i];
    if (ring.length < 3) continue;
    for (var e = 0; e < ring.length; e++) {
      final c = ring[e];
      final d = ring[(e + 1) % ring.length];
      if (_segmentsNear(a, b, c, d)) {
        hits.add(i);
        break;
      }
    }
  }
  return hits;
}

bool _segmentsNear(Offset a, Offset b, Offset c, Offset d) {
  if (_segmentsCross(a, b, c, d)) return true;
  if (_distanceToSegment(a, c, d) <= 1e-2) return true;
  if (_distanceToSegment(b, c, d) <= 1e-2) return true;
  if (_distanceToSegment(c, a, b) <= 1e-2) return true;
  if (_distanceToSegment(d, a, b) <= 1e-2) return true;
  return false;
}

/// True when [edge] is penciled and another blueprint piece has a penned
/// edge on the same line.
bool penciledRidesPennedNeighbor(
  List<List<Offset>> pieces,
  List<List<EdgeStyle>> styles,
  Offset a,
  Offset b, {
  List<bool> closed = const [],
}) {
  var penciled = false;
  var pennedNeighbor = false;
  for (var i = 0; i < pieces.length; i++) {
    final ring = pieces[i];
    final ringClosed = i >= closed.length || closed[i];
    final edges = ringClosed ? ring.length : ring.length - 1;
    if (edges < 1) continue;
    final style = i < styles.length && styles[i].length == ring.length
        ? styles[i]
        : List<EdgeStyle>.filled(ring.length, EdgeStyle.penned);
    for (var e = 0; e < edges; e++) {
      final c = ring[e];
      final d = ring[(e + 1) % ring.length];
      if (!_sameSpan(a, b, c, d) && !_collinearOverlap(a, b, c, d)) continue;
      if (style[e] == EdgeStyle.penciled && _sameSpan(a, b, c, d)) {
        penciled = true;
      } else if (style[e] == EdgeStyle.penned &&
          _collinearOverlap(a, b, c, d)) {
        pennedNeighbor = true;
      }
    }
  }
  return penciled && pennedNeighbor;
}

bool _sameSpan(Offset a, Offset b, Offset c, Offset d) {
  return ((a - c).distance < 1e-3 && (b - d).distance < 1e-3) ||
      ((a - d).distance < 1e-3 && (b - c).distance < 1e-3);
}

bool _collinearOverlap(Offset a, Offset b, Offset c, Offset d) {
  if (_distanceToSegment(a, c, d) > 1e-2 &&
      _distanceToSegment(c, a, b) > 1e-2) {
    return false;
  }
  if (_distanceToSegment(b, c, d) > 1e-2 &&
      _distanceToSegment(d, a, b) > 1e-2) {
    return false;
  }
  final ab = b - a;
  final cd = d - c;
  final cross = ab.dx * cd.dy - ab.dy * cd.dx;
  if (cross.abs() > 1e-2 * math.max(ab.distance, 1)) return false;
  return true;
}
