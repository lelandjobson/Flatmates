import 'package:flatmates/gameplay/paper/paper_cost.dart';
import 'package:flatmates/gameplay/paper/paper_wallet.dart';
import 'package:flatmates/gameplay/paths/path_store.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flatmates/gameplay/walls/wall_edge.dart';
import 'package:flatmates/gameplay/walls/wall_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('papersForArea ceils to whole sheets and never halves', () {
    expect(papersForArea(0), 0);
    expect(papersForArea(1), 1);
    expect(papersForArea(16), 1);
    expect(papersForArea(17), 2);
  });

  test('default volume cell costs 20 sheets', () {
    final volumes = VolumeStore();
    expect(volumes.paintAt(2, 2), isTrue);
    expect(volumeExteriorArea(volumes.volumes.single, volumes.grid), 320);
    expect(volumePaperCost(volumes.volumes.single, volumes.grid), 20);
  });

  test('rounding bounce cannot mint paper', () {
    final wallet = PaperWallet(held: 10);
    expect(wallet.settleVolumes({1: 2}), isTrue);
    expect(wallet.held, 8);
    expect(wallet.settleVolumes({1: 1}), isTrue);
    expect(wallet.held, 9);
    expect(wallet.settleVolumes({1: 2}), isTrue);
    expect(wallet.held, 8);
  });

  test('broke wallet blocks a spend and leaves committed unchanged', () {
    final wallet = PaperWallet(held: 1);
    expect(wallet.settleVolumes({1: 2}), isFalse);
    expect(wallet.held, 1);
    expect(wallet.volumeCommitted, isEmpty);
  });

  test('merged mass refunds the swallowed wall', () {
    final volumes = VolumeStore();
    expect(volumes.paintAt(1, 1), isTrue);
    expect(volumes.paintAt(2, 1), isTrue);
    final one = volumePaperCost(
      Volume(id: 1, cells: [VolumeCell(tx: 1, ty: 1, box: BoxPrimitive())]),
      volumes.grid,
    );
    final two = volumePaperCost(volumes.volumes.single, volumes.grid);
    expect(two, lessThan(one * 2));
    expect(two, 34);
  });

  test('settleWorld charges volume, path island, and wall together', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    final walls = WallStore(grid: volumes.grid);
    expect(volumes.paintAt(2, 2), isTrue);
    expect(paths.placeAndJoin(4, 4), isTrue);
    expect(walls.add(WallEdge(0, 0, 1, 0)), isTrue);
    final wallet = PaperWallet();
    expect(wallet.settleWorld(volumes: volumes, paths: paths, walls: walls), isTrue);
    expect(wallet.held, kStartingPaper - 20 - 1 - 1);
    expect(wallet.volumeCommitted[volumes.volumes.single.id], 20);
    expect(wallet.pathCommitted, 1);
    expect(wallet.wallCommitted, 1);
  });

  test('settleWorld is atomic when the wallet cannot cover the world', () {
    final volumes = VolumeStore();
    expect(volumes.paintAt(2, 2), isTrue);
    final wallet = PaperWallet(held: 5);
    expect(
      wallet.settleWorld(
        volumes: volumes,
        paths: PathStore(grid: volumes.grid),
        walls: WallStore(grid: volumes.grid),
      ),
      isFalse,
    );
    expect(wallet.held, 5);
    expect(wallet.volumeCommitted, isEmpty);
  });

  test('a lone path island costs one sheet', () {
    final paths = PathStore();
    expect(paths.placeAndJoin(2, 2), isTrue);
    expect(userPathFootprintArea(paths), 16);
    expect(pathPaperCost(paths), 1);
  });

  test('each wall edge costs one sheet', () {
    expect(wallPaperCost(0), 0);
    expect(wallPaperCost(3), 3);
    final walls = WallStore()..add(WallEdge(1, 1, 2, 1));
    final wallet = PaperWallet(held: 5);
    expect(wallet.settleWorld(
      volumes: VolumeStore(),
      paths: PathStore(),
      walls: walls,
    ), isTrue);
    expect(wallet.held, 4);
    expect(wallet.wallCommitted, 1);
  });
}
