import 'dart:ui';

import '../gridcraft/edit.dart' show MarqueePick, polygonInMarquee;
import '../gridcraft/wrap_cut.dart' show FaceNeighbor;
import 'asmr_net.dart';

/// The faces whose unfolded blueprint the hologram shows.
///
/// The orbit tool never changes this. The select tool replaces it: a tap
/// takes one face, a tap off the model clears it, and a marquee takes the
/// faces inside its box.
class HologramSelection {
  List<HologramPick> _picks = const [];

  List<HologramPick> get picks => _picks;

  Set<int> get faces => {for (final pick in _picks) pick.face};

  bool contains(int face) => _picks.any((pick) => pick.face == face);

  /// Replaces the selection. Returns whether it changed.
  bool replace(List<HologramPick> picks) {
    if (picks.length == _picks.length) {
      var same = true;
      for (var i = 0; i < picks.length; i++) {
        if (picks[i] != _picks[i]) {
          same = false;
          break;
        }
      }
      if (same) return false;
    }
    _picks = List.of(picks);
    return true;
  }
}

/// Faces whose screen [projected] outline the marquee takes. A null entry is
/// a face that does not project, and it is left out. Left to right contains;
/// right to left also takes what the box crosses, as [marqueePick] decides.
Set<int> marqueeFaces(
  List<List<Offset>?> projected,
  Rect rect,
  MarqueePick pick,
) {
  final hits = <int>{};
  for (var i = 0; i < projected.length; i++) {
    final ring = projected[i];
    if (ring == null) continue;
    if (polygonInMarquee(ring, rect, pick)) hits.add(i);
  }
  return hits;
}

/// [faces] unfolded in an order where each one after a component's root
/// hinges to the selected neighbor it was reached from. [prefer] is the
/// root when it is one of [faces]: the face nearest the middle of a marquee.
List<HologramPick> hologramPicks(
  Iterable<int> faces,
  List<List<FaceNeighbor?>> adjacency, {
  int? prefer,
}) {
  final remaining = {
    for (final face in faces)
      if (face >= 0 && face < adjacency.length) face,
  };
  if (remaining.isEmpty) return const [];
  final picks = <HologramPick>[];
  while (remaining.isNotEmpty) {
    var start = remaining.reduce((a, b) => a < b ? a : b);
    if (prefer != null && remaining.contains(prefer)) {
      start = prefer;
      prefer = null;
    }
    remaining.remove(start);
    picks.add(HologramPick(start));
    final queue = [start];
    while (queue.isNotEmpty) {
      final at = queue.removeAt(0);
      final neighbors = <int>[];
      for (final neighbor in adjacency[at]) {
        final face = neighbor?.face;
        if (face != null && remaining.contains(face)) neighbors.add(face);
      }
      neighbors.sort();
      for (final face in neighbors) {
        if (!remaining.remove(face)) continue;
        picks.add(HologramPick(face, from: at));
        queue.add(face);
      }
    }
  }
  return picks;
}
