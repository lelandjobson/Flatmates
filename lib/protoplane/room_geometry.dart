import 'dart:ui';
import 'geometry.dart';
import 'models.dart';

const roomThickness = .01;

class RoomPanel {
  RoomPanel(this.key, this.frame, this.regions);
  final String key;
  final CraftPlane frame;
  final List<Region> regions;
}

Region mapRegion(Region r, Offset Function(Offset) map) => Region(
  r.outer.map(map).toList(),
  r.holes.map((h) => h.map(map).toList()).toList(),
);

/// Thin planar prisms shared by rendering, picking, and collision.
List<RoomPanel> roomPanels(CraftObject room, CraftPlane source) {
  CraftPlane frame(String key, Region region, {double height = 0}) =>
      CraftPlane(
        id: 'surface-${room.id}-$key',
        origin: source.point(Offset.zero, height),
        u: source.u,
        v: source.v,
        region: region,
        owner: room.id,
        grids: [lattice(key, region)],
      );
  final result = <RoomPanel>[
    RoomPanel('floor', frame('floor', room.region, height: .002), [
      room.region,
    ]),
    RoomPanel(
      'roof',
      frame('roof', room.region, height: room.depth - roomThickness + .002),
      [room.region],
    ),
  ];
  for (final (ringIndex, raw) in room.region.rings.indexed) {
    final ring = simplifyRing(raw);
    final area = edges(
      ring,
    ).fold<double>(0, (sum, e) => sum + cross(e.$1, e.$2));
    final sign = (area > 0 ? 1.0 : -1.0) * (ringIndex == 0 ? 1.0 : -1.0);
    for (var i = 0; i < ring.length; i++) {
      var a = ring[i], b = ring[(i + 1) % ring.length];
      if (sign < 0) {
        final swap = a;
        a = b;
        b = swap;
      }
      final u = (source.point(b) - source.point(a)).normalized();
      final key = 'wall-$ringIndex-$i',
          region = rectangle((b - a).distance, room.depth);
      final normal = u.cross(source.normal).normalized();
      final panel = CraftPlane(
        id: 'surface-${room.id}-$key',
        origin: source.point(a, .002) - normal * roomThickness,
        u: u,
        v: source.normal,
        region: region,
        owner: room.id,
        grids: [lattice(key, region)],
      );
      var pieces = [region];
      for (final opening in room.openings.where((o) => o.wall == key)) {
        pieces = pieces.expand((r) => r.subtract(opening.region)).toList();
      }
      result.add(RoomPanel(key, panel, pieces));
    }
  }
  return result;
}

/// Physical front/back identity is independent of visibility and camera focus.
List<CraftPlane> roomSurfaces(CraftObject room, CraftPlane source) {
  final result = <CraftPlane>[];
  final panels = roomPanels(room, source);
  for (final panel in panels) {
    final p = panel.frame;
    for (final inside in [false, true]) {
      final flip = panel.key == 'floor' ? !inside : inside;
      final offset = panel.key == 'floor'
          ? (inside ? roomThickness + .002 : 0.0)
          : (inside ? -.002 : roomThickness + .002);
      var exposed = panel.regions;
      if (inside && (panel.key == 'floor' || panel.key == 'roof')) {
        for (final wall in panels.where((w) => w.key.startsWith('wall-'))) {
          final a = wall.frame.point(Offset.zero),
              b = wall.frame.point(Offset(wall.frame.region.bounds.width, 0)),
              n = wall.frame.normal * roomThickness;
          final strip = Region([
            p.local(a),
            p.local(b),
            p.local(b + n),
            p.local(a + n),
          ]);
          exposed = exposed.expand((r) => r.subtract(strip)).toList();
        }
      }
      for (final (index, region) in exposed.indexed) {
        final id =
            'surface-${room.id}-${panel.key}-${inside ? 'in' : 'out'}-$index';
        final r = flip ? mapRegion(region, (v) => Offset(-v.dx, v.dy)) : region;
        result.add(
          CraftPlane(
            id: id,
            origin: p.origin + p.normal * offset,
            u: flip ? -p.u : p.u,
            v: p.v,
            region: r,
            owner: room.id,
            grids: [lattice(id, r)],
            roomId: room.id,
            roomFace: panel.key,
            interior: inside,
          ),
        );
      }
    }
  }
  return result;
}

/// A doorway needs a clear quarter-unit mouth reaching the floor.
Offset? doorwayCenter(Region opening) {
  if (opening.bounds.top.abs() > geometryEpsilon) return null;
  for (
    var x = (opening.bounds.left * 4).ceil() / 4;
    x + .25 <= opening.bounds.right + geometryEpsilon;
    x += .25
  ) {
    if (opening.containsRegion(rectangle(.25, .5, origin: Offset(x, 0)))) {
      return Offset(x + .125, 0);
    }
  }
  return null;
}
