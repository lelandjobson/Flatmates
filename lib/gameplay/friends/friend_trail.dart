import 'package:flutter/material.dart';

import 'friend_instance.dart';

/// How long a ground-ink stamp stays visible.
const kFriendTrailLifetime = 2.0;

/// World-space gap between consecutive ink stamps.
const kFriendTrailSpacing = 0.3;

/// Teleports larger than this start a new stroke instead of filling the gap.
const kFriendTrailMaxJump = 5.0;

/// Wet-ink mark left on the ground while a friend walks.
class FriendTrailStamp {
  const FriendTrailStamp({
    required this.xz,
    required this.color,
    required this.age,
    required this.seed,
  });

  final Offset xz;
  final Color color;
  final double age;
  final int seed;

  FriendTrailStamp aged(double dt) =>
      FriendTrailStamp(xz: xz, color: color, age: age + dt, seed: seed);
}

/// Ordered stamps for one friend, oldest first.
class FriendTrail {
  const FriendTrail({required this.friendId, required this.stamps});

  final String friendId;
  final List<FriendTrailStamp> stamps;
}

/// Session-only ground-ink recorder. Call [advance] once per tick, then
/// [record] after each friend's pose update.
class FriendTrailStore {
  FriendTrailStore({
    this.lifetime = kFriendTrailLifetime,
    this.spacing = kFriendTrailSpacing,
    this.maxJump = kFriendTrailMaxJump,
  });

  final double lifetime;
  final double spacing;
  final double maxJump;

  final Map<String, List<FriendTrailStamp>> _stamps = {};
  final Map<String, Offset> _cursor = {};

  bool get isEmpty {
    for (final stamps in _stamps.values) {
      if (stamps.isNotEmpty) return false;
    }
    return true;
  }

  List<FriendTrail> get trails {
    return [
      for (final entry in _stamps.entries)
        if (entry.value.isNotEmpty)
          FriendTrail(
            friendId: entry.key,
            stamps: List.unmodifiable(entry.value),
          ),
    ];
  }

  List<FriendTrailStamp> stampsFor(String friendId) =>
      List.unmodifiable(_stamps[friendId] ?? const []);

  void clear() {
    _stamps.clear();
    _cursor.clear();
  }

  void clearFriend(String friendId) {
    _stamps.remove(friendId);
    _cursor.remove(friendId);
  }

  void advance(double dt) {
    if (dt <= 0) return;
    for (final id in _stamps.keys.toList()) {
      final next = <FriendTrailStamp>[];
      for (final stamp in _stamps[id]!) {
        final aged = stamp.aged(dt);
        if (aged.age < lifetime) next.add(aged);
      }
      if (next.isEmpty) {
        _stamps.remove(id);
      } else {
        _stamps[id] = next;
      }
    }
  }

  void record(FriendInstance instance) {
    recordPoint(
      friendId: instance.id,
      xz: Offset(instance.position.x, instance.position.z),
      color: instance.friend.color,
      moving: instance.movement.isMoving,
    );
  }

  void recordPoint({
    required String friendId,
    required Offset xz,
    required Color color,
    required bool moving,
  }) {
    if (!moving) return;
    final last = _cursor[friendId];
    if (last == null) {
      _add(friendId, xz, color);
      _cursor[friendId] = xz;
      return;
    }
    final delta = xz - last;
    final gap = delta.distance;
    if (gap < spacing) return;
    if (gap > maxJump) {
      _add(friendId, xz, color);
      _cursor[friendId] = xz;
      return;
    }
    final dir = Offset(delta.dx / gap, delta.dy / gap);
    var placed = last;
    var remaining = gap;
    while (remaining >= spacing) {
      placed += dir * spacing;
      _add(friendId, placed, color);
      remaining -= spacing;
    }
    _cursor[friendId] = placed;
  }

  void _add(String friendId, Offset xz, Color color) {
    final seed = Object.hash(
      friendId,
      (xz.dx * 20).round(),
      (xz.dy * 20).round(),
    );
    _stamps
        .putIfAbsent(friendId, () => [])
        .add(FriendTrailStamp(xz: xz, color: color, age: 0, seed: seed));
  }
}

/// 1 at birth, 0 at [lifetime]. Holds a moment, then soaks away.
double friendTrailFade({required double age, required double lifetime}) {
  if (lifetime <= 1e-9) return 0;
  final t = (age / lifetime).clamp(0.0, 1.0);
  return (1 - t) * (1 - t * 0.45);
}

/// Darker, inkier take on a friend's display color.
Color friendTrailInkColor(Color friendColor) {
  final hsl = HSLColor.fromColor(friendColor);
  return hsl
      .withLightness((hsl.lightness * 0.52).clamp(0.16, 0.58))
      .withSaturation((hsl.saturation * 1.08).clamp(0.0, 1.0))
      .toColor();
}
