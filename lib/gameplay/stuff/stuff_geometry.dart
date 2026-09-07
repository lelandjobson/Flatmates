import 'package:vector_math/vector_math_64.dart';

import '../../geometry/geometries.dart';
import '../../geometry/geometry.dart';
import 'stuff_catalog.dart';

/// Local-space visual mesh. Floor items sit on y=0; wall items sit on z=0
/// and grow into +Z (into the room after [stuffEuler] alignment).
Geometry stuffGeometry(String specId) {
  return switch (specId) {
    kStuffBed => _bed(),
    kStuffDesk => _desk(),
    kStuffLamp => _lamp(),
    kStuffChair => _chair(),
    kStuffCrate => _box(0.7, 0.7, 0.7, name: 'Crate'),
    kStuffShelf => _box(1.6, 0.8, 0.18, name: 'Shelf'),
    _ => _box(0.5, 0.5, 0.5, name: 'Stuff'),
  };
}

(Vector3 min, Vector3 max) stuffLocalBounds(String specId) {
  final geo = stuffGeometry(specId);
  return _boundsOf(geo.vertices);
}

Geometry _bed() {
  final b = _Builder('Bed');
  b.box(2.4, 0.32, 1.35, y: 0.16);
  b.box(2.52, 0.04, 1.46, y: 0.34);
  b.box(2.52, 0.10, 0.04, y: 0.27, z: -0.75);
  b.box(2.52, 0.10, 0.04, y: 0.27, z: 0.75);
  b.box(0.04, 0.10, 1.46, y: 0.27, x: -1.28);
  b.box(0.04, 0.10, 1.46, y: 0.27, x: 1.28);
  b.box(0.55, 0.12, 1.05, y: 0.42, x: -0.75);
  return b.build();
}

Geometry _desk() {
  final b = _Builder('Desk');
  b.box(1.6, 0.08, 0.8, y: 0.66);
  b.box(0.08, 0.62, 0.08, y: 0.31, x: -0.72, z: -0.32);
  b.box(0.08, 0.62, 0.08, y: 0.31, x: 0.72, z: -0.32);
  b.box(0.08, 0.62, 0.08, y: 0.31, x: -0.72, z: 0.32);
  b.box(0.08, 0.62, 0.08, y: 0.31, x: 0.72, z: 0.32);
  return b.build();
}

Geometry _lamp() {
  final b = _Builder('Lamp');
  b.box(0.28, 0.06, 0.28, y: 0.03);
  b.box(0.07, 0.62, 0.07, y: 0.37);
  b.box(0.32, 0.22, 0.32, y: 0.80);
  return b.build();
}

Geometry _chair() {
  final b = _Builder('Chair');
  b.box(0.56, 0.08, 0.56, y: 0.38);
  b.box(0.56, 0.42, 0.07, y: 0.63, z: -0.24);
  b.box(0.07, 0.34, 0.07, y: 0.17, x: -0.22, z: -0.22);
  b.box(0.07, 0.34, 0.07, y: 0.17, x: 0.22, z: -0.22);
  b.box(0.07, 0.34, 0.07, y: 0.17, x: -0.22, z: 0.22);
  b.box(0.07, 0.34, 0.07, y: 0.17, x: 0.22, z: 0.22);
  return b.build();
}

Geometry _box(double w, double h, double d, {required String name}) {
  final b = _Builder(name);
  b.box(w, h, d, y: h * 0.5);
  return b.build();
}

class _Builder {
  _Builder(this.name);

  final String name;
  final vertices = <Vector3>[];
  final faces = <List<int>>[];

  void box(
    double w,
    double h,
    double d, {
    double x = 0,
    double y = 0,
    double z = 0,
  }) {
    final hx = w * 0.5;
    final hy = h * 0.5;
    final hz = d * 0.5;
    final base = vertices.length;
    vertices.addAll([
      Vector3(x - hx, y - hy, z - hz),
      Vector3(x + hx, y - hy, z - hz),
      Vector3(x + hx, y + hy, z - hz),
      Vector3(x - hx, y + hy, z - hz),
      Vector3(x - hx, y - hy, z + hz),
      Vector3(x + hx, y - hy, z + hz),
      Vector3(x + hx, y + hy, z + hz),
      Vector3(x - hx, y + hy, z + hz),
    ]);
    for (final face in GeometryBuilders.cubeFaces) {
      faces.add([for (final i in face) i + base]);
    }
  }

  Geometry build() => Geometry(
        id: name.toLowerCase(),
        name: name,
        vertices: vertices,
        faces: faces,
      );
}

(Vector3 min, Vector3 max) _boundsOf(List<Vector3> points) {
  var min = Vector3(double.infinity, double.infinity, double.infinity);
  var max = Vector3(-double.infinity, -double.infinity, -double.infinity);
  for (final p in points) {
    min = Vector3(
      min.x < p.x ? min.x : p.x,
      min.y < p.y ? min.y : p.y,
      min.z < p.z ? min.z : p.z,
    );
    max = Vector3(
      max.x > p.x ? max.x : p.x,
      max.y > p.y ? max.y : p.y,
      max.z > p.z ? max.z : p.z,
    );
  }
  if (min.x.isInfinite) return (Vector3.zero(), Vector3.zero());
  return (min, max);
}
