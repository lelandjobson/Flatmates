import 'package:flatmates/gameplay/walls/region_color.dart';
import 'package:flatmates/gameplay/walls/wall_edge.dart';
import 'package:flatmates/gameplay/walls/wall_regions.dart';
import 'package:flatmates/gameplay/walls/wall_store.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void encloseTile(WallStore store, int tx, int ty) {
  store.add(WallEdge(tx, ty, tx + 1, ty));
  store.add(WallEdge(tx + 1, ty, tx + 1, ty + 1));
  store.add(WallEdge(tx, ty + 1, tx + 1, ty + 1));
  store.add(WallEdge(tx, ty, tx, ty + 1));
}

void main() {
  test('palette is half-saturated OYGBIV plus brown, without alert red', () {
    expect(kRegionPaletteVividArgb, hasLength(kRegionPaletteSize));
    expect(kRegionPaletteArgb, hasLength(kRegionPaletteSize));
    expect(kRegionPaletteVividArgb, isNot(contains(kRegionAlertArgb)));
    expect(kRegionPaletteArgb, isNot(contains(kRegionAlertArgb)));
    expect(kRegionPaletteVividArgb.first, 0xFFFB8C00);
    expect(kRegionPaletteVividArgb.last, 0xFF6D4C41);
    for (var i = 0; i < kRegionPaletteSize; i++) {
      final vivid = HSLColor.fromColor(Color(kRegionPaletteVividArgb[i]));
      final muted = HSLColor.fromColor(Color(kRegionPaletteArgb[i]));
      expect(
        kRegionPaletteArgb[i],
        desaturateArgb(kRegionPaletteVividArgb[i], 0.5),
      );
      expect(muted.saturation, closeTo(vivid.saturation * 0.5, 0.01));
      expect(muted.hue, closeTo(vivid.hue, 2));
      expect(muted.lightness, closeTo(vivid.lightness, 0.01));
    }
  });

  test('neighboring regions get different colors', () {
    final store = WallStore();
    encloseTile(store, 2, 2);
    encloseTile(store, 3, 2);
    final regions = computeEnclosedRegions(store);
    expect(regions, hasLength(2));
    final adj = regionAdjacency(regions);
    expect(adj[0], {1});
    expect(adj[1], {0});
    final colors = assignRegionColors(regions);
    expect(colors.indices[0], isNot(colors.indices[1]));
  });

  test('far-apart regions may reuse a color', () {
    final store = WallStore();
    encloseTile(store, 0, 0);
    encloseTile(store, 5, 5);
    final regions = computeEnclosedRegions(store);
    final adj = regionAdjacency(regions);
    expect(adj[0], isEmpty);
    expect(adj[1], isEmpty);
    final colors = assignRegionColors(regions);
    expect(colors.indices[0], colors.indices[1]);
  });

  test('expanding a region keeps its color', () {
    final store = WallStore();
    encloseTile(store, 1, 1);
    final first = computeEnclosedRegions(store);
    final before = assignRegionColors(first);
    store.add(WallEdge(2, 1, 3, 1));
    store.add(WallEdge(3, 1, 3, 2));
    store.add(WallEdge(2, 2, 3, 2));
    store.remove(WallEdge(2, 1, 2, 2));
    final grown = computeEnclosedRegions(store);
    expect(grown, hasLength(1));
    expect(grown.single.tiles, {(1, 1), (2, 1)});
    final after = assignRegionColors(
      grown,
      previousRegions: first,
      previous: before,
    );
    expect(after.indices.single, before.indices.single);
  });

  test('a row of three rooms never shares a color with a neighbor', () {
    final store = WallStore();
    encloseTile(store, 0, 0);
    encloseTile(store, 1, 0);
    encloseTile(store, 2, 0);
    final regions = computeEnclosedRegions(store);
    expect(regions, hasLength(3));
    final colors = assignRegionColors(regions);
    final adj = regionAdjacency(regions);
    for (var i = 0; i < regions.length; i++) {
      for (final j in adj[i]) {
        expect(colors.indices[i], isNot(colors.indices[j]));
      }
    }
  });

  test('a new neighbor does not steal the grown room color', () {
    final store = WallStore();
    encloseTile(store, 1, 1);
    final first = computeEnclosedRegions(store);
    final before = assignRegionColors(first);
    encloseTile(store, 2, 1);
    final two = computeEnclosedRegions(store);
    final after = assignRegionColors(
      two,
      previousRegions: first,
      previous: before,
    );
    final kept = wallRegionContaining(two, 1, 1);
    final other = wallRegionContaining(two, 2, 1);
    expect(kept, isNotNull);
    expect(other, isNotNull);
    final keptIndex = two.indexWhere((r) => r == kept);
    final otherIndex = two.indexWhere((r) => r == other);
    expect(after.indices[keptIndex], before.indices.single);
    expect(after.indices[otherIndex], isNot(after.indices[keptIndex]));
  });
}
