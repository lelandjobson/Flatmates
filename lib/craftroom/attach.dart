import 'dart:ui';

import '../asmr/asmr_net.dart';
import '../asmr/asmr_paper.dart';
import '../asmr/asmr_piece.dart';
import '../geometry/polygon_union.dart'
    show isInsidePolygon, polygonCentroid, polygonSignedArea, unionPolygons;
import '../gridcraft/scissor.dart' show ownsPoint;
import 'bench_paper.dart';

/// The white paper the craft room prints on, as the model draws it.
const AsmrPaper kBenchAsmrPaper = AsmrPaper(
  id: 'bench-white',
  name: 'White paper',
  color: kBenchPaperColor,
  pattern: AsmrPattern.plain,
);

/// The faces of [net]'s island [island].
List<AsmrNetFace> islandFaces(AsmrNet net, int island) => [
  for (final face in net.faces)
    if (face.island == island) face,
];

/// Whether [paper], opened flat, lies inside [net]: every corner and each
/// piece's middle sits on a face. A paper that sticks out does not.
bool insideBlueprint(BenchPaper paper, AsmrNet net) {
  if (net.faces.isEmpty) return false;
  bool onNet(Offset point) {
    for (final face in net.faces) {
      if (ownsPoint(face.ring, point)) return true;
    }
    return false;
  }

  for (final piece in paper.sheet.pieces) {
    final ring = [for (final p in piece.vertices) paper.toDesk(p)];
    if (ring.isEmpty || !ring.every(onNet)) return false;
    if (!onNet(polygonCentroid(ring))) return false;
  }
  return paper.sheet.pieces.isNotEmpty;
}

/// The net island [paper] cuts out exactly, or null.
///
/// The test is [isIslandCutout]'s, on the paper's flat outline: every corner
/// of every face of the island lies on the paper, no face's middle sits in a
/// hole, and the paper's area is the island's. Paper folded before the cut
/// is measured opened, so it still matches.
int? matchedIsland(BenchPaper paper, AsmrNet net) {
  if (net.isEmpty) return null;
  final pieces = [
    for (final piece in paper.sheet.pieces)
      (
        ring: [for (final p in piece.vertices) paper.toDesk(p)],
        holes: [
          for (final hole in piece.holes)
            [for (final p in hole) paper.toDesk(p)],
        ],
      ),
  ];
  bool onPaper(Offset point, {bool strict = false}) {
    for (final piece in pieces) {
      final inside = strict
          ? isInsidePolygon(point, piece.ring)
          : ownsPoint(piece.ring, point);
      if (!inside) continue;
      if (piece.holes.any(
        (hole) => isInsidePolygon(point, hole) && !_onRing(point, hole),
      )) {
        continue;
      }
      return true;
    }
    return false;
  }

  final area = paper.area;
  for (final island in net.islands) {
    final faces = islandFaces(net, island);
    var islandArea = 0.0;
    var fits = true;
    for (final face in faces) {
      islandArea += polygonSignedArea(face.ring).abs();
      if (!face.ring.every(onPaper) ||
          !onPaper(polygonCentroid(face.ring), strict: true)) {
        fits = false;
        break;
      }
    }
    if (!fits) continue;
    if ((area - islandArea).abs() < 1e-3 * kBenchGrid * kBenchGrid) {
      return island;
    }
  }
  return null;
}

/// [paper] opened flat as an [AsmrPiece] on the desk, bound to [net].
AsmrPiece boundPiece(BenchPaper paper, AsmrNet net) {
  final rings = paper.flatRings;
  final holes = [
    for (final piece in paper.sheet.pieces)
      for (final hole in piece.holes) [for (final p in hole) paper.toDesk(p)],
  ];
  var outer = rings.first;
  if (rings.length > 1) {
    final loops = unionPolygons(rings);
    var best = -1.0;
    for (final loop in loops) {
      final area = polygonSignedArea(loop).abs();
      if (area > best) {
        best = area;
        outer = loop;
      }
    }
    for (final loop in loops) {
      if (!identical(loop, outer)) holes.add(loop);
    }
  }
  return AsmrPiece(
    id: paper.id,
    paper: kBenchAsmrPaper,
    ring: outer,
    holes: holes,
    liberated: true,
    binding: net,
  );
}

bool _onRing(Offset point, List<Offset> ring) {
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 < 1e-12) continue;
    final t = (((point.dx - a.dx) * ab.dx + (point.dy - a.dy) * ab.dy) / len2)
        .clamp(0.0, 1.0);
    if ((point - (a + ab * t)).distance < 1e-3) return true;
  }
  return false;
}
