import 'package:flatmates/rendering/scene/grid_motif.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('seam coverage is antialiased and empty in the cell center', () {
    const size = 32;
    expect(GridMotif.seamCoverage(size ~/ 2, size ~/ 2, size), 0);
    expect(GridMotif.seamCoverage(0, size ~/ 2, size), greaterThan(0.8));
    expect(GridMotif.seamCoverage(size - 1, size ~/ 2, size), greaterThan(0.8));
    final fringe = GridMotif.seamCoverage(1, size ~/ 2, size);
    expect(fringe, greaterThan(0));
    expect(fringe, lessThan(1));
  });

  test('corner coverage is a dot at intersections, not a line', () {
    const size = 32;
    expect(GridMotif.cornerCoverage(size ~/ 2, size ~/ 2, size), 0);
    expect(GridMotif.cornerCoverage(0, 0, size), greaterThan(0.8));
    expect(GridMotif.cornerCoverage(size - 1, size - 1, size), greaterThan(0.8));
    expect(GridMotif.cornerCoverage(0, size ~/ 2, size), 0);
    final fringe = GridMotif.cornerCoverage(2, 0, size);
    expect(fringe, greaterThan(0));
    expect(fringe, lessThan(1));
  });

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

  testWidgets('subtile dots motif is a small tileable cell', (tester) async {
    final motif = GridMotif.subtileDots(worldSize: 1);
    addTearDown(motif.dispose);
    expect(motif.id, 'subtile_dots');
    expect(motif.worldSize, 1);
    expect(motif.image.width, 32);
    expect(motif.image.height, 32);
    expect(motif.shader, isNotNull);
  });

  testWidgets('appendRepeating stamps one subtile quad across a tile', (
    tester,
  ) async {
    final motif = GridMotif.subtileDots(worldSize: 1);
    addTearDown(motif.dispose);
    final positions = <Offset>[];
    final uvs = <Offset>[];
    motif.appendRepeating(
      minX: 0,
      maxX: 8,
      minZ: 0,
      maxZ: 8,
      y: 0,
      project: (x, y, z) => Offset(x, z),
      positions: positions,
      texCoords: uvs,
    );
    // 8 x 8 cells, two tris each.
    expect(positions, hasLength(8 * 8 * 6));
    expect(uvs, hasLength(positions.length));
    expect(uvs, contains(const Offset(0, 0)));
    expect(uvs, contains(const Offset(8 * 32, 8 * 32)));
  });
}
