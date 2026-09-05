import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_program.dart';
import 'package:flatmates/gameplay/volumes/volume_program_graph.dart';
import 'package:flatmates/gameplay/walls/wall_edge.dart';
import 'package:flatmates/gameplay/walls/wall_store.dart';
import 'package:flutter_test/flutter_test.dart';

Volume _mass(List<(int, int)> tiles, {int id = 1}) {
  return Volume(
    id: id,
    cells: [
      for (final (tx, ty) in tiles) VolumeCell(tx: tx, ty: ty, box: BoxPrimitive()),
    ],
  );
}

void main() {
  test('adjacent bedroom and circulation regions share an edge', () {
    final volume = _mass([(2, 2), (3, 2)]);
    final programs = VolumeProgramStore()
      ..assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom)
      ..assignIndoor(tx: 3, ty: 2, programId: kProgramCirculation);
    final graph = buildVolumeProgramGraph(
      volume: volume,
      programs: programs,
      walls: WallStore(),
    );
    expect(graph.regions, hasLength(2));
    expect(graph.edges, hasLength(1));
    expect(graph.hasDisconnectedBedroom, isFalse);
  });

  test('bedroom with a door on its cell is connected', () {
    final volume = _mass([(2, 2)]);
    volume.cells.single.accessibleSides.add(VolumeSide.east);
    final programs = VolumeProgramStore()
      ..assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom);
    final graph = buildVolumeProgramGraph(
      volume: volume,
      programs: programs,
      walls: WallStore(),
    );
    expect(graph.doors, hasLength(1));
    expect(graph.hasDisconnectedBedroom, isFalse);
  });

  test('bedroom next to leisure with no door is disconnected', () {
    final volume = _mass([(2, 2), (3, 2)]);
    final programs = VolumeProgramStore()
      ..assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom)
      ..assignIndoor(tx: 3, ty: 2, programId: kProgramLeisure);
    final graph = buildVolumeProgramGraph(
      volume: volume,
      programs: programs,
      walls: WallStore(),
    );
    expect(graph.hasDisconnectedBedroom, isTrue);
    expect(graph.disconnectedBedrooms, hasLength(1));
  });

  test('a wall between bedroom and circulation disconnects the bedroom', () {
    final volume = _mass([(2, 2), (3, 2)]);
    final programs = VolumeProgramStore()
      ..assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom)
      ..assignIndoor(tx: 3, ty: 2, programId: kProgramCirculation);
    final walls = WallStore()..add(WallEdge(3, 2, 3, 3));
    final graph = buildVolumeProgramGraph(
      volume: volume,
      programs: programs,
      walls: walls,
    );
    expect(graph.edges, isEmpty);
    expect(graph.hasDisconnectedBedroom, isTrue);
  });

  test('same-program neighbors collapse to one region node', () {
    final volume = _mass([(2, 2), (3, 2), (3, 3)]);
    final programs = VolumeProgramStore()
      ..assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom)
      ..assignIndoor(tx: 3, ty: 2, programId: kProgramBedroom)
      ..assignIndoor(tx: 3, ty: 3, programId: kProgramCirculation);
    final graph = buildVolumeProgramGraph(
      volume: volume,
      programs: programs,
      walls: WallStore(),
    );
    expect(graph.bedrooms, hasLength(1));
    expect(graph.bedrooms.single.tiles, {(2, 2), (3, 2)});
    expect(graph.hasDisconnectedBedroom, isFalse);
  });
}
