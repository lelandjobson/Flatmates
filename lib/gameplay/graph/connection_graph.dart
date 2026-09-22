import 'package:vector_math/vector_math_64.dart';

import '../paths/path_store.dart';
import '../volumes/volume.dart';
import '../volumes/volume_store.dart';
import '../walls/wall_edge.dart';
import '../walls/wall_regions.dart';
import '../walls/wall_store.dart';

enum NodeKind { inside, outside, region }

enum JointKind { inIn, inOut, outOut }

enum SubgraphKind { volume, region }

enum GraphAnchorKind { volumeDoor, regionOpening }

/// Tile-space node: [x]/[y] are tile indices, [z] is subtile height.
class GraphNode {
  const GraphNode({
    required this.x,
    required this.y,
    required this.z,
    required this.kind,
    this.subgraphId,
  });

  final int x;
  final int y;
  final int z;
  final NodeKind kind;
  final String? subgraphId;

  /// World position for overlay drawing. [z] is floor height in subtles.
  Vector3 worldPosition(VolumeGrid grid, {double visualLift = 2}) {
    final p = grid.tileCenter(x, y);
    p.y = z * grid.subtileSize + visualLift;
    return p;
  }

  @override
  bool operator ==(Object other) =>
      other is GraphNode &&
      other.x == x &&
      other.y == y &&
      other.z == z &&
      other.kind == kind &&
      other.subgraphId == subgraphId;

  @override
  int get hashCode => Object.hash(x, y, z, kind, subgraphId);
}

class GraphEdge {
  GraphEdge({
    required GraphNode a,
    required GraphNode b,
    required this.kind,
  })  : a = _order(a, b).$1,
        b = _order(a, b).$2;

  final GraphNode a;
  final GraphNode b;
  final JointKind kind;

  static (GraphNode, GraphNode) _order(GraphNode a, GraphNode b) {
    final cmp = a.x != b.x
        ? a.x.compareTo(b.x)
        : a.y != b.y
            ? a.y.compareTo(b.y)
            : a.z != b.z
                ? a.z.compareTo(b.z)
                : a.kind.index != b.kind.index
                    ? a.kind.index.compareTo(b.kind.index)
                    : (a.subgraphId ?? '').compareTo(b.subgraphId ?? '');
    return cmp <= 0 ? (a, b) : (b, a);
  }

  @override
  bool operator ==(Object other) =>
      other is GraphEdge && other.a == a && other.b == b && other.kind == kind;

  @override
  int get hashCode => Object.hash(a, b, kind);
}

/// Accessible-side door from a volume cell onto an empty outdoor neighbor tile.
class InOutLink {
  const InOutLink({
    required this.cell,
    required this.side,
    required this.outTx,
    required this.outTy,
  });

  final VolumeCell cell;
  final VolumeSide side;
  final int outTx;
  final int outTy;
}

/// Cut-wall gate from a region tile onto an outdoor path tile.
class RegionOutLink {
  const RegionOutLink({
    required this.region,
    required this.wall,
    required this.inTx,
    required this.inTy,
    required this.outTx,
    required this.outTy,
  });

  final Playground region;
  final WallEdge wall;
  final int inTx;
  final int inTy;
  final int outTx;
  final int outTy;
}

/// Pair of tiles that joins two graphs: a volume/region and the outdoor
/// path graph (or another subgraph). Created by a door or a region opening.
class GraphAnchor {
  const GraphAnchor({
    required this.kind,
    required this.inner,
    required this.outer,
    required this.innerSubgraphId,
    this.outerSubgraphId,
  });

  final GraphAnchorKind kind;
  final GraphNode inner;
  final GraphNode outer;
  final String innerSubgraphId;
  final String? outerSubgraphId;

  (int, int) get innerTile => (inner.x, inner.y);

  (int, int) get outerTile => (outer.x, outer.y);

  String get id =>
      '${kind.name}:${innerTile.$1},${innerTile.$2}:${outerTile.$1},${outerTile.$2}';

  bool involvesNode(GraphNode node) => node == inner || node == outer;

  bool joins(String a, String? b) =>
      (innerSubgraphId == a && outerSubgraphId == b) ||
      (innerSubgraphId == b && outerSubgraphId == a);

  GraphEdge get crossing => GraphEdge(a: inner, b: outer, kind: JointKind.inOut);

  @override
  bool operator ==(Object other) =>
      other is GraphAnchor &&
      other.kind == kind &&
      other.inner == inner &&
      other.outer == outer &&
      other.innerSubgraphId == innerSubgraphId &&
      other.outerSubgraphId == outerSubgraphId;

  @override
  int get hashCode => Object.hash(
        kind,
        inner,
        outer,
        innerSubgraphId,
        outerSubgraphId,
      );
}

/// Per-volume or per-region tile graph. [anchors] are the crossings out.
class GraphSubgraph {
  const GraphSubgraph({
    required this.id,
    required this.kind,
    required this.nodes,
    required this.edges,
    this.anchors = const [],
  });

  final String id;
  final SubgraphKind kind;
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final List<GraphAnchor> anchors;

  Set<(int, int)> get tiles => {for (final n in nodes) (n.x, n.y)};

  bool containsTile(int x, int y) {
    for (final n in nodes) {
      if (n.x == x && n.y == y) return true;
    }
    return false;
  }

  List<(int, int)> innersAtOuter((int, int) outer) {
    return [
      for (final a in anchors)
        if (a.outerTile == outer) a.innerTile,
    ];
  }
}

/// Joint graph rebuilt from volumes, paths, and wall regions.
class ConnectionGraph {
  const ConnectionGraph({
    required this.nodes,
    required this.edges,
    this.subgraphs = const [],
    this.anchors = const [],
  });

  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final List<GraphSubgraph> subgraphs;
  final List<GraphAnchor> anchors;

  static const empty = ConnectionGraph(nodes: [], edges: []);

  bool isAnchorNode(GraphNode node) {
    for (final anchor in anchors) {
      if (anchor.involvesNode(node)) return true;
    }
    return false;
  }

  List<GraphAnchor> anchorsBetween(String a, String? b) => [
        for (final anchor in anchors)
          if (anchor.joins(a, b)) anchor,
      ];

  GraphSubgraph? subgraphById(String id) {
    for (final sub in subgraphs) {
      if (sub.id == id) return sub;
    }
    return null;
  }

  GraphSubgraph? subgraphContaining(int x, int y) {
    for (final sub in subgraphs) {
      if (sub.containsTile(x, y)) return sub;
    }
    return null;
  }

  /// Tile node at ([x], [y]), preferring volume then region then outdoor.
  GraphNode? tileNode(int x, int y) {
    GraphNode? outside;
    GraphNode? region;
    for (final n in nodes) {
      if (n.x != x || n.y != y) continue;
      if (n.kind == NodeKind.inside) return n;
      if (n.kind == NodeKind.region) region = n;
      if (n.kind == NodeKind.outside) outside = n;
    }
    return region ?? outside;
  }

  Map<GraphNode, Set<GraphNode>> nodeAdjacency() {
    final adj = <GraphNode, Set<GraphNode>>{};
    for (final edge in edges) {
      adj.putIfAbsent(edge.a, () => {}).add(edge.b);
      adj.putIfAbsent(edge.b, () => {}).add(edge.a);
    }
    return adj;
  }

  /// Ortho walk inside [sub] from [start] to [goal].
  static List<(int, int)>? subgraphWalk(
    GraphSubgraph sub,
    (int, int) start,
    (int, int) goal,
  ) {
    if (start == goal) return [start];
    if (!sub.containsTile(start.$1, start.$2) ||
        !sub.containsTile(goal.$1, goal.$2)) {
      return null;
    }
    final adj = <(int, int), Set<(int, int)>>{};
    for (final edge in sub.edges) {
      final a = (edge.a.x, edge.a.y);
      final b = (edge.b.x, edge.b.y);
      adj.putIfAbsent(a, () => {}).add(b);
      adj.putIfAbsent(b, () => {}).add(a);
    }
    final parents = <(int, int), (int, int)>{};
    final seen = {start};
    final queue = [start];
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      if (current == goal) {
        final path = <(int, int)>[goal];
        var cursor = goal;
        while (cursor != start) {
          final parent = parents[cursor];
          if (parent == null) return [start];
          path.add(parent);
          cursor = parent;
        }
        return path.reversed.toList();
      }
      for (final next in adj[current] ?? const <(int, int)>{}) {
        if (!seen.add(next)) continue;
        parents[next] = current;
        queue.add(next);
      }
    }
    return null;
  }

  /// Tile walk from [from] to [to] through [sub], including outdoor anchors.
  List<(int, int)>? expandPortalHop(
    GraphSubgraph sub,
    (int, int) from,
    (int, int) to,
  ) {
    final fromIn = sub.containsTile(from.$1, from.$2);
    final toIn = sub.containsTile(to.$1, to.$2);
    if (fromIn && toIn) return subgraphWalk(sub, from, to);
    if (fromIn && !toIn) {
      final exits = sub.innersAtOuter(to);
      if (exits.isEmpty) return [from, to];
      List<(int, int)>? best;
      for (final exit in exits) {
        final walk = subgraphWalk(sub, from, exit);
        if (walk == null) continue;
        final full = [...walk, to];
        if (best == null || full.length < best.length) best = full;
      }
      return best ?? [from, to];
    }
    if (!fromIn && toIn) {
      final entries = sub.innersAtOuter(from);
      if (entries.isEmpty) return [from, to];
      List<(int, int)>? best;
      for (final entry in entries) {
        final walk = subgraphWalk(sub, entry, to);
        if (walk == null) continue;
        final full = [from, ...walk];
        if (best == null || full.length < best.length) best = full;
      }
      return best ?? [from, to];
    }
    final entries = sub.innersAtOuter(from);
    final exits = sub.innersAtOuter(to);
    if (entries.isEmpty || exits.isEmpty) return [from, to];
    List<(int, int)>? best;
    for (final entry in entries) {
      for (final exit in exits) {
        final walk = subgraphWalk(sub, entry, exit);
        if (walk == null) continue;
        final full = [from, ...walk, to];
        if (best == null || full.length < best.length) best = full;
      }
    }
    return best ?? [from, to];
  }

  /// Doors from volume cells onto empty outdoor neighbor tiles.
  static Iterable<InOutLink> inOutLinks(VolumeStore volumes) sync* {
    for (final volume in volumes.visibleVolumes) {
      for (final cell in volume.cells) {
        for (final side in cell.accessibleSides) {
          final (dx, dy) = side.tileDelta;
          final nx = cell.tx + dx;
          final ny = cell.ty + dy;
          if (volume.cellAt(nx, ny) != null) continue;
          if (!volumes.grid.inBounds(nx, ny)) continue;
          if (volumes.isOccupied(nx, ny)) continue;
          yield InOutLink(
            cell: cell,
            side: side,
            outTx: nx,
            outTy: ny,
          );
        }
      }
    }
  }

  /// Cut region openings that have an outdoor path on the far side.
  static Iterable<RegionOutLink> regionOutLinks({
    required Iterable<Playground> regions,
    required WallStore walls,
    required PathStore paths,
  }) sync* {
    for (final region in regions) {
      for (final stored in walls.edges) {
        if (stored.kind != WallKind.cutFence) continue;
        final pair = stored.separatedTiles;
        if (pair == null) continue;
        final aIn = region.tiles.contains(pair.$1);
        final bIn = region.tiles.contains(pair.$2);
        if (aIn == bIn) continue;
        final inside = aIn ? pair.$1 : pair.$2;
        final outside = aIn ? pair.$2 : pair.$1;
        if (!paths.contains(outside.$1, outside.$2)) continue;
        yield RegionOutLink(
          region: region,
          wall: stored,
          inTx: inside.$1,
          inTy: inside.$2,
          outTx: outside.$1,
          outTy: outside.$2,
        );
      }
    }
  }

  static String volumeSubgraphId(int volumeId) => 'v$volumeId';

  static String regionSubgraphId(Playground region) {
    final tiles = region.tiles.toList()
      ..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
    final first = tiles.isEmpty ? (0, 0) : tiles.first;
    return 'r${first.$1}_${first.$2}_${tiles.length}';
  }

  static ConnectionGraph build({
    required VolumeStore volumes,
    required PathStore paths,
    WallStore? walls,
    List<Playground> regions = const [],
  }) {
    final nodeMap = <(int, int, int, NodeKind, String?), GraphNode>{};
    final edgeSet = <GraphEdge>{};
    final allAnchors = <GraphAnchor>[];
    final subgraphs = <GraphSubgraph>[];

    GraphNode put(
      int x,
      int y,
      NodeKind kind, {
      int z = 0,
      String? subgraphId,
    }) {
      return nodeMap.putIfAbsent(
        (x, y, z, kind, subgraphId),
        () => GraphNode(
          x: x,
          y: y,
          z: z,
          kind: kind,
          subgraphId: subgraphId,
        ),
      );
    }

    GraphAnchor addAnchor({
      required GraphAnchorKind kind,
      required GraphNode inner,
      required GraphNode outer,
      required String innerSubgraphId,
      String? outerSubgraphId,
    }) {
      final anchor = GraphAnchor(
        kind: kind,
        inner: inner,
        outer: outer,
        innerSubgraphId: innerSubgraphId,
        outerSubgraphId: outerSubgraphId,
      );
      allAnchors.add(anchor);
      edgeSet.add(anchor.crossing);
      return anchor;
    }

    final regionAt = <(int, int), Playground>{};
    for (final region in regions) {
      for (final tile in region.tiles) {
        if (volumes.isOccupied(tile.$1, tile.$2)) continue;
        regionAt[tile] = region;
      }
    }

    for (final volume in volumes.visibleVolumes) {
      final id = volumeSubgraphId(volume.id);
      if (volume.cells.isEmpty) continue;
      final subNodes = <GraphNode>[];
      final subEdges = <GraphEdge>{};

      for (final cell in volume.cells) {
        subNodes.add(put(cell.tx, cell.ty, NodeKind.inside, subgraphId: id));
      }

      for (final cell in volume.cells) {
        final a = put(cell.tx, cell.ty, NodeKind.inside, subgraphId: id);
        for (final side in VolumeSide.values) {
          final (dx, dy) = side.tileDelta;
          final nx = cell.tx + dx;
          final ny = cell.ty + dy;
          final neighbor = volume.cellAt(nx, ny);
          if (neighbor == null) continue;
          if (nx < cell.tx || (nx == cell.tx && ny < cell.ty)) continue;
          if (!cell.box.touchesTileEdge(side, volumes.grid.subtilesPerTile)) {
            continue;
          }
          if (!neighbor.box.touchesTileEdge(
            side.opposite,
            volumes.grid.subtilesPerTile,
          )) {
            continue;
          }
          final b = put(nx, ny, NodeKind.inside, subgraphId: id);
          final edge = GraphEdge(a: a, b: b, kind: JointKind.inIn);
          edgeSet.add(edge);
          subEdges.add(edge);
        }
      }

      for (final link in inOutLinks(volumes)) {
        if (volume.cellAt(link.cell.tx, link.cell.ty) == null) continue;
        final inner = put(
          link.cell.tx,
          link.cell.ty,
          NodeKind.inside,
          subgraphId: id,
        );
        final dest = (link.outTx, link.outTy);
        final destRegion = regionAt[dest];
        final GraphNode outer;
        String? outerId;
        if (destRegion != null) {
          outerId = regionSubgraphId(destRegion);
          outer = put(
            dest.$1,
            dest.$2,
            NodeKind.region,
            subgraphId: outerId,
          );
        } else {
          outer = put(dest.$1, dest.$2, NodeKind.outside);
        }
        addAnchor(
          kind: GraphAnchorKind.volumeDoor,
          inner: inner,
          outer: outer,
          innerSubgraphId: id,
          outerSubgraphId: outerId,
        );
      }

      subgraphs.add(
        GraphSubgraph(
          id: id,
          kind: SubgraphKind.volume,
          nodes: subNodes,
          edges: subEdges.toList(),
          anchors: [
            for (final anchor in allAnchors)
              if (anchor.innerSubgraphId == id) anchor,
          ],
        ),
      );
    }

    for (final region in regions) {
      final tiles = [
        for (final tile in region.tiles)
          if (!volumes.isOccupied(tile.$1, tile.$2)) tile,
      ];
      if (tiles.isEmpty) continue;
      final id = regionSubgraphId(region);
      final subNodes = <GraphNode>[];
      final subEdges = <GraphEdge>{};
      final tileSet = tiles.toSet();

      for (final tile in tiles) {
        subNodes.add(put(tile.$1, tile.$2, NodeKind.region, subgraphId: id));
      }

      for (final tile in tiles) {
        final a = put(tile.$1, tile.$2, NodeKind.region, subgraphId: id);
        for (final side in VolumeSide.values) {
          final (dx, dy) = side.tileDelta;
          final nx = tile.$1 + dx;
          final ny = tile.$2 + dy;
          if (nx < tile.$1 || (nx == tile.$1 && ny < tile.$2)) continue;
          if (!tileSet.contains((nx, ny))) continue;
          final b = put(nx, ny, NodeKind.region, subgraphId: id);
          final edge = GraphEdge(a: a, b: b, kind: JointKind.inIn);
          edgeSet.add(edge);
          subEdges.add(edge);
        }
      }

      if (walls != null) {
        for (final link in regionOutLinks(
          regions: [region],
          walls: walls,
          paths: paths,
        )) {
          final inner = put(
            link.inTx,
            link.inTy,
            NodeKind.region,
            subgraphId: id,
          );
          final outer = put(link.outTx, link.outTy, NodeKind.outside);
          addAnchor(
            kind: GraphAnchorKind.regionOpening,
            inner: inner,
            outer: outer,
            innerSubgraphId: id,
          );
        }
      }

      subgraphs.add(
        GraphSubgraph(
          id: id,
          kind: SubgraphKind.region,
          nodes: subNodes,
          edges: subEdges.toList(),
          anchors: [
            for (final anchor in allAnchors)
              if (anchor.innerSubgraphId == id || anchor.outerSubgraphId == id)
                anchor,
          ],
        ),
      );
    }

    for (final (tx, ty) in paths.tiles) {
      if (volumes.isOccupied(tx, ty)) continue;
      if (regionAt.containsKey((tx, ty))) continue;
      put(tx, ty, NodeKind.outside);
    }

    for (final edge in paths.edges) {
      if (volumes.isOccupied(edge.x0, edge.y0)) continue;
      if (volumes.isOccupied(edge.x1, edge.y1)) continue;
      if (regionAt.containsKey((edge.x0, edge.y0))) continue;
      if (regionAt.containsKey((edge.x1, edge.y1))) continue;
      final a = put(edge.x0, edge.y0, NodeKind.outside);
      final b = put(edge.x1, edge.y1, NodeKind.outside);
      edgeSet.add(GraphEdge(a: a, b: b, kind: JointKind.outOut));
    }

    return ConnectionGraph(
      nodes: nodeMap.values.toList(),
      edges: edgeSet.toList(),
      subgraphs: subgraphs,
      anchors: allAnchors,
    );
  }
}
