import 'package:flatmates/protoplane/controller.dart';
import 'construction_fixture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'protoplane_test.dart' as fixtures;
import 'package:flatmates/protoplane/plane_navigation.dart';

void main() {
  test(
    'floor swipe skips wall folds while wall topology and undo retain exits',
    () {
      final model = constructionWorld();
      addTearDown(model.dispose);
      final floor = fixtures.floor(model);
      final surface = 'surface-${floor.id}', wall = 'wall-${floor.id}-0';
      var graph = model.navigationGraph;
      expect(graph.neighbors[surface]!.any((e) => e.planeId == wall), isTrue);
      // The harvested source is empty; navigation retains its construction portals.
      expect(graph.neighbors[surface]!.any((e) => e.planeId == wall), isTrue);
      model.enter(wall);
      fixtures.draw(model, [0, 1, 2, 5, 8, 7, 6, 3, 0]);
      expect(model.create(), isTrue, reason: model.error);
      final wallSurface = 'surface-${model.objects.values.last.id}';
      graph = model.navigationGraph;
      expect(
        graph.neighbors[surface]!.any((e) => e.planeId == wallSurface),
        isTrue,
      );
      expect(
        graph.neighbors[wallSurface]!.any(
          (e) => e.planeId == 'upper-${floor.id}',
        ),
        isTrue,
      );
      expect(
        graph.neighbors[wall]!.any((e) => e.planeId == 'upper-${floor.id}'),
        isTrue,
      );
      model.undo();
      expect(model.navigationGraph.neighbors.containsKey(wallSurface), isFalse);
      expect(
        model.navigationGraph.neighbors[surface]!.any((e) => e.planeId == wall),
        isTrue,
      );
    },
  );
  test('ground has edge neighbors only and graph survives draft changes', () {
    final model = ProtoplaneController();
    addTearDown(model.dispose);
    final graph = model.navigationGraph;
    expect(
      graph.neighbors['ground-starter-paperWhite-0-0']!
          .map((e) => e.planeId)
          .toSet(),
      {
        'ground-starter-paperWhite--1-0',
        'ground-starter-paperWhite-1-0',
        'ground-starter-paperWhite-0--1',
        'ground-starter-paperWhite-0-1',
      },
    );

    model.enter('ground-starter-paperWhite-0-0');
    model.appendNode(0);
    expect(identical(graph, model.navigationGraph), isTrue);
    expect(
      graph.inDirection(
        'ground-starter-paperWhite-0-0',
        const Offset(100, 0),
        const Offset(.5, .5),
        (p) => Offset(p.x, -p.z),
      ),
      'ground-starter-paperWhite-1-0',
    );
    model.clearWorld();
    expect(identical(graph, model.navigationGraph), isFalse);
    model.undo();
    expect(
      model.navigationGraph.neighbors['ground-starter-paperWhite-0-0']!.length,
      4,
    );
  });

  test('swipe needs both fingers, threshold, and only fires once', () {
    final swipe = PlaneSwipe()..start([Offset.zero, const Offset(0, 100)]);
    expect(
      swipe.update([const Offset(99, 0), const Offset(99, 100)], 100),
      isNull,
    );
    expect(
      swipe.update([const Offset(120, 0), const Offset(120, 100)], 100),
      const Offset(120, 0),
    );
    expect(
      swipe.update([const Offset(250, 0), const Offset(250, 100)], 100),
      isNull,
    );
    swipe.start([Offset.zero, const Offset(0, 100)]);
    expect(
      swipe.update([const Offset(0, -150), const Offset(0, 250)], 100),
      isNull,
    );
    expect(
      swipe.update([
        Offset.zero,
        const Offset(0, 100),
        const Offset(10, 10),
      ], 100),
      isNull,
    );
    expect(swipe.consumed, isTrue);
  });
}
