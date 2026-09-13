import 'package:flatmates/gameplay/walls/region_tool.dart';
import 'package:flatmates/gameplay/walls/wall_edge.dart';
import 'package:flatmates/gameplay/walls/wall_regions.dart';
import 'package:flatmates/gameplay/walls/wall_store.dart';
import 'package:flutter_test/flutter_test.dart';

void encloseTile(WallStore store, int tx, int ty) {
  for (final edge in tileBoundaryEdges(tx, ty)) {
    store.add(edge);
  }
}

void main() {
  test('isolated fill creates a one-tile region and sets last', () {
    final store = WallStore();
    final result = applyRegionFill(
      walls: store,
      regions: const [],
      tx: 3,
      ty: 4,
      lastSeed: null,
    );
    expect(result.changed, isTrue);
    expect(result.lastSeed, (3, 4));
    expect(result.addEdges, hasLength(4));
    expect(result.removeEdges, isEmpty);
    final regions = computeEnclosedRegions(store);
    expect(regions, hasLength(1));
    expect(regions.single.tiles, {(3, 4)});
  });

  test('second orthogonal fill expands last and drops the shared wall', () {
    final store = WallStore();
    final first = applyRegionFill(
      walls: store,
      regions: const [],
      tx: 3,
      ty: 4,
      lastSeed: null,
    );
    final regions = computeEnclosedRegions(store);
    final second = applyRegionFill(
      walls: store,
      regions: regions,
      tx: 4,
      ty: 4,
      lastSeed: first.lastSeed,
    );
    expect(second.changed, isTrue);
    expect(second.lastSeed, first.lastSeed);
    expect(store.contains(WallEdge(4, 4, 4, 5)), isFalse);
    final next = computeEnclosedRegions(store);
    expect(next, hasLength(1));
    expect(next.single.tiles, {(3, 4), (4, 4)});
  });

  test('fill next to another region while last is set does not merge', () {
    final store = WallStore();
    final first = applyRegionFill(
      walls: store,
      regions: const [],
      tx: 0,
      ty: 0,
      lastSeed: null,
    );
    encloseTile(store, 3, 0);
    final regions = computeEnclosedRegions(store);
    expect(regions, hasLength(2));
    final extra = applyRegionFill(
      walls: store,
      regions: regions,
      tx: 4,
      ty: 0,
      lastSeed: first.lastSeed,
    );
    expect(extra.changed, isTrue);
    expect(extra.lastSeed, first.lastSeed);
    expect(store.contains(WallEdge(4, 0, 4, 1)), isTrue);
    final next = computeEnclosedRegions(store);
    expect(next, hasLength(3));
    expect(wallRegionContaining(next, 0, 0)?.tiles, {(0, 0)});
    expect(wallRegionContaining(next, 3, 0)?.tiles, {(3, 0)});
    expect(wallRegionContaining(next, 4, 0)?.tiles, {(4, 0)});
  });

  test('last null next to an existing region adopts and merges', () {
    final store = WallStore();
    encloseTile(store, 0, 0);
    final regions = computeEnclosedRegions(store);
    final result = applyRegionFill(
      walls: store,
      regions: regions,
      tx: 1,
      ty: 0,
      lastSeed: null,
    );
    expect(result.changed, isTrue);
    expect(result.lastSeed, (1, 0));
    expect(store.contains(WallEdge(1, 0, 1, 1)), isFalse);
    final next = computeEnclosedRegions(store);
    expect(next, hasLength(1));
    expect(next.single.tiles, {(0, 0), (1, 0)});
  });

  test('last null and two neighbors merges only the NESW-first region', () {
    final store = WallStore();
    encloseTile(store, 2, 1);
    encloseTile(store, 3, 2);
    final regions = computeEnclosedRegions(store);
    expect(regions, hasLength(2));
    final result = applyRegionFill(
      walls: store,
      regions: regions,
      tx: 2,
      ty: 2,
      lastSeed: null,
    );
    expect(result.changed, isTrue);
    expect(store.contains(WallEdge(2, 2, 3, 2)), isFalse);
    expect(store.contains(WallEdge(3, 2, 3, 3)), isTrue);
    final next = computeEnclosedRegions(store);
    expect(next, hasLength(2));
    expect(wallRegionContaining(next, 2, 1)?.tiles, {(2, 1), (2, 2)});
    expect(wallRegionContaining(next, 3, 2)?.tiles, {(3, 2)});
  });

  test('fill on an enclosed tile adopts when last is null and no-ops when set', () {
    final store = WallStore();
    encloseTile(store, 5, 5);
    final regions = computeEnclosedRegions(store);
    final adopt = previewRegionFill(
      walls: store,
      regions: regions,
      tx: 5,
      ty: 5,
      lastSeed: null,
    );
    expect(adopt.changed, isFalse);
    expect(adopt.lastSeed, (5, 5));
    expect(adopt.addEdges, isEmpty);

    final noop = previewRegionFill(
      walls: store,
      regions: regions,
      tx: 5,
      ty: 5,
      lastSeed: (0, 0),
    );
    expect(noop.changed, isFalse);
    expect(noop.lastSeed, (0, 0));
  });

  test('dividerMergeEdges returns every shared wall on an L interface', () {
    final store = WallStore();
    store.add(WallEdge(0, 0, 1, 0));
    store.add(WallEdge(1, 0, 2, 0));
    store.add(WallEdge(2, 0, 2, 1));
    store.add(WallEdge(2, 1, 2, 2));
    store.add(WallEdge(1, 2, 2, 2));
    store.add(WallEdge(0, 2, 1, 2));
    store.add(WallEdge(0, 1, 0, 2));
    store.add(WallEdge(0, 0, 0, 1));
    final vertical = WallEdge(1, 1, 1, 2);
    final horizontal = WallEdge(1, 1, 2, 1);
    store.add(vertical);
    store.add(horizontal);
    final regions = computeEnclosedRegions(store);
    expect(regions, hasLength(2));
    final merge = dividerMergeEdges(vertical, regions, store);
    expect(merge, isNotNull);
    expect(merge, containsAll([vertical, horizontal]));
    expect(merge, hasLength(2));
  });

  test('resolved last seed clears when that tile is no longer enclosed', () {
    final store = WallStore();
    encloseTile(store, 1, 1);
    final regions = computeEnclosedRegions(store);
    expect(resolvedLastRegionSeed(regions, (1, 1)), (1, 1));
    expect(store.remove(WallEdge(1, 1, 2, 1)), isTrue);
    expect(
      resolvedLastRegionSeed(computeEnclosedRegions(store), (1, 1)),
      isNull,
    );
  });

  test('fill touching last and another region merges only last', () {
    final store = WallStore();
    final first = applyRegionFill(
      walls: store,
      regions: const [],
      tx: 0,
      ty: 0,
      lastSeed: null,
    );
    encloseTile(store, 2, 0);
    final regions = computeEnclosedRegions(store);
    final result = applyRegionFill(
      walls: store,
      regions: regions,
      tx: 1,
      ty: 0,
      lastSeed: first.lastSeed,
    );
    expect(result.lastSeed, first.lastSeed);
    expect(store.contains(WallEdge(1, 0, 1, 1)), isFalse);
    expect(store.contains(WallEdge(2, 0, 2, 1)), isTrue);
    final next = computeEnclosedRegions(store);
    expect(wallRegionContaining(next, 0, 0)?.tiles, {(0, 0), (1, 0)});
    expect(wallRegionContaining(next, 2, 0)?.tiles, {(2, 0)});
  });
}
