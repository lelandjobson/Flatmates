import 'dart:math' as math;
import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

import '../asmr/asmr_net.dart';
import '../asmr/hologram_selection.dart';
import '../gridcraft/blueprint.dart' show polygonBounds;
import '../gridcraft/folded_model.dart';
import '../gridcraft/wrap_cut.dart' show FaceNeighbor;
import 'bench_paper.dart';
import 'craft_theme.dart';

/// Grid squares between a group and the group merged into it.
const double kMergeGap = 3;

/// Faces picked on the model, their net laid out on the bench, and the
/// bench paper cut for them: everything done on the desk while the group is
/// shown.
///
/// A saved group has a [letter], A to E. The null group has no letter and
/// no faces; it holds the desk while nothing is selected. Each net island
/// can be moved and turned on its own; [net] holds that layout.
class CraftGroup {
  const CraftGroup({
    this.letter,
    required this.picks,
    required this.net,
    this.papers = const [],
  });

  /// The null group, empty.
  static final CraftGroup none = CraftGroup(
    picks: const [],
    net: AsmrNet.empty,
  );

  /// 0 for A, 1 for B, through 4 for E. Null for the null group, and for a
  /// selection not saved yet.
  final int? letter;
  final List<HologramPick> picks;
  final AsmrNet net;
  final List<BenchPaper> papers;

  bool get saved => letter != null;

  Set<int> get faces => {for (final pick in picks) pick.face};

  String get name => saved ? String.fromCharCode(0x41 + letter! % 26) : '';

  CraftTheme get theme => saved ? craftGroupTheme(letter!) : kCraftNoneTheme;

  Color get color => theme.accent;

  CraftGroup copyWith({
    int? letter,
    List<HologramPick>? picks,
    AsmrNet? net,
    List<BenchPaper>? papers,
  }) => CraftGroup(
    letter: letter ?? this.letter,
    picks: picks ?? this.picks,
    net: net ?? this.net,
    papers: papers ?? this.papers,
  );
}

/// [picks] unfolded one model unit to a grid square, slid so the net's top
/// left corner sits on a grid point.
AsmrNet gridNet(
  FoldedModel model,
  List<List<FaceNeighbor?>> adjacency,
  List<HologramPick> picks,
) {
  final net = unfoldSelection(model, adjacency, picks, scale: kBenchGrid);
  if (net.isEmpty) return net;
  final corner = net.bounds.topLeft;
  final shift = Offset(
    (corner.dx / kBenchGrid).roundToDouble() * kBenchGrid - corner.dx,
    (corner.dy / kBenchGrid).roundToDouble() * kBenchGrid - corner.dy,
  );
  return shiftedNet(net, shift);
}

/// Every island of [net] slid by [shift].
AsmrNet shiftedNet(AsmrNet net, Offset shift) {
  if (shift.distance < 1e-12) return net;
  final by = Matrix4.translationValues(shift.dx, shift.dy, 0);
  return net.transformedIslands({for (final island in net.islands) island: by});
}

/// Bounds of [island] on the desk.
Rect islandBounds(AsmrNet net, int island) => polygonBounds([
  for (final face in net.faces)
    if (face.island == island) face.ring,
]);

/// The island of [net] whose face holds [desk], if any.
int? islandAt(AsmrNet net, Offset desk) {
  for (final face in net.faces.reversed) {
    if (_inside(desk, face.ring)) return face.island;
  }
  return null;
}

/// The model face whose net face lies under [desk], or null.
int? netFaceAt(AsmrNet net, Offset desk) {
  for (final face in net.faces.reversed) {
    if (_inside(desk, face.ring)) return face.face;
  }
  return null;
}

/// Turns [island] by [angle] about [pivot], then slides it by [shift].
Matrix4 islandMove({
  Offset shift = Offset.zero,
  double angle = 0,
  Offset pivot = Offset.zero,
}) =>
    Matrix4.translationValues(shift.dx + pivot.dx, shift.dy + pivot.dy, 0) *
    Matrix4.rotationZ(angle) *
    Matrix4.translationValues(-pivot.dx, -pivot.dy, 0);

/// [target] with [dropped] merged in. The dropped group's layout, and the
/// paper laid over it, moves to [gap] grid squares right of the target's,
/// tops level. Faces both groups hold stay where the target has them.
CraftGroup mergeGroups(
  CraftGroup target,
  CraftGroup dropped, {
  double gap = kMergeGap,
}) {
  final held = target.faces;
  final keep = [
    for (final face in dropped.net.faces)
      if (!held.contains(face.face)) face,
  ];
  if (keep.isEmpty) return target;
  final kept = {for (final face in keep) face.face};
  final there = target.net.isEmpty ? Rect.zero : target.net.bounds;
  final from = polygonBounds([for (final face in keep) face.ring]);
  final shift = Offset(there.right + gap - from.left, there.top - from.top);
  final islands = target.net.islands;
  final base = islands.isEmpty ? 0 : islands.reduce(math.max) + 1;
  final by = Matrix4.translationValues(shift.dx, shift.dy, 0);
  final moved = AsmrNet.fromParts(
    [
      for (final face in keep)
        AsmrNetFace(
          face: face.face,
          parent: kept.contains(face.parent) ? face.parent : null,
          island: base + face.island,
          faceToNet: by * face.faceToNet,
          ring: [for (final p in face.ring) p + shift],
        ),
    ],
    [
      for (final edge in dropped.net.edges)
        if (kept.contains(edge.face))
          AsmrNetEdge(
            face: edge.face,
            edge: edge.edge,
            a: edge.a + shift,
            b: edge.b + shift,
            fold: edge.fold,
          ),
    ],
  );
  return target.copyWith(
    picks: [
      ...target.picks,
      for (final pick in dropped.picks)
        if (!held.contains(pick.face)) pick,
    ],
    net: AsmrNet.fromParts(
      [...target.net.faces, ...moved.faces],
      [...target.net.edges, ...moved.edges],
    ),
    papers: [
      ...target.papers,
      for (final paper in dropped.papers)
        paper.copyWith(position: paper.position + shift),
    ],
  );
}

/// Every face of [model] that is not in [faces], picked in hinge order.
List<HologramPick> invertedPicks(
  FoldedModel model,
  List<List<FaceNeighbor?>> adjacency,
  Set<int> faces,
) => hologramPicks([
  for (var f = 0; f < model.faces.length; f++)
    if (!faces.contains(f)) f,
], adjacency);

/// The lowest letter no group in [groups] has, or null when A to E are all
/// taken.
int? nextLetter(Iterable<CraftGroup> groups) {
  final used = {for (final group in groups) group.letter};
  for (var letter = 0; letter < kMaxCraftGroups; letter++) {
    if (!used.contains(letter)) return letter;
  }
  return null;
}

/// How a selection of [faces] on the model reads once no face may be in two
/// groups: the group it opens, and the faces in no group, which can be
/// saved as a new group or added to the open one.
///
/// [prefer] is the face that decides between groups: the face tapped, or
/// the one nearest the middle of a marquee. Without it the group with the
/// most faces in the selection is opened. Faces of other groups are let go.
({int? open, Set<int> free}) resolveSelection(
  Set<int> faces,
  Iterable<CraftGroup> groups, {
  int? prefer,
}) {
  final owner = <int, int>{
    for (final group in groups)
      if (group.letter != null)
        for (final face in group.faces) face: group.letter!,
  };
  final free = {
    for (final face in faces)
      if (!owner.containsKey(face)) face,
  };
  int? open = prefer == null ? null : owner[prefer];
  if (open == null) {
    final counts = <int, int>{};
    for (final face in faces) {
      final letter = owner[face];
      if (letter != null) counts[letter] = (counts[letter] ?? 0) + 1;
    }
    var most = 0;
    for (final entry in counts.entries) {
      if (entry.value > most ||
          (entry.value == most && open != null && entry.key < open)) {
        most = entry.value;
        open = entry.key;
      }
    }
  }
  return (open: open, free: free);
}

bool _inside(Offset p, List<Offset> ring) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final a = ring[i];
    final b = ring[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) &&
        p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}
