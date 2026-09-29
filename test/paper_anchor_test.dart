import 'package:flatmates/geometry/geometry_2d.dart';
import 'package:flatmates/geometry/geometry_algorithms.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a rectangle anchor is its center', () {
    final rect = Polygon2D.simple(const [
      Offset(0, 0),
      Offset(10, 0),
      Offset(10, 10),
      Offset(0, 10),
    ]);
    final anchor = paperAnchor(rect);
    expect(anchor, isNotNull);
    expect(anchor!.dx, closeTo(5, 1e-6));
    expect(anchor.dy, closeTo(5, 1e-6));
  });

  test('a c-shape anchor stays on the paper when the centroid does not', () {
    final cShape = Polygon2D.simple(const [
      Offset(0, 0),
      Offset(8, 0),
      Offset(8, 1),
      Offset(1, 1),
      Offset(1, 5),
      Offset(8, 5),
      Offset(8, 6),
      Offset(0, 6),
    ]);
    final mass = centroid(cShape);
    expect(mass, isNotNull);
    expect(isPointStrictlyInside(mass!, cShape), isFalse);

    final anchor = paperAnchor(cShape);
    expect(anchor, isNotNull);
    expect(isPointStrictlyInside(anchor!, cShape), isTrue);
  });

  test('a holed rectangle anchor is not in the hole', () {
    final frame = Polygon2D(
      const Ring2D([
        Offset(0, 0),
        Offset(10, 0),
        Offset(10, 10),
        Offset(0, 10),
      ]),
      const [
        Ring2D([
          Offset(4, 4),
          Offset(6, 4),
          Offset(6, 6),
          Offset(4, 6),
        ]),
      ],
    );
    final anchor = paperAnchor(frame);
    expect(anchor, isNotNull);
    expect(isPointStrictlyInside(anchor!, frame), isTrue);
    final hole = Polygon2D.simple(const [
      Offset(4, 4),
      Offset(6, 4),
      Offset(6, 6),
      Offset(4, 6),
    ]);
    expect(isPointStrictlyInside(anchor, hole), isFalse);
  });
}
