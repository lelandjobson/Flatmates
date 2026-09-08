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
  test('adjacent bedroom and unprogrammed tiles share an edge', () {
    final volume = _mass([(2, 2), (3, 2)]);
    final programs = VolumeProgramStore()
      ..assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom);
    final graph = buildVolumeProgramGraph(
      volume: volume,
      programs: programs,
      walls: WallStore(),
    );
    expect(graph.regions, hasLength(2));
    expect(graph.edges, hasLength(1));
    expect(graph.hasDisconnectedBedroom, isFalse);
  });

  test('a one-cell bedroom is the whole volume and does not need circulation', () {
    final volume = _mass([(2, 2)]);
    final programs = VolumeProgramStore()
      ..assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom);
    final graph = buildVolumeProgramGraph(
      volume: volume,
      programs: programs,
      walls: WallStore(),
    );
    expect(graph.isWholeVolumeBedroom, isTrue);
    expect(graph.hasDisconnectedBedroom, isFalse);
  });

  test('a door on the bedroom does not replace circulation when other rooms exist',
      () {
    final volume = _mass([(2, 2), (3, 2)]);
    volume.cellAt(2, 2)!.accessibleSides.add(VolumeSide.west);
    final programs = VolumeProgramStore()
      ..assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom)
      ..assignIndoor(tx: 3, ty: 2, programId: kProgramLeisure);
    final graph = buildVolumeProgramGraph(
      volume: volume,
      programs: programs,
      walls: WallStore(),
    );
    expect(graph.doors, hasLength(1));
    expect(graph.hasDisconnectedBedroom, isTrue);
  });

  test('unprogrammed circulation may sit away from the door', () {
    final volume = _mass([(2, 2), (3, 2), (4, 2)]);
    volume.cellAt(4, 2)!.accessibleSides.add(VolumeSide.east);
    final programs = VolumeProgramStore()
      ..assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom)
      ..assignIndoor(tx: 4, ty: 2, programId: kProgramLeisure);
    final graph = buildVolumeProgramGraph(
      volume: volume,
      programs: programs,
      walls: WallStore(),
    );
    expect(graph.doors, hasLength(1));
    expect(graph.hasDisconnectedBedroom, isFalse);
  });

  test('bedroom next to leisure with no circulation is disconnected', () {
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

  test('a wall between bedroom and unprogrammed tiles disconnects the bedroom', () {
    final volume = _mass([(2, 2), (3, 2)]);
    final programs = VolumeProgramStore()
      ..assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom);
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
      ..assignIndoor(tx: 3, ty: 2, programId: kProgramBedroom);
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
