import 'dart:ui';

import 'package:flatmates/asmr/asmr_cube.dart';
import 'package:flatmates/asmr/asmr_net.dart';
import 'package:flatmates/asmr/hologram_selection.dart';
import 'package:flatmates/gridcraft/edit.dart';
import 'package:flatmates/gridcraft/wrap_cut.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _faces(HologramSelection s) => [for (final p in s.picks) p.face];

void main() {
  final model = asmrCubeModel();
  final adjacency = faceAdjacency(model);

  test('a marquee to the right takes only faces inside the box', () {
    final projected = <List<Offset>?>[
      [const Offset(0, 0), const Offset(10, 0), const Offset(10, 10)],
      [const Offset(20, 0), const Offset(30, 0), const Offset(30, 10)],
      [const Offset(0, 20), const Offset(40, 20), const Offset(40, 30)],
      null,
    ];
    final hits = marqueeFaces(
      projected,
      const Rect.fromLTRB(0, 0, 12, 12),
      MarqueePick.contain,
    );
    expect(hits, {0});
  });

  test('a marquee to the left also takes faces the box crosses', () {
    final projected = <List<Offset>?>[
      [const Offset(0, 0), const Offset(10, 0), const Offset(10, 10)],
      [const Offset(8, 0), const Offset(20, 0), const Offset(20, 10)],
    ];
    final hits = marqueeFaces(
      projected,
      const Rect.fromLTRB(0, 0, 12, 12),
      MarqueePick.cross,
    );
    expect(hits, {0, 1});
  });

  test('selected faces hinge to the neighbor they were reached from', () {
    final a = 0;
    final b = adjacency[a].first!.face;
    final c = adjacency[b]
        .map((n) => n!.face)
        .firstWhere((f) => f != a && adjacency[a].any((n) => n?.face == f));
    final picks = hologramPicks({a, b, c}, adjacency, prefer: b);
    expect(picks.first, HologramPick(b));
    expect(picks.map((p) => p.face).toSet(), {a, b, c});
    for (final pick in picks.skip(1)) {
      expect(pick.from, isNotNull);
      expect(adjacency[pick.from!].any((n) => n?.face == pick.face), isTrue);
    }
  });

  test('a face sharing no edge stays its own component', () {
    final opposite = [
      for (var f = 1; f < model.faces.length; f++)
        if (!adjacency[0].any((n) => n?.face == f)) f,
    ].single;
    final picks = hologramPicks({0, opposite}, adjacency, prefer: 0);
    expect(picks, [const HologramPick(0), HologramPick(opposite)]);
  });

  test('replacing the selection reports whether it changed', () {
    final s = HologramSelection();
    expect(s.replace([const HologramPick(1)]), isTrue);
    expect(s.replace([const HologramPick(1)]), isFalse);
    expect(s.replace(const []), isTrue);
    expect(_faces(s), isEmpty);
    expect(s.contains(1), isFalse);
  });
}
