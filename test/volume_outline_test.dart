import 'package:flatmates/gameplay/volumes/volume_outline.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  test('a single cell has twelve outer edges', () {
    final volumes = VolumeStore();
    expect(volumes.startNew(2, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    final outline = buildVolumeOutline(
      volumes.volumes.single,
      volumes.grid,
    );
    expect(outline.edges, hasLength(12));
  });

  test('joining two cells drops the shared-face edges', () {
    final volumes = VolumeStore();
    expect(volumes.paintAt(2, 2), isTrue);
    expect(volumes.paintAt(3, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    final outline = buildVolumeOutline(
      volumes.volumes.single,
      volumes.grid,
    );
    expect(outline.edges.length, lessThan(24));
    expect(outline.edges, hasLength(12));
    final joinX = volumes.grid.tileOrigin(3, 2).x;
    final interior = outline.edges.where((e) {
      return (e.a.x - joinX).abs() < 1e-6 && (e.b.x - joinX).abs() < 1e-6;
    });
    expect(interior, isEmpty);
  });

  test('only front silhouettes and creases are visible', () {
    final back = VolumeOutlineFace(
      normal: Vector3(-1, 0, 0),
      center: Vector3.zero(),
    );
    final front = VolumeOutlineFace(
      normal: Vector3(1, 0, 0),
      center: Vector3.zero(),
    );
    final roof = VolumeOutlineFace(
      normal: Vector3(0, 1, 0),
      center: Vector3.zero(),
    );
    final camera = Vector3(10, 4, 0);
    expect(
      volumeOutlineEdgeVisible(
        VolumeOutlineEdge(a: Vector3.zero(), b: Vector3(0, 1, 0), faces: [back]),
        camera,
      ),
      isFalse,
    );
    expect(
      volumeOutlineEdgeVisible(
        VolumeOutlineEdge(
          a: Vector3.zero(),
          b: Vector3(0, 1, 0),
          faces: [front, back],
        ),
        camera,
      ),
      isTrue,
    );
    expect(
      volumeOutlineEdgeVisible(
        VolumeOutlineEdge(
          a: Vector3.zero(),
          b: Vector3(0, 0, 1),
          faces: [front, roof],
        ),
        camera,
      ),
      isTrue,
    );
    expect(
      volumeOutlineEdgeVisible(
        VolumeOutlineEdge(
          a: Vector3.zero(),
          b: Vector3(0, 1, 0),
          faces: [back, back],
        ),
        camera,
      ),
      isFalse,
    );
  });

  test('outline store rebuilds when a cell is added', () {
    final volumes = VolumeStore();
    final store = VolumeOutlineStore();
    expect(volumes.startNew(2, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    store.rebuild(volumes);
    expect(store.byVolume.values.single.edges, hasLength(12));
    expect(volumes.paintAt(3, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    store.rebuild(volumes);
    expect(store.byVolume.values.single.edges, hasLength(12));
  });

  test('four merged ceilings stay one outer loop after an inset scale', () {
    final volumes = VolumeStore();
    expect(volumes.paintAt(2, 2), isTrue);
    expect(volumes.paintAt(3, 2), isTrue);
    expect(volumes.paintAt(2, 3), isTrue);
    expect(volumes.paintAt(3, 3), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    final grid = volumes.grid;
    final full = buildVolumeOutline(volumes.volumes.single, grid);
    final fullCeil = _ceilingPerimeter(full.edges);
    expect(fullCeil, closeTo(8 * grid.tileSize, 1e-6));

    final se = volumes.volumes.single.cellAt(3, 3)!;
    se.box.widthSubtiles -= 1;
    se.box.depthSubtiles -= 1;
    final inset = buildVolumeOutline(volumes.volumes.single, grid);
    final insetCeil = _ceilingPerimeter(inset.edges);
    // A one-subtile SE notch replaces a corner of the same length, so the
    // outer peri stays 8 tiles. A leftover inner roof seam would add ~2 tiles.
    expect(insetCeil, closeTo(fullCeil, 1e-4));
    expect(insetCeil, lessThan(fullCeil + grid.tileSize));
    final joinZ = grid.tileOrigin(3, 2).z + grid.tileSize;
    final innerSeam = inset.edges.where((edge) {
      final roof = edge.faces.any((face) => face.normal.y > 0.9);
      if (!roof) return false;
      if ((edge.a.z - joinZ).abs() > 1e-6 || (edge.b.z - joinZ).abs() > 1e-6) {
        return false;
      }
      return (edge.a - edge.b).length > grid.tileSize * 0.5;
    });
    expect(innerSeam, isEmpty);
  });
}

double _ceilingPerimeter(List<VolumeOutlineEdge> edges) {
  var length = 0.0;
  for (final edge in edges) {
    final roof = edge.faces.any((face) => face.normal.y > 0.9);
    if (!roof) continue;
    if ((edge.a.y - edge.b.y).abs() > 1e-6) continue;
    length += (edge.a - edge.b).length;
  }
  return length;
}
