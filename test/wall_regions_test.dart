import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/walls/wall_edge.dart';
import 'package:flatmates/gameplay/walls/wall_regions.dart';
import 'package:flatmates/gameplay/walls/wall_store.dart';
import 'package:flutter_test/flutter_test.dart';

void encloseTile(WallStore store, int tx, int ty) {
  store.add(WallEdge(tx, ty, tx + 1, ty));
  store.add(WallEdge(tx + 1, ty, tx + 1, ty + 1));
  store.add(WallEdge(tx, ty + 1, tx + 1, ty + 1));
  store.add(WallEdge(tx, ty, tx, ty + 1));
}

void main() {
  test('open fences do not enclose a region or the whole map', () {
    final store = WallStore();
    store.add(WallEdge(2, 2, 3, 2));
    store.add(WallEdge(3, 2, 4, 2));
    store.add(WallEdge(4, 2, 4, 3));
    expect(computeEnclosedRegions(store), isEmpty);
    expect(enclosedTilesOf(computeEnclosedRegions(store)), isEmpty);
  });

  test('empty walls enclose nothing', () {
    final store = WallStore();
    expect(computeEnclosedRegions(store), isEmpty);
  });

  test('world border is the map perimeter', () {
    final edges = worldBorderEdges(const VolumeGrid(tilesSide: 16));
    expect(edges, hasLength(64));
    expect(edges, contains(WallEdge(0, 0, 1, 0)));
    expect(edges, contains(WallEdge(0, 0, 0, 1)));
    expect(edges, contains(WallEdge(15, 0, 16, 0)));
    expect(edges, contains(WallEdge(16, 15, 16, 16)));
  });

  test('a closed loop around one tile is an enclosed region', () {
    final store = WallStore();
    encloseTile(store, 3, 4);
    final regions = computeEnclosedRegions(store);
    expect(regions, hasLength(1));
    expect(regions.single.tiles, {(3, 4)});
  });

  test('a 2x2 outer fence encloses four tiles', () {
    final store = WallStore();
    // Outer rectangle from (2,2) to (4,4).
    store.add(WallEdge(2, 2, 3, 2));
    store.add(WallEdge(3, 2, 4, 2));
    store.add(WallEdge(4, 2, 4, 3));
    store.add(WallEdge(4, 3, 4, 4));
    store.add(WallEdge(3, 4, 4, 4));
    store.add(WallEdge(2, 4, 3, 4));
    store.add(WallEdge(2, 3, 2, 4));
    store.add(WallEdge(2, 2, 2, 3));
    final regions = computeEnclosedRegions(store);
    expect(regions, hasLength(1));
    expect(regions.single.tiles, {(2, 2), (3, 2), (2, 3), (3, 3)});
  });

  test('removing one fence unencloses the tile', () {
    final store = WallStore();
    encloseTile(store, 1, 1);
    expect(enclosedTilesOf(computeEnclosedRegions(store)), {(1, 1)});
    expect(store.remove(WallEdge(1, 1, 2, 1)), isTrue);
    expect(computeEnclosedRegions(store), isEmpty);
  });

  test('two separate yards are two regions', () {
    final store = WallStore();
    encloseTile(store, 1, 1);
    encloseTile(store, 5, 6);
    final regions = computeEnclosedRegions(store);
    expect(regions, hasLength(2));
    final tiles = enclosedTilesOf(regions);
    expect(tiles, {(1, 1), (5, 6)});
    expect(wallRegionContaining(regions, 5, 6)?.tiles, {(5, 6)});
    expect(wallRegionContaining(regions, 2, 2), isNull);
  });

  test('two rooms that share a wall are distinct inner faces', () {
    final store = WallStore();
    encloseTile(store, 2, 2);
    encloseTile(store, 3, 2);
    final regions = computeEnclosedRegions(store);
    expect(regions, hasLength(2));
    expect(
      regions.map((r) => r.tiles).toSet(),
      {
        {(2, 2)},
        {(3, 2)},
      },
    );
    final outlines = [for (final r in regions) r.outline.toSet()];
    expect(
      outlines.any((o) => o.contains(WallEdge(3, 2, 3, 3))),
      isTrue,
    );
    expect(
      tileSetOutline({(2, 2), (3, 2)}).contains(WallEdge(3, 2, 3, 3)),
      isFalse,
    );
  });

  test('a divider splits one yard into two regions', () {
    final store = WallStore();
    store.add(WallEdge(2, 2, 3, 2));
    store.add(WallEdge(3, 2, 4, 2));
    store.add(WallEdge(4, 2, 4, 3));
    store.add(WallEdge(4, 3, 4, 4));
    store.add(WallEdge(3, 4, 4, 4));
    store.add(WallEdge(2, 4, 3, 4));
    store.add(WallEdge(2, 3, 2, 4));
    store.add(WallEdge(2, 2, 2, 3));
    store.add(WallEdge(3, 2, 3, 3));
    store.add(WallEdge(3, 3, 3, 4));
    final regions = computeEnclosedRegions(store);
    expect(regions, hasLength(2));
    expect(
      regions.map((r) => r.tiles).toSet(),
      {
        {(2, 2), (2, 3)},
        {(3, 2), (3, 3)},
      },
    );
  });

  test('tileSetOutline is the perimeter of the enclosed tiles', () {
    final outline = tileSetOutline({(2, 2)});
    expect(outline, hasLength(4));
    expect(outline, containsAll([
      WallEdge(2, 2, 3, 2),
      WallEdge(3, 2, 3, 3),
      WallEdge(2, 3, 3, 3),
      WallEdge(2, 2, 2, 3),
    ]));
  });
}
