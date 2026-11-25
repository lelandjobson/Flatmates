import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/harvest_meshes.dart';
import 'package:flatmates/protoplane/models.dart';
import 'layered_terrain_test.dart' show centerId, drawTile, snapshot;

void main() {
  testWidgets('atlas updates columns only, stable pans and restore signatures', (
    tester,
  ) async {
    final c = ProtoplaneController();
    final cache = HarvestMeshCache();
    addTearDown(c.dispose);
    addTearDown(cache.dispose);
    final before = snapshot(c);
    cache.synchronize(c.planes.values, c.landscape);
    final initial = cache.rasterizedTiles;
    final wallMeshes = cache.walls(c.landscape.terrain).toList();
    expect(wallMeshes.length, greaterThan(6));
    final initialWalls = cache.rebuiltWalls;
    final image = cache.atlas.image;
    final watch = Stopwatch()..start();
    for (var i = 0; i < 120; i++) {
      cache.synchronize(c.planes.values, c.landscape);
    }
    watch.stop();
    // ignore: avoid_print
    print(
      'Layered terrain 120 cache-only pan checks: ${watch.elapsedMilliseconds} ms; $initial slots',
    );
    expect(cache.rasterizedTiles, initial);
    expect(cache.atlas.image, same(image));
    final id = centerId(c, PaperMaterial.paperWhite);
    c.enter(id);
    drawTile(c);
    c.commitDrawing();
    cache.synchronize(c.planes.values, c.landscape);
    cache.walls(c.landscape.terrain).toList();
    expect(cache.rasterizedTiles, initial + 3);
    expect(cache.rebuiltWalls, initialWalls + 1);
    c.undo();
    expect(snapshot(c), before);
    cache.synchronize(c.planes.values, c.landscape);
    expect(cache.rasterizedTiles, initial + 6);
    c.redo();
    cache.synchronize(c.planes.values, c.landscape);
    expect(cache.rasterizedTiles, initial + 9);
  });
}
