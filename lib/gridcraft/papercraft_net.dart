import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

import '../papercut/craft_v1.dart';
import '../papercut/fold_pose.dart';
import 'blueprint.dart';

/// A face of a papercraft design: its corners in world space, in order round
/// it. World z is up.
class NetFace {
  const NetFace(this.name, this.corners);

  final String name;
  final List<Vector3> corners;
}

/// Faces of a design that unfold together into one net piece. [root] lies
/// flat with its edge from corner `axis.$1` to corner `axis.$2` along +x.
/// Every other face hinges to its [parents] entry over the edge they share.
class NetIsland {
  const NetIsland({
    required this.faces,
    required this.root,
    required this.parents,
    this.axis = (0, 1),
  });

  final List<NetFace> faces;
  final String root;
  final Map<String, String> parents;
  final (int, int) axis;
}

/// A papercraft described in 3D, unfolded by [unfoldPapercraft] into a craft
/// and the level that prints its net.
class PapercraftDesign {
  const PapercraftDesign({
    required this.craftId,
    required this.layer,
    required this.puzzleId,
    required this.name,
    required this.islands,
  });

  final String craftId;
  final String layer;
  final String puzzleId;
  final String name;
  final List<NetIsland> islands;
}

/// One face laid out on the sheet.
class NetPiece {
  NetPiece({
    required this.name,
    required this.island,
    required this.ring,
    required this.corners,
    required this.pose,
    this.parent,
    this.hinge,
  });

  final String name;
  final int island;

  /// Counter-clockwise, on whole grid units.
  List<Offset> ring;

  /// World corners, parallel to [ring].
  List<Vector3> corners;

  /// Sheet to world.
  Matrix4 pose;

  /// Index of the face this one hinges to, null for an island root.
  final int? parent;

  /// The edge shared with [parent], on the sheet.
  (Offset, Offset)? hinge;
}

/// A design unfolded onto one sheet: every face on whole grid units, no two
/// overlapping, each island's outline one simple loop.
class PapercraftNet {
  PapercraftNet._(this.design, this.pieces);

  final PapercraftDesign design;
  final List<NetPiece> pieces;

  int get islandCount => design.islands.length;

  Rect get bounds => polygonBounds([for (final p in pieces) p.ring]);

  /// The printed sheet: [bounds] with a margin of 2.
  Rect get sheet => bounds.inflate(2);

  bool isHinge(int piece, Offset a, Offset b) {
    final hinge = pieces[piece].hinge;
    if (hinge != null && _sameEdge(hinge, a, b)) return true;
    for (final other in pieces) {
      if (other.parent != piece) continue;
      if (_sameEdge(other.hinge!, a, b)) return true;
    }
    return false;
  }

  /// The outline of [island] on the sheet, counter-clockwise.
  List<Offset> islandOutline(int island) {
    final next = <Offset, Offset>{};
    for (var i = 0; i < pieces.length; i++) {
      if (pieces[i].island != island) continue;
      final ring = pieces[i].ring;
      for (var e = 0; e < ring.length; e++) {
        final a = ring[e];
        final b = ring[(e + 1) % ring.length];
        if (isHinge(i, a, b)) continue;
        if (next.containsKey(a)) {
          throw StateError(
            '${design.craftId}: island $island touches itself at $a',
          );
        }
        next[a] = b;
      }
    }
    final start = next.keys.first;
    final loop = [start];
    var at = next[start]!;
    while (at != start) {
      loop.add(at);
      at = next[at]!;
    }
    if (loop.length != next.length) {
      throw StateError('${design.craftId}: island $island has a hole');
    }
    return loop;
  }

  /// Every face edge once, hinges included.
  List<(Offset, Offset)> get printedLines {
    final seen = <String>{};
    final lines = <(Offset, Offset)>[];
    for (final piece in pieces) {
      final ring = piece.ring;
      for (var e = 0; e < ring.length; e++) {
        final a = ring[e];
        final b = ring[(e + 1) % ring.length];
        final key = _edgeKey(a, b);
        if (seen.add(key)) lines.add((a, b));
      }
    }
    return lines;
  }

  /// The level: one ring per face, hinges penciled, the net printed once on
  /// the sheet.
  GridBlueprint level() {
    final sheet = this.sheet;
    return GridBlueprint(
      id: design.puzzleId,
      name: design.name,
      steps: [
        GridStep(
          id: design.puzzleId,
          label: design.name,
          polygons: [for (final p in pieces) p.ring],
          edgeStyles: [
            for (var i = 0; i < pieces.length; i++)
              [
                for (var e = 0; e < pieces[i].ring.length; e++)
                  isHinge(
                        i,
                        pieces[i].ring[e],
                        pieces[i].ring[(e + 1) % pieces[i].ring.length],
                      )
                      ? EdgeStyle.penciled
                      : EdgeStyle.penned,
              ],
          ],
          craft: CraftLink(id: design.craftId, step: 1),
          pattern: CutPattern(
            period: Offset(sheet.width + 1, sheet.height + 1),
            segments: printedLines,
            sheet: sheet,
          ),
        ),
      ],
    );
  }

  /// Level file text, with each point and each ring's edge styles on one line.
  String levelJsonText() =>
      _compact(_jsonText(_whole(level().toJson())! as Map<String, dynamic>));

  /// Version-1 craft. Roots carry their pose; every other face turns about
  /// its hinge.
  Map<String, dynamic> craftJson() {
    final craftId = design.craftId;
    final pieceKey = '$craftId#0';
    final layer = '${design.layer}::1';
    final faces = <Map<String, dynamic>>[];
    for (var i = 0; i < pieces.length; i++) {
      final piece = pieces[i];
      final parent = piece.parent;
      final Map<String, dynamic> transform;
      if (parent == null) {
        transform = {
          'type': 'movement',
          'forward': _rowMajor(Matrix4.inverted(piece.pose)),
          'inverse': _rowMajor(piece.pose),
        };
      } else {
        final (a, b) = piece.hinge!;
        transform = {
          'type': 'rotation',
          'axis': [a.dx, a.dy, 0.0, b.dx, b.dy, 0.0],
          'angleRadians':
              '${_hingeAngle(pieces[parent].pose, piece.pose, a, b)}',
        };
      }
      faces.add({
        'flatmates.surfaceId': '$i',
        'flatmates.groupId': craftId,
        'flatmates.pieceKey': pieceKey,
        'flatmates.islandId': '${piece.island}',
        'flatmates.craftingStep': '1',
        'flatmates.layer': layer,
        if (parent != null) 'flatmates.foldParentSurfaceId': '$parent',
        'flatmates.transformType': transform['type'],
        'flatLoops': [
          [
            for (final point in [...piece.ring, piece.ring.first])
              [point.dx, point.dy, 0.0],
          ],
        ],
        'transform': transform,
        'id': _faceId(piece.island, i),
      });
    }

    final edges = <Map<String, dynamic>>[];
    for (var i = 0; i < pieces.length; i++) {
      final piece = pieces[i];
      final ring = piece.ring;
      for (var e = 0; e < ring.length; e++) {
        final a = ring[e];
        final b = ring[(e + 1) % ring.length];
        final folds = piece.hinge != null && _sameEdge(piece.hinge!, a, b);
        if (!folds && isHinge(i, a, b)) continue;
        final other = folds ? piece.parent! : null;
        edges.add({
          'flatmates.groupId': craftId,
          'flatmates.pieceKey': pieceKey,
          'flatmates.islandId': '${piece.island}',
          'flatmates.role': folds ? 'fold' : 'cut',
          'flatmates.surfaceIdA': '${other ?? i}',
          if (folds) 'flatmates.surfaceIdB': '$i',
          'flatmates.craftingStep': '1',
          'flatmates.layer': layer,
          'curve': [
            [a.dx, a.dy, 0.0],
            [b.dx, b.dy, 0.0],
          ],
          'faceA': _faceId(piece.island, other ?? i),
          if (folds) 'faceB': _faceId(piece.island, i),
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

  String craftJsonText() => _jsonText(craftJson());

  /// Folded faces as OBJ, one object per face.
  String craftObj(String generator) {
    final craft = CraftV1.fromJson(craftJson());
    final poses = applyFoldPose(craft, 1, 1);
    final out = StringBuffer()
      ..writeln('# Generated by $generator')
      ..writeln('# @craft: ${design.craftId}');
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
}

/// Unfolds [design] onto whole grid units and packs its islands onto one
/// sheet, two units apart. Throws when a face lands off the grid, bends,
/// turns concave, overlaps another, or folds back to anywhere but its place.
///
/// The sheet's +z folds toward each island's middle, as in the cube craft:
/// the paper's rings then run the same way round as the model's faces.
PapercraftNet unfoldPapercraft(PapercraftDesign design) {
  final islands = <List<NetPiece>>[];
  for (var k = 0; k < design.islands.length; k++) {
    islands.add(_unfoldIsland(design, k));
  }

  final shifts = _pack([
    for (final island in islands)
      polygonBounds([for (final p in island) p.ring]),
  ]);
  final pieces = <NetPiece>[];
  final offset = <int>[];
  for (var k = 0; k < islands.length; k++) {
    offset.add(pieces.length);
    final shift = shifts[k];
    final back = Matrix4.translation(Vector3(-shift.dx, -shift.dy, 0));
    for (final piece in islands[k]) {
      final hinge = piece.hinge;
      pieces.add(
        NetPiece(
          name: piece.name,
          island: k,
          ring: [for (final p in piece.ring) p + shift],
          corners: piece.corners,
          pose: piece.pose * back,
          parent: piece.parent == null ? null : piece.parent! + offset[k],
          hinge: hinge == null ? null : (hinge.$1 + shift, hinge.$2 + shift),
        ),
      );
    }
  }

  final net = PapercraftNet._(design, pieces);
  _check(net);
  return net;
}

List<NetPiece> _unfoldIsland(PapercraftDesign design, int k) {
  final island = design.islands[k];
  final byName = {for (final face in island.faces) face.name: face};
  final children = <String, List<String>>{};
  for (final face in island.faces) {
    final parent = island.parents[face.name];
    if (parent == null) continue;
    if (!byName.containsKey(parent)) {
      throw StateError('${design.craftId}: ${face.name} hinges to $parent');
    }
    (children[parent] ??= []).add(face.name);
  }

  final root = byName[island.root]!;
  final origin = root.corners[island.axis.$1];
  final u = (root.corners[island.axis.$2] - origin).normalized();
  var n = _normal(root.corners);
  final middle = _middle([for (final face in island.faces) ...face.corners]);
  if (n.dot(middle - _middle(root.corners)) < 0) n = -n;
  final v = n.cross(u);
  final rootRing = [
    for (final p in root.corners)
      _onGrid(
        design,
        root.name,
        Offset((p - origin).dot(u), (p - origin).dot(v)),
      ),
  ];
  for (final p in root.corners) {
    if ((p - origin).dot(n).abs() > 1e-6) {
      throw StateError('${design.craftId}: ${root.name} bends');
    }
  }

  final pieces = <NetPiece>[
    NetPiece(
      name: root.name,
      island: k,
      ring: rootRing,
      corners: root.corners,
      pose: _frame(origin, u, v),
    ),
  ];
  final index = {root.name: 0};
  final queue = [root.name];
  while (queue.isNotEmpty) {
    final current = queue.removeAt(0);
    final parentIndex = index[current]!;
    final parent = pieces[parentIndex];
    for (final name in children[current] ?? const <String>[]) {
      final face = byName[name]!;
      final shared = _sharedEdge(face.corners, parent.corners);
      if (shared == null) {
        throw StateError(
          '${design.craftId}: $name shares no edge with $current',
        );
      }
      final (i, j, l) = shared;
      final corner = face.corners;
      final A = corner[i];
      final B = corner[(i + 1) % corner.length];
      final a = parent.ring[j];
      final b = parent.ring[l];

      final ew = (B - A).normalized();
      final middle = _middle(corner) - A;
      final mw = (middle - ew * middle.dot(ew)).normalized();
      final nw = ew.cross(mw);
      final ef = Vector3(b.dx - a.dx, b.dy - a.dy, 0).normalized();
      var mf = Vector3(-ef.y, ef.x, 0);
      final parentMiddle = _middle2(parent.ring) - a;
      if (parentMiddle.dx * mf.x + parentMiddle.dy * mf.y > 0) mf = -mf;

      final ring = <Offset>[];
      for (final p in corner) {
        final d = p - A;
        if (d.dot(nw).abs() > 1e-6) {
          throw StateError('${design.craftId}: $name bends');
        }
        final along = d.dot(ew);
        final out = d.dot(mw);
        ring.add(
          _onGrid(
            design,
            name,
            Offset(
              a.dx + ef.x * along + mf.x * out,
              a.dy + ef.y * along + mf.y * out,
            ),
          ),
        );
      }
      final a3 = Vector3(a.dx, a.dy, 0);
      final pose = _frame(A, ew, mw) * Matrix4.inverted(_frame(a3, ef, mf));
      index[name] = pieces.length;
      pieces.add(
        NetPiece(
          name: name,
          island: k,
          ring: ring,
          corners: corner,
          pose: pose,
          parent: parentIndex,
          hinge: (a, b),
        ),
      );
      queue.add(name);
    }
  }
  if (pieces.length != island.faces.length) {
    throw StateError('${design.craftId}: island $k leaves faces unhinged');
  }

  for (final piece in pieces) {
    if (_signedArea(piece.ring) < 0) {
      piece.ring = piece.ring.reversed.toList();
      piece.corners = piece.corners.reversed.toList();
    }
  }
  return pieces;
}

/// Shelf packing, tallest first, rows about as wide as the islands are deep.
List<Offset> _pack(List<Rect> boxes) {
  const gap = 2.0;
  var area = 0.0;
  var widest = 0.0;
  for (final box in boxes) {
    area += (box.width + gap) * (box.height + gap);
    widest = math.max(widest, box.width);
  }
  final rowWidth = math.max(widest, (math.sqrt(area) * 1.3).ceilToDouble());
  final order = [for (var i = 0; i < boxes.length; i++) i]
    ..sort((a, b) => boxes[b].height.compareTo(boxes[a].height));
  final shifts = List<Offset>.filled(boxes.length, Offset.zero);
  var x = 0.0;
  var y = 0.0;
  var rowHeight = 0.0;
  for (final i in order) {
    final box = boxes[i];
    if (x > 0 && x + box.width > rowWidth) {
      x = 0;
      y += rowHeight + gap;
      rowHeight = 0;
    }
    shifts[i] = Offset(x - box.left, y - box.top);
    x += box.width + gap;
    rowHeight = math.max(rowHeight, box.height);
  }
  return shifts;
}

void _check(PapercraftNet net) {
  final id = net.design.craftId;
  final pieces = net.pieces;
  for (final piece in pieces) {
    final ring = piece.ring;
    for (var e = 0; e < ring.length; e++) {
      final a = ring[e];
      final b = ring[(e + 1) % ring.length];
      final c = ring[(e + 2) % ring.length];
      final turn = (b - a).dx * (c - b).dy - (b - a).dy * (c - b).dx;
      if (turn <= 1e-9) throw StateError('$id: ${piece.name} is not convex');
    }
  }
  for (var i = 0; i < pieces.length; i++) {
    for (var j = i + 1; j < pieces.length; j++) {
      if (_overlap(pieces[i].ring, pieces[j].ring)) {
        throw StateError(
          '$id: ${pieces[i].name} overlaps ${pieces[j].name} on the sheet',
        );
      }
    }
  }
  for (var k = 0; k < net.islandCount; k++) {
    net.islandOutline(k);
  }

  final craft = CraftV1.fromJson(net.craftJson());
  final poses = applyFoldPose(craft, 1, 1);
  for (var i = 0; i < pieces.length; i++) {
    final pose = poses[craft.faces[i].id]!;
    for (var c = 0; c < pieces[i].ring.length; c++) {
      final flat = pieces[i].ring[c];
      final folded = pose.transformed3(Vector3(flat.dx, flat.dy, 0));
      if ((folded - pieces[i].corners[c]).length > 1e-6) {
        throw StateError('$id: ${pieces[i].name} folds to $folded');
      }
    }
  }
}

/// Separating axes: true when the interiors of two convex rings meet.
bool _overlap(List<Offset> a, List<Offset> b) {
  for (final ring in [a, b]) {
    for (var e = 0; e < ring.length; e++) {
      final edge = ring[(e + 1) % ring.length] - ring[e];
      final axis = Offset(-edge.dy, edge.dx);
      double lo(List<Offset> r) =>
          r.map((p) => p.dx * axis.dx + p.dy * axis.dy).reduce(math.min);
      double hi(List<Offset> r) =>
          r.map((p) => p.dx * axis.dx + p.dy * axis.dy).reduce(math.max);
      if (hi(a) <= lo(b) + 1e-9 || hi(b) <= lo(a) + 1e-9) return false;
    }
  }
  return true;
}

/// Craft angle for the hinge a→b that carries [parent]'s pose to [child]'s.
/// [applyFoldPose] turns flat to folded by −angle.
double _hingeAngle(Matrix4 parent, Matrix4 child, Offset a, Offset b) {
  final turn = Matrix4.inverted(parent) * child;
  final d = Vector3(b.dx - a.dx, b.dy - a.dy, 0).normalized();
  final q = Vector3(-d.y, d.x, 0);
  final a3 = Vector3(a.dx, a.dy, 0);
  final turned = turn.transformed3(a3 + q) - turn.transformed3(a3);
  return -math.atan2(d.dot(q.cross(turned)), q.dot(turned));
}

/// Indices (i in [ring], j and l in [other]) of an edge ring[i]→ring[i+1]
/// that [other] also has, as other[j], other[l].
(int, int, int)? _sharedEdge(List<Vector3> ring, List<Vector3> other) {
  int? find(Vector3 p) {
    for (var j = 0; j < other.length; j++) {
      if ((other[j] - p).length < 1e-9) return j;
    }
    return null;
  }

  for (var i = 0; i < ring.length; i++) {
    final j = find(ring[i]);
    final l = find(ring[(i + 1) % ring.length]);
    if (j == null || l == null) continue;
    if ((j - l).abs() == 1 || (j - l).abs() == other.length - 1) {
      return (i, j, l);
    }
  }
  return null;
}

Offset _onGrid(PapercraftDesign design, String face, Offset p) {
  final x = p.dx.roundToDouble();
  final y = p.dy.roundToDouble();
  if ((p.dx - x).abs() > 1e-6 || (p.dy - y).abs() > 1e-6) {
    throw StateError('${design.craftId}: $face unfolds to $p, off the grid');
  }
  return Offset(x == 0 ? 0.0 : x, y == 0 ? 0.0 : y);
}

/// Columns x, y, x × y, translated to [origin].
Matrix4 _frame(Vector3 origin, Vector3 x, Vector3 y) {
  final z = x.cross(y);
  return Matrix4.columns(
    Vector4(x.x, x.y, x.z, 0),
    Vector4(y.x, y.y, y.z, 0),
    Vector4(z.x, z.y, z.z, 0),
    Vector4(origin.x, origin.y, origin.z, 1),
  );
}

/// Newell's normal.
Vector3 _normal(List<Vector3> corners) {
  final n = Vector3.zero();
  for (var i = 0; i < corners.length; i++) {
    final a = corners[i];
    final b = corners[(i + 1) % corners.length];
    n.x += (a.y - b.y) * (a.z + b.z);
    n.y += (a.z - b.z) * (a.x + b.x);
    n.z += (a.x - b.x) * (a.y + b.y);
  }
  return n.normalized();
}

Vector3 _middle(List<Vector3> corners) {
  final sum = Vector3.zero();
  for (final p in corners) {
    sum.add(p);
  }
  return sum / corners.length.toDouble();
}

Offset _middle2(List<Offset> ring) {
  var sum = Offset.zero;
  for (final p in ring) {
    sum += p;
  }
  return sum / ring.length.toDouble();
}

double _signedArea(List<Offset> ring) {
  var area = 0.0;
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    area += a.dx * b.dy - b.dx * a.dy;
  }
  return area / 2;
}

bool _sameEdge((Offset, Offset) edge, Offset a, Offset b) =>
    (edge.$1 == a && edge.$2 == b) || (edge.$1 == b && edge.$2 == a);

String _edgeKey(Offset a, Offset b) {
  final first = (a.dx, a.dy).toString();
  final second = (b.dx, b.dy).toString();
  return first.compareTo(second) < 0 ? '$first $second' : '$second $first';
}

String _faceId(int island, int ring) => 's1_p0_i${island}_f$ring';

String _jsonText(Map<String, dynamic> json) =>
    '${const JsonEncoder.withIndent('  ').convert(json)}\n';

/// Whole doubles as ints, so level files read like hand-written ones.
Object? _whole(Object? value) {
  if (value is double && value == value.roundToDouble()) return value.toInt();
  if (value is List) return [for (final item in value) _whole(item)];
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries) '${entry.key}': _whole(entry.value),
    };
  }
  return value;
}

String _compact(String text) => text
    .replaceAllMapped(
      RegExp(r'\[\s+(-?[\d.]+),\s+(-?[\d.]+)\s+\]'),
      (match) => '[${match[1]}, ${match[2]}]',
    )
    .replaceAllMapped(
      RegExp(r'\[\s+("\w+"(?:,\s+"\w+")*)\s+\]'),
      (match) => '[${match[1]!.split(RegExp(r',\s+')).join(', ')}]',
    );

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

String _num(double value) {
  final rounded = (value * 1e6).round() / 1e6;
  return (rounded == 0 ? 0.0 : rounded).toString();
}
