import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

import '../papercut/craft_v1.dart';
import '../papercut/fold_pose.dart';
import 'blueprint.dart';
import 'cube_blueprint.dart';
import 'folded_model.dart' show stepIslands;

const String kCubeCraftId = 'craft_Cube';
const String kCubeCraftDirectory = 'assets/craft_viewer/$kCubeCraftId';

const String kBoxStackCraftId = 'craft_BoxStack';
const String kBoxStackCraftDirectory = 'assets/craft_viewer/$kBoxStackCraftId';
const String kBoxStackLevelPath = 'levels/boxes/$kBoxStackId.json';

/// How far the top box of the stack turns about the vertical, from above.
const double kBoxStackTwist = 15 * math.pi / 180;

/// Version-1 craft for [cubeBlueprint]. Every square is one face of a single
/// island. The hub is the root. Each other face turns a quarter about the
/// penciled edge it shares with its parent, toward +z.
Map<String, dynamic> cubeCraftJson() =>
    _netCraftJson(kCubeCraftId, 'Cube', cubeBlueprint().steps.single);

String cubeCraftJsonText() => _jsonText(cubeCraftJson());

/// Folded faces of [cubeCraftJson] as OBJ, one object per face.
String cubeCraftObj() => _craftObj(kCubeCraftId, cubeCraftJson());

/// [boxStackBlueprint] linked to its craft.
GridBlueprint boxStackLevel() =>
    boxStackBlueprint(craft: const CraftLink(id: kBoxStackCraftId, step: 1));

/// Level file text, with each point and each ring's edge styles on one line.
String boxStackLevelJsonText() => _jsonText(boxStackLevel().toJson())
    .replaceAllMapped(
      RegExp(r'\[\s+(-?[\d.]+),\s+(-?[\d.]+)\s+\]'),
      (match) => '[${match[1]}, ${match[2]}]',
    )
    .replaceAllMapped(
      RegExp(r'\[\s+("\w+"(?:,\s+"\w+")*)\s+\]'),
      (match) => '[${match[1]!.split(RegExp(r',\s+')).join(', ')}]',
    );

/// Version-1 craft for [boxStackBlueprint]: one cube island per cross, folded
/// as in [cubeCraftJson]. Each cube then stands on its side with its hub
/// facing −y, centered over the sheet. The second sits on the first's lid,
/// turned by [kBoxStackTwist].
Map<String, dynamic> boxStackCraftJson() {
  final step = boxStackBlueprint().steps.single;
  final center = polygonBounds(step.polygons).center;
  return _netCraftJson(
    kBoxStackCraftId,
    'BoxStack',
    step,
    rootPose: (island, hub) {
      final middle = _center(step.polygons[hub]);
      const half = kCubeFace / 2;
      return Matrix4.translation(
          Vector3(center.dx, center.dy, half + island * kCubeFace),
        )
        ..rotateZ(island * kBoxStackTwist)
        ..multiply(_standOnSide)
        ..translateByVector3(Vector3(-middle.dx, -middle.dy, -half));
    },
  );
}

String boxStackCraftJsonText() => _jsonText(boxStackCraftJson());

String boxStackCraftObj() => _craftObj(kBoxStackCraftId, boxStackCraftJson());

/// Carries x to −x, y to z, and z to y: a cube folded up from a hub on the
/// sheet turns onto its side, the hub facing −y and reading upright.
final Matrix4 _standOnSide = Matrix4(
  -1,
  0,
  0,
  0, //
  0,
  0,
  1,
  0, //
  0,
  1,
  0,
  0, //
  0,
  0,
  0,
  1,
);

/// One island per set of rings joined by penciled edges. Each island's hub,
/// the ring with every edge penciled, is its root. [rootPose] places a root;
/// null leaves it where it lies.
Map<String, dynamic> _netCraftJson(
  String craftId,
  String layerName,
  GridStep step, {
  Matrix4? Function(int island, int hub)? rootPose,
}) {
  final rings = step.polygons;
  final islands = [for (final set in stepIslands(step)) set.toList()..sort()]
    ..sort((a, b) => a.first.compareTo(b.first));
  final islandOf = <int, int>{};
  final parents = List<int?>.filled(rings.length, null);
  final roots = <int, Matrix4?>{};
  for (var k = 0; k < islands.length; k++) {
    final hub = _hubIndex(step, islands[k]);
    for (final ring in islands[k]) {
      islandOf[ring] = k;
    }
    final tree = _foldTree(step, islands[k], hub);
    for (final entry in tree.entries) {
      parents[entry.key] = entry.value;
    }
    roots[hub] = rootPose?.call(k, hub);
  }
  final pieceKey = '$craftId#0';
  final layer = '$layerName::1';

  Map<String, dynamic> common(int ring) => {
    'flatmates.surfaceId': '$ring',
    'flatmates.groupId': craftId,
    'flatmates.pieceKey': pieceKey,
    'flatmates.islandId': '${islandOf[ring]}',
    'flatmates.craftingStep': '1',
    'flatmates.layer': layer,
  };

  final faces = <Map<String, dynamic>>[];
  for (var i = 0; i < rings.length; i++) {
    if (!islandOf.containsKey(i)) continue;
    final ring = rings[i];
    final parent = parents[i];
    final Map<String, dynamic> transform;
    if (parent == null) {
      final pose = roots[i] ?? Matrix4.identity();
      transform = {
        'type': 'movement',
        'forward': _rowMajor(Matrix4.inverted(pose)),
        'inverse': _rowMajor(pose),
      };
    } else {
      final (a, b) = _sharedEdge(ring, rings[parent])!;
      transform = {
        'type': 'rotation',
        'axis': [a.dx, a.dy, 0.0, b.dx, b.dy, 0.0],
        'angleRadians': '${_liftAngle(a, b, _center(ring))}',
      };
    }
    faces.add({
      ...common(i),
      if (parent != null) 'flatmates.foldParentSurfaceId': '$parent',
      'flatmates.transformType': transform['type'],
      'flatLoops': [
        [
          for (final point in [...ring, ring.first]) [point.dx, point.dy, 0.0],
        ],
      ],
      'transform': transform,
      'id': _faceId(islandOf[i]!, i),
    });
  }

  final edges = <Map<String, dynamic>>[];
  for (var i = 0; i < rings.length; i++) {
    final island = islandOf[i];
    if (island == null) continue;
    final ring = rings[i];
    final styles = step.edgeStyleOf(i);
    for (var e = 0; e < ring.length; e++) {
      final a = ring[e];
      final b = ring[(e + 1) % ring.length];
      int? other;
      if (styles[e] == EdgeStyle.penciled) {
        for (final j in islands[island]) {
          if (j != i && _hasEdge(rings[j], a, b)) other = j;
        }
        if (other == null || other < i) continue;
      }
      edges.add({
        'flatmates.groupId': craftId,
        'flatmates.pieceKey': pieceKey,
        'flatmates.islandId': '$island',
        'flatmates.role': other == null ? 'cut' : 'fold',
        'flatmates.surfaceIdA': '$i',
        if (other != null) 'flatmates.surfaceIdB': '$other',
        'flatmates.craftingStep': '1',
        'flatmates.layer': layer,
        'curve': [
          [a.dx, a.dy, 0.0],
          [b.dx, b.dy, 0.0],
        ],
        'faceA': _faceId(island, i),
        if (other != null) 'faceB': _faceId(island, other),
        'pieceIndex': 0,
      });
    }
  }

  return {
    'version': 1,
    'craft': craftId,
    'foldedModel': 'folded.obj',
    'steps': [
      {'craftingStep': 1, 'model': 'folded.obj'},
    ],
    'faces': faces,
    'edges': edges,
  };
}

String _jsonText(Map<String, dynamic> json) =>
    '${const JsonEncoder.withIndent('  ').convert(json)}\n';

String _craftObj(String craftId, Map<String, dynamic> json) {
  final craft = CraftV1.fromJson(json);
  final poses = applyFoldPose(craft, 1, 1);
  final out = StringBuffer()
    ..writeln('# Generated by tool/generate_cube_craft.dart')
    ..writeln('# @craft: $craftId');
  var next = 1;
  for (final face in craft.faces) {
    final pose = poses[face.id] ?? Matrix4.identity();
    final loop = face.flatLoops.first;
    final corners = loop.sublist(0, loop.length - 1);
    out.writeln('o ${face.id}');
    for (final corner in corners) {
      final point = pose.transformed3(corner);
      out.writeln('v ${_num(point.x)} ${_num(point.y)} ${_num(point.z)}');
    }
    out.writeln(
      'f ${[for (var k = 0; k < corners.length; k++) next + k].join(' ')}',
    );
    next += corners.length;
  }
  return out.toString();
}

/// Rhino order: row by row.
List<double> _rowMajor(Matrix4 matrix) => [
  for (var r = 0; r < 4; r++)
    for (var c = 0; c < 4; c++) _clean(matrix.entry(r, c)),
];

double _clean(double value) {
  final whole = value.roundToDouble();
  if ((value - whole).abs() < 1e-12) return whole == 0 ? 0.0 : whole;
  return value;
}

Offset _center(List<Offset> ring) {
  var sum = Offset.zero;
  for (final point in ring) {
    sum += point;
  }
  return sum / ring.length.toDouble();
}

String _faceId(int island, int ring) => 's1_p0_i${island}_f$ring';

int _hubIndex(GridStep step, List<int> island) {
  for (final i in island) {
    if (step.edgeStyleOf(i).every((style) => style == EdgeStyle.penciled)) {
      return i;
    }
  }
  return island.first;
}

/// Breadth-first parents over shared edges within [island], rooted at [hub].
Map<int, int> _foldTree(GridStep step, List<int> island, int hub) {
  final rings = step.polygons;
  final parents = <int, int>{};
  final seen = {hub};
  final queue = [hub];
  while (queue.isNotEmpty) {
    final current = queue.removeAt(0);
    for (final j in island) {
      if (seen.contains(j)) continue;
      if (_sharedEdge(rings[j], rings[current]) == null) continue;
      parents[j] = current;
      seen.add(j);
      queue.add(j);
    }
  }
  return parents;
}

(Offset, Offset)? _sharedEdge(List<Offset> ring, List<Offset> other) {
  for (var e = 0; e < ring.length; e++) {
    final a = ring[e];
    final b = ring[(e + 1) % ring.length];
    if (_hasEdge(other, a, b)) return (a, b);
  }
  return null;
}

bool _hasEdge(List<Offset> ring, Offset a, Offset b) {
  for (var e = 0; e < ring.length; e++) {
    final p = ring[e];
    final q = ring[(e + 1) % ring.length];
    if ((p == a && q == b) || (p == b && q == a)) return true;
  }
  return false;
}

/// Craft angle for a quarter fold about a→b that lifts [center] toward +z.
/// [applyFoldPose] turns flat to folded by −angle.
double _liftAngle(Offset a, Offset b, Offset center) {
  final along = b - a;
  final out = center - a;
  final lift = along.dx * out.dy - along.dy * out.dx;
  return lift > 0 ? -math.pi / 2 : math.pi / 2;
}

String _num(double value) {
  final rounded = (value * 1e6).round() / 1e6;
  return (rounded == 0 ? 0.0 : rounded).toString();
}
