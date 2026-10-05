import 'dart:io';

import 'package:flatmates/geometry/polygon_union.dart';
import 'package:flatmates/gridcraft/blueprint.dart';
import 'package:flatmates/gridcraft/fold.dart';
import 'package:flatmates/gridcraft/level_io.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/grid_play_sim.dart';

const _out = [Offset(-1, 0), Offset(0, -1), Offset(0, 1), Offset(1, 0)];

/// From the paper edge straight in to a vertex of [ring], then once around.
/// The entry line may not touch another blueprint piece. Entries from the left
/// and bottom come first so they do not cross slits left by earlier cuts.
GridCut _cutAround(GridStep step, int index) {
  final ring = step.polygons[index];
  final paper = step.paper;
  final others = [
    for (var i = 0; i < step.polygons.length; i++)
      if (i != index && step.isRingClosed(i)) step.polygons[i],
  ];
  for (final out in _out) {
    for (var v = 0; v < ring.length; v++) {
      final vertex = ring[v];
      if (isInsidePolygon(vertex + out * 0.1, ring)) continue;
      final edge = Offset(
        out.dx < 0 ? paper.left : (out.dx > 0 ? paper.right : vertex.dx),
        out.dy < 0 ? paper.top : (out.dy > 0 ? paper.bottom : vertex.dy),
      );
      if (piecesTouched(others, edge, vertex).isNotEmpty) continue;
      if (piecesTouched([ring], edge, vertex + out * 0.05).isNotEmpty) {
        continue;
      }
      final around = [
        for (var k = 1; k <= ring.length; k++) ring[(v + k) % ring.length],
      ];
      return GridCut.via(edge, [vertex, ...around]);
    }
  }
  throw StateError('piece $index has no clear entry');
}

void _cutsOut(String collection, String slug) {
  test('$collection/$slug: every piece cuts out along its outline', () {
    final step = loadLevel(collection, slug);
    final cuts = [
      for (var i = 0; i < step.polygons.length; i++)
        if (step.isRingClosed(i)) _cutAround(step, i),
    ];
    expect(cuts, isNotEmpty);
    expect(playGridCuts(step, cuts), isNull);
  });
}

void main() {
  for (final slug in ['1-legs', '2-tabletop', '3-shelf', '4-knob']) {
    _cutsOut('side-table', slug);
  }
  _cutsOut('side-table-consolidated', 'side-table');

  test('play shows only the side table collections', () async {
    final collections = await LevelStore(
      directory: Directory('levels'),
    ).loadCollections();
    final shown = [
      for (final collection in collections)
        if (collection.playable case final playable?) playable.name,
    ];
    expect(shown, ['side_table', 'side_table_consolidated']);
  });
}
