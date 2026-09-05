import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_program.dart';
import 'package:flatmates/gameplay/volumes/volume_program_clusters.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flatmates/gameplay/walls/wall_edge.dart';
import 'package:flatmates/gameplay/walls/wall_regions.dart';
import 'package:flatmates/gameplay/walls/wall_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('indoor assignment is per cell and has no default', () {
    final volume = Volume(
      id: 1,
      cells: [VolumeCell(tx: 2, ty: 2, box: BoxPrimitive())],
    );
    final programs = VolumeProgramStore();
    expect(programs.indoorAt(2, 2), isNull);
    expect(programs.isVolumeProgrammed(volume), isFalse);
    expect(programs.canAssignToVolume(volume), isTrue);
    expect(
      programs.assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom),
      isTrue,
    );
    expect(programs.indoorAt(2, 2), kProgramBedroom);
    expect(programs.isVolumeProgrammed(volume), isTrue);
  });

  test('outdoor tiles default to circulation', () {
    final programs = VolumeProgramStore();
    expect(programs.outdoorAt(1, 1), kProgramCirculation);
    final region = WallRegion({(1, 1), (1, 2), (2, 1), (2, 2)});
    expect(programs.outdoorRegionProgram(region.tiles), kProgramCirculation);
    expect(
      programs.assignOutdoorRegion(region.tiles, kProgramGarden),
      isTrue,
    );
    expect(programs.outdoorAt(1, 1), kProgramGarden);
    expect(programs.outdoorRegionProgram(region.tiles), kProgramGarden);
    expect(
      programs.assignOutdoorRegion(region.tiles, kProgramCirculation),
      isTrue,
    );
    expect(programs.outdoorAt(1, 1), kProgramCirculation);
  });

  test('rejects programs that do not belong on the surface', () {
    final programs = VolumeProgramStore();
    expect(
      programs.assignIndoor(tx: 0, ty: 0, programId: kProgramGarden),
      isFalse,
    );
    expect(
      programs.assignOutdoorRegion({(0, 0)}, kProgramBedroom),
      isFalse,
    );
  });

  test('programsPossessed follows catalog order', () {
    final volume = Volume(
      id: 1,
      cells: [
        VolumeCell(tx: 0, ty: 0, box: BoxPrimitive()),
        VolumeCell(tx: 1, ty: 0, box: BoxPrimitive()),
        VolumeCell(tx: 0, ty: 1, box: BoxPrimitive()),
      ],
    );
    final programs = VolumeProgramStore();
    programs.assignIndoor(tx: 0, ty: 1, programId: kProgramLeisure);
    programs.assignIndoor(tx: 1, ty: 0, programId: kProgramBedroom);
    programs.assignIndoor(tx: 0, ty: 0, programId: kProgramCirculation);
    expect(
      programs.programsPossessed(volume).map((s) => s.id),
      [kProgramCirculation, kProgramBedroom, kProgramLeisure],
    );
  });

  test('first indoor program fills the rest of the mass with circulation', () {
    final volume = Volume(
      id: 1,
      cells: [
        VolumeCell(tx: 0, ty: 0, box: BoxPrimitive()),
        VolumeCell(tx: 1, ty: 0, box: BoxPrimitive()),
        VolumeCell(tx: 0, ty: 1, box: BoxPrimitive()),
      ],
    );
    final programs = VolumeProgramStore();
    expect(
      programs.assignIndoorInVolume(
        volume: volume,
        tx: 1,
        ty: 0,
        programId: kProgramBedroom,
      ),
      isTrue,
    );
    expect(programs.indoorAt(1, 0), kProgramBedroom);
    expect(programs.indoorAt(0, 0), kProgramCirculation);
    expect(programs.indoorAt(0, 1), kProgramCirculation);
    expect(
      programs.assignIndoorInVolume(
        volume: volume,
        tx: 0,
        ty: 0,
        programId: kProgramStorage,
      ),
      isTrue,
    );
    expect(programs.indoorAt(0, 0), kProgramStorage);
    expect(programs.indoorAt(0, 1), kProgramCirculation);
    expect(programs.indoorAt(1, 0), kProgramBedroom);
  });

  test('one programmed cell clears the mass unprogrammed flag', () {
    final volume = Volume(
      id: 1,
      cells: [
        VolumeCell(tx: 0, ty: 0, box: BoxPrimitive()),
        VolumeCell(tx: 1, ty: 0, box: BoxPrimitive()),
      ],
    );
    final programs = VolumeProgramStore();
    expect(programs.isVolumeProgrammed(volume), isFalse);
    programs.assignIndoor(tx: 1, ty: 0, programId: kProgramStorage);
    expect(programs.isVolumeProgrammed(volume), isTrue);
    expect(programs.indoorAt(0, 0), isNull);
  });

  test('prune drops assignments whose cells are gone', () {
    final volumes = VolumeStore();
    expect(volumes.startNew(1, 1), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    final programs = VolumeProgramStore();
    programs.assignIndoor(tx: 1, ty: 1, programId: kProgramBedroom);
    programs.assignIndoor(tx: 4, ty: 4, programId: kProgramStorage);
    programs.prune(volumes);
    expect(programs.indoorAt(1, 1), kProgramBedroom);
    expect(programs.indoorAt(4, 4), isNull);
  });

  test('remap follows a translated volume', () {
    final volume = Volume(
      id: 1,
      cells: [VolumeCell(tx: 3, ty: 2, box: BoxPrimitive())],
    );
    final programs = VolumeProgramStore();
    programs.assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom);
    programs.remapVolumeTiles(volume, 1, 0);
    expect(programs.indoorAt(2, 2), isNull);
    expect(programs.indoorAt(3, 2), kProgramBedroom);
  });

  test('neighboring same-program cells join unless a wall separates them', () {
    final volumes = VolumeStore();
    final a = Volume(
      id: 1,
      cells: [
        VolumeCell(tx: 2, ty: 2, box: BoxPrimitive()),
        VolumeCell(tx: 3, ty: 2, box: BoxPrimitive()),
      ],
    );
    volumes.volumes.add(a);
    final programs = VolumeProgramStore();
    programs.assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom);
    programs.assignIndoor(tx: 3, ty: 2, programId: kProgramBedroom);
    final walls = WallStore(grid: volumes.grid);
    var clusters = indoorProgramClusters(
      volumes: volumes,
      programs: programs,
      walls: walls,
    );
    expect(clusters, hasLength(1));
    expect(clusters.single.tiles, {(2, 2), (3, 2)});

    walls.add(WallEdge(3, 2, 3, 3));
    clusters = indoorProgramClusters(
      volumes: volumes,
      programs: programs,
      walls: walls,
    );
    expect(clusters, hasLength(2));
  });

  test('catalog order is circulation, bedroom, storage, leisure, garden', () {
    expect(
      kProgramCatalog.map((s) => s.id),
      [
        kProgramCirculation,
        kProgramBedroom,
        kProgramStorage,
        kProgramLeisure,
        kProgramGarden,
      ],
    );
    expect(programsForSurface(outdoor: false).map((s) => s.id), [
      kProgramCirculation,
      kProgramBedroom,
      kProgramStorage,
      kProgramLeisure,
    ]);
    expect(programsForSurface(outdoor: true).map((s) => s.id), [
      kProgramCirculation,
      kProgramLeisure,
      kProgramGarden,
    ]);
  });
}
