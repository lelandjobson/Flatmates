import '../walls/wall_store.dart';
import 'volume.dart';
import 'volume_program.dart';

enum ProgramGraphNodeKind { region, door }

/// One program region or door on a single volume mass.
class ProgramGraphNode {
  const ProgramGraphNode({
    required this.id,
    required this.kind,
    required this.volumeId,
    this.programId,
    this.tiles = const {},
    this.tx,
    this.ty,
    this.side,
  });

  final String id;
  final ProgramGraphNodeKind kind;
  final int volumeId;
  final String? programId;
  final Set<(int, int)> tiles;
  final int? tx;
  final int? ty;
  final VolumeSide? side;

  bool get isRegion => kind == ProgramGraphNodeKind.region;
  bool get isDoor => kind == ProgramGraphNodeKind.door;
  bool get isCirculation => programId == kProgramCirculation;
  bool get isBedroom => programId == kProgramBedroom;
}

class ProgramGraphEdge {
  ProgramGraphEdge(String a, String b)
      : a = a.compareTo(b) <= 0 ? a : b,
        b = a.compareTo(b) <= 0 ? b : a;

  final String a;
  final String b;

  String other(String id) => id == a ? b : a;

  @override
  bool operator ==(Object other) =>
      other is ProgramGraphEdge && other.a == a && other.b == b;

  @override
  int get hashCode => Object.hash(a, b);
}

/// Adjacency of indoor program regions and exterior doors on one volume.
class ProgramGraph {
  ProgramGraph({
    required this.volumeId,
    required List<ProgramGraphNode> nodes,
    required List<ProgramGraphEdge> edges,
  })  : nodes = List<ProgramGraphNode>.unmodifiable(nodes),
        edges = List<ProgramGraphEdge>.unmodifiable(edges),
        _byId = {for (final node in nodes) node.id: node},
        _adj = _adjacency(edges);

  factory ProgramGraph.empty(int volumeId) => ProgramGraph(
        volumeId: volumeId,
        nodes: const [],
        edges: const [],
      );

  final int volumeId;
  final List<ProgramGraphNode> nodes;
  final List<ProgramGraphEdge> edges;
  final Map<String, ProgramGraphNode> _byId;
  final Map<String, List<String>> _adj;

  ProgramGraphNode? nodeById(String id) => _byId[id];

  Iterable<ProgramGraphNode> get regions =>
      nodes.where((n) => n.isRegion);

  Iterable<ProgramGraphNode> get doors => nodes.where((n) => n.isDoor);

  Iterable<ProgramGraphNode> get bedrooms =>
      nodes.where((n) => n.isBedroom);

  Iterable<ProgramGraphNode> neighborsOf(ProgramGraphNode node) sync* {
    for (final id in _adj[node.id] ?? const <String>[]) {
      final next = _byId[id];
      if (next != null) yield next;
    }
  }

  /// Bedroom is OK if it touches a circulation region or a door.
  bool bedroomHasAccess(ProgramGraphNode bedroom) {
    if (!bedroom.isBedroom) return true;
    for (final next in neighborsOf(bedroom)) {
      if (next.isDoor || next.isCirculation) return true;
    }
    return false;
  }

  bool get hasDisconnectedBedroom {
    for (final bedroom in bedrooms) {
      if (!bedroomHasAccess(bedroom)) return true;
    }
    return false;
  }

  List<ProgramGraphNode> get disconnectedBedrooms => [
        for (final bedroom in bedrooms)
          if (!bedroomHasAccess(bedroom)) bedroom,
      ];

  static Map<String, List<String>> _adjacency(List<ProgramGraphEdge> edges) {
    final adj = <String, List<String>>{};
    for (final edge in edges) {
      adj.putIfAbsent(edge.a, () => []).add(edge.b);
      adj.putIfAbsent(edge.b, () => []).add(edge.a);
    }
    return adj;
  }
}

/// Build the program adjacency graph for one joined mass.
ProgramGraph buildVolumeProgramGraph({
  required Volume volume,
  required VolumeProgramStore programs,
  required WallStore walls,
}) {
  final kinds = <(int, int), String>{
    for (final cell in volume.cells)
      (cell.tx, cell.ty): ?programs.indoorAt(cell.tx, cell.ty),
  };

  final regionNodes = <ProgramGraphNode>[];
  final tileToRegion = <(int, int), String>{};
  var regionIndex = 0;
  final remaining = Set<(int, int)>.from(kinds.keys);
  const deltas = [(1, 0), (-1, 0), (0, 1), (0, -1)];
  while (remaining.isNotEmpty) {
    final start = remaining.first;
    final programId = kinds[start]!;
    final tiles = <(int, int)>{};
    final queue = [start];
    remaining.remove(start);
    while (queue.isNotEmpty) {
      final tile = queue.removeLast();
      tiles.add(tile);
      for (final (dx, dy) in deltas) {
        final next = (tile.$1 + dx, tile.$2 + dy);
        if (!remaining.contains(next)) continue;
        if (kinds[next] != programId) continue;
        if (walls.separatesTiles(tile, next)) continue;
        remaining.remove(next);
        queue.add(next);
      }
    }
    final id = 'region_${volume.id}_${regionIndex++}';
    regionNodes.add(
      ProgramGraphNode(
        id: id,
        kind: ProgramGraphNodeKind.region,
        volumeId: volume.id,
        programId: programId,
        tiles: tiles,
      ),
    );
    for (final tile in tiles) {
      tileToRegion[tile] = id;
    }
  }

  final doorNodes = <ProgramGraphNode>[];
  for (final cell in volume.cells) {
    for (final side in cell.accessibleSides) {
      if (volume.hasNeighborOn(cell, side.handle)) continue;
      doorNodes.add(
        ProgramGraphNode(
          id: 'door_${volume.id}_${cell.tx}_${cell.ty}_${side.name}',
          kind: ProgramGraphNodeKind.door,
          volumeId: volume.id,
          tx: cell.tx,
          ty: cell.ty,
          side: side,
          tiles: {(cell.tx, cell.ty)},
        ),
      );
    }
  }

  final edges = <ProgramGraphEdge>{};
  for (var i = 0; i < regionNodes.length; i++) {
    for (var j = i + 1; j < regionNodes.length; j++) {
      if (_regionsAdjacent(regionNodes[i], regionNodes[j], walls)) {
        edges.add(ProgramGraphEdge(regionNodes[i].id, regionNodes[j].id));
      }
    }
  }
  for (final door in doorNodes) {
    final tx = door.tx;
    final ty = door.ty;
    if (tx == null || ty == null) continue;
    final regionId = tileToRegion[(tx, ty)];
    if (regionId != null) {
      edges.add(ProgramGraphEdge(door.id, regionId));
    }
  }

  return ProgramGraph(
    volumeId: volume.id,
    nodes: [...regionNodes, ...doorNodes],
    edges: edges.toList(),
  );
}

bool _regionsAdjacent(
  ProgramGraphNode a,
  ProgramGraphNode b,
  WallStore walls,
) {
  const deltas = [(1, 0), (-1, 0), (0, 1), (0, -1)];
  for (final tile in a.tiles) {
    for (final (dx, dy) in deltas) {
      final next = (tile.$1 + dx, tile.$2 + dy);
      if (!b.tiles.contains(next)) continue;
      if (walls.separatesTiles(tile, next)) continue;
      return true;
    }
  }
  return false;
}
