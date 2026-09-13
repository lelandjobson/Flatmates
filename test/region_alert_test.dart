import 'package:flatmates/gameplay/alerts/alert_reveal.dart';
import 'package:flatmates/gameplay/alerts/region_alerts.dart';
import 'package:flatmates/gameplay/alerts/world_alert.dart';
import 'package:flatmates/gameplay/graph/connection_graph.dart';
import 'package:flatmates/gameplay/paths/path_store.dart';
import 'package:flatmates/gameplay/picking/selectable.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flatmates/gameplay/walls/region_opening.dart';
import 'package:flatmates/gameplay/walls/region_tool.dart';
import 'package:flatmates/gameplay/walls/wall_edge.dart';
import 'package:flatmates/gameplay/walls/wall_regions.dart';
import 'package:flatmates/gameplay/walls/wall_store.dart';
import 'package:flatmates/ui/game/game_tool_carousel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void encloseTile(WallStore store, int tx, int ty) {
  store.add(WallEdge(tx, ty, tx + 1, ty));
  store.add(WallEdge(tx + 1, ty, tx + 1, ty + 1));
  store.add(WallEdge(tx, ty + 1, tx + 1, ty + 1));
  store.add(WallEdge(tx, ty, tx, ty + 1));
}

({ConnectionGraph graph, List<WallRegion> regions}) _syncLikeGame({
  required VolumeStore volumes,
  required WallStore walls,
  required PathStore paths,
}) {
  final regions = computeEnclosedRegions(walls);
  syncRegionOpeningsFromPaths(
    walls: walls,
    paths: paths,
    regions: regions,
  );
  return (
    graph: ConnectionGraph.build(
      volumes: volumes,
      paths: paths,
      walls: walls,
      regions: regions,
    ),
    regions: regions,
  );
}

ConnectionGraph _graph({
  required VolumeStore volumes,
  required WallStore walls,
  required PathStore paths,
  required List<WallRegion> regions,
}) {
  return ConnectionGraph.build(
    volumes: volumes,
    paths: paths,
    walls: walls,
    regions: regions,
  );
}

List<WorldAlert> _alerts({
  required ConnectionGraph graph,
  required List<WallRegion> regions,
  required VolumeStore volumes,
  required PathStore paths,
  required WallStore walls,
}) {
  return collectRegionAlerts(
    graph: graph,
    regions: regions,
    grid: volumes.grid,
    paths: paths,
    volumes: volumes,
    walls: walls,
  );
}

void main() {
  test('an enclosed region with no path raises a path-tool alert', () {
    final volumes = VolumeStore();
    final walls = WallStore(grid: volumes.grid);
    encloseTile(walls, 2, 2);
    final regions = computeEnclosedRegions(walls);
    final paths = PathStore(grid: volumes.grid);
    final graph = _graph(
      volumes: volumes,
      walls: walls,
      paths: paths,
      regions: regions,
    );
    expect(regionSubgraphConnectedToPath(regions.single, graph), isFalse);
    final alerts = collectRegionAlerts(
      graph: graph,
      regions: regions,
      grid: volumes.grid,
      paths: paths,
      volumes: volumes,
    );
    expect(alerts, hasLength(1));
    expect(alerts.single.hostKey, regionHostKey(regions.single));
    expect(alerts.single.primary.id, '${regionHostKey(regions.single)}:noPath');
    expect(alerts.single.primary.requirementIcon, Icons.add_road);
    expect(alerts.single.primary.remediation.mode, GameMode.create);
    expect(
      alerts.single.primary.remediation.createTool,
      GameCreateTool.path,
    );
    expect(
      alerts.single.primary.remediation.selectKind,
      SelectableKind.region,
    );
  });

  test('a cut fence onto a path clears the region alert', () {
    final volumes = VolumeStore();
    final walls = WallStore(grid: volumes.grid);
    encloseTile(walls, 2, 2);
    expect(walls.cut(WallEdge(3, 2, 3, 3)), isTrue);
    final regions = computeEnclosedRegions(walls);
    final paths = PathStore(grid: volumes.grid)..addIsland(3, 2);
    final graph = _graph(
      volumes: volumes,
      walls: walls,
      paths: paths,
      regions: regions,
    );
    expect(regionSubgraphConnectedToPath(regions.single, graph), isTrue);
    expect(
      collectRegionAlerts(
        graph: graph,
        regions: regions,
        grid: volumes.grid,
        paths: paths,
        volumes: volumes,
      ),
      isEmpty,
    );
  });

  test('only the disconnected yard alerts when two regions exist', () {
    final volumes = VolumeStore();
    final walls = WallStore(grid: volumes.grid);
    encloseTile(walls, 1, 1);
    encloseTile(walls, 5, 5);
    expect(walls.cut(WallEdge(6, 5, 6, 6)), isTrue);
    final regions = computeEnclosedRegions(walls);
    final paths = PathStore(grid: volumes.grid)..addIsland(6, 5);
    final graph = _graph(
      volumes: volumes,
      walls: walls,
      paths: paths,
      regions: regions,
    );
    final alerts = collectRegionAlerts(
      graph: graph,
      regions: regions,
      grid: volumes.grid,
      paths: paths,
      volumes: volumes,
    );
    expect(alerts, hasLength(1));
    final closed = wallRegionContaining(regions, 1, 1)!;
    expect(alerts.single.hostKey, regionHostKey(closed));
  });

  test('gate candidate prefers an outdoor tile that already has a path', () {
    final volumes = VolumeStore();
    final walls = WallStore(grid: volumes.grid);
    encloseTile(walls, 2, 2);
    final regions = computeEnclosedRegions(walls);
    final paths = PathStore(grid: volumes.grid)..addIsland(3, 2);
    expect(
      gateCandidateTile(
        region: regions.single,
        paths: paths,
        volumes: volumes,
      ),
      (3, 2),
    );
  });

  test('placeAndJoin then a gate click clears the region alert', () {
    final volumes = VolumeStore();
    final walls = WallStore(grid: volumes.grid);
    applyRegionFill(
      walls: walls,
      regions: const [],
      tx: 2,
      ty: 2,
      lastSeed: null,
    );
    final paths = PathStore(grid: volumes.grid);
    var world = _syncLikeGame(
      volumes: volumes,
      walls: walls,
      paths: paths,
    );
    expect(
      _alerts(
        graph: world.graph,
        regions: world.regions,
        volumes: volumes,
        paths: paths,
        walls: walls,
      ),
      hasLength(1),
    );

    expect(
      paths.placeAndJoin(3, 2, walls: walls, regions: world.regions),
      isTrue,
    );
    world = _syncLikeGame(volumes: volumes, walls: walls, paths: paths);
    expect(
      _alerts(
        graph: world.graph,
        regions: world.regions,
        volumes: volumes,
        paths: paths,
        walls: walls,
      ),
      hasLength(1),
      reason: 'a path beside a solid fence is not a gate yet',
    );

    expect(
      paths.placeAndJoin(3, 2, walls: walls, regions: world.regions),
      isTrue,
    );
    world = _syncLikeGame(volumes: volumes, walls: walls, paths: paths);
    expect(world.graph.anchors, isNotEmpty);
    expect(
      world.graph.anchors.every(
        (anchor) => anchor.kind == GraphAnchorKind.regionOpening,
      ),
      isTrue,
    );
    expect(regionSubgraphConnectedToPath(world.regions.single, world.graph), isTrue);
    expect(
      _alerts(
        graph: world.graph,
        regions: world.regions,
        volumes: volumes,
        paths: paths,
        walls: walls,
      ),
      isEmpty,
    );
  });

  test('graph anchors still clear the alert when the subgraph copy is empty', () {
    final region = WallRegion({(2, 2)});
    final id = ConnectionGraph.regionSubgraphId(region);
    final inner = GraphNode(
      x: 2,
      y: 2,
      z: 0,
      kind: NodeKind.region,
      subgraphId: id,
    );
    final outer = GraphNode(x: 3, y: 2, z: 0, kind: NodeKind.outside);
    final anchor = GraphAnchor(
      kind: GraphAnchorKind.regionOpening,
      inner: inner,
      outer: outer,
      innerSubgraphId: 'stale-id',
    );
    final graph = ConnectionGraph(
      nodes: [inner, outer],
      edges: [anchor.crossing],
      subgraphs: [
        GraphSubgraph(
          id: id,
          kind: SubgraphKind.region,
          nodes: [inner],
          edges: const [],
        ),
      ],
      anchors: [anchor],
    );
    expect(graph.subgraphs.single.anchors, isEmpty);
    expect(regionSubgraphConnectedToPath(region, graph), isTrue);
    expect(
      collectRegionAlerts(
        graph: graph,
        regions: [region],
        grid: const VolumeGrid(),
        paths: PathStore()..addIsland(3, 2),
      ),
      isEmpty,
    );
  });

  test('a volume door into a yard does not count as a path connection', () {
    final volumes = VolumeStore();
    expect(volumes.startNew(3, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    volumes.volumes.single.cells.single.accessibleSides.add(VolumeSide.west);
    final walls = WallStore(grid: volumes.grid);
    encloseTile(walls, 2, 2);
    final paths = PathStore(grid: volumes.grid);
    final world = _syncLikeGame(
      volumes: volumes,
      walls: walls,
      paths: paths,
    );
    expect(world.graph.anchors, isNotEmpty);
    expect(
      world.graph.anchors.every(
        (anchor) => anchor.kind == GraphAnchorKind.volumeDoor,
      ),
      isTrue,
    );
    expect(
      _alerts(
        graph: world.graph,
        regions: world.regions,
        volumes: volumes,
        paths: paths,
        walls: walls,
      ),
      hasLength(1),
    );
  });

  test('region path alerts stay visible in create mode', () {
    final volumes = VolumeStore();
    final walls = WallStore(grid: volumes.grid);
    encloseTile(walls, 2, 2);
    final paths = PathStore(grid: volumes.grid);
    final world = _syncLikeGame(
      volumes: volumes,
      walls: walls,
      paths: paths,
    );
    final alerts = _alerts(
      graph: world.graph,
      regions: world.regions,
      volumes: volumes,
      paths: paths,
      walls: walls,
    );
    expect(
      visibleWorldAlerts(
        alerts: alerts,
        createMode: true,
        lookingInside: (_) => false,
        showInCreate: (alert) => alert.hostKey.startsWith('region:'),
      ),
      alerts,
    );
  });
}
