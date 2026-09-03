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
    expect(outline.edges, hasLength(16));
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
    expect(store.byVolume.values.single.edges, hasLength(16));
  });
}
