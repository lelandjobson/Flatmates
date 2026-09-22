import 'dart:math' as math;
import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

import '../paths/path_store.dart';
import '../volumes/volume.dart';
import 'flatmate_pathfinder.dart';
import 'movement_curve.dart';
import 'movement_profile.dart';

/// Walk phase for start wind-up, travel, and stop settle.
enum MovementPhase { idle, starting, moving, stopping, settling }

/// Session-only walk along a [MovementCurve] built from a tile route.
class FlatmateMovement {
  List<(int, int)> tiles = [];
  MovementCurve? curve;
  MovementProfile profile = MovementProfile.hop;
  String seed = '';
  double distance = 0;
  bool loop = false;
  double? _pendingProgress;

  MovementPhase phase = MovementPhase.idle;
  double phaseT = 0;
  double overlayAlong = 0;
  double pitch = 0;
  bool stopRequested = false;
  double? stopDistance;

  Offset? _startFrom;
  Offset? _startEntry;
  Offset _startTangent = const Offset(1, 0);
  int? _stopDestIndex;
  double _stopU0 = 1;

  bool get isMoving =>
      phase == MovementPhase.starting ||
      phase == MovementPhase.moving ||
      phase == MovementPhase.stopping ||
      phase == MovementPhase.settling;

  bool get canRequestStart =>
      tiles.length >= 2 &&
      (phase == MovementPhase.idle || phase == MovementPhase.settling);

  bool get canRequestStop =>
      phase == MovementPhase.starting || phase == MovementPhase.moving;

  /// 0–1 along the built curve (not a tile index).
  double get progress {
    final built = curve;
    if (built == null || built.totalLength < 1e-9) {
      return _pendingProgress ?? 0;
    }
    return (distance / built.totalLength).clamp(0.0, 1.0);
  }

  set progress(double t) {
    final built = curve;
    if (built == null || built.totalLength < 1e-9) {
      _pendingProgress = t.clamp(0.0, 1.0);
      return;
    }
    distance = t.clamp(0.0, 1.0) * built.totalLength;
    _pendingProgress = null;
    if (phase == MovementPhase.starting) {
      _retargetStartEntry();
    }
  }

  (int, int)? get currentTile {
    if (tiles.isEmpty) return null;
    final built = curve;
    if (built != null) return built.tileAtDistance(distance);
    final i = (progress * (tiles.length - 1)).round().clamp(0, tiles.length - 1);
    return tiles[i];
  }

  void start(
    List<(int, int)> path, {
    VolumeGrid? grid,
    MovementProfile? profile,
    PathStore? paths,
    String seed = '',
    bool loop = false,
    bool flourish = true,
    Offset? startFrom,
  }) {
    tiles = List<(int, int)>.from(path);
    this.profile = profile ?? this.profile;
    this.seed = seed;
    this.loop = loop;
    distance = 0;
    _pendingProgress = 0;
    curve = null;
    _resetFlourish();
    if (grid != null) {
      _rebuild(grid, paths: paths, keepFraction: false);
    }
    if (tiles.length < 2) {
      phase = MovementPhase.idle;
      return;
    }
    _bindStartPose(startFrom);
    if (flourish) {
      phase = MovementPhase.starting;
    } else {
      _landOnCurve();
      phase = MovementPhase.moving;
    }
  }

  /// Aim the start flourish at the current curve slot while keeping [startFrom].
  void captureStartFrom(Offset startFrom, {bool entryAtDistance = false}) {
    _bindStartPose(startFrom, entryAtDistance: entryAtDistance);
  }

  void applyProfile(
    MovementProfile profile,
    VolumeGrid grid, {
    PathStore? paths,
  }) {
    this.profile = profile;
    if (tiles.length >= 2) {
      _rebuild(grid, paths: paths, keepFraction: true);
    }
    if (phase == MovementPhase.starting) {
      _retargetStartEntry();
    }
    if ((phase == MovementPhase.stopping || phase == MovementPhase.settling) &&
        _stopDestIndex != null) {
      _recomputeStopDistance();
    }
  }

  void clear() {
    tiles = [];
    curve = null;
    distance = 0;
    loop = false;
    _pendingProgress = null;
    _resetFlourish();
    phase = MovementPhase.idle;
  }

  /// Begin walking from the current curve distance. Does not lerp onto a tile.
  void requestStart({Offset? startFrom}) {
    if (!canRequestStart) return;
    overlayAlong = 0;
    pitch = 0;
    phaseT = 0;
    stopRequested = false;
    stopDistance = null;
    _stopDestIndex = null;
    if (tiles.length >= 3 && tiles.first == tiles.last) {
      loop = true;
    }
    _bindStartPose(startFrom);
    phase = MovementPhase.starting;
  }

  /// Commit a stop at the next route tile. Continues at current speed.
  void requestStop() {
    if (!canRequestStop) return;
    stopRequested = true;
    if (phase == MovementPhase.moving) {
      _commitStopStation();
      phase = MovementPhase.stopping;
    }
  }

  /// Advance [dt] seconds. [baseTilesPerSecond] is scaled by bend and path tiles.
  bool advance({
    required double dt,
    required double baseTilesPerSecond,
    required bool Function(int tx, int ty) onPath,
    VolumeGrid? grid,
    PathStore? paths,
  }) {
    if (grid != null) _ensureCurve(grid, paths: paths);
    final built = curve;
    if (built == null || built.totalLength < 1e-9) return false;
    switch (phase) {
      case MovementPhase.idle:
        return false;
      case MovementPhase.starting:
        _tickStarting(dt);
        return true;
      case MovementPhase.moving:
        _tickTravel(
          dt: dt,
          baseTilesPerSecond: baseTilesPerSecond,
          onPath: onPath,
          built: built,
        );
        return isMoving;
      case MovementPhase.stopping:
        _tickStopping(
          dt: dt,
          baseTilesPerSecond: baseTilesPerSecond,
          onPath: onPath,
          built: built,
        );
        return true;
      case MovementPhase.settling:
        _tickSettling(dt);
        return isMoving;
    }
  }

  Vector3 worldPosition(
    VolumeGrid grid,
    double sitY, {
    String swaySeed = '',
    double bodySize = 2,
    PathStore? paths,
  }) {
    if (swaySeed.isNotEmpty && seed.isEmpty) seed = swaySeed;
    _ensureCurve(grid, paths: paths);
    final built = curve;
    if (built == null || built.points.isEmpty) {
      if (tiles.isEmpty) return Vector3(0, sitY, 0);
      final c = grid.tileCenter(tiles.first.$1, tiles.first.$2);
      return Vector3(c.x, sitY, c.z);
    }
    if (phase == MovementPhase.starting) {
      final from = _startFrom ?? built.pointAtDistance(distance);
      final entry = _startEntry ?? built.pointAtDistance(distance);
      final p = Offset.lerp(from, entry, phaseT.clamp(0.0, 1.0))!;
      final backup = _startTangent * overlayAlong;
      return Vector3(p.dx + backup.dx, sitY, p.dy + backup.dy);
    }
    if (phase == MovementPhase.settling && _stopDestIndex != null) {
      final t = phaseT.clamp(0.0, 1.0);
      final ease = 1 - (1 - t) * (1 - t);
      final u = _stopU0 + (1 - _stopU0) * ease;
      final p = built.arrivalPoint(_stopDestIndex!, u);
      return Vector3(p.dx, sitY, p.dy);
    }
    final p = built.pointAtDistance(distance);
    final tangent = built.tangentAtDistance(distance);
    final plant = phase == MovementPhase.settling && phaseT > 0;
    final hop = plant ? 0.0 : built.hopHeightAtDistance(distance, bodySize);
    return Vector3(
      p.dx + tangent.dx * overlayAlong,
      sitY + hop,
      p.dy + tangent.dy * overlayAlong,
    );
  }

  /// Yaw in radians so +Z is south (tile +Y).
  double facingYaw() {
    final built = curve;
    if (built == null || built.points.length < 2) {
      if (tiles.length < 2) return 0;
      final a = tiles[0];
      final b = tiles[1];
      final dx = (b.$1 - a.$1).toDouble();
      final dz = (b.$2 - a.$2).toDouble();
      if (dx.abs() < 1e-8 && dz.abs() < 1e-8) return 0;
      return math.atan2(dx, dz);
    }
    return built.facingYawAtDistance(distance);
  }

  void _ensureCurve(VolumeGrid grid, {PathStore? paths}) {
    if (curve != null || tiles.length < 2) return;
    _rebuild(grid, paths: paths, keepFraction: false);
  }

  void _rebuild(
    VolumeGrid grid, {
    PathStore? paths,
    required bool keepFraction,
  }) {
    final frac = keepFraction ? progress : (_pendingProgress ?? 0);
    final oldTotal = curve?.totalLength ?? 0;
    final stopFrac = stopDistance != null && oldTotal > 1e-9
        ? stopDistance! / oldTotal
        : null;
    curve = buildMovementCurve(
      tiles: tiles,
      grid: grid,
      profile: profile,
      paths: paths,
      seed: seed,
    );
    distance = frac.clamp(0.0, 1.0) * (curve?.totalLength ?? 0);
    if (stopFrac != null) {
      stopDistance = stopFrac * (curve?.totalLength ?? 0);
    }
    _pendingProgress = null;
  }

  void _resetFlourish() {
    phase = MovementPhase.idle;
    phaseT = 0;
    overlayAlong = 0;
    pitch = 0;
    stopRequested = false;
    stopDistance = null;
    _startFrom = null;
    _startEntry = null;
    _startTangent = const Offset(1, 0);
    _stopDestIndex = null;
    _stopU0 = 1;
  }

  void _bindStartPose(Offset? startFrom, {bool entryAtDistance = false}) {
    final built = curve;
    if (built == null || built.points.isEmpty) {
      _startFrom = startFrom;
      _startEntry = startFrom;
      _startTangent = const Offset(1, 0);
      return;
    }
    if (startFrom != null) {
      _startFrom = startFrom;
      if (entryAtDistance) {
        _startEntry = built.pointAtDistance(distance);
        _startTangent = built.tangentAtDistance(distance);
      } else {
        final d = built.closestDistance(startFrom);
        _startEntry = built.pointAtDistance(d);
        _startTangent = built.tangentAtDistance(d);
      }
      return;
    }
    final here = built.pointAtDistance(distance);
    _startFrom = here;
    _startEntry = here;
    _startTangent = built.tangentAtDistance(distance);
  }

  void _retargetStartEntry() {
    final built = curve;
    if (built == null || built.points.isEmpty) return;
    _startEntry = built.pointAtDistance(distance);
    _startTangent = built.tangentAtDistance(distance);
  }

  void _landOnCurve() {
    final built = curve;
    if (built == null || built.points.isEmpty) return;
    final target = _startEntry ?? built.pointAtDistance(distance);
    distance = built.closestDistance(target);
    overlayAlong = 0;
    pitch = 0;
    phaseT = 0;
  }

  void _commitStopStation() {
    final built = curve;
    if (built == null || built.totalLength < 1e-9) {
      stopDistance = distance;
      return;
    }
    var target = built.nextTileStopDistance(distance, loop: loop);
    final wrapped = built.isClosed
        ? (distance % built.totalLength + built.totalLength) % built.totalLength
        : distance;
    if (loop && built.isClosed && target + 1e-6 < wrapped) {
      target += built.totalLength;
    }
    _stopDestIndex = built.destTileIndexForDistance(target);
    _stopU0 = (1 - profile.stopSlide.clamp(0.0, 1.0));
    _recomputeStopDistance();
  }

  void _recomputeStopDistance() {
    final built = curve;
    final destIndex = _stopDestIndex;
    if (built == null || destIndex == null || built.totalLength < 1e-9) {
      stopDistance = distance;
      return;
    }
    var stopAt = built.closestDistance(built.arrivalPoint(destIndex, _stopU0));
    if (loop && built.isClosed) {
      final wrapped =
          (distance % built.totalLength + built.totalLength) % built.totalLength;
      if (stopAt + 1e-6 < wrapped) stopAt += built.totalLength;
    }
    stopDistance = stopAt;
  }

  void _tickStarting(double dt) {
    final dur = math.max(profile.startSeconds, 1e-6);
    phaseT = (phaseT + dt / dur).clamp(0.0, 1.0);
    _applyStartOverlay(phaseT);
    if (phaseT < 1) return;
    _landOnCurve();
    if (stopRequested) {
      _commitStopStation();
      phase = MovementPhase.stopping;
    } else {
      phase = MovementPhase.moving;
    }
  }

  void _tickTravel({
    required double dt,
    required double baseTilesPerSecond,
    required bool Function(int tx, int ty) onPath,
    required MovementCurve built,
  }) {
    _advanceDistance(
      dt: dt,
      baseTilesPerSecond: baseTilesPerSecond,
      onPath: onPath,
      built: built,
    );
    if (loop) {
      if (built.totalLength > 1e-9) {
        distance %= built.totalLength;
        if (distance < 0) distance += built.totalLength;
      }
      return;
    }
    _armOpenPathArrival(built);
    final target = stopDistance ?? built.totalLength;
    if (distance + 1e-6 >= target) {
      distance = target;
      _beginSettle();
    }
  }

  void _tickStopping({
    required double dt,
    required double baseTilesPerSecond,
    required bool Function(int tx, int ty) onPath,
    required MovementCurve built,
  }) {
    _advanceDistance(
      dt: dt,
      baseTilesPerSecond: baseTilesPerSecond,
      onPath: onPath,
      built: built,
    );
    final target = stopDistance ?? built.totalLength;
    if (distance + 1e-6 >= target) {
      distance = target;
      if (loop && built.isClosed && built.totalLength > 1e-9) {
        distance %= built.totalLength;
        if (distance < 0) distance += built.totalLength;
      }
      _beginSettle();
    }
  }

  void _tickSettling(double dt) {
    final dur = math.max(profile.stopSeconds, 1e-6);
    phaseT = (phaseT + dt / dur).clamp(0.0, 1.0);
    _applyStopOverlay(phaseT);
    if (phaseT < 1) return;
    overlayAlong = 0;
    pitch = 0;
    phaseT = 0;
    stopRequested = false;
    final built = curve;
    final destIndex = _stopDestIndex;
    if (built != null && destIndex != null) {
      distance = built.closestDistance(built.offsetDest(destIndex));
    }
    stopDistance = null;
    _stopDestIndex = null;
    phase = MovementPhase.idle;
  }

  void _beginSettle() {
    overlayAlong = 0;
    pitch = 0;
    phaseT = 0;
    final built = curve;
    if (_stopDestIndex == null && built != null) {
      _stopDestIndex = built.destTileIndexForDistance(distance);
      _stopU0 = 1 - profile.stopSlide.clamp(0.0, 1.0);
    }
    phase = MovementPhase.settling;
  }

  void _armOpenPathArrival(MovementCurve built) {
    if (stopDistance != null) return;
    _stopDestIndex = tiles.length - 1;
    _stopU0 = 1 - profile.stopSlide.clamp(0.0, 1.0);
    stopDistance = built.closestDistance(
      built.arrivalPoint(_stopDestIndex!, _stopU0),
    );
  }

  void _advanceDistance({
    required double dt,
    required double baseTilesPerSecond,
    required bool Function(int tx, int ty) onPath,
    required MovementCurve built,
  }) {
    final tile = built.tileAtDistance(distance);
    final speed = baseTilesPerSecond *
        built.speedMultiplierAtDistance(distance) *
        (onPath(tile.$1, tile.$2)
            ? FlatmatePathfinder.pathSpeedMultiplier
            : 1);
    distance += dt * speed * built.tileSize;
  }

  void _applyStartOverlay(double t) {
    final tile = curve?.tileSize ?? 8;
    final wave = math.sin(math.pi * t.clamp(0.0, 1.0));
    overlayAlong = -profile.startBackup * tile * wave;
    pitch = profile.startTilt * wave;
  }

  void _applyStopOverlay(double t) {
    overlayAlong = 0;
    final wave = math.sin(math.pi * t.clamp(0.0, 1.0));
    pitch = -profile.stopTilt * wave;
  }
}
