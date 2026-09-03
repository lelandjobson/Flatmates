import 'package:flatmates/gameplay/outlines/outline_edges.dart';
import 'package:flatmates/gameplay/outlines/outline_union.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  test('union two adjacent roof quads into one face', () {
    final up = Vector3(0, 1, 0);
    final a = OutlineQuad(
      points: [
        Vector3(0, 6, 0),
        Vector3(8, 6, 0),
        Vector3(8, 6, 8),
        Vector3(0, 6, 8),
      ],
      normal: up,
    );
    final b = OutlineQuad(
      points: [
        Vector3(8, 6, 0),
        Vector3(16, 6, 0),
        Vector3(16, 6, 8),
        Vector3(8, 6, 8),
      ],
      normal: up,
    );
    final merged = unionCoplanarQuads([a, b]);
    expect(merged, hasLength(1));
    expect(collectOuterEdges(merged), hasLength(4));
  });

  test('union drops a T-junction roof seam', () {
    final up = Vector3(0, 1, 0);
    final large = OutlineQuad(
      points: [
        Vector3(0, 6, 0),
        Vector3(16, 6, 0),
        Vector3(16, 6, 8),
        Vector3(0, 6, 8),
      ],
      normal: up,
    );
    final inset = OutlineQuad(
      points: [
        Vector3(0, 6, 8),
        Vector3(7, 6, 8),
        Vector3(7, 6, 16),
        Vector3(0, 6, 16),
      ],
      normal: up,
    );
    final merged = unionCoplanarQuads([large, inset]);
    expect(merged, hasLength(1));
    final edges = collectOuterEdges(merged);
    var peri = 0.0;
    for (final e in edges) {
      peri += (e.a - e.b).length;
    }
    expect(peri, closeTo(64, 1e-4));
  });
}
