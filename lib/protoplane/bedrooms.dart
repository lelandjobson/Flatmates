import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import 'geometry.dart';
import 'models.dart';

enum ResidentKind { frogman, cubeBoy }

extension ResidentName on ResidentKind {
  String get label => this == ResidentKind.frogman ? 'Frogman' : 'Cube Boy';
}

class Bedroom {
  const Bedroom({
    required this.floorId,
    required this.missing,
    required this.comfort,
    required this.bonuses,
    this.bedId,
    this.mattressId,
    this.resident,
    this.position,
  });
  final String floorId;
  final List<String> missing;
  final int comfort;
  final Map<String, int> bonuses;
  final String? bedId, mattressId;
  final ResidentKind? resident;
  final Offset? position;
  bool get usable => missing.isEmpty;
  String get residentId => 'resident-$floorId';
  String get mood => comfort >= 85
      ? 'Delighted'
      : comfort >= 65
      ? 'Comfortable'
      : 'Settled';
}

String? supportingFloor(
  String? objectId,
  Map<String, CraftObject> objects,
  Map<String, CraftPlane> planes,
) {
  final visited = <String>{};
  while (objectId != null && visited.add(objectId)) {
    final object = objects[objectId];
    if (object == null) return null;
    if (object.kind == CraftKind.floor) return object.id;
    objectId = planes[object.planeId]?.owner;
  }
  return null;
}

/// A room currently corresponds to one authored floor footprint. Enclosure is
/// physical wall coverage, not merely the existence of wall candidate planes.
/// Residency is derived from stable floor IDs, so save/load and undo never
/// reroll a character or create duplicate occupants.
List<Bedroom> evaluateBedrooms(
  Map<String, CraftObject> objects,
  Map<String, CraftPlane> planes,
) {
  final result = <Bedroom>[];
  for (final floor in objects.values.where((o) => o.kind == CraftKind.floor)) {
    final source = planes[floor.planeId];
    if (source == null) continue;
    final contents = objects.values
        .where(
          (o) =>
              o.id != floor.id &&
              supportingFloor(o.id, objects, planes) == floor.id,
        )
        .toList();
    final walls = contents.where((o) => o.kind == CraftKind.wall).toList();
    final candidates = planes.values
        .where((p) => p.owner == floor.id && p.wallCandidate)
        .toList();
    final enclosed =
        candidates.isNotEmpty &&
        candidates.every((p) {
          final covers = <Region>[];
          for (final wall in walls.where((o) => o.planeId == p.id)) {
            covers.add(wall.region);
            for (final opening in contents.where(
              (o) =>
                  (o.kind == CraftKind.door || o.kind == CraftKind.window) &&
                  planes[o.planeId]?.owner == wall.id,
            )) {
              covers.add(Region(opening.region.outer));
            }
          }
          final band = rectangle(
            p.region.bounds.width,
            .65,
            origin: p.region.bounds.topLeft,
          );
          return measure(
                [band, ...covers],
                (point) =>
                    band.contains(point) &&
                    !covers.any((r) => r.contains(point)),
              ) <
              geometryEpsilon;
        });
    final doors = contents
        .where(
          (o) =>
              o.kind == CraftKind.door &&
              o.region.bounds.top <= .01 &&
              o.region.bounds.width >= .12 &&
              o.region.bounds.height >= .35,
        )
        .toList();
    final beds = contents
        .where(
          (o) =>
              o.kind == CraftKind.bedFrame &&
              o.region.holes.isEmpty &&
              o.region.area >= .025 &&
              o.depth >= .03 &&
              planes[o.planeId]?.owner == floor.id,
        )
        .toList();
    CraftObject? bed, mattress;
    Offset? arrival;
    for (final candidate in beds) {
      final mattresses = contents.where(
        (o) =>
            o.kind == CraftKind.mattress &&
            planes[o.planeId]?.owner == candidate.id &&
            o.region.holes.isEmpty &&
            o.region.area >= candidate.region.area * .65 &&
            o.depth >= .015 &&
            candidate.region.containsRegion(o.region),
      );
      for (final m in mattresses) {
        bed ??= candidate;
        mattress ??= m;
        final accessible = _accessibleBed(
          floor,
          source,
          candidate,
          doors,
          contents,
          planes,
        );
        if (accessible != null) {
          bed = candidate;
          mattress = m;
          arrival = accessible;
          break;
        }
      }
      if (arrival != null) break;
    }
    final missing = <String>[
      if (!enclosed) 'Walls',
      if (doors.isEmpty) 'Door',
      if (beds.isEmpty) 'Bed frame' else if (mattress == null) 'Mattress',
      if (doors.isNotEmpty && mattress != null && arrival == null)
        'Clear access',
    ];
    final bedding = contents
        .where((o) => planes[o.planeId]?.owner == mattress?.id)
        .toList();
    bool hasBedding(CraftKind kind, double coverage) =>
        mattress != null &&
        bedding.any(
          (o) =>
              o.kind == kind &&
              o.region.area >= mattress!.region.area * coverage &&
              o.region.holes.isEmpty,
        );
    final bonuses = <String, int>{
      'Pillow': hasBedding(CraftKind.pillow, .04) ? 12 : 0,
      'Blanket': hasBedding(CraftKind.blanket, .35) ? 16 : 0,
      'Lighting':
          contents.any((o) => o.kind == CraftKind.lamp && o.depth >= .08)
          ? 12
          : contents.any((o) => o.kind == CraftKind.window)
          ? 6
          : 0,
      'Storage':
          contents.any((o) => o.kind == CraftKind.storage && o.depth >= .06)
          ? 12
          : 0,
      'Rug':
          contents.any(
            (o) =>
                o.kind == CraftKind.rug && planes[o.planeId]?.owner == floor.id,
          )
          ? 8
          : 0,
    };
    final usable = missing.isEmpty;
    final seed = floor.id.codeUnits.fold(0, (a, b) => a + b);
    result.add(
      Bedroom(
        floorId: floor.id,
        missing: missing,
        comfort: usable ? 40 + bonuses.values.fold(0, (a, b) => a + b) : 0,
        bonuses: bonuses,
        bedId: bed?.id,
        mattressId: mattress?.id,
        position: usable ? arrival : null,
        resident: usable ? ResidentKind.values[seed % 2] : null,
      ),
    );
  }
  return result;
}

/// Flood a modest clearance grid from the inside of each real doorway.
/// Four-neighbor movement prevents slipping diagonally between furnishings.
Offset? _accessibleBed(
  CraftObject floor,
  CraftPlane floorPlane,
  CraftObject bed,
  List<CraftObject> doors,
  List<CraftObject> contents,
  Map<String, CraftPlane> planes,
) {
  final b = floor.region.bounds;
  const resolution = 36, radius = .025;
  final dx = b.width / resolution, dy = b.height / resolution;
  final obstacles = contents
      .where(
        (o) =>
            planes[o.planeId]?.owner == floor.id &&
            o.kind != CraftKind.wall &&
            o.kind != CraftKind.rug &&
            o.depth > .02,
      )
      .toList();
  bool free(Offset point) {
    final samples = [
      point,
      point + const Offset(radius, radius),
      point + const Offset(-radius, radius),
      point + const Offset(radius, -radius),
      point + const Offset(-radius, -radius),
    ];
    if (samples.any((p) => !floor.region.contains(p))) return false;
    for (final obstacle in obstacles) {
      if (obstacle.kind == CraftKind.screen) {
        for (var i = 1; i < obstacle.path.length; i++) {
          if (_distance(point, obstacle.path[i - 1], obstacle.path[i]) <
              radius + .004) {
            return false;
          }
        }
      } else if (samples.any(obstacle.region.contains) ||
          obstacle.region.rings
              .expand(edges)
              .any((e) => _distance(point, e.$1, e.$2) < radius)) {
        return false;
      }
    }
    return true;
  }

  Offset cell(int index) => Offset(
    b.left + (index % resolution + .5) * dx,
    b.top + (index ~/ resolution + .5) * dy,
  );
  final walkable = List.generate(resolution * resolution, (i) => free(cell(i)));
  final queue = Queue<int>(), seen = <int>{};
  for (final door in doors) {
    final p = planes[door.planeId];
    if (p == null) continue;
    final world = p.point(
      Offset(door.region.bounds.center.dx, door.region.bounds.top),
    );
    final inside = floorPlane.local(world - p.normal * .07);
    if (!free(inside) || !free(floorPlane.local(world - p.normal * .05))) {
      continue;
    }
    var best = -1, distance = .075;
    for (var i = 0; i < walkable.length; i++) {
      if (walkable[i] && (cell(i) - inside).distance < distance) {
        best = i;
        distance = (cell(i) - inside).distance;
      }
    }
    if (best >= 0 && seen.add(best)) queue.add(best);
  }
  while (queue.isNotEmpty) {
    final i = queue.removeFirst(), p = cell(i);
    if (bed.region.outer.asMap().entries.any(
      (e) =>
          _distance(
            p,
            e.value,
            bed.region.outer[(e.key + 1) % bed.region.outer.length],
          ) <
          .07,
    )) {
      return p;
    }
    final x = i % resolution, y = i ~/ resolution;
    for (final next in [
      if (x > 0) i - 1,
      if (x < resolution - 1) i + 1,
      if (y > 0) i - resolution,
      if (y < resolution - 1) i + resolution,
    ]) {
      if (walkable[next] && seen.add(next)) queue.add(next);
    }
  }
  return null;
}

double _distance(Offset p, Offset a, Offset b) {
  final d = b - a;
  if (d.distanceSquared < geometryEpsilon) return (p - a).distance;
  final t = math.max(
    0.0,
    math.min(1.0, ((p - a).dx * d.dx + (p - a).dy * d.dy) / d.distanceSquared),
  );
  return (p - a - d * t).distance;
}
