import 'package:flatmates/gameplay/flatmates/flatmate_movement.dart';
import 'package:flatmates/gameplay/flatmates/flatmate_walk_style.dart';
import 'package:flatmates/gameplay/flatmates/movement_profile.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const grid = VolumeGrid(tilesSide: 16, tileSize: 8);
  const sitY = 1.0;
  const bodySize = 2.0;

  MovementProfile hopProfile({double hopHeight = 0.85}) {
    return MovementProfile(
      id: 'hop',
      name: 'Hop',
      offset: 0,
      jank: 0,
      smoothness: 0,
      hopHeight: hopHeight,
      bendSlowdown: 0,
    );
  }

  FlatmateMovement eastWalk({double hopHeight = 0.85}) {
    return FlatmateMovement()
      ..start(
        [(0, 0), (1, 0)],
        grid: grid,
        profile: hopProfile(hopHeight: hopHeight),
        seed: 'cubeboy',
      );
  }

  test('hop lifts mid-stride and lands on the destination', () {
    final move = eastWalk();
    final start = grid.tileCenter(0, 0);
    final end = grid.tileCenter(1, 0);

    move.progress = 0;
    final grounded = move.worldPosition(grid, sitY, bodySize: bodySize);
    expect(grounded.y, closeTo(sitY, 1e-9));
    expect(grounded.x, closeTo(start.x, 1e-9));

    move.progress = 0.5;
    final mid = move.worldPosition(grid, sitY, bodySize: bodySize);
    expect(mid.y, greaterThan(sitY + 0.5));
    expect(mid.x, closeTo((start.x + end.x) * 0.5, 1e-6));

    move.progress = 1;
    final landed = move.worldPosition(grid, sitY, bodySize: bodySize);
    expect(landed.y, closeTo(sitY, 1e-9));
    expect(landed.x, closeTo(end.x, 1e-9));
    expect(landed.z, closeTo(end.z, 1e-9));
  });

  test('slide stays on the ground with no hop', () {
    final move = eastWalk(hopHeight: 0)..progress = 0.45;
    final start = grid.tileCenter(0, 0);
    final end = grid.tileCenter(1, 0);
    final pos = move.worldPosition(grid, sitY, bodySize: bodySize);
    expect(pos.y, closeTo(sitY, 1e-9));
    expect(pos.z, closeTo(start.z, 1e-9));
    expect(pos.x, closeTo(start.x + (end.x - start.x) * 0.45, 1e-6));
  });

  test('hop lifts mid-stride on every orthogonal heading', () {
    const paths = <List<(int, int)>>[
      [(2, 2), (3, 2)],
      [(2, 2), (1, 2)],
      [(2, 2), (2, 3)],
      [(2, 2), (2, 1)],
    ];
    for (final path in paths) {
      final move = FlatmateMovement()
        ..start(
          path,
          grid: grid,
          profile: hopProfile(),
          seed: 'heading',
        )
        ..progress = 0.5;
      final start = grid.tileCenter(path[0].$1, path[0].$2);
      final end = grid.tileCenter(path[1].$1, path[1].$2);
      final mid = move.worldPosition(grid, sitY, bodySize: bodySize);
      expect(mid.y, greaterThan(sitY + 0.8), reason: '$path');
      expect(
        mid.x,
        closeTo((start.x + end.x) * 0.5, 1e-6),
        reason: '$path x',
      );
      expect(
        mid.z,
        closeTo((start.z + end.z) * 0.5, 1e-6),
        reason: '$path z',
      );
    }
  });

  test('facing follows the segment tangent', () {
    final east = eastWalk();
    expect(east.facingYaw(), closeTo(1.5707963267948966, 1e-6));
    final south = FlatmateMovement()
      ..start(
        [(0, 0), (0, 1)],
        grid: grid,
        profile: hopProfile(hopHeight: 0),
      );
    expect(south.facingYaw(), closeTo(0, 1e-6));
  });

  test('byId falls back to hop', () {
    expect(FlatmateWalkStyle.byId('whoosh'), FlatmateWalkStyle.whoosh);
    expect(FlatmateWalkStyle.byId('missing'), FlatmateWalkStyle.hop);
    expect(
      FlatmateWalkStyle.sideSign(0, 'alpha'),
      FlatmateWalkStyle.sideSign(0, 'alpha'),
    );
  });
}
