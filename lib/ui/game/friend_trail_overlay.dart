import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../gameplay/friends/friend_instance_store.dart';
import '../../gameplay/friends/friend_mesh_sync.dart';
import '../../gameplay/friends/friend_overlay_visibility.dart';
import '../../gameplay/friends/friend_trail.dart';
import '../../gameplay/volumes/volume_store.dart';
import '../../rendering/scene/camera.dart';
import '../../rendering/scene/scene.dart';

/// Friend-colored ink on the ground. Fades with [FriendTrailStore] age.
class FriendTrailOverlay extends StatelessWidget {
  const FriendTrailOverlay({
    super.key,
    required this.trails,
    required this.camera,
    required this.viewport,
    required this.tileSize,
    this.friends,
    this.volumes,
    this.interiorOpen,
    this.tileVisible,
    this.listenable,
    this.lift = 0.16,
    this.scale = 1,
  });

  final FriendTrailStore trails;
  final Camera camera;
  final Size viewport;
  final double tileSize;
  final FriendInstanceStore? friends;
  final VolumeStore? volumes;
  final bool Function(int tx, int ty)? interiorOpen;
  final bool Function(int tx, int ty)? tileVisible;
  final Scene? listenable;
  final double lift;

  /// `0` hides the trail; `1` is the current drawn max.
  final double scale;

  @override
  Widget build(BuildContext context) {
    final listenable = this.listenable;
    if (listenable != null) {
      return ListenableBuilder(
        listenable: listenable,
        builder: (context, _) => _paint(),
      );
    }
    return _paint();
  }

  Widget _paint() {
    if (scale <= 0 || trails.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        size: viewport,
        painter: _TrailPainter(
          trails: trails,
          camera: camera,
          viewport: viewport,
          tileSize: tileSize,
          friends: friends,
          volumes: volumes,
          interiorOpen: interiorOpen,
          tileVisible: tileVisible,
          lift: lift,
          scale: scale,
        ),
      ),
    );
  }
}

class _ProjectedStamp {
  const _ProjectedStamp({
    required this.stamp,
    required this.screen,
    required this.radius,
    required this.fade,
  });

  final FriendTrailStamp stamp;
  final Offset screen;
  final double radius;
  final double fade;
}

class _TrailPainter extends CustomPainter {
  _TrailPainter({
    required this.trails,
    required this.camera,
    required this.viewport,
    required this.tileSize,
    this.friends,
    this.volumes,
    this.interiorOpen,
    this.tileVisible,
    required this.lift,
    required this.scale,
  });

  final FriendTrailStore trails;
  final Camera camera;
  final Size viewport;
  final double tileSize;
  final FriendInstanceStore? friends;
  final VolumeStore? volumes;
  final bool Function(int tx, int ty)? interiorOpen;
  final bool Function(int tx, int ty)? tileVisible;
  final double lift;
  final double scale;

  double get _worldWidth =>
      FriendMeshLayout.worldSize(tileSize: tileSize) * 0.28 * scale;

  double get _skipRadius =>
      FriendMeshLayout.worldSize(tileSize: tileSize) * 0.38;

  @override
  void paint(Canvas canvas, Size size) {
    if (viewport.width <= 0 || viewport.height <= 0) return;
    for (final trail in trails.trails) {
      _paintTrail(canvas, trail);
    }
  }

  void _paintTrail(Canvas canvas, FriendTrail trail) {
    final projected = <_ProjectedStamp>[];
    for (final stamp in trail.stamps) {
      if (!_stampVisible(trail.friendId, stamp)) continue;
      final fade = friendTrailFade(age: stamp.age, lifetime: trails.lifetime);
      if (fade <= 0.01) continue;
      final screen = camera.projectToScreen(
        Vector3(stamp.xz.dx, lift, stamp.xz.dy),
        viewport,
      );
      if (screen == null) continue;
      final edge = camera.projectToScreen(
        Vector3(stamp.xz.dx + _worldWidth, lift, stamp.xz.dy),
        viewport,
      );
      final radius = edge == null
          ? 3.0
          : (edge - screen).distance.clamp(1.2, 28.0);
      projected.add(
        _ProjectedStamp(
          stamp: stamp,
          screen: screen,
          radius: radius,
          fade: fade,
        ),
      );
    }
    if (projected.isEmpty) return;

    for (var i = 0; i < projected.length - 1; i++) {
      final a = projected[i];
      final b = projected[i + 1];
      if ((b.screen - a.screen).distance > math.max(a.radius, b.radius) * 8) {
        continue;
      }
      _strokeSegment(canvas, a, b);
    }
    for (final point in projected) {
      _blot(canvas, point);
    }
  }

  void _strokeSegment(Canvas canvas, _ProjectedStamp a, _ProjectedStamp b) {
    final fade = (a.fade + b.fade) * 0.5;
    final width = (a.radius + b.radius);
    final ink = friendTrailInkColor(a.stamp.color);
    final bleed = Paint()
      ..color = ink.withValues(alpha: 0.22 * fade)
      ..strokeWidth = width * 1.55
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, width * 0.28);
    final core = Paint()
      ..color = ink.withValues(alpha: 0.58 * fade)
      ..strokeWidth = width * 0.92
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(a.screen, b.screen, bleed);
    canvas.drawLine(a.screen, b.screen, core);
  }

  void _blot(Canvas canvas, _ProjectedStamp point) {
    final ink = friendTrailInkColor(point.stamp.color);
    final u0 = _unit(point.stamp.seed, 1);
    final u1 = _unit(point.stamp.seed, 2);
    final u2 = _unit(point.stamp.seed, 3);
    final along = point.radius * (0.95 + 0.45 * u0);
    final across = point.radius * (0.42 + 0.38 * u1);
    final rot = u2 * math.pi;
    canvas.save();
    canvas.translate(point.screen.dx, point.screen.dy);
    canvas.rotate(rot);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(along * 0.06, across * 0.03),
        width: along * 1.75,
        height: across * 1.75,
      ),
      Paint()..color = ink.withValues(alpha: 0.48 * point.fade),
    );
    canvas.restore();
  }

  bool _stampVisible(String friendId, FriendTrailStamp stamp) {
    final world = Vector3(stamp.xz.dx, lift, stamp.xz.dy);
    if (hideFriendOverlay(
      position: world,
      volumes: volumes,
      interiorOpen: interiorOpen,
    )) {
      return false;
    }
    final visibleTile = tileVisible;
    final store = volumes;
    if (store != null && visibleTile != null) {
      final tile = store.grid.tileAtWorld(world);
      if (tile == null || !visibleTile(tile.$1, tile.$2)) return false;
    }
    final friend = friends?.byId(friendId);
    if (friend != null) {
      final dx = friend.position.x - stamp.xz.dx;
      final dz = friend.position.z - stamp.xz.dy;
      if (dx * dx + dz * dz < _skipRadius * _skipRadius) return false;
    }
    return true;
  }

  static double _unit(int seed, int salt) {
    var x = seed ^ (salt * 0x9e3779b9);
    x = 0x45d9f3b * ((x >> 16) ^ x);
    x = 0x45d9f3b * ((x >> 16) ^ x);
    return (((x >> 16) ^ x) & 0xffff) / 0xffff;
  }

  @override
  bool shouldRepaint(covariant _TrailPainter oldDelegate) => true;
}
