import 'package:flatmates/gameplay/paper/paper_cost.dart';
import 'package:flatmates/gameplay/paper/paper_quote.dart';
import 'package:flatmates/gameplay/paper/paper_wallet.dart';
import 'package:flatmates/gameplay/paths/path_store.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_partition.dart';
import 'package:flatmates/gameplay/volumes/volume_program.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flatmates/gameplay/walls/wall_store.dart';
import 'package:flutter_test/flutter_test.dart';

VolumeStore _mass(Iterable<(int, int)> tiles) {
  final volumes = VolumeStore();
  for (final tile in tiles) {
    expect(volumes.paintAt(tile.$1, tile.$2), isTrue);
  }
  return volumes;
}

void main() {
  test('an isolated programmed cell has no partition walls', () {
    final volumes = _mass([(2, 2)]);
    final programs = VolumeProgramStore()
      ..assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom);
    expect(collectProgramPartitions(volumes, programs), isEmpty);
    expect(partitionPaperCost(volumes, programs), 0);
  });

  test('a programmed cell among neighbors gets interior edges only', () {
    final volumes = _mass([(1, 2), (2, 2), (3, 2)]);
    final programs = VolumeProgramStore()
      ..assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom);
    final walls = collectProgramPartitions(volumes, programs);
    expect(walls, hasLength(2));
    expect(
      walls.map((w) => {w.tile0, w.tile1}),
      containsAll([
        {(1, 2), (2, 2)},
        {(2, 2), (3, 2)},
      ]),
    );
    expect(walls.every((w) => w.widthSubtiles == 8), isTrue);
    expect(walls.every((w) => w.door != null), isTrue);
    expect(walls.every((w) => w.door!.originU == 3), isTrue);
    expect(walls.every((w) => w.netArea == 32), isTrue);
    expect(partitionPaperCost(volumes, programs), 4);
  });

  test('joining the same program drops the shared wall', () {
    final volumes = _mass([(2, 2), (3, 2)]);
    final programs = VolumeProgramStore()
      ..assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom);
    expect(collectProgramPartitions(volumes, programs), hasLength(1));
    expect(partitionEdgePaperCost(collectProgramPartitions(volumes, programs).single), 2);

    programs.assignIndoor(tx: 3, ty: 2, programId: kProgramBedroom);
    expect(collectProgramPartitions(volumes, programs), isEmpty);
    expect(partitionPaperCost(volumes, programs), 0);
  });

  test('different programs keep the shared wall', () {
    final volumes = _mass([(2, 2), (3, 2)]);
    final programs = VolumeProgramStore()
      ..assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom)
      ..assignIndoor(tx: 3, ty: 2, programId: kProgramStorage);
    final walls = collectProgramPartitions(volumes, programs);
    expect(walls, hasLength(1));
    expect(walls.single.side, VolumeSide.east);
  });

  test('clearing a program drops walls that are no longer a boundary', () {
    final volumes = _mass([(2, 2), (3, 2)]);
    final programs = VolumeProgramStore()
      ..assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom);
    expect(collectProgramPartitions(volumes, programs), hasLength(1));
    programs.clearIndoor(2, 2);
    expect(collectProgramPartitions(volumes, programs), isEmpty);
  });

  test('one default partition costs two sheets and joining refunds them', () {
    final volumes = _mass([(2, 2), (3, 2)]);
    final programs = VolumeProgramStore()
      ..assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom);
    final paths = PathStore(grid: volumes.grid);
    final walls = WallStore(grid: volumes.grid);
    final wallet = PaperWallet();
    expect(
      wallet.settleWorld(
        volumes: volumes,
        paths: paths,
        walls: walls,
        programs: programs,
      ),
      isTrue,
    );
    final volumeCost = volumePaperCost(volumes.volumes.single, volumes.grid);
    expect(wallet.partitionCommitted, 2);
    expect(wallet.held, kStartingPaper - volumeCost - 2);

    programs.assignIndoor(tx: 3, ty: 2, programId: kProgramBedroom);
    expect(
      wallet.settleWorld(
        volumes: volumes,
        paths: paths,
        walls: walls,
        programs: programs,
      ),
      isTrue,
    );
    expect(wallet.partitionCommitted, 0);
    expect(wallet.held, kStartingPaper - volumeCost);
  });

  test('broke wallet cannot afford a partition and leaves committed unchanged', () {
    final volumes = _mass([(2, 2), (3, 2)]);
    final programs = VolumeProgramStore()
      ..assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom);
    final volumeCost = volumePaperCost(volumes.volumes.single, volumes.grid);
    final wallet = PaperWallet(held: volumeCost + 1);
    expect(
      wallet.settleWorld(
        volumes: volumes,
        paths: PathStore(grid: volumes.grid),
        walls: WallStore(grid: volumes.grid),
      ),
      isTrue,
    );
    expect(wallet.held, 1);
    expect(
      wallet.settleWorld(
        volumes: volumes,
        paths: PathStore(grid: volumes.grid),
        walls: WallStore(grid: volumes.grid),
        programs: programs,
      ),
      isFalse,
    );
    expect(wallet.held, 1);
    expect(wallet.partitionCommitted, 0);
  });

  test('quoting a volume cell beside a program includes the new partition', () {
    final volumes = _mass([(2, 2)]);
    final programs = VolumeProgramStore()
      ..assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom);
    final paths = PathStore(grid: volumes.grid);
    final walls = WallStore(grid: volumes.grid);
    final paper = PaperWallet();
    expect(
      paper.settleWorld(
        volumes: volumes,
        paths: paths,
        walls: walls,
        programs: programs,
      ),
      isTrue,
    );

    final withoutProgram = quoteVolumePaintAt(
      paper: paper,
      volumes: volumes,
      paths: paths,
      walls: walls,
      tx: 3,
      ty: 2,
    );
    final withProgram = quoteVolumePaintAt(
      paper: paper,
      volumes: volumes,
      paths: paths,
      walls: walls,
      programs: programs,
      tx: 3,
      ty: 2,
    );
    expect(withoutProgram, 14);
    expect(withProgram, 16);
  });
}
