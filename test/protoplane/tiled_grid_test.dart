import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/geometry.dart';

void main() {
  test(
    'tiling preserves motifs, expands coverage and persists without reroll',
    () {
      final region = rectangle(1, 1);
      final motif = floorGrids('test', region, 42).first;
      final tiled = tileFloorGrid(motif, region);
      expect(tiled.nodes.length, greaterThan(motif.nodes.length));
      expect(tiled.nodes.take(motif.nodes.length), motif.nodes);
      expect(tiled.examples, motif.examples);
      expect(tiled.nodes.every(region.contains), isTrue);
      final restored = CraftGrid.fromJson(tiled.toJson());
      expect(tileFloorGrid(restored, region).toJson(), tiled.toJson());
      for (final example in tiled.examples.values) {
        expect(tiled.trace(example), motif.trace(example));
      }
    },
  );
  test('repeated edges do not bridge holes or concave gaps', () {
    final region = Region(
      [
        const Offset(0, 0),
        const Offset(1, 0),
        const Offset(1, 1),
        const Offset(0, 1),
      ],
      [rectangle(.2, .2, origin: const Offset(.65, .4)).outer],
    );
    for (final motif in floorGrids('holes', region, 8)) {
      final tiled = tileFloorGrid(motif, region);
      for (final edge in tiled.edges) {
        final points = edge.points(tiled.nodes);
        for (var i = 1; i < points.length; i++) {
          expect(region.contains((points[i - 1] + points[i]) / 2), isTrue);
        }
      }
    }
  });
}
