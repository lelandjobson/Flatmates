import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

import '../geometry/geometry.dart';
import '../rendering/mesh.dart';
import 'geometry.dart';
import 'models.dart';

const paperColors = <PaperColor, Color>{
  PaperColor.red: Color(0xffe8a19b),
  PaperColor.yellow: Color(0xffe9d88d),
  PaperColor.green: Color(0xffa4c8ac),
};

Geometry regionGeometry(
  String id,
  CraftPlane plane,
  Region region,
  double depth, {
  double base = 0,
}) {
  final vertices = <Vector3>[];
  final faces = <List<int>>[];
  void face(List<Vector3> points) {
    final start = vertices.length;
    vertices.addAll(points);
    faces.add(List.generate(points.length, (i) => start + i));
  }

  final simplified = Region(
    simplifyRing(region.outer),
    region.holes.map(simplifyRing).toList(),
  );
  for (final t in slabs([simplified], simplified.contains)) {
    face(t.map((p) => plane.point(p, base + depth)).toList());
    if (depth > geometryEpsilon) {
      face(t.reversed.map((p) => plane.point(p, base)).toList());
    }
  }
  if (depth > geometryEpsilon) {
    for (final ring in region.rings) {
      for (final e in edges(ring)) {
        face([
          plane.point(e.$1, base),
          plane.point(e.$2, base),
          plane.point(e.$2, base + depth),
          plane.point(e.$1, base + depth),
        ]);
      }
    }
  }
  return Geometry(
    id: id,
    name: id,
    vertices: vertices,
    faces: faces,
    colorSeed: 7,
  );
}

Mesh planeMesh(CraftPlane plane, {double highlight = 0}) => Mesh(
  id: plane.id,
  name: 'Protoplane',
  groundPlane: plane.id.startsWith('ground-'),
  geometry: regionGeometry(plane.id, plane, plane.region, 0),
  material: MaterialModel(
    color: Color.lerp(
      const Color(0xff1a222e),
      const Color(0xff8a83db),
      highlight,
    )!,
    doubleSided: true,
    opacity: plane.id.startsWith('ground-') ? 1 : .23,
    strokeEdges: false,
  ),
);

List<Mesh> objectMeshes(
  CraftObject object,
  CraftPlane plane, {
  double highlight = 0,
  double opacity = 1,
  double growth = 1,
}) {
  final color = Color.lerp(
    paperColors[object.color],
    const Color(0xffffffff),
    highlight,
  )!;
  Mesh mesh(String suffix, Geometry geometry) => Mesh(
    id: '${object.id}$suffix',
    name: object.kind.label,
    geometry: geometry,
    material: MaterialModel(
      color: color,
      doubleSided: true,
      opacity: opacity,
      strokeEdges: false,
    ),
  );
  final depth = object.depth * growth;
  if (object.kind == CraftKind.screen) {
    final points = <Vector3>[];
    final faces = <List<int>>[];
    for (var i = 1; i < object.path.length; i++) {
      final index = points.length;
      points.addAll([
        plane.point(object.path[i - 1], .003),
        plane.point(object.path[i], .003),
        plane.point(object.path[i], depth),
        plane.point(object.path[i - 1], depth),
      ]);
      faces.add([index, index + 1, index + 2, index + 3]);
    }
    return [
      mesh(
        '',
        Geometry(
          id: object.id,
          name: 'Screen',
          vertices: points,
          faces: faces,
          colorSeed: 7,
        ),
      ),
    ];
  }
  final region = object.region;
  if (object.kind == CraftKind.mattress || object.kind == CraftKind.pillow) {
    final center = region.bounds.center;
    final inset = Region(
      region.outer.map((p) => center + (p - center) * .94).toList(),
    );
    if (region.holes.isEmpty && region.containsRegion(inset)) {
      final base = regionGeometry(
        object.id,
        plane,
        region,
        depth * .65,
        base: .002,
      );
      final vertices = <Vector3>[...base.vertices];
      final faces = <List<int>>[...base.faces];
      for (var i = 0; i < region.outer.length; i++) {
        final j = (i + 1) % region.outer.length, start = vertices.length;
        vertices.addAll([
          plane.point(region.outer[i], depth * .65 + .002),
          plane.point(region.outer[j], depth * .65 + .002),
          plane.point(inset.outer[j], depth + .002),
          plane.point(inset.outer[i], depth + .002),
        ]);
        faces.add([start, start + 1, start + 2, start + 3]);
      }
      return [
        mesh(
          '',
          Geometry(
            id: object.id,
            name: object.kind.label,
            vertices: vertices,
            faces: faces,
            colorSeed: 7,
          ),
        ),
        mesh(
          '-top',
          regionGeometry(
            '${object.id}-top',
            plane,
            inset,
            0,
            base: depth + .002,
          ),
        ),
      ];
    }
  }
  if (object.kind == CraftKind.lamp) {
    final safe = interiorSquare(region), w = safe.width * .18;
    final stem = rectangle(w, w, origin: safe.center - Offset(w / 2, w / 2));
    final shade = Region(
      region.outer
          .map((p) => region.bounds.center + (p - region.bounds.center) * .85)
          .toList(),
    );
    return [
      mesh('', regionGeometry(object.id, plane, region, depth * .1)),
      mesh(
        '-stem',
        regionGeometry('${object.id}-stem', plane, stem, depth * .65),
      ),
      mesh(
        '-shade',
        regionGeometry(
          '${object.id}-shade',
          plane,
          shade,
          depth * .35,
          base: depth * .65,
        ),
      ),
    ];
  }
  if (object.kind == CraftKind.bedFrame) {
    final b = region.bounds;
    final head = b.height >= b.width
        ? rectangle(b.width, b.height * .08, origin: b.topLeft)
        : rectangle(b.width * .08, b.height, origin: b.topLeft);
    return [
      mesh('', regionGeometry(object.id, plane, region, depth, base: .002)),
      if (region.containsRegion(head))
        mesh(
          '-headboard',
          regionGeometry(
            '${object.id}-head',
            plane,
            head,
            depth * .7,
            base: depth,
          ),
        ),
    ];
  }
  if (object.kind == CraftKind.bench) {
    // Seat preserves the drawn outline; two inset supports make its height legible.
    final result = [
      mesh(
        '',
        regionGeometry(
          object.id,
          plane,
          region,
          depth > .025 ? .025 : depth,
          base: depth > .025 ? depth - .025 : .002,
        ),
      ),
    ];
    final safe = interiorSquare(region);
    final w = safe.width * .16;
    for (final x in [safe.left + w, safe.right - 2 * w]) {
      final leg = rectangle(
        w,
        safe.height * .75,
        origin: Offset(x, safe.top + safe.height * .125),
      );
      result.add(
        mesh(
          '-leg$x',
          regionGeometry(
            '${object.id}-leg$x',
            plane,
            leg,
            depth > .025 ? depth - .025 : 0,
          ),
        ),
      );
    }
    return result;
  }
  return [
    mesh('', regionGeometry(object.id, plane, region, depth, base: .002)),
  ];
}
