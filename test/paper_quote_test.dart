import 'package:flatmates/gameplay/paper/paper_cost.dart';
import 'package:flatmates/gameplay/paper/paper_quote.dart';
import 'package:flatmates/gameplay/paper/paper_wallet.dart';
import 'package:flatmates/gameplay/paths/path_store.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flatmates/gameplay/walls/wall_edge.dart';
import 'package:flatmates/gameplay/walls/wall_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  test('quoting a new volume cell costs 20 and does not mutate live stores', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    final walls = WallStore(grid: volumes.grid);
    final paper = PaperWallet();
    final quote = quoteVolumePaintAt(
      paper: paper,
      volumes: volumes,
      paths: paths,
      walls: walls,
      tx: 2,
      ty: 2,
    );
    expect(quote, 20);
    expect(volumes.volumes, isEmpty);
    expect(paper.held, kStartingPaper);
  });

  test('quoting an occupied volume tile is a no-op', () {
    final volumes = VolumeStore();
    expect(volumes.paintAt(2, 2), isTrue);
    final paper = PaperWallet();
    expect(
      paper.settleWorld(
        volumes: volumes,
        paths: PathStore(grid: volumes.grid),
        walls: WallStore(grid: volumes.grid),
      ),
      isTrue,
    );
    expect(
      quoteVolumePaintAt(
        paper: paper,
        volumes: volumes,
        paths: PathStore(grid: volumes.grid),
        walls: WallStore(grid: volumes.grid),
        tx: 2,
        ty: 2,
      ),
      isNull,
    );
  });

  test('quoting a path on an isolated volume is a no-op', () {
    final volumes = VolumeStore();
    expect(volumes.startNew(2, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    expect(
      quotePathPlaceAt(
        paper: PaperWallet(),
        volumes: volumes,
        paths: PathStore(grid: volumes.grid),
        walls: WallStore(grid: volumes.grid),
        tx: 2,
        ty: 2,
      ),
      isNull,
    );
  });

  test('quoting a path island is one sheet', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    final quote = quotePathPlaceAt(
      paper: PaperWallet(),
      volumes: volumes,
      paths: paths,
      walls: WallStore(grid: volumes.grid),
      tx: 3,
      ty: 3,
    );
    expect(quote, 1);
    expect(paths.tiles, isEmpty);
  });

  test('quoting a wall add is one sheet and a remove refunds one', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    final walls = WallStore(grid: volumes.grid);
    final paper = PaperWallet();
    final edge = WallEdge(1, 1, 2, 1);
    final a = walls.vertexWorld(edge.x0, edge.y0);
    final b = walls.vertexWorld(edge.x1, edge.y1);
    final hit = (a + b) * 0.5;
    expect(
      quoteWallToggleAt(
        paper: paper,
        volumes: volumes,
        paths: paths,
        walls: walls,
        hit: hit,
      ),
      1,
    );
    expect(walls.edges, isEmpty);

    expect(walls.add(WallEdge(1, 1, 2, 1)), isTrue);
    expect(paper.settleWorld(volumes: volumes, paths: paths, walls: walls), isTrue);
    expect(
      quoteWallToggleAt(
        paper: paper,
        volumes: volumes,
        paths: paths,
        walls: walls,
        hit: hit,
      ),
      -1,
    );
    expect(walls.edges, hasLength(1));
  });
}
