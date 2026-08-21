import 'package:vector_math/vector_math_64.dart';

import '../paths/path_store.dart';
import '../volumes/volume.dart';
import '../volumes/volume_store.dart';

enum NodeKind { inside, outside }

enum JointKind { inIn, inOut, outOut }

/// Tile-space node: [x]/[y] are tile indices, [z] is subtile height.
class GraphNode {
  const GraphNode({
    required this.x,
    required this.y,
    required this.z,
    required this.kind,
  });

  final int x;
  final int y;
  final int z;
  final NodeKind kind;

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
      other.kind == kind;

  @override
  int get hashCode => Object.hash(x, y, z, kind);
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
                : a.kind.index.compareTo(b.kind.index);
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

/// Joint graph rebuilt from volumes and paths.
class ConnectionGraph {
  const ConnectionGraph({required this.nodes, required this.edges});

  final List<GraphNode> nodes;
  final List<GraphEdge> edges;

  static const empty = ConnectionGraph(nodes: [], edges: []);

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

  static ConnectionGraph build({
    required VolumeStore volumes,
    required PathStore paths,
  }) {
    final nodeMap = <(int, int, int, NodeKind), GraphNode>{};
    final edgeSet = <GraphEdge>{};

    GraphNode put(int x, int y, NodeKind kind, {int z = 0}) {
      return nodeMap.putIfAbsent(
        (x, y, z, kind),
        () => GraphNode(x: x, y: y, z: z, kind: kind),
      );
    }

    for (final volume in volumes.visibleVolumes) {
      for (final cell in volume.cells) {
        put(cell.tx, cell.ty, NodeKind.inside);
      }
    }

    for (final (tx, ty) in paths.tiles) {
      put(tx, ty, NodeKind.outside);
    }

    for (final volume in volumes.visibleVolumes) {
      for (final cell in volume.cells) {
        final a = put(cell.tx, cell.ty, NodeKind.inside);
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
          final b = put(nx, ny, NodeKind.inside);
          edgeSet.add(GraphEdge(a: a, b: b, kind: JointKind.inIn));
        }
      }
    }

    for (final link in inOutLinks(volumes)) {
      final a = put(link.cell.tx, link.cell.ty, NodeKind.inside);
      final out = put(link.outTx, link.outTy, NodeKind.outside);
      edgeSet.add(GraphEdge(a: a, b: out, kind: JointKind.inOut));
    }

    for (final edge in paths.edges) {
      final a = put(edge.x0, edge.y0, NodeKind.outside);
      final b = put(edge.x1, edge.y1, NodeKind.outside);
      edgeSet.add(GraphEdge(a: a, b: b, kind: JointKind.outOut));
    }

    return ConnectionGraph(
      nodes: nodeMap.values.toList(),
      edges: edgeSet.toList(),
    );
  }
}
