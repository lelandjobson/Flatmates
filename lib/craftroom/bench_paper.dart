import 'dart:math' as math;
import 'dart:ui';

import '../geometry/polygon_union.dart' show polygonCentroid, polygonSignedArea;
import '../gridcraft/fold.dart';
import '../papercut/paper.dart';
import '../papercut/split.dart';

/// One grid square of the craft room bench, in desk units. One model unit
/// is one grid square.
const double kBenchGrid = 1;

/// A fresh sheet, in grid squares: US letter proportions.
const Size kBenchSheetSize = Size(17, 22);

const Color kBenchPaperColor = Color(0xFFF7F5EF);
const Color kBenchPaperBack = Color(0xFFE9E3D6);

const double _kEps = 1e-4;

/// Paper on the bench: a [PapercutSheet] in its own grid coordinates, laid
/// on the desk at [position], turned by [angle].
///
/// Pieces joined by folds stay one paper; a cut that frees a piece makes it
/// its own. [slits] are cuts that have not freed anything yet, in unfolded
/// sheet coordinates, so the next cut that meets them can finish the job.
class BenchPaper {
  const BenchPaper({
    required this.id,
    required this.sheet,
    this.position = Offset.zero,
    this.angle = 0,
    this.slits = const [],
    this.shade = 0,
  });

  /// A whole white sheet with its top left corner at [topLeft].
  factory BenchPaper.fresh(String id, Offset topLeft) {
    final w = kBenchSheetSize.width;
    final h = kBenchSheetSize.height;
    return BenchPaper(
      id: id,
      position: topLeft,
      sheet: PapercutSheet(
        pieces: [
          PapercutPiece(
            id: id,
            color: kBenchPaperColor,
            backColor: kBenchPaperBack,
            vertices: [Offset.zero, Offset(w, 0), Offset(w, h), Offset(0, h)],
          ),
        ],
      ),
    );
  }

  final String id;
  final PapercutSheet sheet;
  final Offset position;
  final double angle;
  final List<List<Offset>> slits;

  /// How far this paper is darkened, 0 for none. Scraps left outside the
  /// blueprint each keep their own amount.
  final double shade;

  BenchPaper copyWith({
    String? id,
    PapercutSheet? sheet,
    Offset? position,
    double? angle,
    List<List<Offset>>? slits,
    double? shade,
  }) => BenchPaper(
    id: id ?? this.id,
    sheet: sheet ?? this.sheet,
    position: position ?? this.position,
    angle: angle ?? this.angle,
    slits: slits ?? this.slits,
    shade: shade ?? this.shade,
  );

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

  /// [piece] where it is drawn on the desk, folds applied. [bend] swings
  /// that fold [bendT] of the way over.
  List<Offset> drawnRing(
    PapercutPiece piece, {
    List<Offset>? ring,
    int? bend,
    double bendT = 1,
  }) => [
    for (final point in shownRing(
      ring ?? piece.vertices,
      piece.separation,
      sheet.folds,
      pieceId: piece.id,
      bend: bend,
      bendT: bendT,
    ))
      toDesk(point),
  ];

  /// Every piece's outline where it is drawn.
  List<List<Offset>> get drawnRings => [
    for (final piece in sheet.pieces) drawnRing(piece),
  ];

  /// Every piece's outline flat, as if every fold were opened.
  List<List<Offset>> get flatRings => [
    for (final piece in sheet.pieces)
      [for (final p in piece.vertices) toDesk(p)],
  ];

  bool contains(Offset desk) => topPieceIndex(toLocal(desk), sheet) >= 0;

  /// Paper area, folded layers counted once each.
  double get area {
    var total = 0.0;
    for (final piece in sheet.pieces) {
      total += polygonSignedArea(piece.vertices).abs();
      for (final hole in piece.holes) {
        total -= polygonSignedArea(hole).abs();
      }
    }
    return total;
  }

  /// The same paper turned by [by] about [pivot] on the desk.
  BenchPaper turnedAbout(double by, Offset pivot) {
    final c = math.cos(by);
    final s = math.sin(by);
    final d = position - pivot;
    return copyWith(
      position: pivot + Offset(c * d.dx - s * d.dy, s * d.dx + c * d.dy),
      angle: angle + by,
    );
  }

  /// Middle of the paper as drawn.
  Offset get deskCenter {
    final rings = drawnRings;
    if (rings.isEmpty) return position;
    var sum = Offset.zero;
    var count = 0;
    for (final ring in rings) {
      sum += polygonCentroid(ring);
      count++;
    }
    return sum / count.toDouble();
  }
}

/// What one cut did to the bench.
class BenchCut {
  const BenchCut({required this.papers, required this.freed});

  final List<BenchPaper> papers;

  /// Ids of the papers that came out of a paper the cut split, the part that
  /// keeps the old id included.
  final Set<String> freed;

  bool get split => freed.isNotEmpty;
}

/// Cuts every paper [deskStroke] crosses, through its folds. Each paper's
/// [BenchPaper.slits] are cut along with it. A paper the cut splits becomes
/// one paper per set of pieces still joined by folds: the largest keeps its
/// id, and the others are named by [nextId].
///
/// Returns null when the stroke touches no paper.
BenchCut? cutBench(
  List<BenchPaper> papers,
  List<Offset> deskStroke, {
  required String Function() nextId,
}) {
  if (deskStroke.length < 2) return null;
  final next = <BenchPaper>[];
  final freed = <String>{};
  var touched = false;
  for (final paper in papers) {
    final local = [for (final p in deskStroke) paper.toLocal(p)];
    final before = paper.sheet.cutStrokes.length;
    final cut = cutThroughFolds(paper.sheet, local);
    if (cut == null) {
      next.add(paper);
      continue;
    }
    touched = true;
    final added = cut.cutStrokes.sublist(before);
    var sheet = cut;
    var slits = <List<Offset>>[...paper.slits, ...added];
    if (cut.pieces.length == paper.sheet.pieces.length &&
        paper.slits.isNotEmpty) {
      final joined = applyPapercutCuts(
        PapercutSheet(pieces: cut.pieces, nextPieceId: cut.nextPieceId),
        slits,
        recordStroke: false,
      );
      if (joined != null && joined.pieces.length > cut.pieces.length) {
        sheet = cut.copyWith(
          pieces: joined.pieces,
          nextPieceId: joined.nextPieceId,
        );
      }
    }
    final parts = splitSheet(sheet);
    if (parts.length < 2) {
      next.add(paper.copyWith(sheet: sheet, slits: slits));
      continue;
    }
    slits = const [];
    var largest = 0;
    var largestArea = -1.0;
    for (var i = 0; i < parts.length; i++) {
      final area = _sheetArea(parts[i]);
      if (area > largestArea) {
        largestArea = area;
        largest = i;
      }
    }
    for (var i = 0; i < parts.length; i++) {
      final part = paper.copyWith(
        id: i == largest ? paper.id : nextId(),
        sheet: parts[i],
        slits: slits,
      );
      freed.add(part.id);
      next.add(part);
    }
  }
  if (!touched) return null;
  return BenchCut(papers: next, freed: freed);
}

/// How far a straight cut runs past the paper, in grid squares, so it leaves
/// the sheet instead of stopping on the edge.
const double kThroughEdge = 0.5;

/// The straight cut the segment [a]–[b] sets: for each paper the segment
/// touches, the line through it from where the line enters to where it
/// leaves. [lo] and [hi] are line parameters, 0 at [a] and 1 at [b], that
/// the straight edge keeps the cut inside.
List<(String, List<Offset>)> straightThrough(
  List<BenchPaper> papers,
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
  if (to - from < 1e-9) return const [];
  final drawn = [a + dir * from, a + dir * to];
  final past = kThroughEdge / length;
  final lines = <(String, List<Offset>)>[];
  for (final paper in papers) {
    if (!_segmentTouches(paper, drawn)) continue;
    final hits = _lineHits(_deskLoops(paper), a, b);
    if (hits.length < 2) continue;
    final start = math.max(hits.first - past, lo);
    final end = math.min(hits.last + past, hi);
    if (end - start < 1e-9) continue;
    lines.add((paper.id, [a + dir * start, a + dir * end]));
  }
  return lines;
}

/// Where a straight cut will show on the paper: each through-line clipped to
/// the sheet it cuts.
List<(Offset, Offset)> straightThroughPreview(
  List<BenchPaper> papers,
  Offset a,
  Offset b, {
  double lo = double.negativeInfinity,
  double hi = double.infinity,
}) {
  final byId = {for (final paper in papers) paper.id: paper};
  final shown = <(Offset, Offset)>[];
  for (final (id, line) in straightThrough(papers, a, b, lo: lo, hi: hi)) {
    final paper = byId[id];
    if (paper == null) continue;
    final local = [for (final p in line) paper.toLocal(p)];
    for (final piece in paper.sheet.pieces) {
      for (final part in clipStrokePolylines(local, piece)) {
        if (part.length < 2) continue;
        shown.add((paper.toDesk(part.first), paper.toDesk(part.last)));
      }
    }
  }
  return shown;
}

/// Cuts [a]–[b] straight through every paper the segment touches.
BenchCut? cutStraight(
  List<BenchPaper> papers,
  Offset a,
  Offset b, {
  required String Function() nextId,
  double lo = double.negativeInfinity,
  double hi = double.infinity,
}) {
  final lines = straightThrough(papers, a, b, lo: lo, hi: hi);
  if (lines.isEmpty) return null;
  var current = papers;
  final freed = <String>{};
  var any = false;
  for (final (id, line) in lines) {
    final i = current.indexWhere((paper) => paper.id == id);
    if (i < 0) continue;
    final cut = cutBench([current[i]], line, nextId: nextId);
    if (cut == null) continue;
    any = true;
    current = [
      ...current.sublist(0, i),
      ...cut.papers,
      ...current.sublist(i + 1),
    ];
    freed.addAll(cut.freed);
  }
  if (!any) return null;
  return BenchCut(papers: current, freed: freed);
}

bool _segmentTouches(BenchPaper paper, List<Offset> drawn) {
  final local = [for (final p in drawn) paper.toLocal(p)];
  for (final piece in paper.sheet.pieces) {
    if (clipStrokePolylines(local, piece).isNotEmpty) return true;
  }
  return false;
}

/// Outlines and holes of [paper] on the desk, folds opened.
List<List<Offset>> _deskLoops(BenchPaper paper) => [
  for (final piece in paper.sheet.pieces) ...[
    [for (final p in piece.vertices) paper.toDesk(p)],
    for (final hole in piece.holes) [for (final p in hole) paper.toDesk(p)],
  ],
];

/// Where the line through [a] and [b] crosses [rings], as line parameters:
/// 0 at [a], 1 at [b]. Cramer's rule against each edge, as in
/// Boost.Geometry's `cartesian_segments`.
List<double> _lineHits(List<List<Offset>> rings, Offset a, Offset b) {
  final dir = b - a;
  final hits = <double>[];
  for (final ring in rings) {
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

/// The sheets [sheet] falls into: one per set of pieces joined across an
/// edge that no cut runs along. Each keeps the folds that move its pieces.
List<PapercutSheet> splitSheet(PapercutSheet sheet) {
  final pieces = sheet.pieces;
  if (pieces.length < 2) return [sheet];
  final parent = [for (var i = 0; i < pieces.length; i++) i];
  int find(int i) {
    while (parent[i] != i) {
      parent[i] = parent[parent[i]];
      i = parent[i];
    }
    return i;
  }

  for (var i = 0; i < pieces.length; i++) {
    for (var j = i + 1; j < pieces.length; j++) {
      if (find(i) == find(j)) continue;
      if (_joined(pieces[i], pieces[j], sheet.cutStrokes)) {
        parent[find(j)] = find(i);
      }
    }
  }
  final sets = <int, List<PapercutPiece>>{};
  for (var i = 0; i < pieces.length; i++) {
    (sets[find(i)] ??= []).add(pieces[i]);
  }
  if (sets.length < 2) return [sheet];
  return [
    for (final members in sets.values)
      sheet.copyWith(
        pieces: members,
        folds: [
          for (final joint in sheet.folds)
            if (joint.pieceIds.isEmpty ||
                members.any((piece) => foldJointOwnsPiece(joint, piece.id)))
              joint,
        ],
      ),
  ];
}

/// Whether [a] and [b] share a stretch of edge that no cut runs along: a
/// crease, where a fold split the paper without cutting it.
bool _joined(PapercutPiece a, PapercutPiece b, List<List<Offset>> cuts) {
  for (final ra in [a.vertices, ...a.holes]) {
    for (final rb in [b.vertices, ...b.holes]) {
      for (var i = 0; i < ra.length; i++) {
        final p = ra[i];
        final q = ra[(i + 1) % ra.length];
        for (var j = 0; j < rb.length; j++) {
          final mid = _overlapMiddle(p, q, rb[j], rb[(j + 1) % rb.length]);
          if (mid == null) continue;
          if (!_onAnyCut(mid, cuts)) return true;
        }
      }
    }
  }
  return false;
}

/// Middle of the stretch where segments p–q and r–s lie on one another, or
/// null when they only touch or do not meet.
Offset? _overlapMiddle(Offset p, Offset q, Offset r, Offset s) {
  final d = q - p;
  final length = d.distance;
  if (length < _kEps) return null;
  final u = d / length;
  double off(Offset x) => (x - p).dx * u.dy - (x - p).dy * u.dx;
  if (off(r).abs() > 1e-3 || off(s).abs() > 1e-3) return null;
  double along(Offset x) => (x - p).dx * u.dx + (x - p).dy * u.dy;
  final lo = math.max(0.0, math.min(along(r), along(s)));
  final hi = math.min(length, math.max(along(r), along(s)));
  if (hi - lo < 1e-3) return null;
  return p + u * ((lo + hi) / 2);
}

bool _onAnyCut(Offset point, List<List<Offset>> cuts) {
  for (final cut in cuts) {
    for (var i = 0; i + 1 < cut.length; i++) {
      final a = cut[i];
      final b = cut[i + 1];
      final ab = b - a;
      final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
      if (len2 < 1e-12) continue;
      final t = (((point.dx - a.dx) * ab.dx + (point.dy - a.dy) * ab.dy) / len2)
          .clamp(0.0, 1.0);
      if ((point - (a + ab * t)).distance < 1e-3) return true;
    }
  }
  return false;
}

double _sheetArea(PapercutSheet sheet) {
  var total = 0.0;
  for (final piece in sheet.pieces) {
    total += polygonSignedArea(piece.vertices).abs();
    for (final hole in piece.holes) {
      total -= polygonSignedArea(hole).abs();
    }
  }
  return total;
}

/// Where the folder will crease [paper] for an aim at [deskAim], in desk
/// coordinates, or null when the aim is off the paper.
({FolderGuide guide, Offset a, Offset b, Offset? flap})? benchFolderGuide(
  BenchPaper paper,
  Offset deskAim,
) {
  final guide = folderGuide(paper.toLocal(deskAim), paper.sheet, kBenchGrid);
  if (guide == null) return null;
  final (a, b) = guide.drawn;
  final flap = guide.flap;
  return (
    guide: guide,
    a: paper.toDesk(a),
    b: paper.toDesk(b),
    flap: flap == null ? null : paper.toDesk(flap + guide.separation),
  );
}

/// [paper] folded along [guide], its flap over toward the viewer. Null when
/// the fold is blocked.
BenchPaper? foldBench(BenchPaper paper, FolderGuide guide) {
  final flap = guide.flap;
  if (flap == null) return null;
  final folded = foldSheet(
    sheet: paper.sheet,
    spanA: guide.line.$1,
    spanB: guide.line.$2,
    flapPoint: flap,
    facing: FoldFacing.toward,
    cutShift: guide.separation,
    pieceId: guide.pieceId,
  );
  if (folded == null) return null;
  return paper.copyWith(sheet: folded);
}

/// Opens the fold of [paper] nearest [deskPoint], or null when none is near.
BenchPaper? unfoldBench(BenchPaper paper, Offset deskPoint) {
  final opened = unfoldAt(paper.sheet, paper.toLocal(deskPoint));
  if (opened == null) return null;
  return paper.copyWith(sheet: opened);
}

/// The crease of [paper] that [unfoldBench] would open, on the desk.
(Offset, Offset)? benchUnfoldCue(BenchPaper paper, Offset deskPoint) {
  final cue = unfoldCue(paper.sheet, paper.toLocal(deskPoint));
  if (cue == null) return null;
  return (paper.toDesk(cue.$1), paper.toDesk(cue.$2));
}
