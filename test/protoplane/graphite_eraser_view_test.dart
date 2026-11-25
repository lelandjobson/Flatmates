import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/harvest_meshes.dart';
import 'package:flatmates/protoplane/models.dart';
import 'graphite_eraser_test.dart' show graphiteWorld;

void main() {
  testWidgets('scrub updates two atlas slots per batch and bounded local walls', (
    tester,
  ) async {
    final c = graphiteWorld();
    addTearDown(c.dispose);
    final cache = HarvestMeshCache();
    addTearDown(cache.dispose);
    cache.synchronize(c.planes.values, c.landscape);
    cache.walls(c.landscape.terrain).toList();
    final slots = cache.rasterizedTiles, walls = cache.rebuiltWalls;
    c.beginErasing();
    final times = <int>[];
    for (var row = 0; row < 16; row++) {
      final watch = Stopwatch()..start();
      c.eraseGraphite([
        (Offset(0, (row + .5) / 16), Offset(1, (row + .5) / 16)),
      ]);
      cache.synchronize(c.planes.values, c.landscape);
      cache.walls(c.landscape.terrain).toList();
      watch.stop();
      times.add(watch.elapsedMicroseconds);
    }
    c.finishErasing();
    times.sort();
    debugPrint(
      'Graphite scrub update: median ${times[8]} us, max ${times.last} us; slots ${cache.rasterizedTiles - slots}, wall chunks ${cache.rebuiltWalls - walls}',
    );
    expect(cache.rasterizedTiles, slots + 30);
    expect(cache.rebuiltWalls, lessThanOrEqualTo(walls + 80));
    final image = cache.atlas.image;
    for (var frame = 0; frame < 120; frame++) {
      cache.synchronize(c.planes.values, c.landscape);
    }
    expect(cache.atlas.image, same(image));
    expect(c.balances[PaperMaterial.graphite], 128);
  });
}
