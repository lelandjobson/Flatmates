import 'package:flatmates/gameplay/outlines/outline_edges.dart';
import 'package:flatmates/gameplay/paths/path_outline.dart';
import 'package:flatmates/gameplay/paths/path_store.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  test('a lone path island has four outer edges', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid)..addIsland(2, 2);
    final edges = buildPathOutline(paths: paths, volumes: volumes);
    expect(edges, hasLength(4));
  });

  test('joining two path tiles drops the shared boundary', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid)
      ..placeAndJoin(2, 2)
      ..placeAndJoin(3, 2);
    final edges = buildPathOutline(paths: paths, volumes: volumes);
    expect(edges.length, greaterThanOrEqualTo(4));
    expect(edges.length, lessThan(16));
    final joinX = volumes.grid.tileOrigin(3, 2).x;
    final interior = edges.where((e) {
      return (e.a.x - joinX).abs() < 1e-6 && (e.b.x - joinX).abs() < 1e-6;
    });
    expect(interior, isEmpty);
  });

  test('path outline store rebuilds when a tile is joined', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid)..addIsland(2, 2);
    final store = PathOutlineStore()
      ..rebuild(paths: paths, volumes: volumes);
    expect(store.edges, hasLength(4));
    paths.placeAndJoin(3, 2);
    store.rebuild(paths: paths, volumes: volumes);
    expect(store.edges.length, greaterThan(4));
    expect(store.edges, isNot(hasLength(4)));
  });

  test('flat path edges hide when the camera is below the paper', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid)..addIsland(2, 2);
    final edges = buildPathOutline(paths: paths, volumes: volumes);
    expect(edges, isNotEmpty);
    expect(
      edges.every((e) => outlineEdgeVisible(e, Vector3(0, 10, 0))),
      isTrue,
    );
    expect(
      edges.every((e) => !outlineEdgeVisible(e, Vector3(0, -10, 0))),
      isTrue,
    );
  });
}
