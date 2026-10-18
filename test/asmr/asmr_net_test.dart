import 'dart:ui';

import 'package:flatmates/asmr/asmr_cube.dart';
import 'package:flatmates/asmr/asmr_net.dart';
import 'package:flatmates/geometry/polygon_union.dart';
import 'package:flatmates/gridcraft/folded_model.dart';
import 'package:flatmates/gridcraft/wrap_cut.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

Vector3 _world(FoldedModel model, AsmrNetFace face, Offset net) =>
    model.faces[face.face].world(applyAffine(face.netToFace, net));

/// Faces in an order where each one after the first touches the one before.
List<HologramPick> _walk(FoldedModel model, List<List<FaceNeighbor?>> adj) {
  final picks = <HologramPick>[const HologramPick(0)];
  final seen = {0};
  var at = 0;
  while (seen.length < model.faces.length) {
    final next = adj[at]
        .map((n) => n?.face)
        .whereType<int>()
        .firstWhere((f) => !seen.contains(f), orElse: () => -1);
    if (next < 0) {
      final any = [
        for (var f = 0; f < model.faces.length; f++)
          if (!seen.contains(f)) f,
      ].first;
      picks.add(HologramPick(any, from: at));
      seen.add(any);
      at = any;
      continue;
    }
    picks.add(HologramPick(next, from: at));
    seen.add(next);
    at = next;
  }
  return picks;
}

void main() {
  final model = asmrCubeModel();
  final adjacency = faceAdjacency(model);

  test('the cube unfolds whole into one non-overlapping island', () {
    final net = unfoldSelection(model, adjacency, _walk(model, adjacency));
    expect(net.faces, hasLength(6));
    expect(net.faces.map((f) => f.island).toSet(), {0});
    for (final face in net.faces) {
      expect(polygonSignedArea(face.ring).abs(), closeTo(2500, 1e-6));
    }
    for (final a in net.faces) {
      for (final b in net.faces) {
        if (identical(a, b)) continue;
        expect(
          isInsidePolygon(polygonCentroid(a.ring), b.ring),
          isFalse,
          reason: '${a.face} overlaps ${b.face}',
        );
      }
    }
    expect(net.bounds.center.dx, closeTo(0, 1e-6));
    expect(net.bounds.center.dy, closeTo(0, 1e-6));
  });

  test('a hinge maps to the same world edge from both faces', () {
    final net = unfoldSelection(model, adjacency, _walk(model, adjacency));
    var folds = 0;
    for (final edge in net.edges.where((e) => e.fold)) {
      folds++;
      final child = net.of(edge.face)!;
      final parent = net.of(child.parent!)!;
      for (final point in [edge.a, edge.b]) {
        final fromChild = _world(model, child, point);
        final fromParent = _world(model, parent, point);
        expect((fromChild - fromParent).length, lessThan(1e-6));
      }
    }
    expect(folds, 5);
  });

  test('every face reads as seen from outside the model', () {
    final net = unfoldSelection(model, adjacency, _walk(model, adjacency));
    for (final face in net.faces) {
      final o = _world(model, face, Offset.zero);
      final x = _world(model, face, const Offset(1, 0)) - o;
      final y = _world(model, face, const Offset(0, 1)) - o;
      final toward = -x.cross(y).normalized();
      expect(
        toward.dot(model.outwardNormal(face.face)),
        closeTo(1, 1e-6),
        reason: 'face ${face.face}',
      );
    }
  });

  test('a face sharing no edge starts a new island to the right', () {
    final opposite = [
      for (var f = 1; f < model.faces.length; f++)
        if (!adjacency[0].any((n) => n?.face == f)) f,
    ].single;
    final net = unfoldSelection(model, adjacency, [
      const HologramPick(0),
      HologramPick(opposite, from: 0),
    ]);
    expect(net.faces.map((f) => f.island).toList(), [0, 1]);
    final first = polygonBounds(net.faces[0].ring);
    final second = polygonBounds(net.faces[1].ring);
    expect(second.left - first.right, closeTo(kAsmrIslandGap, 1e-6));
    expect(net.edges.where((e) => e.fold), isEmpty);
    expect(net.outlines, hasLength(2));
  });

  test('a face hinges to the face the aim left when they touch', () {
    final a = 0;
    final b = adjacency[a].first!.face;
    final c = adjacency[b]
        .map((n) => n!.face)
        .firstWhere((f) => f != a && adjacency[a].any((n) => n?.face == f));
    final net = unfoldSelection(model, adjacency, [
      HologramPick(a),
      HologramPick(b, from: a),
      HologramPick(c, from: b),
    ]);
    expect(net.of(c)!.parent, b);
  });
}

Rect polygonBounds(List<Offset> ring) {
  var box = Rect.fromLTRB(ring.first.dx, ring.first.dy, ring.first.dx, ring.first.dy);
  for (final p in ring) {
    box = box.expandToInclude(Rect.fromLTRB(p.dx, p.dy, p.dx, p.dy));
  }
  return box;
}
