import 'dart:math' as math;
import 'dart:ui';
import '../geometry/polygon_union.dart'
    show PlanarGraph, splitAllAtIntersections, polygonSignedArea;
import 'geometry.dart';
import 'models.dart';
import 'pencil.dart';

enum FocusToolCard { drawing, stickerbook }

enum DrawingImplement {
  pencil('Pencil', .25, 0),
  pen('Pen', .25, 0),
  marker('Marker', 1, 0),
  crookedPencil('Crooked pencil', .25, math.pi / 4),
  eraser('Eraser', .25, 0);

  const DrawingImplement(this.label, this.spacing, this.angle);
  final String label;
  final double spacing, angle;
  Offset toSurface(Offset p) => Offset(
    p.dx * math.cos(angle) - p.dy * math.sin(angle),
    p.dx * math.sin(angle) + p.dy * math.cos(angle),
  );
  Offset toLattice(Offset p) => Offset(
    p.dx * math.cos(angle) + p.dy * math.sin(angle),
    -p.dx * math.sin(angle) + p.dy * math.cos(angle),
  );
}

String drawingPointKey(Offset p) =>
    '${(p.dx * 1e6).round()},${(p.dy * 1e6).round()}';
String drawingEdgeKey(PencilSegment s) {
  final a = drawingPointKey(s.a), b = drawingPointKey(s.b);
  return a.compareTo(b) < 0 ? '$a:$b' : '$b:$a';
}

class DrawingFace {
  DrawingFace(this.graph, this.region);
  final DrawingGraph graph;
  final Region region;
  late final String id =
      (region.rings
              .map(
                (ring) =>
                    (ring.map(drawingPointKey).toList()..sort()).join(';'),
              )
              .toList()
            ..sort())
          .join('|');
}

/// Topological edges, independent of pointer strokes and intermediate grid pips.
class DrawingGraph {
  DrawingGraph(
    this.surfaceId,
    this.implement,
    this.frame, [
    Iterable<PencilSegment> segments = const [],
  ]) {
    replace(segments);
  }
  final String surfaceId;
  final DrawingImplement implement;
  final CraftPlane frame;
  int revision = 0;
  List<PencilSegment> edges = [];
  List<DrawingFace> faces = [];
  String get key => '$surfaceId/${implement.name}';

  void replace(Iterable<PencilSegment> segments) {
    final unique = <String, PencilSegment>{};
    for (final (a, b) in splitAllAtIntersections(
      segments
          .where((s) => s.length > geometryEpsilon)
          .map((s) => (s.a, s.b))
          .toList(),
    )) {
      final s = PencilSegment(a, b);
      if (s.length > geometryEpsilon) unique[drawingEdgeKey(s)] = s;
    }
    var list = unique.values.toList();
    var changed = true;
    while (changed) {
      changed = false;
      final incident = <String, List<int>>{};
      for (var i = 0; i < list.length; i++) {
        (incident[drawingPointKey(list[i].a)] ??= []).add(i);
        (incident[drawingPointKey(list[i].b)] ??= []).add(i);
      }
      for (final entry in incident.entries) {
        if (entry.value.length != 2) continue;
        final i = entry.value[0], j = entry.value[1];
        final a = list[i], b = list[j];
        final joint = drawingPointKey(a.a) == entry.key ? a.a : a.b;
        final from = drawingPointKey(a.a) == entry.key ? a.b : a.a;
        final to = drawingPointKey(b.a) == entry.key ? b.b : b.a;
        if (!near(from, to) && onSegment(joint, from, to)) {
          list = [
            for (var n = 0; n < list.length; n++)
              if (n != i && n != j) list[n],
            PencilSegment(from, to),
          ];
          changed = true;
          break;
        }
      }
    }
    edges = list
      ..sort((a, b) => drawingEdgeKey(a).compareTo(drawingEdgeKey(b)));
    final rings = PlanarGraph(edges.map((s) => (s.a, s.b)).toList())
        .findFaces()
        .where((r) => polygonSignedArea(r) < -geometryEpsilon)
        .map((r) => Region(simplifyRing(r)))
        .where((r) => r.valid)
        .toList();
    faces = [];
    for (final ring in rings) {
      var parts = [ring];
      for (final inner in rings) {
        if (inner.area >= ring.area - geometryEpsilon ||
            !ring.containsRegion(inner)) {
          continue;
        }
        parts = parts.expand((r) => r.subtract(inner)).toList();
      }
      faces.addAll(
        parts.where((r) => r.valid).map((r) => DrawingFace(this, r)),
      );
    }
    revision++;
  }

  Set<String> intersections(Offset a, Offset b) => {
    if (!near(a, b))
      for (final edge in edges)
        if (segmentsTouch(a, b, edge.a, edge.b)) drawingEdgeKey(edge),
  };
  Map<String, dynamic> toJson() => {
    'surface': surfaceId,
    'implement': implement.name,
    'frame': frame.toJson(),
    'edges': [
      for (final e in edges) [e.a.dx, e.a.dy, e.b.dx, e.b.dy],
    ],
  };
  factory DrawingGraph.fromJson(Map<String, dynamic> j) {
    final implement = DrawingImplement.values.byName(j['implement']);
    if (implement == DrawingImplement.eraser) {
      throw const FormatException('Invalid drawing implement');
    }
    final segments = <PencilSegment>[];
    for (final raw in j['edges'] as List) {
      final n = (raw as List).map((v) => (v as num).toDouble()).toList();
      if (n.length != 4 || n.any((v) => !v.isFinite)) {
        throw const FormatException('Invalid drawing edge');
      }
      final s = PencilSegment(Offset(n[0], n[1]), Offset(n[2], n[3]));
      final d = implement.toLattice(s.b - s.a);
      if (d.dx.abs() > 1e-6 && d.dy.abs() > 1e-6) {
        throw const FormatException('Nonorthogonal drawing');
      }
      segments.add(s);
    }
    return DrawingGraph(
      j['surface'],
      implement,
      CraftPlane.fromJson(j['frame']),
      segments,
    );
  }
}

class DrawingSurface {
  DrawingSurface(this.id, this.frame, this.sources, {List<Region>? regions})
    : regions = regions ?? [frame.region];
  final String id;
  final CraftPlane frame;
  final List<String> sources;
  final List<Region> regions;
  List<PencilSegment> clip(Iterable<PencilSegment> segments) =>
      newPencilCoverage([
        for (final r in regions) ...clipPencil(segments, r),
      ], const []);
  CraftGrid grid(DrawingImplement implement) {
    final coordinates = frame.region.outer.map(implement.toLattice).toList();
    final left = coordinates.map((p) => p.dx).reduce(math.min),
        right = coordinates.map((p) => p.dx).reduce(math.max);
    final top = coordinates.map((p) => p.dy).reduce(math.min),
        bottom = coordinates.map((p) => p.dy).reduce(math.max);
    final step = implement.spacing, nodes = <Offset>[], ids = <String, int>{};
    for (
      var y = (top / step).ceil();
      y <= (bottom / step + 1e-6).floor();
      y++
    ) {
      for (
        var x = (left / step).ceil();
        x <= (right / step + 1e-6).floor();
        x++
      ) {
        final p = implement.toSurface(Offset(x * step, y * step));
        if (!regions.any((r) => r.contains(p))) continue;
        ids['$x,$y'] = nodes.length;
        nodes.add(p);
      }
    }
    final connections = <GridEdge>[];
    for (final entry in ids.entries) {
      final xy = entry.key.split(',').map(int.parse).toList();
      for (final key in ['${xy[0] + 1},${xy[1]}', '${xy[0]},${xy[1] + 1}']) {
        final next = ids[key];
        if (next == null) continue;
        final edge = PencilSegment(nodes[entry.value], nodes[next]);
        final coverage = clipPencil([
          edge,
        ], frame.region).fold<double>(0, (s, e) => s + e.length);
        if (coverage >= edge.length - 1e-6) {
          connections.add(GridEdge(entry.value, next));
        }
      }
    }
    return CraftGrid(
      id: '$id/${implement.name}',
      name: implement.label,
      nodes: nodes,
      edges: connections,
      recipes: const [],
    );
  }
}
