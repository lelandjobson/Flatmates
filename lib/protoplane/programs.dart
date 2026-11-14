import 'dart:ui';
import 'geometry.dart';
import 'models.dart';
import 'region_workspace.dart';

enum ProgramKind {
  cut('Cut', ['scissors', 'remove']),
  place('Place', ['fill', 'paper', 'floor', 'wall']),
  erase('Erase', ['eraser', 'graphite']),
  volume('Volume', ['depth', 'extrude']),
  house('House', ['home', 'building']),
  pool('Pool', ['water', 'basin']),
  rug('Rug', ['carpet']),
  table('Table', ['desk', 'furniture']),
  pictureFrame('Picture Frame', ['art', 'frame']),
  combine('Combine', ['merge', 'join']);

  const ProgramKind(this.label, this.aliases);
  final String label;
  final List<String> aliases;
  bool matches(String query) {
    final words = query.toLowerCase().trim().split(RegExp(r'\s+'));
    final text = '$label ${aliases.join(' ')}'.toLowerCase();
    return words.every(text.contains);
  }
}

enum ProgramIssue {
  tooSmall('Region is too small'),
  orientation('Wrong surface orientation'),
  material('This material does not support the program'),
  collision('Another object occupies this space'),
  support('Supporting material or attachments would be lost'),
  paper('Not enough paper'),
  outline('The outline cannot hold this program'),
  empty('No applicable material'),
  stale('The target has changed');

  const ProgramIssue(this.label);
  final String label;
}

/// Persistent grouping, with ordinary editable objects as its components.
class ProgramAssembly {
  ProgramAssembly({
    required this.id,
    required this.program,
    required this.frame,
    required this.footprint,
    required this.components,
    required this.supports,
    this.parameters = const {},
    this.water,
  });
  final String id;
  final ProgramKind program;
  final CraftPlane frame;
  final Region footprint;
  final Map<String, String> components;
  final List<String> supports;
  final Map<String, double> parameters;
  final Region? water;
  Map<String, dynamic> toJson() => {
    'id': id,
    'program': program.name,
    'frame': frame.toJson(),
    'footprint': footprint.toJson(),
    'components': Map<String, String>.of(components),
    'supports': List<String>.of(supports),
    'parameters': parameters,
    if (water != null) 'water': water!.toJson(),
  };
  factory ProgramAssembly.fromJson(Map<String, dynamic> j) => ProgramAssembly(
    id: j['id'],
    program: ProgramKind.values.byName(j['program']),
    frame: CraftPlane.fromJson(j['frame']),
    footprint: Region.fromJson(j['footprint']),
    components: Map<String, String>.from(j['components']),
    supports: List<String>.from(j['supports']),
    parameters: {
      for (final e in (j['parameters'] as Map).entries)
        e.key: (e.value as num).toDouble(),
    },
    water: j['water'] == null ? null : Region.fromJson(j['water']),
  );
}

class ProgramEvaluation {
  ProgramEvaluation({
    required this.program,
    required this.target,
    required this.surface,
    required this.drop,
    required this.revision,
    this.regionRevision = 0,
    this.depth = .1,
    this.issue,
    this.quote = 0,
    this.world,
    this.objects = const [],
    this.frames = const {},
    this.water,
    this.waterDepth = -.05,
  });
  final ProgramKind program;
  final LightRegion target;
  final RegionSurface surface;
  final Offset drop;
  final int revision;
  final int regionRevision;
  final double depth;
  final ProgramIssue? issue;
  final int quote;
  final Map<String, dynamic>? world;
  final List<CraftObject> objects;
  final Map<String, CraftPlane> frames;
  final Region? water;
  final double waterDepth;
  bool get valid => issue == null && world != null;
}

/// Negative polygon buffer built from boundary strips and miter joins.
/// Follows Boost's distance_symmetric deflation and join_miter (limit 5).
/// Boolean subtraction resolves concave joins and reports collapsed interiors.
List<Region> insetProgramRegion(Region source, double distance) {
  var remaining = [source];
  for (final raw in source.rings) {
    var ring = List<Offset>.of(raw);
    final area = edges(ring).fold<double>(0, (s, e) => s + cross(e.$1, e.$2));
    final outer = identical(raw, source.outer);
    if ((area > 0) != outer) ring = ring.reversed.toList();
    final normals = [
      for (final e in edges(ring))
        Offset(-(e.$2 - e.$1).dy, (e.$2 - e.$1).dx) / (e.$2 - e.$1).distance,
    ];
    final bands = <Region>[];
    for (var i = 0; i < ring.length; i++) {
      final a = ring[i],
          b = ring[(i + 1) % ring.length],
          n = normals[i] * distance;
      bands.add(Region([a, b, b + n, a + n]));
      final previous = (i + ring.length - 1) % ring.length;
      final p = a + normals[previous] * distance, q = a + n;
      final u = a - ring[previous], v = b - a, denominator = cross(u, v);
      if (denominator.abs() <= geometryEpsilon) continue;
      var hit = p + u * (cross(q - p, v) / denominator);
      if ((hit - a).distance > 5 * distance) {
        hit = a + (hit - a) / (hit - a).distance * (5 * distance);
      }
      final join = Region([a, p, hit, q]);
      if (join.valid) bands.add(join);
    }
    for (final band in bands) {
      remaining = remaining.expand((r) => r.subtract(band)).toList();
    }
  }
  return remaining.where((r) => r.valid).toList();
}
