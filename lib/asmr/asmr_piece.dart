import 'dart:math' as math;
import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

import '../geometry/polygon_union.dart';
import '../papercut/paper.dart';
import '../papercut/split.dart';
import 'asmr_net.dart';
import 'asmr_paper.dart';

/// A fresh sheet from the drawer, in desk units.
const Size kAsmrSheetSize = Size(160, 220);

/// A cut that ends this close to the paper's edge, a score, or the cut so
/// far is carried onto it, in desk units.
const double kAsmrCutReach = 3;

/// Desk units between exacto stroke samples.
const double kAsmrStrokeSpacing = 1;

/// A paper piece on the ASMR desk. [ring] and [holes] are in the paper's
/// own coordinates, where its pattern is printed; [position] and [angle]
/// lay it on the desk.
///
/// A piece is [liberated] once a cut frees it from the rest of its sheet.
/// A liberated piece over the hologram takes that hologram as its
/// [binding], and keeps it while the hologram changes.
class AsmrPiece {
  const AsmrPiece({
    required this.id,
    required this.paper,
    required this.ring,
    this.holes = const [],
    this.position = Offset.zero,
    this.angle = 0,
    this.liberated = false,
    this.binding,
    this.scores = const [],
  });

  /// A whole sheet of [paper] centered on [at].
  factory AsmrPiece.sheet({
    required String id,
    required AsmrPaper paper,
    required Offset at,
    Size size = kAsmrSheetSize,
  }) {
    final w = size.width / 2;
    final h = size.height / 2;
    return AsmrPiece(
      id: id,
      paper: paper,
      ring: [Offset(-w, -h), Offset(w, -h), Offset(w, h), Offset(-w, h)],
      position: at,
    );
  }

  final String id;
  final AsmrPaper paper;
  final List<Offset> ring;
  final List<List<Offset>> holes;
  final Offset position;
  final double angle;
  final bool liberated;
  final AsmrNet? binding;

  /// Cuts that did not free anything yet, in paper coordinates.
  final List<List<Offset>> scores;

  AsmrPiece copyWith({
    Offset? position,
    double? angle,
    bool? liberated,
    AsmrNet? binding,
    List<List<Offset>>? scores,
  }) => AsmrPiece(
    id: id,
    paper: paper,
    ring: ring,
    holes: holes,
    position: position ?? this.position,
    angle: angle ?? this.angle,
    liberated: liberated ?? this.liberated,
    binding: binding ?? this.binding,
    scores: scores ?? this.scores,
  );

  /// The same piece, attached to no faces.
  AsmrPiece unbound() => AsmrPiece(
    id: id,
    paper: paper,
    ring: ring,
    holes: holes,
    position: position,
    angle: angle,
    liberated: liberated,
    scores: scores,
  );

  /// Paper coordinates to the desk.
  Matrix4 get pose =>
      Matrix4.translationValues(position.dx, position.dy, 0) *
      Matrix4.rotationZ(angle);

  Offset toDesk(Offset local) {
    final c = math.cos(angle);
    final s = math.sin(angle);
    return position +
        Offset(c * local.dx - s * local.dy, s * local.dx + c * local.dy);
  }

  Offset toLocal(Offset desk) {
    final d = desk - position;
    final c = math.cos(angle);
    final s = math.sin(angle);
    return Offset(c * d.dx + s * d.dy, -s * d.dx + c * d.dy);
  }

  List<Offset> get deskRing => [for (final p in ring) toDesk(p)];

  List<List<Offset>> get deskHoles => [
    for (final hole in holes) [for (final p in hole) toDesk(p)],
  ];

  double get area {
    var total = polygonSignedArea(ring).abs();
    for (final hole in holes) {
      total -= polygonSignedArea(hole).abs();
    }
    return total;
  }

  Offset get localCentroid => polygonCentroid(ring);

  Offset get deskCentroid => toDesk(localCentroid);

  bool containsLocal(Offset local) {
    if (!isInsidePolygon(local, ring)) return false;
    for (final hole in holes) {
      if (isInsidePolygon(local, hole)) return false;
    }
    return true;
  }

  bool contains(Offset desk) => containsLocal(toLocal(desk));

  /// The same piece turned to [angle] about its centroid.
  AsmrPiece turnedTo(double angle) => turnedAbout(angle, deskCentroid);

  /// The same piece turned to [angle] about [pivot], which stays where it is.
  AsmrPiece turnedAbout(double angle, Offset pivot) {
    final local = toLocal(pivot);
    final c = math.cos(angle);
    final s = math.sin(angle);
    final spun = Offset(
      c * local.dx - s * local.dy,
      s * local.dx + c * local.dy,
    );
    return copyWith(position: pivot - spun, angle: angle);
  }

  /// Midpoint of the outline edge [from] sits across from.
  Offset edgeCenterOpposite(Offset from) {
    final ring = deskRing;
    var best = double.infinity;
    var mid = deskCentroid;
    for (var i = 0; i < ring.length; i++) {
      final a = ring[i];
      final b = ring[(i + 1) % ring.length];
      if ((b - a).distance < 1e-9) continue;
      final center = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      final distance = (center - from).distance;
      if (distance < best) {
        best = distance;
        mid = center;
      }
    }
    return mid;
  }

  /// Paper outline as a path in paper coordinates, holes cut out.
  Path get localPath {
    final path = Path()..fillType = PathFillType.evenOdd;
    void addRing(List<Offset> ring) {
      if (ring.length < 3) return;
      path.moveTo(ring.first.dx, ring.first.dy);
      for (final p in ring.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      path.close();
    }

    addRing(ring);
    holes.forEach(addRing);
    return path;
  }

  PapercutPiece _asPapercut() =>
      PapercutPiece(id: id, color: paper.color, vertices: ring, holes: holes);
}

/// What one exacto stroke did to the desk.
class AsmrCut {
  const AsmrCut({required this.pieces, required this.freed});

  final List<AsmrPiece> pieces;

  /// Ids of pieces this cut split off.
  final Set<String> freed;

  bool get split => freed.isNotEmpty;
}

/// Cuts every piece [deskStroke] crosses. A piece the stroke splits becomes
/// its parts: the largest keeps the piece's place as the sheet, and every
/// other part is liberated. Parts keep the piece's pose and binding. A
/// piece the stroke only scores keeps the stroke when [keepScores].
///
/// Mid-stroke, pass [finished] false: the tip is still moving, so it is not
/// carried onto anything near it yet.
///
/// When [exact] is set, the stroke is the cut. Its ends stay where they
/// are, instead of being carried onto a nearby edge, score, or earlier
/// part of the stroke.
///
/// Returns null when the stroke touches no paper.
AsmrCut? cutPieces(
  List<AsmrPiece> pieces,
  List<Offset> deskStroke, {
  bool keepScores = true,
  bool finished = true,
  bool exact = false,
}) {
  if (deskStroke.length < 2) return null;
  final next = <AsmrPiece>[];
  final freed = <String>{};
  var touched = false;
  for (final piece in pieces) {
    final local = [for (final p in deskStroke) piece.toLocal(p)];
    final papercut = piece._asPapercut();
    if (clipStrokePolylines(local, papercut).isEmpty) {
      next.add(piece);
      continue;
    }
    touched = true;
    final reached = finished && !exact
        ? _reachEdges(_closeLoop(_joinScores(local, piece.scores)), piece)
        : local;
    final result = applyPapercutCuts(PapercutSheet(pieces: [papercut]), [
      ...piece.scores,
      reached,
    ], recordStroke: false);
    final parts = result?.pieces ?? const <PapercutPiece>[];
    if (parts.length < 2) {
      next.add(
        keepScores ? piece.copyWith(scores: [...piece.scores, reached]) : piece,
      );
      continue;
    }
    var largest = 0;
    var largestArea = -1.0;
    final areas = <double>[];
    for (var i = 0; i < parts.length; i++) {
      var area = polygonSignedArea(parts[i].vertices).abs();
      for (final hole in parts[i].holes) {
        area -= polygonSignedArea(hole).abs();
      }
      areas.add(area);
      if (area > largestArea) {
        largestArea = area;
        largest = i;
      }
    }
    for (var i = 0; i < parts.length; i++) {
      final part = AsmrPiece(
        id: '${piece.id}.$i',
        paper: piece.paper,
        ring: parts[i].vertices,
        holes: parts[i].holes,
        position: piece.position,
        angle: piece.angle,
        liberated: piece.liberated || i != largest,
        binding: piece.binding,
      );
      if (i != largest) freed.add(part.id);
      next.add(part);
    }
  }
  if (!touched) return null;
  return AsmrCut(pieces: next, freed: freed);
}

/// Desk units a straight cut runs past the paper's edge, so it leaves it.
const double _kThroughEdge = 0.5;

/// Where the line through [a] and [b] crosses [piece]'s outline and holes,
/// as line parameters: 0 at [a], 1 at [b]. Cramer's rule against each edge,
/// as in Boost.Geometry's `cartesian_segments`.
List<double> lineCrossings(AsmrPiece piece, Offset a, Offset b) {
  final dir = b - a;
  final hits = <double>[];
  for (final ring in [piece.deskRing, ...piece.deskHoles]) {
    for (var i = 0; i < ring.length; i++) {
      final c = ring[i];
      final edge = ring[(i + 1) % ring.length] - c;
      final denom = dir.dx * edge.dy - dir.dy * edge.dx;
      if (denom.abs() < 1e-12) continue;
      final w = c - a;
      final t = (w.dx * edge.dy - w.dy * edge.dx) / denom;
      final u = (w.dx * dir.dy - w.dy * dir.dx) / denom;
      if (u >= -1e-9 && u <= 1 + 1e-9) hits.add(t);
    }
  }
  hits.sort();
  return hits;
}

/// The straight cut through each piece the segment [a]–[b] touches: the
/// line through them, from where it enters that piece's paper to where it
/// leaves, kept within the line parameters [lo]..[hi]. A piece the segment
/// touches only outside [lo]..[hi] is not cut.
List<(AsmrPiece, List<Offset>)> straightCutLines(
  List<AsmrPiece> pieces,
  Offset a,
  Offset b, {
  double lo = double.negativeInfinity,
  double hi = double.infinity,
}) {
  final dir = b - a;
  final length = dir.distance;
  if (length < 1e-6) return const [];
  final from = math.max(0.0, lo);
  final to = math.min(1.0, hi);
  if (to <= from) return const [];
  final drawn = [a + dir * from, a + dir * to];
  final past = _kThroughEdge / length;
  final lines = <(AsmrPiece, List<Offset>)>[];
  for (final piece in pieces) {
    final local = [for (final p in drawn) piece.toLocal(p)];
    if (clipStrokePolylines(local, piece._asPapercut()).isEmpty) continue;
    final hits = lineCrossings(piece, a, b);
    if (hits.length < 2) continue;
    final start = math.max(hits.first - past, lo);
    final end = math.min(hits.last + past, hi);
    if (end - start < 1e-9) continue;
    lines.add((piece, [a + dir * start, a + dir * end]));
  }
  return lines;
}

/// The parts of a straight cut that lie on the paper. The cut itself still
/// runs a hair past the edge so it leaves the paper; this is the glowing
/// preview of where that cut will be.
List<List<Offset>> straightCutPreview(
  List<AsmrPiece> pieces,
  Offset a,
  Offset b, {
  double lo = double.negativeInfinity,
  double hi = double.infinity,
}) {
  final preview = <List<Offset>>[];
  for (final (piece, line) in straightCutLines(pieces, a, b, lo: lo, hi: hi)) {
    final local = [for (final p in line) piece.toLocal(p)];
    for (final part in clipStrokePolylines(local, piece._asPapercut())) {
      if (part.length < 2) continue;
      preview.add([for (final p in part) piece.toDesk(p)]);
    }
  }
  return preview;
}

/// Cuts each piece the segment [a]–[b] touches along its [straightCutLines].
/// Returns null when the segment touches no paper.
AsmrCut? cutPiecesAlongLine(
  List<AsmrPiece> pieces,
  Offset a,
  Offset b, {
  double lo = double.negativeInfinity,
  double hi = double.infinity,
}) {
  final lines = {
    for (final (piece, line) in straightCutLines(pieces, a, b, lo: lo, hi: hi))
      piece.id: line,
  };
  if (lines.isEmpty) return null;
  final next = <AsmrPiece>[];
  final freed = <String>{};
  for (final piece in pieces) {
    final line = lines[piece.id];
    final cut = line == null ? null : cutPieces([piece], line, exact: true);
    if (cut == null) {
      next.add(piece);
      continue;
    }
    next.addAll(cut.pieces);
    freed.addAll(cut.freed);
  }
  return AsmrCut(pieces: next, freed: freed);
}

/// Carries each end of [stroke] that stops just short of [piece]'s edge a
/// little past it, so a hand-drawn cut that meets the edge goes through.
List<Offset> _reachEdges(List<Offset> stroke, AsmrPiece piece) {
  if (stroke.length < 2) return stroke;
  final rings = [piece.ring, ...piece.holes];
  Offset? past(Offset end) {
    if (!piece.containsLocal(end)) return null;
    Offset? nearest;
    var best = kAsmrCutReach;
    for (final ring in rings) {
      for (var i = 0; i < ring.length; i++) {
        final q = _closestOnSegment(end, ring[i], ring[(i + 1) % ring.length]);
        final d = (q - end).distance;
        if (d < best) {
          best = d;
          nearest = q;
        }
      }
    }
    if (nearest == null) return null;
    final away = nearest - end;
    final length = away.distance;
    if (length < 1e-9) return null;
    return nearest + away / length * 0.5;
  }

  final out = List<Offset>.of(stroke);
  final head = past(stroke.first);
  if (head != null) out.insert(0, head);
  final tail = past(stroke.last);
  if (tail != null) out.add(tail);
  return out;
}

/// Joins each end of [stroke] to the nearest point of a score it stops just
/// short of, so a cut can carry on from where an earlier one left off.
List<Offset> _joinScores(List<Offset> stroke, List<List<Offset>> scores) {
  if (stroke.length < 2 || scores.isEmpty) return stroke;
  Offset? nearest(Offset end) {
    Offset? found;
    var best = kAsmrCutReach;
    for (final score in scores) {
      for (var i = 0; i < score.length - 1; i++) {
        final q = _closestOnSegment(end, score[i], score[i + 1]);
        final d = (q - end).distance;
        if (d < best) {
          best = d;
          found = q;
        }
      }
    }
    return best < 1e-6 ? null : found;
  }

  final head = nearest(stroke.first);
  final tail = nearest(stroke.last);
  return [?head, ...stroke, ?tail];
}

/// Joins the end of [stroke] to an earlier part of it that it stops just
/// short of, so a loop drawn by hand closes.
List<Offset> _closeLoop(List<Offset> stroke) {
  final skip = (kAsmrCutReach * 3 / kAsmrStrokeSpacing).ceil();
  if (stroke.length <= skip + 1) return stroke;
  final end = stroke.last;
  Offset? nearest;
  var best = kAsmrCutReach;
  for (var i = 0; i < stroke.length - skip - 1; i++) {
    final q = _closestOnSegment(end, stroke[i], stroke[i + 1]);
    final d = (q - end).distance;
    if (d < best) {
      best = d;
      nearest = q;
    }
  }
  if (nearest == null || best < 1e-6) return stroke;
  return [...stroke, nearest];
}

Offset _closestOnSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 < 1e-12) return a;
  final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2).clamp(
    0.0,
    1.0,
  );
  return a + ab * t;
}

/// A tool stroke smoothed by [amount], from 0 (the points as drawn) to 1
/// (the heaviest smooth). The first and last points stay put.
List<Offset> smoothToolCurve(List<Offset> points, double amount) {
  if (points.length < 3 || amount <= 0) return List<Offset>.from(points);
  final window = math.max(1, (amount.clamp(0.0, 1.0) * 12).round());
  final smoothed = smoothOffsets(points, window: window);
  smoothed[0] = points.first;
  smoothed[smoothed.length - 1] = points.last;
  return smoothed;
}

/// Appends [point] to [stroke] at [spacing] steps.
void addStrokePoint(
  List<Offset> stroke,
  Offset point, {
  double spacing = kAsmrStrokeSpacing,
}) {
  if (stroke.isEmpty) {
    stroke.add(point);
    return;
  }
  var last = stroke.last;
  var d = (point - last).distance;
  while (d >= spacing) {
    last = last + (point - last) / d * spacing;
    stroke.add(last);
    d = (point - last).distance;
  }
}
