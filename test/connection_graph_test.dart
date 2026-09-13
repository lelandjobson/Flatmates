import 'package:flatmates/gameplay/graph/connection_graph.dart';
import 'package:flatmates/gameplay/paths/path_store.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flatmates/gameplay/walls/wall_edge.dart';
import 'package:flatmates/gameplay/walls/wall_regions.dart';
import 'package:flatmates/gameplay/walls/wall_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('merge creates in_in between connected cells', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    expect(volumes.startNew(2, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    volumes.toggleAccess(VolumeSide.east);
    expect(volumes.confirmAccess(), isTrue);

    final grow = volumes.growCandidates().firstWhere((c) => c.tx == 3 && c.ty == 2);
    expect(volumes.startGrow(grow), isTrue);
    expect(volumes.confirmEdit(), isTrue);

    final graph = ConnectionGraph.build(volumes: volumes, paths: paths);
    expect(
      graph.edges.where((e) => e.kind == JointKind.inIn),
      hasLength(1),
    );
    expect(
      graph.nodes.where((n) => n.kind == NodeKind.inside),
      hasLength(2),
    );
  });

  test('accessible side creates in_out to the neighbor tile', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    expect(volumes.startNew(2, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    volumes.toggleAccess(VolumeSide.east);
    expect(volumes.confirmAccess(), isTrue);

    final graph = ConnectionGraph.build(volumes: volumes, paths: paths);
    expect(graph.edges.where((e) => e.kind == JointKind.inOut), hasLength(1));
    expect(graph.subgraphs, hasLength(1));
    expect(graph.anchors, hasLength(1));
    expect(graph.anchors.single.kind, GraphAnchorKind.volumeDoor);
    expect(graph.anchors.single.innerTile, (2, 2));
    expect(graph.anchors.single.outerTile, (3, 2));
    expect(graph.anchors.single.innerSubgraphId, ConnectionGraph.volumeSubgraphId(1));
    expect(graph.anchors.single.outerSubgraphId, isNull);
    expect(
      graph.nodes.any(
        (n) => n.kind == NodeKind.outside && n.x == 3 && n.y == 2,
      ),
      isTrue,
    );
    expect(
      graph.nodes.any(
        (n) => n.kind == NodeKind.inside && n.x == 2 && n.y == 2,
      ),
      isTrue,
    );
  });

  test('path edge is out_out', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    expect(paths.connect(1, 1, 2, 1), isTrue);

    final graph = ConnectionGraph.build(volumes: volumes, paths: paths);
    expect(graph.edges.where((e) => e.kind == JointKind.outOut), hasLength(1));
    expect(graph.nodes.where((n) => n.kind == NodeKind.outside), hasLength(2));
  });

  test('region tiles get in_in and an opening anchor at a cut', () {
    final volumes = VolumeStore();
    final walls = WallStore(grid: volumes.grid);
    walls.add(WallEdge(2, 2, 3, 2));
    walls.add(WallEdge(3, 2, 4, 2));
    walls.add(WallEdge(4, 2, 4, 3));
    walls.add(WallEdge(4, 3, 4, 4));
    walls.add(WallEdge(3, 4, 4, 4));
    walls.add(WallEdge(2, 4, 3, 4));
    walls.add(WallEdge(2, 3, 2, 4));
    walls.add(WallEdge(2, 2, 2, 3));
    expect(walls.cut(WallEdge(4, 2, 4, 3)), isTrue);
    final regions = computeEnclosedRegions(walls);
    expect(regions.single.tiles, {(2, 2), (3, 2), (2, 3), (3, 3)});
    final paths = PathStore(grid: volumes.grid)..addIsland(4, 2);
    final graph = ConnectionGraph.build(
      volumes: volumes,
      paths: paths,
      walls: walls,
      regions: regions,
    );
    expect(graph.nodes.where((n) => n.kind == NodeKind.region), hasLength(4));
    expect(
      graph.edges.where((e) => e.kind == JointKind.inIn).length,
      greaterThanOrEqualTo(4),
    );
    expect(
      graph.subgraphs.where((s) => s.kind == SubgraphKind.region),
      hasLength(1),
    );
    expect(graph.anchors, hasLength(1));
    expect(graph.anchors.single.kind, GraphAnchorKind.regionOpening);
    expect(graph.anchors.single.innerTile, (3, 2));
    expect(graph.anchors.single.outerTile, (4, 2));
    expect(
      graph.edges.where((e) => e.kind == JointKind.inOut),
      hasLength(1),
    );
    expect(
      graph.nodes.where((n) => n.kind == NodeKind.outside),
      hasLength(1),
    );
  });

  test('adjacent islands without an edge stay disconnected', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    expect(paths.addIsland(1, 1), isTrue);
    expect(paths.addIsland(2, 1), isTrue);

    final graph = ConnectionGraph.build(volumes: volumes, paths: paths);
    expect(graph.nodes, hasLength(2));
    expect(graph.edges, isEmpty);
  });

  test('adding and removing a door creates and drops an anchor', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    expect(volumes.startNew(2, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    expect(volumes.confirmAccess(), isTrue);
    expect(
      ConnectionGraph.build(volumes: volumes, paths: paths).anchors,
      isEmpty,
    );

    volumes.volumes.single.cells.single.accessibleSides.add(VolumeSide.east);
    final opened = ConnectionGraph.build(volumes: volumes, paths: paths);
    expect(opened.anchors, hasLength(1));
    expect(opened.subgraphs.single.anchors, hasLength(1));
    expect(opened.isAnchorNode(opened.anchors.single.inner), isTrue);
    expect(opened.isAnchorNode(opened.anchors.single.outer), isTrue);

    volumes.volumes.single.cells.single.accessibleSides.clear();
    expect(
      ConnectionGraph.build(volumes: volumes, paths: paths).anchors,
      isEmpty,
    );
  });

  test('two doors on one volume are two anchors to the outdoor graph', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    expect(volumes.startNew(2, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    volumes.volumes.single.cells.single.accessibleSides.addAll({
      VolumeSide.east,
      VolumeSide.south,
    });
    final graph = ConnectionGraph.build(volumes: volumes, paths: paths);
    expect(graph.anchors, hasLength(2));
    expect(
      {for (final anchor in graph.anchors) anchor.outerTile},
      {(3, 2), (2, 3)},
    );
    expect(
      graph.anchorsBetween(ConnectionGraph.volumeSubgraphId(1), null),
      hasLength(2),
    );
  });

  test('removing the approach path drops the region opening anchor', () {
    final volumes = VolumeStore();
    final walls = WallStore(grid: volumes.grid);
    walls.add(WallEdge(3, 2, 4, 2));
    walls.add(WallEdge(4, 2, 4, 3));
    walls.add(WallEdge(3, 3, 4, 3));
    walls.add(WallEdge(3, 2, 3, 3));
    expect(walls.cut(WallEdge(4, 2, 4, 3)), isTrue);
    final regions = computeEnclosedRegions(walls);
    final paths = PathStore(grid: volumes.grid)..addIsland(4, 2);
    expect(
      ConnectionGraph.build(
        volumes: volumes,
        paths: paths,
        walls: walls,
        regions: regions,
      ).anchors,
      hasLength(1),
    );
    expect(paths.removeTile(4, 2), isTrue);
    expect(
      ConnectionGraph.build(
        volumes: volumes,
        paths: paths,
        walls: walls,
        regions: regions,
      ).anchors,
      isEmpty,
    );
  });

  test('two openings between a yard and the path graph stay distinct', () {
    final volumes = VolumeStore();
    final walls = WallStore(grid: volumes.grid);
    for (var x = 3; x < 6; x++) {
      walls.add(WallEdge(x, 2, x + 1, 2));
      walls.add(WallEdge(x, 3, x + 1, 3));
    }
    walls.add(WallEdge(3, 2, 3, 3));
    walls.add(WallEdge(6, 2, 6, 3));
    expect(walls.cut(WallEdge(3, 2, 3, 3)), isTrue);
    expect(walls.cut(WallEdge(6, 2, 6, 3)), isTrue);
    final regions = computeEnclosedRegions(walls);
    expect(regions.single.tiles, {(3, 2), (4, 2), (5, 2)});
    final paths = PathStore(grid: volumes.grid)
      ..addIsland(2, 2)
      ..addIsland(6, 2);
    final graph = ConnectionGraph.build(
      volumes: volumes,
      paths: paths,
      walls: walls,
      regions: regions,
    );
    expect(graph.anchors, hasLength(2));
    expect(
      {for (final anchor in graph.anchors) anchor.kind},
      {GraphAnchorKind.regionOpening},
    );
    expect(
      {for (final anchor in graph.anchors) (anchor.innerTile, anchor.outerTile)},
      {((3, 2), (2, 2)), ((5, 2), (6, 2))},
    );
    final regionId = ConnectionGraph.regionSubgraphId(regions.single);
    expect(graph.anchorsBetween(regionId, null), hasLength(2));
    expect(graph.subgraphs.single.anchors, hasLength(2));
  });
}
