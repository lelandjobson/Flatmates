import 'package:flatmates/gameplay/paths/path_store.dart';
import 'package:flatmates/gameplay/walls/wall_edge.dart';
import 'package:flatmates/gameplay/walls/wall_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('click places a disconnected island', () {
    final paths = PathStore();
    expect(paths.addIsland(1, 1), isTrue);
    expect(paths.addIsland(2, 1), isTrue);
    expect(paths.tiles, hasLength(2));
    expect(paths.edges, isEmpty);
    expect(paths.hasEdge(1, 1, 2, 1), isFalse);
  });

  test('paintStroke connects tiles along the drag', () {
    final paths = PathStore();
    expect(paths.paintStroke((1, 1), (3, 1)), isTrue);
    expect(paths.contains(1, 1), isTrue);
    expect(paths.contains(2, 1), isTrue);
    expect(paths.contains(3, 1), isTrue);
    expect(paths.hasEdge(1, 1, 2, 1), isTrue);
    expect(paths.hasEdge(2, 1, 3, 1), isTrue);
  });

  test('paintStroke joins two existing islands', () {
    final paths = PathStore()
      ..addIsland(1, 1)
      ..addIsland(4, 1);
    expect(paths.edges, isEmpty);
    expect(paths.paintStroke((1, 1), (4, 1)), isTrue);
    expect(paths.hasEdge(1, 1, 2, 1), isTrue);
    expect(paths.hasEdge(2, 1, 3, 1), isTrue);
    expect(paths.hasEdge(3, 1, 4, 1), isTrue);
    expect(paths.tiles, hasLength(4));
  });

  test('paintStroke between adjacent islands adds only the edge', () {
    final paths = PathStore()
      ..addIsland(2, 2)
      ..addIsland(3, 2);
    expect(paths.paintStroke((2, 2), (3, 2)), isTrue);
    expect(paths.tiles, hasLength(2));
    expect(paths.hasEdge(2, 2, 3, 2), isTrue);
  });

  test('placeAndJoin connects to every 4-adjacent path', () {
    final paths = PathStore()
      ..addIsland(2, 1)
      ..addIsland(3, 2)
      ..addIsland(2, 3)
      ..addIsland(1, 2);
    expect(paths.placeAndJoin(2, 2), isTrue);
    expect(paths.contains(2, 2), isTrue);
    expect(paths.hasEdge(2, 2, 2, 1), isTrue);
    expect(paths.hasEdge(2, 2, 3, 2), isTrue);
    expect(paths.hasEdge(2, 2, 2, 3), isTrue);
    expect(paths.hasEdge(2, 2, 1, 2), isTrue);
  });

  test('severAcross drops the edge and keeps both tiles', () {
    final paths = PathStore()..placeAndJoin(2, 2)..placeAndJoin(3, 2);
    expect(paths.hasEdge(2, 2, 3, 2), isTrue);
    expect(paths.severAcross(WallEdge(3, 2, 3, 3)), isTrue);
    expect(paths.hasEdge(2, 2, 3, 2), isFalse);
    expect(paths.contains(2, 2), isTrue);
    expect(paths.contains(3, 2), isTrue);
  });

  test('paintStroke skippable tiles are not placed', () {
    final paths = PathStore();
    expect(
      paths.paintStroke(
        (1, 1),
        (3, 1),
        skippable: (tx, ty) => tx == 2 && ty == 1,
      ),
      isTrue,
    );
    expect(paths.contains(1, 1), isTrue);
    expect(paths.contains(2, 1), isFalse);
    expect(paths.contains(3, 1), isTrue);
    expect(paths.hasEdge(1, 1, 3, 1), isFalse);
  });

  test('placeAndJoin deletes a wall the new connection would cross', () {
    final walls = WallStore()..add(WallEdge(3, 2, 3, 3));
    final paths = PathStore()..addIsland(3, 2);
    expect(walls.separatesTiles((2, 2), (3, 2)), isTrue);
    expect(paths.placeAndJoin(2, 2, walls: walls), isTrue);
    expect(paths.hasEdge(2, 2, 3, 2), isTrue);
    expect(walls.contains(WallEdge(3, 2, 3, 3)), isFalse);
  });
}
