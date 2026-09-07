import 'package:flatmates/gameplay/flatmates/flatmate_movement.dart';
import 'package:flatmates/gameplay/flatmates/flatmate_walk_style.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const grid = VolumeGrid(tilesSide: 16, tileSize: 8);
  const sitY = 1.0;
  const bodySize = 2.0;

  FlatmateMovement eastWalk() {
    return FlatmateMovement()..start([(0, 0), (1, 0)]);
  }

  test('hop lifts mid-tile and lands on the destination', () {
    final move = eastWalk();
    final start = grid.tileCenter(0, 0);
    final end = grid.tileCenter(1, 0);

    move.progress = 0;
    final grounded = move.worldPosition(
      grid,
      sitY,
      style: FlatmateWalkStyle.hop,
      swaySeed: 'cubeboy',
      bodySize: bodySize,
    );
    expect(grounded.y, closeTo(sitY, 1e-9));
    expect(grounded.x, closeTo(start.x, 1e-9));

    move.progress = 0.45;
    final mid = move.worldPosition(
      grid,
      sitY,
      style: FlatmateWalkStyle.hop,
      swaySeed: 'cubeboy',
      bodySize: bodySize,
    );
    expect(mid.y, greaterThan(sitY + 0.5));
    expect(mid.z, isNot(closeTo(start.z, 1e-6)));

    move.progress = 1;
    final landed = move.worldPosition(
      grid,
      sitY,
      style: FlatmateWalkStyle.hop,
      swaySeed: 'cubeboy',
      bodySize: bodySize,
    );
    expect(landed.y, closeTo(sitY, 1e-9));
    expect(landed.x, closeTo(end.x, 1e-9));
    expect(landed.z, closeTo(end.z, 1e-9));
  });

  test('hop sway sign is stable for the same segment and seed', () {
    final move = eastWalk()..progress = 0.45;
    final a = move.worldPosition(
      grid,
      sitY,
      style: FlatmateWalkStyle.hop,
      swaySeed: 'alpha',
      bodySize: bodySize,
    );
    final b = move.worldPosition(
      grid,
      sitY,
      style: FlatmateWalkStyle.hop,
      swaySeed: 'alpha',
      bodySize: bodySize,
    );
    expect(a.z, closeTo(b.z, 1e-9));
    expect(
      FlatmateWalkStyle.sideSign(0, 'alpha'),
      FlatmateWalkStyle.sideSign(0, 'alpha'),
    );
  });

  test('slide stays on the ground with no sway', () {
    final move = eastWalk()..progress = 0.45;
    final start = grid.tileCenter(0, 0);
    final end = grid.tileCenter(1, 0);
    final pos = move.worldPosition(
      grid,
      sitY,
      style: FlatmateWalkStyle.slide,
      swaySeed: 'cubeboy',
      bodySize: bodySize,
    );
    expect(pos.y, closeTo(sitY, 1e-9));
    expect(pos.z, closeTo(start.z, 1e-9));
    expect(pos.x, closeTo(start.x + (end.x - start.x) * 0.45, 1e-9));
  });

  test('whoosh holds near the start during its pause', () {
    final move = eastWalk()..progress = 0.1;
    final start = grid.tileCenter(0, 0);
    final pos = move.worldPosition(
      grid,
      sitY,
      style: FlatmateWalkStyle.whoosh,
      swaySeed: 'cubeboy',
      bodySize: bodySize,
    );
    expect(pos.x, closeTo(start.x, 1e-9));
    expect(pos.z, closeTo(start.z, 1e-9));
    expect(pos.y, closeTo(sitY, 1e-9));
  });

  test('hop lifts mid-tile on every orthogonal heading', () {
    const paths = <List<(int, int)>>[
      [(2, 2), (3, 2)], // east
      [(2, 2), (1, 2)], // west
      [(2, 2), (2, 3)], // south
      [(2, 2), (2, 1)], // north
    ];
    for (final path in paths) {
      final move = FlatmateMovement()
        ..start(path)
        ..progress = 0.5;
      final start = grid.tileCenter(path[0].$1, path[0].$2);
      final end = grid.tileCenter(path[1].$1, path[1].$2);
      final mid = move.worldPosition(
        grid,
        sitY,
        style: FlatmateWalkStyle.hop,
        swaySeed: 'heading',
        bodySize: bodySize,
      );
      expect(mid.y, greaterThan(sitY + 0.8), reason: '$path');
      final alongX = (end.x - start.x).abs() > 1e-6;
      if (alongX) {
        expect(mid.z, isNot(closeTo(start.z, 1e-6)), reason: '$path sway');
      } else {
        expect(mid.x, isNot(closeTo(start.x, 1e-6)), reason: '$path sway');
      }

      move.progress = 0.08;
      final planted = move.worldPosition(
        grid,
        sitY,
        style: FlatmateWalkStyle.hop,
        swaySeed: 'heading',
        bodySize: bodySize,
      );
      if (alongX) {
        expect(planted.x, closeTo(start.x, 1e-6), reason: '$path plant');
      } else {
        expect(planted.z, closeTo(start.z, 1e-6), reason: '$path plant');
      }
    }
  });

  test('byId falls back to hop', () {
    expect(FlatmateWalkStyle.byId('whoosh'), FlatmateWalkStyle.whoosh);
    expect(FlatmateWalkStyle.byId('missing'), FlatmateWalkStyle.hop);
  });
}
