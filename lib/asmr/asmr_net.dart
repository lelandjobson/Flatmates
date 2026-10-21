import 'dart:math' as math;
import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

import '../geometry/polygon_union.dart' show polygonCentroid, unionPolygons;
import '../gridcraft/blueprint.dart' show polygonBounds;
import '../gridcraft/folded_model.dart';
import '../gridcraft/wrap_cut.dart' show FaceNeighbor;

/// Desk units per model unit: a 5-unit cube face is 50 across on the desk.
const double kAsmrNetScale = 10;

/// Space between the islands of one hologram, in desk units.
const double kAsmrIslandGap = 10;

/// A model face in the hologram. [from] is the face the aim left to reach
/// it, which it hinges to when they share an edge.
class HologramPick {
  const HologramPick(this.face, {this.from});

  final int face;
  final int? from;

  @override
  bool operator ==(Object other) =>
      other is HologramPick && other.face == face && other.from == from;

  @override
  int get hashCode => Object.hash(face, from);
}

/// One model face laid flat in a hologram, in desk units. The desk shows
/// each face as seen from outside the model.
class AsmrNetFace {
  AsmrNetFace({
    required this.face,
    required this.parent,
    required this.island,
    required this.faceToNet,
    required this.ring,
  }) : netToFace = Matrix4.inverted(faceToNet);

  final int face;

  /// The face this one hinges to, null for an island root.
  final int? parent;
  final int island;

  /// Face outline coordinates to the desk.
  final Matrix4 faceToNet;
  final Matrix4 netToFace;

  /// The face outline on the desk.
  final List<Offset> ring;
}

/// An edge of the hologram. A [fold] joins a face to the face it hinges to
/// and is listed once, on the child.
class AsmrNetEdge {
  const AsmrNetEdge({
    required this.face,
    required this.edge,
    required this.a,
    required this.b,
    required this.fold,
  });

  final int face;
  final int edge;
  final Offset a;
  final Offset b;
  final bool fold;

  String get key => '$face:$edge';
}

/// The unfolded blueprint of the selected faces, centered on the desk origin.
class AsmrNet {
  AsmrNet._(this.faces, this.edges);

  /// [faces] and [edges] where they lie, as one net.
  factory AsmrNet.fromParts(List<AsmrNetFace> faces, List<AsmrNetEdge> edges) =>
      AsmrNet._(List.unmodifiable(faces), List.unmodifiable(edges));

  static final AsmrNet empty = AsmrNet._(const [], const []);

  /// The same net with each island in [byIsland] carried on the desk by its
  /// matrix. Other islands stay where they are.
  AsmrNet transformedIslands(Map<int, Matrix4> byIsland) {
    if (byIsland.isEmpty) return this;
    final islandOf = {for (final face in faces) face.face: face.island};
    return AsmrNet._(
      [
        for (final face in faces)
          if (byIsland[face.island] case final by?)
            AsmrNetFace(
              face: face.face,
              parent: face.parent,
              island: face.island,
              faceToNet: by * face.faceToNet,
              ring: [for (final p in face.ring) applyAffine(by, p)],
            )
          else
            face,
      ],
      [
        for (final edge in edges)
          if (byIsland[islandOf[edge.face]] case final by?)
            AsmrNetEdge(
              face: edge.face,
              edge: edge.edge,
              a: applyAffine(by, edge.a),
              b: applyAffine(by, edge.b),
              fold: edge.fold,
            )
          else
            edge,
      ],
    );
  }

  final List<AsmrNetFace> faces;
  final List<AsmrNetEdge> edges;

  late final Map<int, AsmrNetFace> _byFace = {
    for (final face in faces) face.face: face,
  };

  bool get isEmpty => faces.isEmpty;

  /// Island indexes, in face order.
  late final List<int> islands = {
    for (final face in faces) face.island,
  }.toList();

  AsmrNetFace? of(int face) => _byFace[face];

  late final Rect bounds = faces.isEmpty
      ? Rect.zero
      : polygonBounds([for (final face in faces) face.ring]);

  /// Outline of each island, as one or more loops.
  late final List<List<Offset>> outlines = () {
    final islands = <int, List<List<Offset>>>{};
    for (final face in faces) {
      (islands[face.island] ??= []).add(face.ring);
    }
    return [for (final rings in islands.values) ...unionPolygons(rings)];
  }();
}

/// Sets the islands of [placed] in a row. Each island keeps the shape it
/// unfolded to; only a translation is applied, from its bounding box.
void _packIslands(Map<int, AsmrNetFace> placed, List<int> order) {
  final byIsland = <int, List<int>>{};
  for (final face in order) {
    (byIsland[placed[face]!.island] ??= []).add(face);
  }
  if (byIsland.length < 2) return;
  final ids = byIsland.keys.toList()..sort();
  Rect boxOf(int island) =>
      polygonBounds([for (final face in byIsland[island]!) placed[face]!.ring]);
  var cursor = boxOf(ids.first).right;
  final rowCenter = boxOf(ids.first).center.dy;
  for (final island in ids.skip(1)) {
    final box = boxOf(island);
    final dx = cursor + kAsmrIslandGap - box.left;
    final dy = rowCenter - box.center.dy;
    cursor = box.right + dx;
    if (dx.abs() < 1e-9 && dy.abs() < 1e-9) continue;
    final shift = Matrix4.translationValues(dx, dy, 0);
    final delta = Offset(dx, dy);
    for (final face in byIsland[island]!) {
      final held = placed[face]!;
      placed[face] = AsmrNetFace(
        face: held.face,
        parent: held.parent,
        island: held.island,
        faceToNet: shift * held.faceToNet,
        ring: [for (final p in held.ring) p + delta],
      );
    }
  }
}

Offset applyAffine(Matrix4 m, Offset p) {
  final v = m.transformed3(Vector3(p.dx, p.dy, 0));
  return Offset(v.x, v.y);
}

/// Lays [picks] flat, in order. Each face hinges to its [HologramPick.from]
/// face when that is placed, shares an edge with it, and belongs to the same
/// volume. Otherwise it hinges to the earliest placed face of that volume
/// that it touches. A face with no such neighbor starts a new island, which
/// is how separate volumes stay separate even where they meet in 3D. Islands
/// are then set in a row, [kAsmrIslandGap] apart, by each island's bounding
/// box, so one volume does not land on another.
AsmrNet unfoldSelection(
  FoldedModel model,
  List<List<FaceNeighbor?>> adjacency,
  List<HologramPick> picks, {
  double scale = kAsmrNetScale,
}) {
  final placed = <int, AsmrNetFace>{};
  final order = <int>[];
  var islands = 0;

  for (final pick in picks) {
    final face = pick.face;
    if (face < 0 || face >= model.faces.length) continue;
    if (placed.containsKey(face)) continue;
    final base = _outsideView(model, face, scale);

    int? edgeTo(int parent) {
      final edges = adjacency[parent];
      for (var e = 0; e < edges.length; e++) {
        if (edges[e]?.face == face) return e;
      }
      return null;
    }

    int? parent;
    int? parentEdge;
    final volume = model.faces[face].island;
    bool sameVolume(int other) =>
        placed.containsKey(other) && model.faces[other].island == volume;
    final from = pick.from;
    if (from != null && sameVolume(from)) {
      parentEdge = edgeTo(from);
      if (parentEdge != null) parent = from;
    }
    if (parent == null) {
      for (final other in order) {
        if (!sameVolume(other)) continue;
        final e = edgeTo(other);
        if (e != null) {
          parent = other;
          parentEdge = e;
          break;
        }
      }
    }

    Matrix4 faceToNet;
    int island;
    if (parent == null || parentEdge == null) {
      island = islands++;
      faceToNet = base;
    } else {
      final host = placed[parent]!;
      island = host.island;
      faceToNet = _hinged(model, host, parentEdge, face, base);
    }
    placed[face] = AsmrNetFace(
      face: face,
      parent: parent,
      island: island,
      faceToNet: faceToNet,
      ring: [
        for (final p in model.faces[face].outline) applyAffine(faceToNet, p),
      ],
    );
    order.add(face);
  }

  _packIslands(placed, order);

  if (placed.isEmpty) return AsmrNet.empty;
  final center = polygonBounds([for (final f in placed.values) f.ring]).center;
  final shift = Matrix4.translationValues(-center.dx, -center.dy, 0);
  final faces = [
    for (final face in order)
      () {
        final f = placed[face]!;
        final Matrix4 faceToNet = shift * f.faceToNet;
        return AsmrNetFace(
          face: f.face,
          parent: f.parent,
          island: f.island,
          faceToNet: faceToNet,
          ring: [for (final p in f.ring) p - center],
        );
      }(),
  ];

  final edges = <AsmrNetEdge>[];
  final byFace = {for (final f in faces) f.face: f};
  for (final f in faces) {
    final ring = f.ring;
    for (var e = 0; e < ring.length; e++) {
      final across = adjacency[f.face][e]?.face;
      final hinged =
          across != null &&
          byFace.containsKey(across) &&
          (f.parent == across || byFace[across]!.parent == f.face);
      if (hinged && f.parent != across) continue;
      edges.add(
        AsmrNetEdge(
          face: f.face,
          edge: e,
          a: ring[e],
          b: ring[(e + 1) % ring.length],
          fold: hinged,
        ),
      );
    }
  }
  return AsmrNet._(faces, edges);
}

/// Face outline coordinates to the desk, as the face looks from outside the
/// model: desk x to the right and y down, with the face's +y up.
Matrix4 _outsideView(FoldedModel model, int face, double scale) {
  final side = model.outwardSides[face];
  final mirrored = model.faces[face].toWorld.getRotation().determinant() < 0;
  final sx = (side > 0 ? 1.0 : -1.0) * (mirrored ? -1.0 : 1.0);
  return Matrix4.diagonal3Values(sx * scale, -scale, 1);
}

/// [face] laid against [host] over the host's outline edge [hostEdge].
Matrix4 _hinged(
  FoldedModel model,
  AsmrNetFace host,
  int hostEdge,
  int face,
  Matrix4 base,
) {
  final hostFace = model.faces[host.face];
  final hostOutline = hostFace.outline;
  final pa = hostOutline[hostEdge];
  final pb = hostOutline[(hostEdge + 1) % hostOutline.length];
  final wa = hostFace.world(pa);
  final wb = hostFace.world(pb);
  final child = model.faces[face];
  final outline = child.outline;
  Offset local(Vector3 world) {
    var best = outline.first;
    var bestDistance = double.infinity;
    for (final p in outline) {
      final d = (child.world(p) - world).length2;
      if (d < bestDistance) {
        bestDistance = d;
        best = p;
      }
    }
    return best;
  }

  final ca = applyAffine(base, local(wa));
  final cb = applyAffine(base, local(wb));
  final na = applyAffine(host.faceToNet, pa);
  final nb = applyAffine(host.faceToNet, pb);
  final u = cb - ca;
  final v = nb - na;
  final angle = math.atan2(v.dy, v.dx) - math.atan2(u.dy, u.dx);
  var faceToNet =
      Matrix4.translationValues(na.dx, na.dy, 0) *
      Matrix4.rotationZ(angle) *
      Matrix4.translationValues(-ca.dx, -ca.dy, 0) *
      base;

  double sideOf(Offset p) => v.dx * (p.dy - na.dy) - v.dy * (p.dx - na.dx);
  final hostSide = sideOf(polygonCentroid(host.ring));
  final childSide = sideOf(applyAffine(faceToNet, polygonCentroid(outline)));
  if (hostSide * childSide > 0) {
    final theta = math.atan2(v.dy, v.dx);
    final reflect =
        Matrix4.translationValues(na.dx, na.dy, 0) *
        Matrix4.rotationZ(theta) *
        Matrix4.diagonal3Values(1, -1, 1) *
        Matrix4.rotationZ(-theta) *
        Matrix4.translationValues(-na.dx, -na.dy, 0);
    faceToNet = reflect * faceToNet;
  }
  return faceToNet;
}
