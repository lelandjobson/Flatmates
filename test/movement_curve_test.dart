import 'dart:ui';

import 'package:flatmates/gameplay/flatmates/movement_curve.dart';
import 'package:flatmates/gameplay/flatmates/movement_profile.dart';
import 'package:flatmates/gameplay/paths/path_store.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const grid = VolumeGrid(tilesSide: 16, tileSize: 8);

  MovementProfile clean({
    double ratio = 1,
    double offset = 0,
    double jank = 0,
    double smoothness = 0,
    double bendSlowdown = 0.55,
    double hopHeight = 0,
  }) {
    return MovementProfile(
      id: 'test',
      name: 'Test',
      movementTileRatio: ratio,
      offset: offset,
      jank: jank,
      jankIntensity: 0.4,
      smoothness: smoothness,
      bendSlowdown: bendSlowdown,
      hopHeight: hopHeight,
    );
  }

  MovementCurve build(
    List<(int, int)> tiles,
    MovementProfile profile, {
    String seed = 'seed',
    PathStore? paths,
  }) {
    return buildMovementCurve(
      tiles: tiles,
      grid: grid,
      profile: profile,
      seed: seed,
      paths: paths,
    );
  }

  test('stride density follows movementTileRatio on a straight', () {
    const tiles = <(int, int)>[(0, 0), (1, 0), (2, 0), (3, 0)];
    expect(build(tiles, clean(ratio: 1)).knots.length, 4);
    expect(build(tiles, clean(ratio: 2)).knots.length, 3);
    expect(build(tiles, clean(ratio: 0.5)).knots.length, 7);
  });

  test('corners stay as knots even when the stride skips tiles', () {
    const tiles = <(int, int)>[(0, 0), (1, 0), (2, 0), (2, 1)];
    final curve = build(tiles, clean(ratio: 2));
    expect(curve.knots.any((k) => k.isCorner), isTrue);
    final corner = grid.tileCenter(2, 0);
    expect(
      curve.knots.any(
        (k) =>
            (k.median.dx - corner.x).abs() < 1e-6 &&
            (k.median.dy - corner.z).abs() < 1e-6,
      ),
      isTrue,
    );
  });

  test('offset 0 stays on the centerline and 1 sits on the right edge', () {
    const tiles = <(int, int)>[(0, 0), (1, 0)];
    final center = build(tiles, clean());
    final edge = build(tiles, clean(offset: 1));
    final start = grid.tileCenter(0, 0);
    final half = movementPathHalfWidth(grid);
    expect(center.knots.first.position.dy, closeTo(start.z, 1e-6));
    expect(edge.knots.first.position.dy, closeTo(start.z + half, 1e-6));
  });

  test('opposite headings take opposite sides of the path', () {
    final east = build([(0, 0), (1, 0)], clean(offset: 1));
    final west = build([(1, 0), (0, 0)], clean(offset: 1));
    final z0 = grid.tileCenter(0, 0).z;
    final half = movementPathHalfWidth(grid);
    expect(east.knots.first.position.dy, closeTo(z0 + half, 1e-6));
    expect(west.knots.first.position.dy, closeTo(z0 - half, 1e-6));
  });

  test('jank is deterministic for the same seed', () {
    final profile = clean(offset: 0.3, jank: 1, smoothness: 0);
    const tiles = <(int, int)>[(0, 0), (1, 0), (2, 0), (3, 0)];
    final a = build(tiles, profile, seed: 'alpha');
    final b = build(tiles, profile, seed: 'alpha');
    final c = build(tiles, profile, seed: 'beta');
    expect(a.knots.length, b.knots.length);
    for (var i = 0; i < a.knots.length; i++) {
      expect(a.knots[i].position.dx, closeTo(b.knots[i].position.dx, 1e-9));
      expect(a.knots[i].position.dy, closeTo(b.knots[i].position.dy, 1e-9));
    }
    final moved = [
      for (var i = 0; i < a.knots.length; i++)
        (a.knots[i].position - c.knots[i].position).distance,
    ];
    expect(moved.any((d) => d > 1e-6), isTrue);
  });

  test('smoothness 0 stays on the offset knot polyline', () {
    const tiles = <(int, int)>[(0, 0), (1, 0), (2, 0), (2, 1)];
    final curve = build(tiles, clean(offset: 0.4, smoothness: 0));
    final knots = [for (final k in curve.knots) k.position];
    for (final p in curve.points) {
      expect(_distanceToPolyline(p, knots), lessThan(1e-6));
    }
  });

  test('fillet and clamp stay inside an L path footprint', () {
    final paths = PathStore(grid: grid);
    for (final tile in const [(0, 0), (1, 0), (2, 0), (2, 1)]) {
      paths.placeAndJoin(tile.$1, tile.$2);
    }
    final curve = build(
      const [(0, 0), (1, 0), (2, 0), (2, 1)],
      clean(offset: 0.8, smoothness: 1),
      paths: paths,
    );
    final bounds = PathBounds.fromPaths(grid, paths);
    for (final p in curve.points) {
      expect(bounds.contains(p), isTrue, reason: '$p');
    }
  });

  test('bend speed is lower at a corner than on a straight', () {
    final curve = build(
      const [(0, 0), (1, 0), (2, 0), (2, 1)],
      clean(bendSlowdown: 1),
    );
    final corner = curve.knots.firstWhere((k) => k.isCorner);
    var cornerDist = 0.0;
    var best = double.infinity;
    for (var i = 0; i < curve.points.length; i++) {
      final d = (curve.points[i] - corner.position).distanceSquared;
      if (d < best) {
        best = d;
        cornerDist = curve.distances[i];
      }
    }
    final straight = curve.speedMultiplierAtDistance(curve.tileSize * 0.4);
    final bent = curve.speedMultiplierAtDistance(cornerDist);
    expect(straight, greaterThan(0.85));
    expect(bent, lessThan(straight));
    expect(bent, lessThan(0.85));
  });

  test('closed loop keeps every corner and wraps the polyline', () {
    const tiles = <(int, int)>[
      (0, 0),
      (1, 0),
      (2, 0),
      (2, 1),
      (2, 2),
      (1, 2),
      (0, 2),
      (0, 1),
      (0, 0),
    ];
    final curve = build(tiles, clean(ratio: 2, smoothness: 0.8));
    expect(curve.isClosed, isTrue);
    expect(curve.knots.where((k) => k.isCorner).length, greaterThanOrEqualTo(4));
    expect((curve.points.last - curve.points.first).distance, lessThan(1e-3));
  });

  test('next tile stop is the following station, not a mid-segment lerp', () {
    const tiles = <(int, int)>[(0, 0), (1, 0), (2, 0), (3, 0)];
    final curve = build(tiles, clean());
    expect(curve.tileDistances.length, 4);
    expect(curve.tileDistances.first, 0);
    expect(curve.tileDistances.last, closeTo(curve.totalLength, 1e-6));
    final midFirst = curve.tileDistances[1] * 0.4;
    expect(
      curve.nextTileStopDistance(midFirst, loop: false),
      closeTo(curve.tileDistances[1], 1e-6),
    );
    expect(
      curve.nextTileStopDistance(curve.tileDistances[1], loop: false),
      closeTo(curve.tileDistances[2], 1e-6),
    );
  });

  test('closed loop stop wraps to the tile after the start', () {
    const tiles = <(int, int)>[
      (0, 0),
      (1, 0),
      (1, 1),
      (0, 1),
      (0, 0),
    ];
    final curve = build(tiles, clean());
    expect(curve.isClosed, isTrue);
    expect(
      curve.nextTileStopDistance(0, loop: true),
      closeTo(curve.tileDistances[1], 1e-6),
    );
    expect(
      curve.nextTileStopDistance(curve.totalLength, loop: true),
      closeTo(curve.tileDistances[1], 1e-6),
    );
  });

  test('facing right is south when walking east', () {
    expect(movementFacingRight(const Offset(1, 0)).dy, closeTo(1, 1e-9));
    expect(movementFacingRight(const Offset(0, 1)).dx, closeTo(-1, 1e-9));
  });

  test('arrival line runs from the shared-edge mid to the offset dest', () {
    const tiles = <(int, int)>[(0, 0), (1, 0)];
    final center = build(tiles, clean());
    final prev = grid.tileCenter(0, 0);
    final dest = grid.tileCenter(1, 0);
    expect(center.arrivalEdgeMid(1).dx, closeTo((prev.x + dest.x) * 0.5, 1e-6));
    expect(center.arrivalEdgeMid(1).dy, closeTo(prev.z, 1e-6));
    expect(center.offsetDest(1).dx, closeTo(dest.x, 1e-6));
    expect(center.offsetDest(1).dy, closeTo(dest.z, 1e-6));
    expect(center.arrivalPoint(1, 0), center.arrivalEdgeMid(1));
    expect(center.arrivalPoint(1, 1), center.offsetDest(1));

    final right = build(tiles, clean(offset: 1));
    final half = movementPathHalfWidth(grid);
    expect(right.offsetDest(1).dy, closeTo(dest.z + half, 1e-6));
  });
}

double _distanceToPolyline(Offset p, List<Offset> knots) {
  var best = double.infinity;
  for (var i = 0; i < knots.length - 1; i++) {
    final a = knots[i];
    final b = knots[i + 1];
    final ab = b - a;
    final ap = p - a;
    final lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    final t = lenSq < 1e-12
        ? 0.0
        : ((ap.dx * ab.dx + ap.dy * ab.dy) / lenSq).clamp(0.0, 1.0);
    final c = Offset.lerp(a, b, t)!;
    final d = (c - p).distance;
    if (d < best) best = d;
  }
  return best;
}
