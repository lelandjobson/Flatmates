import 'dart:ui';
import 'geometry.dart';
import 'models.dart';

enum StickerKind { house, hill, bed, door, window }

class StickerDefinition {
  const StickerDefinition(
    this.kind,
    this.name,
    this.aliases,
    this.maximumWidth,
    this.maximumHeight,
  );
  final StickerKind kind;
  final String name;
  final List<String> aliases;
  final double maximumWidth, maximumHeight;
  bool matches(String query) => query
      .toLowerCase()
      .trim()
      .split(RegExp(r'\s+'))
      .every(
        (word) => '$name ${aliases.join(' ')}'.toLowerCase().contains(word),
      );
}

const stickerDefinitions = [
  StickerDefinition(StickerKind.house, 'House', ['home', 'building'], 8, 8),
  StickerDefinition(StickerKind.hill, 'Hill', ['steps', 'landform'], 4, 4),
  StickerDefinition(StickerKind.bed, 'Bed', ['sleep', 'furniture'], 1, 2),
  StickerDefinition(
    StickerKind.door,
    'Door',
    ['doorway', 'entrance'],
    .25,
    .75,
  ),
  StickerDefinition(
    StickerKind.window,
    'Window',
    ['opening', 'light'],
    .75,
    .75,
  ),
];

sealed class StickerOperation {
  const StickerOperation();
}

class CreateStickerPanel extends StickerOperation {
  const CreateStickerPanel(this.component, this.object, this.frame);
  final String component;
  final CraftObject object;
  final CraftPlane frame;
}

class CutStickerOpening extends StickerOperation {
  const CutStickerOpening(this.objectId, this.region);
  final String objectId;
  final Region region;
}

class StickerProgram {
  StickerProgram(this.kind, this.operations);
  final StickerKind kind;
  final List<StickerOperation> operations;
}

class ProgramAssembly {
  ProgramAssembly(
    this.id,
    this.kind,
    this.frame,
    this.footprint,
    this.components,
    this.supports,
    this.sourceGraph,
    this.sourceFace,
    this.parameters,
  );
  final String id, sourceGraph, sourceFace;
  final StickerKind kind;
  final CraftPlane frame;
  final Region footprint;
  final Map<String, String> components;
  final List<String> supports;
  final Map<String, double> parameters;
  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'frame': frame.toJson(),
    'footprint': footprint.toJson(),
    'components': components,
    'supports': supports,
    'graph': sourceGraph,
    'face': sourceFace,
    'parameters': parameters,
  };
  factory ProgramAssembly.fromJson(Map<String, dynamic> j) => ProgramAssembly(
    j['id'],
    StickerKind.values.byName(j['kind']),
    CraftPlane.fromJson(j['frame']),
    Region.fromJson(j['footprint']),
    Map<String, String>.from(j['components']),
    List<String>.from(j['supports']),
    j['graph'],
    j['face'],
    {
      for (final e in (j['parameters'] as Map).entries)
        e.key: (e.value as num).toDouble(),
    },
  );
}

class ProgramEvaluation {
  ProgramEvaluation(
    this.kind,
    this.surfaceId,
    this.graphKey,
    this.faceId,
    this.drop, {
    this.targetPlaneId,
    this.issue,
    this.world,
    this.program,
    this.objects = const [],
    this.frames = const {},
    this.region,
    this.quote = 0,
  });
  final StickerKind kind;
  final String surfaceId, graphKey, faceId;
  final Offset drop;
  final String? targetPlaneId;
  final String? issue;
  final Map<String, dynamic>? world;
  final StickerProgram? program;
  final List<CraftObject> objects;
  final Map<String, CraftPlane> frames;
  final Region? region;
  final int quote;
  bool get valid => issue == null && world != null;
}

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
