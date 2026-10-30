import 'dart:math' as math;

import 'package:flatmates/asmr/asmr_cube.dart';
import 'package:flatmates/asmr/asmr_deal.dart';
import 'package:flatmates/asmr/asmr_net.dart';
import 'package:flatmates/asmr/asmr_objects.dart';
import 'package:flatmates/asmr/hologram_selection.dart';
import 'package:flatmates/gridcraft/wrap_cut.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  bool connected(List<int> faces, List<List<FaceNeighbor?>> adjacency) {
    final want = faces.toSet();
    final seen = <int>{faces.first};
    final queue = [faces.first];
    var head = 0;
    while (head < queue.length) {
      final at = queue[head++];
      for (final neighbor in adjacency[at]) {
        final face = neighbor?.face;
        if (face != null && want.contains(face) && seen.add(face)) {
          queue.add(face);
        }
      }
    }
    return seen.length == faces.length;
  }

  void expectPartition(
    List<List<int>> groups,
    int faces, {
    int? count,
    List<List<FaceNeighbor?>>? adjacency,
  }) {
    expect(groups, isNotEmpty);
    if (count != null) {
      expect(groups, hasLength(count));
    } else {
      expect(groups.length, inInclusiveRange(2, 4));
    }
    final flat = [for (final group in groups) ...group];
    expect(flat, hasLength(faces));
    expect(flat.toSet(), hasLength(faces));
    for (final group in groups) {
      expect(group, isNotEmpty);
      if (adjacency != null) expect(connected(group, adjacency), isTrue);
    }
  }

  test('a deal divides every face of the cube into 2, 3, or 4 groups', () {
    final adjacency = faceAdjacency(asmrCubeModel());
    final random = math.Random(7);
    final seen = <int>{};
    for (var i = 0; i < 40; i++) {
      final groups = randomFaceGroups(adjacency, random: random);
      expectPartition(groups, adjacency.length, adjacency: adjacency);
      seen.add(groups.length);
    }
    expect(seen, containsAll(kAsmrGroupCounts));
  });

  test('cube 3-2-1 deals put the triple around a shared corner', () {
    final model = asmrCubeModel();
    final adjacency = faceAdjacency(model);
    final random = math.Random(7);
    final seen = <String>{};
    for (var i = 0; i < 100; i++) {
      final groups = cubeFaceGroups(adjacency, random: random);
      expectPartition(groups, 6, count: 3, adjacency: adjacency);
      expect(groups.map((g) => g.length), [3, 2, 1]);
      final triple = groups.first;
      final sharedCorners = model.faces[triple.first].worldRing().where(
        (point) => triple
            .skip(1)
            .every(
              (face) => model.faces[face].worldRing().any(
                (other) => (point - other).length < 1e-6,
              ),
            ),
      );
      expect(sharedCorners, hasLength(1));
      seen.add(groups.toString());
    }
    expect(seen.length, greaterThan(1));
  });

  test('four groups on the cube leave single faces', () {
    final adjacency = faceAdjacency(asmrCubeModel());
    for (var seed = 0; seed < 20; seed++) {
      final groups = randomFaceGroups(
        adjacency,
        random: math.Random(seed),
        count: 4,
      );
      expectPartition(groups, adjacency.length, count: 4, adjacency: adjacency);
      final sizes = [for (final group in groups) group.length]..sort();
      expect(sizes, [1, 1, 2, 2], reason: 'seed $seed');
    }
  });

  test('the menu lists the cube, the double cube, and the papercrafts', () {
    expect(
      [for (final object in asmrObjects()) object.name],
      ['Cube', 'Double cube', 'Rocket', 'Birdhouse', 'Coffee Cup'],
    );
    final random = math.Random(3);
    for (final object in asmrObjects()) {
      final adjacency = faceAdjacency(object.model);
      final groups = randomFaceGroups(adjacency, random: random);
      expectPartition(groups, object.model.faces.length, adjacency: null);
      for (final group in groups) {
        expect(
          group.every((face) => face >= 0 && face < adjacency.length),
          isTrue,
        );
      }
    }
  });

  test('a dealt net unfolds for every object', () {
    final random = math.Random(1);
    for (final object in asmrObjects()) {
      final adjacency = faceAdjacency(object.model);
      final groups = randomFaceGroups(adjacency, random: random, count: 2);
      for (final faces in groups) {
        final picks = hologramPicks(faces, adjacency);
        final net = unfoldSelection(object.model, adjacency, picks);
        expect(net.faces, isNotEmpty, reason: object.name);
      }
    }
  });

  test('two groups on the double cube cover both cubes', () {
    final model = asmrObjectById('box-stack')!.model;
    final adjacency = faceAdjacency(model);
    final groups = randomFaceGroups(
      adjacency,
      random: math.Random(0),
      count: 2,
    );
    expectPartition(groups, model.faces.length, count: 2);
    expect(model.faces.length, greaterThan(6));
    for (final face in model.faces) {
      expect(
        face.island,
        inInclusiveRange(0, model.islands.length - 1),
        reason: face.id,
      );
    }
    expect(model.foldEdges, hasLength(model.faces.length));
    expect(model.outwardSides, hasLength(model.faces.length));
  });
}
