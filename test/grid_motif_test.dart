import 'package:flatmates/rendering/scene/grid_motif.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('subtile motif is a small tileable cell', (tester) async {
    final motif = GridMotif.subtileLines(worldSize: 1);
    addTearDown(motif.dispose);
    expect(motif.id, 'subtile_lines');
    expect(motif.worldSize, 1);
    expect(motif.image.width, 32);
    expect(motif.image.height, 32);
    expect(motif.shader, isNotNull);
  });

  test('projectCells copies one quad per world cell with wrapping UVs', () {
    final positions = <Offset>[];
    final uvs = <Offset>[];
    GridMotif.projectCells(
      minX: 0,
      maxX: 2,
      minZ: 0,
      maxZ: 1,
      y: 0,
      worldSize: 1,
      imageWidth: 32,
      imageHeight: 32,
      project: (x, y, z) => Offset(x * 10, z * 10),
      positions: positions,
      texCoords: uvs,
    );
    // 2 x 1 cells, two tris each → 12 verts.
    expect(positions, hasLength(12));
    expect(uvs, hasLength(12));
    expect(uvs, contains(const Offset(0, 0)));
    expect(uvs, contains(const Offset(64, 32)));
  });
}
