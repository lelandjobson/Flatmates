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

  test('byId falls back to hop', () {
    expect(FlatmateWalkStyle.byId('whoosh'), FlatmateWalkStyle.whoosh);
    expect(FlatmateWalkStyle.byId('missing'), FlatmateWalkStyle.hop);
  });
}
