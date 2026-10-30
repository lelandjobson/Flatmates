import 'dart:math' as math;
import 'dart:ui';

import '../geometry/polygon_union.dart' show polygonSignedArea;
import 'asmr_piece.dart';

/// One nearest boundary point per paper piece, measured on screen so picking
/// remains predictable with the pitched scissors camera.
class AsmrScissorAim {
  const AsmrScissorAim({
    required this.pieceId,
    required this.point,
    required this.screen,
    required this.edge,
    required this.inward,
  });
  final String pieceId;
  final Offset point;
  final Offset screen;
  final Offset edge;

  /// Into solid paper, including the reversed direction at hole boundaries.
  final Offset inward;
}

/// Recommends only boundaries within half the piece's shorter local side
/// by default (80 desk units for a fresh 160 × 220 sheet). Measure the
/// cutoff on the desk so zoom, camera pitch, and paper rotation do not
/// change its physical reach. Screen distance still chooses the marker.
List<AsmrScissorAim> scissorAimPoints(
  Iterable<AsmrPiece> pieces,
  Offset reticle,
  Offset Function(Offset) project,
  Offset Function(Offset) unproject, {
  double maxDistanceFraction = 0.5,
}) {
  final result = <AsmrScissorAim>[];
  final deskReticle = unproject(reticle);
  for (final piece in pieces) {
    if (piece.ring.length < 3) continue;
    final bounds = piece.localPath.getBounds();
    final maxDistance =
        math.min(bounds.width, bounds.height) * maxDistanceFraction;
    // Conservative local bounds reject distant fragments before projecting
    // every edge. Holes remain eligible whenever the containing piece is near.
    final local = piece.toLocal(deskReticle);
    final dx = math.max(
      0.0,
      math.max(bounds.left - local.dx, local.dx - bounds.right),
    );
    final dy = math.max(
      0.0,
      math.max(bounds.top - local.dy, local.dy - bounds.bottom),
    );
    if (dx * dx + dy * dy > (maxDistance + 1e-9) * (maxDistance + 1e-9)) {
      continue;
    }
    AsmrScissorAim? best;
    var distance = double.infinity;
    final rings = [piece.deskRing, ...piece.deskHoles];
    for (var r = 0; r < rings.length; r++) {
      final ring = rings[r];
      final interior = polygonSignedArea(ring).sign * (r == 0 ? 1 : -1);
      final projected = [for (final point in ring) project(point)];
      for (var i = 0; i < ring.length; i++) {
        final a = ring[i];
        final b = ring[(i + 1) % ring.length];
        final sa = projected[i];
        final sb = projected[(i + 1) % ring.length];
        if (!sa.dx.isFinite ||
            !sa.dy.isFinite ||
            !sb.dx.isFinite ||
            !sb.dy.isFinite) {
          continue;
        }
        final v = sb - sa;
        final length2 = v.distanceSquared;
        if (length2 < 1e-12) continue;
        final w = reticle - sa;
        // Boost.Geometry closest_points_pt_seg: dot product, clamp to the
        // endpoints, otherwise interpolate by c1/c2.
        final t = ((w.dx * v.dx + w.dy * v.dy) / length2).clamp(0.0, 1.0);
        final screen = sa + v * t;
        final d = (screen - reticle).distanceSquared;
        if (d >= distance) continue;
        distance = d;
        best = AsmrScissorAim(
          pieceId: piece.id,
          point: unproject(screen),
          screen: screen,
          edge: b - a,
          inward:
              Offset(a.dy - b.dy, b.dx - a.dx) / (b - a).distance * interior,
        );
      }
    }
    if (best != null &&
        (best.point - deskReticle).distance <= maxDistance + 1e-9) {
      result.add(best);
    }
  }
  return result;
}

/// Nearest perpendicular orientation, only when already within ten degrees.
/// Tangents are undirected, so crossing the ±π seam does not change the result.
double scissorAimAngle(double angle, Offset edge) {
  final tangent = math.atan2(edge.dy, edge.dx) + angle;
  final correction = -(tangent - (tangent / math.pi).round() * math.pi);
  return correction.abs() <= 10 * math.pi / 180 + 1e-9
      ? angle + correction
      : angle;
}

/// Camera turn toward the prospective inward cut. Nothing changes inside
/// the forward hemisphere. At 90° or beyond, take the shortest turn to put
/// that direction straight up the screen.
double? scissorPreCutOrbitAngle(double cameraAngle, Offset inward) {
  if (inward.distanceSquared < 1e-12) return null;
  final direction = math.atan2(inward.dy, inward.dx) + cameraAngle;
  final delta = -math.pi / 2 - direction;
  final turn = math.atan2(math.sin(delta), math.cos(delta));
  if (turn.abs() < math.pi / 2 - 1e-9) return null;
  return cameraAngle + turn;
}
