import 'package:flatmates/gameplay/graph/connection_graph.dart';
import 'package:flatmates/gameplay/paths/path_store.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
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

  test('adjacent islands without an edge stay disconnected', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    expect(paths.addIsland(1, 1), isTrue);
    expect(paths.addIsland(2, 1), isTrue);

    final graph = ConnectionGraph.build(volumes: volumes, paths: paths);
    expect(graph.nodes, hasLength(2));
    expect(graph.edges, isEmpty);
  });
}
