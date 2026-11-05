import 'package:flatmates/protoplane/harvest.dart';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:flatmates/protoplane/geometry.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/plane_navigation.dart';
import 'package:flatmates/protoplane/spatial_index.dart';

import 'construction_fixture.dart';
import 'protoplane_test.dart' as fixtures;

CraftPlane face(
  String id,
  double x,
  double y, {
  Region? region,
  double height = 0,
}) => CraftPlane(
  id: id,
  origin: Vector3(x, height, -y),
  u: Vector3(1, 0, 0),
  v: Vector3(0, 0, -1),
  region: region ?? rectangle(1, 1),
  grids: [],
);

Set<String> adjacent(PlaneNavigationGraph graph, String id) => {
  for (final e in graph.neighbors[id] ?? <PlaneNeighbor>[]) e.planeId,
};

void main() {
  test(
    'partial floor retains exposed source and connects across its perimeter',
    () {
      final model = constructionWorld();
      addTearDown(model.dispose);
      final floor = fixtures.floor(model);
      // A partial replacement exercises the same derivation as a committed cut,
      // without relying on gesture coordinates or recipe recognition.
      final part = rectangle(.5, .5, origin: const Offset(.25, .25));
      model.objects[floor.id] = floor.copyWith(region: part);
      final surface = model.planes['surface-${floor.id}']!;
      model.planes[surface.id] = CraftPlane(
        id: surface.id,
        origin: surface.origin,
        u: surface.u,
        v: surface.v,
        region: part,
        grids: surface.grids,
        owner: floor.id,
      );
      model.landscape = PaperLandscape();
      model.landscape.deplete(floor.planeId, part);
      final source = model.planes[floor.planeId]!;
      final neighbors = <String, CraftPlane>{
        for (final entry in {
          'ground-starter-paperWhite--1-0': const Offset(-1, 0),
          'ground-starter-paperWhite-1-0': const Offset(1, 0),
          'ground-starter-paperWhite-0--1': const Offset(0, -1),
          'ground-starter-paperWhite-0-1': const Offset(0, 1),
        }.entries)
          entry.key: face(
            entry.key,
            entry.value.dx,
            entry.value.dy,
            height: source.origin.y,
          ),
      };
      final graph = PlaneNavigationGraph(
        {
          source.id: source,
          surface.id: model.planes[surface.id]!,
          ...neighbors,
        },
        {floor.id: model.objects[floor.id]!},
      );
      expect(
        adjacent(graph, floor.planeId),
        containsAll([
          'ground-starter-paperWhite--1-0',
          'ground-starter-paperWhite-1-0',
          'ground-starter-paperWhite-0--1',
          'ground-starter-paperWhite-0-1',
          surface.id,
        ]),
      );
      expect(adjacent(graph, surface.id), contains(floor.planeId));
      expect(
        graph.neighbors[surface.id]!.where((e) => e.planeId == floor.planeId),
        hasLength(4),
      );
    },
  );

  test(
    'positive edge overlap includes holes, reversed edges and separate portals',
    () {
      final ring = face(
        'ring',
        0,
        0,
        region: Region(rectangle(3, 3).outer, [
          rectangle(1, 1, origin: const Offset(1, 1)).outer.reversed.toList(),
        ]),
      );
      final inset = face('inset', 1, 1);
      final partial = face('partial', 3, .25, region: rectangle(1, .5));
      final corner = face('corner', 3, 3);
      final separated = face('separated', 3, 0, height: .01);
      final duplicate = face('duplicate', 0, 0, region: ring.region);
      final graph = PlaneNavigationGraph({
        for (final p in [ring, inset, partial, corner, separated, duplicate])
          p.id: p,
      }, {});
      expect(adjacent(graph, 'ring'), {'inset', 'partial'});
      expect(
        graph.neighbors['ring']!.where((e) => e.planeId == 'inset'),
        hasLength(4),
      );
      final exit = graph.neighbors['ring']!.singleWhere(
        (e) => e.planeId == 'partial',
      );
      expect(exit.length, closeTo(.5, 1e-6));
      expect(exit.kind, PlaneAdjacency.coplanar);
      for (final e in graph.neighbors['ring']!) {
        expect(adjacent(graph, e.planeId), contains('ring'));
      }
    },
  );

  test('portal ray chooses a partial exit whose midpoint is off the swipe', () {
    final a = face('a', 0, 0, region: rectangle(1, 10));
    final b = face('b', 1, 0, region: rectangle(1, 6));
    final graph = PlaneNavigationGraph({'a': a, 'b': b}, {});
    expect(
      graph.inDirection(
        'a',
        const Offset(100, 0),
        const Offset(.5, 5),
        (p) => Offset(p.x, -p.z),
      ),
      'b',
    );
    expect(
      graph.inDirection(
        'a',
        const Offset(-100, 0),
        const Offset(.5, 5),
        (p) => Offset(p.x, -p.z),
      ),
      isNull,
    );
  });

  test('rotated and tilted faces use world edges, not axis or tile IDs', () {
    final rotation = Quaternion.axisAngle(Vector3(1, 2, 3).normalized(), .73);
    CraftPlane rotated(CraftPlane p) => CraftPlane(
      id: p.id,
      origin: rotation.rotated(p.origin),
      u: rotation.rotated(p.u),
      v: rotation.rotated(p.v),
      region: p.region,
      grids: [],
    );
    final a = rotated(face('a', -5, 7)), b = rotated(face('b', -4, 7));
    final graph = PlaneNavigationGraph({'a': a, 'b': b}, {});
    expect(adjacent(graph, 'a'), {'b'});
    expect(graph.neighbors['a']!.single.length, closeTo(1, 1e-6));
  });

  test('dependencies and rendered bounds retain structural height', () {
    final model = constructionWorld();
    addTearDown(model.dispose);
    final floor = fixtures.floor(model);
    model.enter('wall-${floor.id}-0');
    fixtures.draw(model, [0, 1, 2, 5, 8, 7, 6, 3, 0]);
    expect(model.create(), isTrue, reason: model.error);
    final wall = model.objects.values.last;
    final graph = model.navigationGraph;
    final upper = planeEntity('upper-${floor.id}');
    expect(
      graph.relations.dependents(objectEntity(floor.id)),
      containsAll([
        objectEntity(wall.id),
        planeEntity('surface-${wall.id}'),
        upper,
      ]),
    );
    expect(
      graph.relations.incoming(upper).map((r) => r.kind),
      containsAll([
        CraftRelationKind.derivedFrom,
        CraftRelationKind.supportedBy,
      ]),
    );
    final surface = model.planes['surface-${floor.id}']!;
    final center = surface.point(surface.region.bounds.center);
    expect(
      graph.spatial.query(
        MapAabb(center - Vector3.all(.0001), center + Vector3.all(.0001)),
      ),
      contains(planeEntity(surface.id)),
    );
    final ground = center.clone()..y = 0;
    expect(
      graph.spatial.query(
        MapAabb(ground - Vector3.all(.0001), ground + Vector3.all(.0001)),
      ),
      isNot(contains(planeEntity(surface.id))),
    );
    model.undo();
    expect(
      model.navigationGraph.relations.dependents(objectEntity(floor.id)),
      isNot(contains(upper)),
    );
    model.redo();
    expect(
      model.navigationGraph.relations.dependents(objectEntity(floor.id)),
      contains(upper),
    );
    model.load(model.toJson());
    expect(
      model.navigationGraph.relations.dependents(objectEntity(floor.id)),
      contains(upper),
    );
  });

  test(
    'BVH queries match exhaustive bounds on flat, long and sparse entries',
    () {
      final random = math.Random(17);
      final bounds = <int, MapAabb>{};
      for (var i = 0; i < 300; i++) {
        final start = Vector3(
          random.nextDouble() * 100 - 50,
          random.nextDouble() * 5,
          random.nextDouble() * 100 - 50,
        );
        bounds[i] = MapAabb(
          start,
          start + Vector3(i % 7 == 0 ? 80 : 1, i % 3 == 0 ? 0 : 1, 2),
        );
      }
      final index = CraftSpatialIndex(bounds);
      for (var i = 0; i < 50; i++) {
        final start = Vector3(
          random.nextDouble() * 100 - 50,
          0,
          random.nextDouble() * 100 - 50,
        );
        final query = MapAabb(start, start + Vector3.all(8));
        expect(index.query(query).toSet(), {
          for (final e in bounds.entries)
            if (e.value.intersects(query)) e.key,
        });
      }
    },
  );

  test('boundary candidate work grows with local contacts on a tile world', () {
    PlaneNavigationGraph build(int side) {
      final planes = <String, CraftPlane>{};
      for (var x = 0; x < side; x++) {
        for (var y = 0; y < side; y++) {
          final p = face('$x/$y', x.toDouble(), y.toDouble());
          planes[p.id] = p;
        }
      }
      final watch = Stopwatch()..start();
      final graph = PlaneNavigationGraph(planes, {});
      // Report measurements, but assert work counts rather than machine speed.
      // ignore: avoid_print
      print(
        '${side * side} planes: ${graph.boundaryComparisons} boundary tests, ${watch.elapsedMilliseconds} ms',
      );
      expect(adjacent(graph, '4/4'), {'3/4', '5/4', '4/3', '4/5'});
      expect(graph.boundaryComparisons, lessThan(side * side * 50));
      return graph;
    }

    final small = build(16), large = build(32);
    expect(
      large.boundaryComparisons,
      lessThan(small.boundaryComparisons * 4.5),
    );
  });

  test('pinch locks out navigation until a new touch or trackpad sequence', () {
    final swipe = PlaneSwipe()..start([Offset.zero, const Offset(0, 100)]);
    expect(
      swipe.update([const Offset(120, 0), const Offset(0, 100)], 80),
      isNull,
    );
    expect(swipe.zooming, isTrue);
    expect(
      swipe.update([const Offset(150, 0), const Offset(150, 100)], 80),
      isNull,
    );
    swipe.start([Offset.zero, const Offset(0, 100)]);
    expect(
      swipe.update([const Offset(90, 6), const Offset(100, 104)], 80),
      isNotNull,
    );
    swipe.startTrackpad();
    expect(swipe.updateTrackpad(const Offset(50, 0), .8, 0, 80), isNull);
    expect(swipe.updateTrackpad(const Offset(150, 0), 1, 0, 80), isNull);
    swipe.startTrackpad();
    expect(
      swipe.updateTrackpad(const Offset(90, 0), 1, 0, 80),
      const Offset(90, 0),
    );
    expect(swipe.updateTrackpad(const Offset(200, 0), 1, 0, 80), isNull);
  });
}
