import 'package:flatmates/gameplay/flatmates/flatmate_movement.dart';
import 'package:flatmates/gameplay/flatmates/movement_profile.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const grid = VolumeGrid(tilesSide: 16, tileSize: 8);
  const sitY = 1.0;

  const profile = MovementProfile(
    id: 'flourish',
    name: 'Flourish',
    offset: 0,
    jank: 0,
    smoothness: 0,
    bendSlowdown: 0,
    hopHeight: 0,
    tileSpeed: 2.5,
    startBackup: 0.2,
    startSeconds: 0.4,
    startTilt: 0.3,
    stopSlide: 0.2,
    stopSeconds: 0.4,
    stopTilt: 0.25,
  );

  FlatmateMovement openWalk({bool flourish = false, bool loop = false}) {
    return FlatmateMovement()
      ..start(
        const [(0, 0), (1, 0), (2, 0), (3, 0)],
        grid: grid,
        profile: profile,
        flourish: flourish,
        loop: loop,
      );
  }

  void step(
    FlatmateMovement move, {
    required double dt,
    double tilesPerSecond = 10,
  }) {
    move.advance(
      dt: dt,
      baseTilesPerSecond: tilesPerSecond,
      onPath: (_, _) => false,
      grid: grid,
    );
  }

  test('requestStop keeps travel speed then snaps to the next tile', () {
    final move = openWalk();
    move.distance = 3;
    move.requestStop();
    expect(move.phase, MovementPhase.stopping);
    expect(move.stopDistance, closeTo(move.curve!.tileDistances[1], 1e-6));
    final target = move.stopDistance!;
    step(move, dt: 0.05);
    expect(move.distance, closeTo(7, 1e-6));
    expect(move.distance, lessThan(target - 1e-6));
    expect(move.phase, MovementPhase.stopping);
    step(move, dt: 1);
    expect(move.distance, closeTo(target, 1e-6));
    expect(move.phase, MovementPhase.settling);
  });

  test('already on a tile station stops at the tile after it', () {
    final move = openWalk();
    move.distance = move.curve!.tileDistances[1];
    move.requestStop();
    expect(move.stopDistance, closeTo(move.curve!.tileDistances[2], 1e-6));
  });

  test('requestStart does not change committed distance and overlays backup', () {
    final move = openWalk();
    move.progress = 0.4;
    final committed = move.distance;
    move.requestStop();
    while (move.phase != MovementPhase.idle) {
      step(move, dt: 0.05);
    }
    final parked = move.distance;
    expect(parked, isNot(committed));
    move.requestStart();
    expect(move.phase, MovementPhase.starting);
    expect(move.distance, closeTo(parked, 1e-9));
    step(move, dt: profile.startSeconds / 2);
    expect(move.distance, closeTo(parked, 1e-9));
    expect(move.overlayAlong, lessThan(0));
    expect(move.pitch, greaterThan(0));
    final start = grid.tileCenter(0, 0);
    final pos = move.worldPosition(grid, sitY);
    expect(pos.x, lessThan(start.x + parked));
    step(move, dt: profile.startSeconds);
    expect(move.distance, closeTo(parked, 1e-9));
    expect(move.overlayAlong, 0);
    expect(move.pitch, 0);
    expect(move.phase, MovementPhase.moving);
  });

  test('settle leans back then returns to rest', () {
    final move = openWalk();
    move.distance = 3;
    move.requestStop();
    while (move.phase != MovementPhase.settling) {
      step(move, dt: 0.05);
    }
    step(move, dt: profile.stopSeconds / 2);
    expect(move.pitch, lessThan(0));
    expect(move.overlayAlong, greaterThan(0));
    step(move, dt: profile.stopSeconds);
    expect(move.phase, MovementPhase.idle);
    expect(move.isMoving, isFalse);
    expect(move.overlayAlong, 0);
    expect(move.pitch, 0);
  });

  test('open path settles on the last tile then is idle', () {
    final move = openWalk();
    move.progress = 0.99;
    step(move, dt: 1);
    expect(move.phase, MovementPhase.settling);
    expect(move.distance, closeTo(move.curve!.totalLength, 1e-6));
    expect(move.isMoving, isTrue);
    step(move, dt: 1);
    expect(move.phase, MovementPhase.idle);
    expect(move.isMoving, isFalse);
    expect(move.overlayAlong, 0);
    expect(move.pitch, 0);
  });

  test('start flourish begins from the first tile without moving distance', () {
    final move = openWalk(flourish: true);
    expect(move.phase, MovementPhase.starting);
    expect(move.distance, 0);
    step(move, dt: profile.startSeconds / 2);
    expect(move.distance, 0);
    expect(move.overlayAlong, lessThan(0));
    expect(move.pitch, greaterThan(0));
  });

  test('start and stop requests are ignored in the wrong phase', () {
    final move = openWalk();
    expect(move.canRequestStart, isFalse);
    expect(move.canRequestStop, isTrue);
    move.requestStart();
    expect(move.phase, MovementPhase.moving);
    move.requestStop();
    expect(move.phase, MovementPhase.stopping);
    move.requestStop();
    expect(move.phase, MovementPhase.stopping);
    while (move.phase != MovementPhase.idle) {
      step(move, dt: 0.05);
    }
    expect(move.canRequestStart, isTrue);
    expect(move.canRequestStop, isFalse);
    move.requestStop();
    expect(move.phase, MovementPhase.idle);
  });
}
