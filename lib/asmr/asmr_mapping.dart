import 'dart:ui';

import '../geometry/geometry_algorithms.dart' show segmentIntersection;
import '../geometry/polygon_union.dart';
import '../gridcraft/blueprint.dart' show pointBounds;
import '../gridcraft/folded_model.dart';
import '../papercut/paper.dart';
import '../papercut/split.dart';
import 'asmr_net.dart';
import 'asmr_piece.dart';

/// Share of a face that must be covered for it to count as filled.
const double kAsmrFilled = 0.98;

/// Desk units within which a stretch of overhang outline counts as lying on
/// a net face's edge.
const double _kOnEdge = 0.05;

/// The part of a bound piece that lies on one net face, in paper coordinates.
/// A sheet that crosses a fold is sliced along that fold, so each face gets
/// only the paper on it. The desk piece stays whole.
class AsmrSlice {
  const AsmrSlice({
    required this.face,
    required this.ring,
    this.holes = const [],
  });

  final int face;
  final List<Offset> ring;
  final List<List<Offset>> holes;

  Path get localPath => _evenOddPath(ring, holes);
}

/// Paper of a bound piece that hangs past its net, in paper coordinates. It
/// lies flat in the plane of net face [face], the face it hangs off. A margin
/// that runs along several faces is split at the folds, so each face carries
/// only the paper hanging off its own edges.
class AsmrOverhang {
  const AsmrOverhang({
    required this.face,
    required this.ring,
    this.holes = const [],
  });

  final int face;
  final List<Offset> ring;
  final List<List<Offset>> holes;

  Path get localPath => _evenOddPath(ring, holes);
}

Path _evenOddPath(List<Offset> ring, List<List<Offset>> holes) {
  final path = Path()..fillType = PathFillType.evenOdd;
  for (final loop in [ring, ...holes]) {
    if (loop.length < 3) continue;
    path.moveTo(loop.first.dx, loop.first.dy);
    for (final p in loop.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    path.close();
  }
  return path;
}

final Expando<List<AsmrOverhang>> _overhangCache = Expando();
final Expando<List<AsmrSlice>> _sliceCache = Expando();

/// The parts of [piece] that lie on its net's faces, one per face it covers.
/// Computed once per piece and kept in memory: moving the piece makes a new
/// one. The cut exists only for the model, so the desk still shows one sheet.
List<AsmrSlice> slicesOf(AsmrPiece piece) =>
    _sliceCache[piece] ??= _slices(piece);

List<AsmrSlice> _slices(AsmrPiece piece) {
  final net = piece.binding;
  if (net == null || net.isEmpty) return const [];
  final whole = PapercutPiece(
    id: piece.id,
    color: piece.paper.color,
    vertices: piece.ring,
    holes: piece.holes,
  );
  final result = <AsmrSlice>[];
  for (final face in net.faces) {
    if (face.ring.length < 3) continue;
    final local = [for (final point in face.ring) piece.toLocal(point)];
    final split = applyPapercutCuts(PapercutSheet(pieces: [whole]), [
      [...local, local.first],
    ], recordStroke: false);
    for (final part in split?.pieces ?? [whole]) {
      final probe = _solidPoint(part);
      if (probe == null) continue;
      if (!isInsidePolygon(piece.toDesk(probe), face.ring)) continue;
      result.add(
        AsmrSlice(face: face.face, ring: part.vertices, holes: part.holes),
      );
    }
  }
  return result;
}

/// The parts of [piece] outside its binding's net that touch it, each given
/// to the net face it shares the most outline with. Paper that does not
/// touch the net is left out. Fold lines are cut through the margin, so a
/// strip that runs past several faces is not left whole on the one face it
/// touches most.
List<AsmrOverhang> overhangOf(AsmrPiece piece) =>
    _overhangCache[piece] ??= _overhang(piece);

List<AsmrOverhang> _overhang(AsmrPiece piece) {
  final net = piece.binding;
  if (net == null || net.isEmpty) return const [];
  final whole = PapercutPiece(
    id: piece.id,
    color: piece.paper.color,
    vertices: piece.ring,
    holes: piece.holes,
  );
  final strokes = <List<Offset>>[
    for (final outline in net.outlines)
      if (outline.length >= 3)
        [
          for (final p in [...outline, outline.first]) piece.toLocal(p),
        ],
    for (final edge in net.edges)
      if (edge.fold) _acrossPiece(piece, edge.a, edge.b),
  ];
  final parts =
      applyPapercutCuts(
        PapercutSheet(pieces: [whole]),
        strokes,
        recordStroke: false,
      )?.pieces ??
      [whole];
  final result = <AsmrOverhang>[];
  for (final part in parts) {
    final inside = _solidPoint(part);
    if (inside == null) continue;
    final desk = piece.toDesk(inside);
    if (net.faces.any((face) => isInsidePolygon(desk, face.ring))) continue;
    final shared = <int, double>{};
    for (final loop in [part.vertices, ...part.holes]) {
      for (var i = 0; i < loop.length; i++) {
        final a = piece.toDesk(loop[i]);
        final b = piece.toDesk(loop[(i + 1) % loop.length]);
        final length = (b - a).distance;
        if (length < 1e-9) continue;
        final mid = (a + b) / 2;
        for (final face in net.faces) {
          if (_onRing(mid, face.ring)) {
            shared[face.face] = (shared[face.face] ?? 0) + length;
            break;
          }
        }
      }
    }
    if (shared.isEmpty) continue;
    final face = shared.entries.reduce((a, b) => b.value > a.value ? b : a).key;
    result.add(
      AsmrOverhang(face: face, ring: part.vertices, holes: part.holes),
    );
  }
  return result;
}

/// [a]–[b] extended both ways until it crosses [piece]. The fold itself sits
/// inside the net; the extension is what divides the margin between faces.
List<Offset> _acrossPiece(AsmrPiece piece, Offset a, Offset b) {
  final start = piece.toLocal(a);
  final end = piece.toLocal(b);
  final dir = end - start;
  final len = dir.distance;
  if (len < 1e-6) return const [];
  final ring = piece.ring;
  var minX = ring.first.dx;
  var maxX = minX;
  var minY = ring.first.dy;
  var maxY = minY;
  for (final p in ring) {
    if (p.dx < minX) minX = p.dx;
    if (p.dx > maxX) maxX = p.dx;
    if (p.dy < minY) minY = p.dy;
    if (p.dy > maxY) maxY = p.dy;
  }
  final unit = dir / len;
  final span = (maxX - minX) + (maxY - minY) + len + 1;
  return [start - unit * span, end + unit * span];
}

/// A point just inside [part]'s paper, off its holes, or null for a sliver.
Offset? _solidPoint(PapercutPiece part) {
  bool solid(Offset p) =>
      isInsidePolygon(p, part.vertices) &&
      !part.holes.any((hole) => isInsidePolygon(p, hole));
  final ring = part.vertices;
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    final d = b - a;
    final length = d.distance;
    if (length < 0.2) continue;
    final normal = Offset(-d.dy, d.dx) / length * 0.05;
    final mid = (a + b) / 2;
    for (final p in [mid + normal, mid - normal]) {
      if (solid(p)) return p;
    }
  }
  return null;
}

bool _onRing(Offset p, List<Offset> ring) {
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 < 1e-12) continue;
    final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2).clamp(
      0.0,
      1.0,
    );
    if ((p - (a + ab * t)).distance <= _kOnEdge) return true;
  }
  return false;
}

/// Points spread over [ring], at the middles of an [n] by [n] grid over its
/// bounds.
List<Offset> _samples(List<Offset> ring, int n) {
  final box = pointBounds(ring);
  return [
    for (var i = 0; i < n; i++)
      for (var j = 0; j < n; j++)
        if (Offset(
              box.left + (i + 0.5) / n * box.width,
              box.top + (j + 0.5) / n * box.height,
            )
            case final p when isInsidePolygon(p, ring))
          p,
  ];
}

/// Per model face, the share of it that bound paper covers. Overhang does
/// not count.
Map<int, double> faceCoverage(
  FoldedModel model,
  Iterable<AsmrPiece> pieces, {
  int samples = 14,
}) {
  final bound = [
    for (final piece in pieces)
      if (piece.binding != null) piece,
  ];
  final coverage = <int, double>{};
  for (var f = 0; f < model.faces.length; f++) {
    final points = _samples(model.faces[f].outline, samples);
    if (points.isEmpty) {
      coverage[f] = 0;
      continue;
    }
    var covered = 0;
    for (final point in points) {
      for (final piece in bound) {
        final netFace = piece.binding!.of(f);
        if (netFace == null) continue;
        final desk = applyAffine(netFace.faceToNet, point);
        if (piece.contains(desk)) {
          covered++;
          break;
        }
      }
    }
    coverage[f] = covered / points.length;
  }
  return coverage;
}

/// Desk units within which paper counts as touching a blueprint edge.
const double kAsmrBlueprintTouch = 0.5;

/// Whether [piece] touches an outer edge of [net]. Fold lines inside the
/// blueprint do not count, and paper that only covers a face's middle does
/// not either.
bool onBlueprintEdge(AsmrPiece piece, AsmrNet net) {
  if (net.isEmpty) return false;
  for (final outline in net.outlines) {
    for (var i = 0; i < outline.length; i++) {
      final a = outline[i];
      final b = outline[(i + 1) % outline.length];
      if (_edgeMeetsPiece(a, b, piece)) return true;
    }
  }
  return false;
}

bool _edgeMeetsPiece(Offset a, Offset b, AsmrPiece piece) {
  if (piece.contains(a) || piece.contains(b) || piece.contains((a + b) / 2)) {
    return true;
  }
  final rings = [piece.deskRing, ...piece.deskHoles];
  for (final ring in rings) {
    for (var i = 0; i < ring.length; i++) {
      final c = ring[i];
      final d = ring[(i + 1) % ring.length];
      if (segmentIntersection(a, b, c, d).hasIntersection) return true;
      if (_distanceToSegment(c, a, b) <= kAsmrBlueprintTouch) return true;
    }
  }
  return false;
}

double _distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 < 1e-12) return (p - a).distance;
  final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2).clamp(
    0.0,
    1.0,
  );
  return (p - (a + ab * t)).distance;
}

/// Whether [piece] covers any of [net]'s faces.
bool overlapsNet(AsmrPiece piece, AsmrNet net) {
  for (final face in net.faces) {
    for (final point in _samples(face.ring, 10)) {
      if (piece.contains(point)) return true;
    }
    for (final point in piece.deskRing) {
      if (isInsidePolygon(point, face.ring)) return true;
    }
  }
  return false;
}
