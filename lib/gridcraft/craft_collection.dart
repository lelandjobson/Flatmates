import 'dart:math' as math;
import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

import '../geometry/geometry_2d.dart';
import '../geometry/geometry_algorithms.dart'
    show PointLocation, pointInPolygon, polygonDifference;
import 'folded_model.dart';

/// The craft collection play opens to.
const String kTestRoomAsset = 'assets/craft_collections/test_room.json';

/// How a collection surface draws.
enum SurfaceCategory {
  /// Always drawn as it is.
  plain,

  /// Double-sided, and fades away when seen from behind, so the crafts past
  /// it show through.
  occludingGeo;

  static SurfaceCategory parse(Object? raw) =>
      raw == 'occluding_geo' ? occludingGeo : plain;

  String get id => this == occludingGeo ? 'occluding_geo' : 'plain';
}

/// Geometry in a craft collection that is not a craft: one planar polygon in
/// world space, outer ring first, then its holes.
class CollectionSurface {
  CollectionSurface({
    required this.category,
    required this.rings,
    Vector3? normal,
  }) : normal = (normal ?? _newell(rings.first)).normalized();

  final SurfaceCategory category;
  final List<List<Vector3>> rings;

  /// The front: the side crafts are seen from.
  final Vector3 normal;

  Vector3 get origin => rings.first.first;

  /// Signed distance of [point] in front of the plane.
  double side(Vector3 point) => (point - origin).dot(normal);

  static CollectionSurface fromJson(Map<String, dynamic> json) {
    final rings = [
      for (final ring in json['rings'] as List)
        [for (final point in ring as List) _vector(point)],
    ];
    final normal = json['normal'];
    return CollectionSurface(
      category: SurfaceCategory.parse(json['category']),
      rings: rings,
      normal: normal == null ? null : _vector(normal),
    );
  }
}

/// Where a craft stands on the collection's ground: the middle of its
/// footprint at [at], turned [turnDegrees] counter-clockwise from above.
/// [puzzleId] names the blueprint.
class CraftSpot {
  const CraftSpot({
    required this.puzzleId,
    required this.at,
    this.turnDegrees = 0,
  });

  final String puzzleId;
  final Offset at;
  final double turnDegrees;

  static CraftSpot fromJson(Map<String, dynamic> json) => CraftSpot(
    puzzleId: json['puzzle'] as String,
    at: _offset(json['at']),
    turnDegrees: (json['turn'] as num?)?.toDouble() ?? 0,
  );
}

/// Where a craft collection opens: looking at [at] from [turnDegrees] about
/// the vertical, measured from +x, and [tiltDegrees] above the ground.
/// A null [halfHeight] frames the whole collection.
class CollectionCamera {
  const CollectionCamera({
    required this.at,
    this.turnDegrees = -90,
    this.tiltDegrees = 32,
    this.halfHeight,
  });

  final Vector3 at;
  final double turnDegrees;
  final double tiltDegrees;
  final double? halfHeight;

  /// Unit vector from [at] toward the eye.
  Vector3 get direction {
    final turn = turnDegrees * math.pi / 180;
    final tilt = tiltDegrees * math.pi / 180;
    return Vector3(
      math.cos(tilt) * math.cos(turn),
      math.cos(tilt) * math.sin(turn),
      math.sin(tilt),
    );
  }

  static CollectionCamera fromJson(Object? raw) {
    if (raw is! Map) return CollectionCamera(at: Vector3.zero());
    return CollectionCamera(
      at: raw['at'] == null ? Vector3.zero() : _vector(raw['at']),
      turnDegrees: (raw['turn'] as num?)?.toDouble() ?? -90,
      tiltDegrees: (raw['tilt'] as num?)?.toDouble() ?? 32,
      halfHeight: (raw['halfHeight'] as num?)?.toDouble(),
    );
  }
}

/// A shared object space: crafts standing on the ground plane, z = 0, and
/// other surfaces around them. A room is one way to make those surfaces.
class CraftCollection {
  const CraftCollection({
    required this.id,
    required this.name,
    required this.crafts,
    this.surfaces = const [],
    required this.camera,
  });

  final String id;
  final String name;
  final List<CraftSpot> crafts;
  final List<CollectionSurface> surfaces;
  final CollectionCamera camera;

  /// Ground the crafts and surfaces span, seen from above.
  Rect get groundBounds {
    final points = [
      for (final spot in crafts) spot.at,
      for (final surface in surfaces)
        for (final ring in surface.rings)
          for (final point in ring) Offset(point.x, point.y),
    ];
    if (points.isEmpty) return Rect.zero;
    var rect = Rect.fromLTRB(
      points.first.dx,
      points.first.dy,
      points.first.dx,
      points.first.dy,
    );
    for (final point in points.skip(1)) {
      rect = rect.expandToInclude(Rect.fromLTWH(point.dx, point.dy, 0, 0));
    }
    return rect;
  }

  /// `geometry` lists generators: `polygon` is one surface as given, and
  /// `room` builds [roomSurfaces].
  static CraftCollection fromJson(Map<String, dynamic> json) {
    final surfaces = <CollectionSurface>[];
    for (final raw in (json['geometry'] as List?) ?? const []) {
      final entry = raw as Map<String, dynamic>;
      switch (entry['type']) {
        case 'polygon':
          surfaces.add(CollectionSurface.fromJson(entry));
        case 'room':
          surfaces.addAll(
            roomSurfaces(
              center: entry['center'] == null
                  ? Offset.zero
                  : _offset(entry['center']),
              width: (entry['width'] as num).toDouble(),
              depth: (entry['depth'] as num).toDouble(),
              height: (entry['height'] as num).toDouble(),
              openings: [
                for (final opening in (entry['openings'] as List?) ?? const [])
                  WallOpening.fromJson(opening as Map<String, dynamic>),
              ],
            ),
          );
        default:
          throw FormatException('Unknown geometry type ${entry['type']}');
      }
    }
    return CraftCollection(
      id: json['id'] as String,
      name: json['name'] as String? ?? json['id'] as String,
      crafts: [
        for (final spot in (json['crafts'] as List?) ?? const [])
          CraftSpot.fromJson(spot as Map<String, dynamic>),
      ],
      surfaces: surfaces,
      camera: CollectionCamera.fromJson(json['camera']),
    );
  }
}

enum RoomWall { north, east, south, west }

enum OpeningKind { door, window }

/// A punch-out in one room wall. [center] runs along the wall from its
/// middle, and [sill] is the height of the opening's bottom edge. A door
/// stands on the floor.
class WallOpening {
  const WallOpening({
    required this.wall,
    required this.kind,
    this.center = 0,
    required this.width,
    this.sill = 0,
    required this.height,
  });

  final RoomWall wall;
  final OpeningKind kind;
  final double center;
  final double width;
  final double sill;
  final double height;

  double get bottom => kind == OpeningKind.door ? 0 : sill;

  static WallOpening fromJson(Map<String, dynamic> json) => WallOpening(
    wall: RoomWall.values.byName(json['wall'] as String),
    kind: OpeningKind.values.byName(json['kind'] as String? ?? 'window'),
    center: (json['center'] as num?)?.toDouble() ?? 0,
    width: (json['width'] as num).toDouble(),
    sill: (json['sill'] as num?)?.toDouble() ?? 0,
    height: (json['height'] as num).toDouble(),
  );
}

/// A box room standing on the ground around [center]: a plain floor and
/// four occluding walls facing in, with [openings] punched through them.
/// North is +y and east is +x.
List<CollectionSurface> roomSurfaces({
  Offset center = Offset.zero,
  required double width,
  required double depth,
  required double height,
  List<WallOpening> openings = const [],
}) {
  final left = center.dx - width / 2;
  final right = center.dx + width / 2;
  final bottom = center.dy - depth / 2;
  final top = center.dy + depth / 2;
  final floor = CollectionSurface(
    category: SurfaceCategory.plain,
    rings: [
      [
        Vector3(left, bottom, 0),
        Vector3(right, bottom, 0),
        Vector3(right, top, 0),
        Vector3(left, top, 0),
      ],
    ],
    normal: Vector3(0, 0, 1),
  );
  final walls = {
    RoomWall.south: (
      Vector3(left, bottom, 0),
      Vector3(1, 0, 0),
      width,
      Vector3(0, 1, 0),
    ),
    RoomWall.east: (
      Vector3(right, bottom, 0),
      Vector3(0, 1, 0),
      depth,
      Vector3(-1, 0, 0),
    ),
    RoomWall.north: (
      Vector3(right, top, 0),
      Vector3(-1, 0, 0),
      width,
      Vector3(0, -1, 0),
    ),
    RoomWall.west: (
      Vector3(left, top, 0),
      Vector3(0, -1, 0),
      depth,
      Vector3(1, 0, 0),
    ),
  };
  return [
    floor,
    for (final MapEntry(key: wall, value: (origin, along, length, inward))
        in walls.entries)
      () {
        final shape = punchedWall(length, height, [
          for (final opening in openings)
            if (opening.wall == wall) opening,
        ]);
        Vector3 lift(Offset point) =>
            origin + along * point.dx + Vector3(0, 0, point.dy);
        return CollectionSurface(
          category: SurfaceCategory.occludingGeo,
          rings: [
            [for (final point in shape.exterior.points) lift(point)],
            for (final hole in shape.holes)
              [for (final point in hole.points) lift(point)],
          ],
          normal: inward,
        );
      }(),
  ];
}

/// A [length] × [height] wall in its own plane, x along it and y up, with
/// [openings] punched out. A door is a notch in the outer ring, since it
/// meets the wall's bottom edge. A window inside the wall becomes a hole.
/// Openings that do not fit are left out.
Polygon2D punchedWall(
  double length,
  double height,
  List<WallOpening> openings,
) {
  const eps = 1e-9;
  final doors =
      [
          for (final opening in openings)
            if (opening.kind == OpeningKind.door) _span(length, opening),
        ].where((span) {
          return span.$1 > eps &&
              span.$2 < length - eps &&
              span.$3 < height - eps &&
              span.$3 > eps;
        }).toList()
        ..sort((a, b) => a.$1.compareTo(b.$1));
  final outer = <Offset>[const Offset(0, 0)];
  var reach = 0.0;
  for (final (start, end, top) in doors) {
    if (start < reach + eps) continue;
    outer.addAll([
      Offset(start, 0),
      Offset(start, top),
      Offset(end, top),
      Offset(end, 0),
    ]);
    reach = end;
  }
  outer.addAll([Offset(length, 0), Offset(length, height), Offset(0, height)]);

  var wall = Polygon2D.simple(outer);
  for (final opening in openings) {
    if (opening.kind != OpeningKind.window) continue;
    final (start, end, top) = _span(length, opening);
    final bottom = opening.bottom;
    if (start <= eps ||
        end >= length - eps ||
        bottom <= eps ||
        top >= height - eps) {
      continue;
    }
    final window = Polygon2D.simple([
      Offset(start, bottom),
      Offset(end, bottom),
      Offset(end, top),
      Offset(start, top),
    ]);
    final punched = polygonDifference(wall, window);
    if (punched.length == 1 &&
        punched.single.holes.length == wall.holes.length + 1) {
      wall = punched.single;
    }
  }
  return wall;
}

(double, double, double) _span(double length, WallOpening opening) {
  final middle = length / 2 + opening.center;
  return (
    middle - opening.width / 2,
    middle + opening.width / 2,
    opening.bottom + opening.height,
  );
}

/// The turn about the vertical and the move that stand [raw] on the ground
/// at [spot]: its footprint's middle over [CraftSpot.at], its lowest point
/// on z = 0.
Matrix4 craftPlacement(FoldedModel raw, CraftSpot spot) {
  final box = raw.bounds;
  return Matrix4.translation(Vector3(spot.at.dx, spot.at.dy, -box.min.z))
    ..rotateZ(spot.turnDegrees * math.pi / 180)
    ..translateByVector3(
      Vector3(-(box.min.x + box.max.x) / 2, -(box.min.y + box.max.y) / 2, 0),
    );
}

/// [raw] standing at [spot]. See [craftPlacement].
FoldedModel placedCraft(FoldedModel raw, CraftSpot spot) =>
    raw.transformed(craftPlacement(raw, spot));

/// How opaque [surface] draws for an eye at [eye]. Plain surfaces always
/// draw in full. Occluding geo fades as the eye moves behind it.
double surfaceOpacity(CollectionSurface surface, Vector3 eye) {
  if (surface.category != SurfaceCategory.occludingGeo) return 1;
  final toEye = eye - _ringCenter(surface.rings.first);
  if (toEye.length2 < 1e-12) return 1;
  final behind = -surface.normal.dot(toEye.normalized());
  final t = ((behind + 0.05) / 0.2).clamp(0.0, 1.0);
  final s = t * t * (3 - 2 * t);
  return 1 + (kOccludedOpacity - 1) * s;
}

/// Occluding geo seen from behind draws this faintly.
const double kOccludedOpacity = 0.08;

/// True when [surface] faces the eye and every craft corner is on the eye's
/// side of its plane, so it can never cover a craft and draws first.
bool isBackground(
  CollectionSurface surface,
  Vector3 eye,
  Iterable<FoldedModel> crafts,
) {
  if (surface.side(eye) <= 0) return false;
  for (final craft in crafts) {
    final box = craft.bounds;
    for (var i = 0; i < 8; i++) {
      final corner = Vector3(
        i & 1 == 0 ? box.min.x : box.max.x,
        i & 2 == 0 ? box.min.y : box.max.y,
        i & 4 == 0 ? box.min.z : box.max.z,
      );
      if (surface.side(corner) < -1e-6) return false;
    }
  }
  return true;
}

/// Ray distance to [surface], or null when the ray misses it or passes
/// through one of its holes.
double? raySurface(
  CollectionSurface surface,
  Vector3 origin,
  Vector3 direction,
) {
  final denom = direction.dot(surface.normal);
  if (denom.abs() < 1e-9) return null;
  final t = (surface.origin - origin).dot(surface.normal) / denom;
  if (t <= 0) return null;
  final hit = origin + direction * t;
  final ring = surface.rings.first;
  var u = ring[1] - ring[0];
  if (u.length2 < 1e-12) return null;
  u.normalize();
  final v = surface.normal.cross(u);
  Offset flat(Vector3 point) {
    final away = point - ring[0];
    return Offset(away.dot(u), away.dot(v));
  }

  final polygon = Polygon2D(Ring2D([for (final point in ring) flat(point)]), [
    for (final hole in surface.rings.skip(1))
      Ring2D([for (final point in hole) flat(point)]),
  ]);
  return pointInPolygon(flat(hit), polygon) == PointLocation.outside ? null : t;
}

/// The craft face nearest along the ray, unless a surface drawn more than
/// half opaque is nearer.
({int craft, int face})? pickCraft(
  List<FoldedModel> crafts,
  List<CollectionSurface> surfaces,
  Vector3 origin,
  Vector3 direction,
) {
  ({int craft, int face, double distance})? best;
  for (var c = 0; c < crafts.length; c++) {
    final hit = pickFace(crafts[c], origin, direction);
    if (hit == null) continue;
    if (best == null || hit.distance < best.distance) {
      best = (craft: c, face: hit.face, distance: hit.distance);
    }
  }
  if (best == null) return null;
  for (final surface in surfaces) {
    if (surfaceOpacity(surface, origin) <= 0.5) continue;
    final distance = raySurface(surface, origin, direction);
    if (distance != null && distance < best.distance - 1e-6) return null;
  }
  return (craft: best.craft, face: best.face);
}

Vector3 _ringCenter(List<Vector3> ring) {
  final sum = Vector3.zero();
  for (final point in ring) {
    sum.add(point);
  }
  return ring.isEmpty ? sum : sum / ring.length.toDouble();
}

/// A view's look-at point and eye direction carried rigidly by [by].
({Vector3 target, Vector3 direction}) carryView(
  Matrix4 by,
  Vector3 target,
  Vector3 direction,
) => (
  target: by.transformed3(target),
  direction: by.getRotation().transformed(direction).normalized(),
);

Vector3 _newell(List<Vector3> ring) {
  final normal = Vector3.zero();
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    normal.x += (a.y - b.y) * (a.z + b.z);
    normal.y += (a.z - b.z) * (a.x + b.x);
    normal.z += (a.x - b.x) * (a.y + b.y);
  }
  return normal.length2 < 1e-18 ? Vector3(0, 0, 1) : normal;
}

Vector3 _vector(Object? raw) {
  final values = [for (final value in raw as List) (value as num).toDouble()];
  return Vector3(
    values[0],
    values.length > 1 ? values[1] : 0,
    values.length > 2 ? values[2] : 0,
  );
}

Offset _offset(Object? raw) {
  final values = [for (final value in raw as List) (value as num).toDouble()];
  return Offset(values[0], values.length > 1 ? values[1] : 0);
}
