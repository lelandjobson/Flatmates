import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/gestures/stroke_reversal.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/pencil.dart';
import 'linear_placement_test.dart' show world, draw;

void main() {
  test('reverse straight tails but never shortcut a bend', () {
    expect(
      reversedTail(const [
        Offset(0, 0),
        Offset(.5, 0),
        Offset(1, 0),
      ], Offset.zero),
      0,
    );
    expect(
      reversedTail(const [
        Offset(0, 0),
        Offset(1, 0),
        Offset(1, 1),
      ], Offset.zero),
      isNull,
    );
  });
  for (final tool in [CraftTool.place, CraftTool.scissors]) {
    test('$tool backtracks through dots and reopens loops', () {
      final c = world();
      addTearDown(c.dispose);
      c.selectTool(tool);
      draw(c, const [
        Offset(0, 0),
        Offset(1, 0),
        Offset(1, 1),
        Offset(0, 1),
        Offset(0, 0),
      ]);
      expect(c.closed, isTrue);
      expect(c.appendNode(c.grid!.nodes.indexOf(const Offset(0, 1))), isTrue);
      expect(c.closed, isFalse);
      expect(c.appendNode(c.grid!.nodes.indexOf(const Offset(1, 1))), isTrue);
      expect(c.appendNode(c.grid!.nodes.indexOf(const Offset(1, 0))), isTrue);
      expect(c.appendNode(c.grid!.nodes.indexOf(Offset.zero)), isTrue);
      expect(c.trace, [Offset.zero]);
    });
  }
  test(
    'pencil retrace only changes preview and charges surviving coverage',
    () {
      final c = world();
      addTearDown(c.dispose);
      c.balances[PaperMaterial.graphite] = 128;
      c.commitMarks([const PencilSegment(Offset(0, 0), Offset(1, 0))]);
      c.selectTool(CraftTool.pencil);
      c.beginPencil(const Offset(0, .25));
      c.extendPencil(const Offset(1, .25));
      c.extendPencil(const Offset(.25, .25));
      expect(c.pencilPreview, [const Offset(0, .25), const Offset(.25, .25)]);
      expect(c.commitPencil(), isTrue);
      expect(c.balances[PaperMaterial.graphite], 123);
      expect(
        c.marksOn(c.activePlane!).fold<double>(0, (n, s) => n + s.length),
        closeTo(1.25, 1e-7),
      );
    },
  );
  for (final subdivisions in [1, 4, 12]) {
    test('shake is rate independent at $subdivisions samples per leg', () {
      final shake = StrokeShake();
      var hit = false, ms = 0;
      var last = Offset.zero;
      shake.update(last, Duration.zero);
      for (final x in [16.0, -16.0, 16.0, -16.0]) {
        final target = Offset(x, 0), from = last;
        for (var i = 1; i <= subdivisions; i++) {
          ms += 80 ~/ subdivisions;
          hit =
              shake.update(
                Offset.lerp(from, target, i / subdivisions)!,
                Duration(milliseconds: ms),
              ) ||
              hit;
        }
        last = target;
      }
      expect(hit, isTrue);
    });
  }
  test('jitter and a sustained reverse drag are not shakes', () {
    final shake = StrokeShake();
    for (var i = 0; i < 50; i++) {
      expect(
        shake.update(
          Offset(i.isEven ? 3 : -3, 0),
          Duration(milliseconds: i * 10),
        ),
        isFalse,
      );
    }
    shake.reset();
    for (var i = 0; i < 30; i++) {
      expect(
        shake.update(
          Offset(i < 15 ? i * 3 : (30 - i) * 3, 0),
          Duration(milliseconds: i * 10),
        ),
        isFalse,
      );
    }
  });
}
