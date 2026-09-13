import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../gameplay/friends/desire_cloud_shape.dart';
import '../../gameplay/friends/emotion_tone.dart';
import '../../gameplay/friends/friend_desire.dart';
import '../../gameplay/friends/friend_feeling.dart';
import '../../gameplay/friends/friend_instance.dart';
import '../../gameplay/friends/friend_instance_store.dart';
import '../../gameplay/friends/friend_overlay_visibility.dart';
import '../../gameplay/friends/friend_thought_display.dart';
import '../../gameplay/friends/friend_thought_layout.dart';
import '../../gameplay/volumes/volume_store.dart';
import '../../rendering/scene/camera.dart';
import '../../rendering/scene/scene.dart';

/// World-projected feeling cards, desire clouds, and percolating teaser dots.
class FriendThoughtOverlay extends StatelessWidget {
  const FriendThoughtOverlay({
    super.key,
    required this.friends,
    required this.camera,
    required this.viewport,
    this.display = const FriendThoughtDisplay(),
    this.tileSize = 8,
    this.volumes,
    this.interiorOpen,
    this.listenable,
  });

  final FriendInstanceStore friends;
  final Camera camera;
  final Size viewport;
  final FriendThoughtDisplay display;
  final double tileSize;
  final VolumeStore? volumes;
  final bool Function(int tx, int ty)? interiorOpen;
  final Scene? listenable;

  @override
  Widget build(BuildContext context) {
    final listenable = this.listenable;
    if (listenable != null) {
      return ListenableBuilder(
        listenable: listenable,
        builder: (context, _) => _stack(),
      );
    }
    return _stack();
  }

  Widget _stack() {
    if (viewport.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final friend in friends.instances)
            if (_visible(friend)) _FriendThoughtMarker(friend: friend, overlay: this),
        ],
      ),
    );
  }

  bool _visible(FriendInstance friend) {
    if (hideFriendOverlay(
      position: friend.position,
      volumes: volumes,
      interiorOpen: interiorOpen,
    )) {
      return false;
    }
    return display.showsAny(friend.thought);
  }
}

class _FriendThoughtMarker extends StatelessWidget {
  const _FriendThoughtMarker({required this.friend, required this.overlay});

  final FriendInstance friend;
  final FriendThoughtOverlay overlay;

  @override
  Widget build(BuildContext context) {
    final thought = friend.thought;
    final display = overlay.display;
    final showCloud = display.showsDesireCloud(thought);
    final showFeeling = display.showsFeelingCard(thought);
    final showPercolate = display.showsPercolate(thought);
    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (showCloud || showFeeling)
            _cards(showCloud: showCloud, showFeeling: showFeeling),
          if (showPercolate && thought.desire != null) _percolate(),
        ],
      ),
    );
  }

  Widget _cards({required bool showCloud, required bool showFeeling}) {
    final screen = overlay.camera.projectToScreen(
      thoughtAnchor(friend, tileSize: overlay.tileSize),
      overlay.viewport,
    );
    if (screen == null) return const SizedBox.shrink();
    const width = 140.0;
    final height = 28.0 + (showCloud ? 88.0 : 0) + (showFeeling ? 48.0 : 0);
    return Positioned(
      left: screen.dx - width * 0.5,
      top: screen.dy - height,
      width: width,
      height: height,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (showCloud && friend.thought.desire != null)
            _DesireCloud(
              desire: friend.thought.desire!,
              shape: desireCloudForSeed(friend.id),
            ),
          if (showFeeling && friend.thought.feeling != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _FeelingCard(feeling: friend.thought.feeling!),
            ),
        ],
      ),
    );
  }

  Widget _percolate() {
    final screen = overlay.camera.projectToScreen(
      percolateAnchor(friend, tileSize: overlay.tileSize),
      overlay.viewport,
    );
    if (screen == null) return const SizedBox.shrink();
    const width = 56.0;
    const height = 36.0;
    return Positioned(
      left: screen.dx - width * 0.5,
      top: screen.dy - height,
      width: width,
      height: height,
      child: CustomPaint(
        painter: _PercolatePainter(
          time: friend.thought.percolateTime,
          color: emotionSwatch(friend.thought.desire!.tone).percolate,
        ),
      ),
    );
  }
}

class _FeelingCard extends StatelessWidget {
  const _FeelingCard({required this.feeling});

  final Feeling feeling;

  @override
  Widget build(BuildContext context) {
    final swatch = emotionSwatch(feeling.tone);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: swatch.fill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: swatch.stroke, width: 1.4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: _ThoughtLabel(icon: feeling.icon, name: feeling.name),
      ),
    );
  }
}

class _DesireCloud extends StatelessWidget {
  const _DesireCloud({required this.desire, required this.shape});

  final Desire desire;
  final DesireCloudShape shape;

  @override
  Widget build(BuildContext context) {
    final swatch = emotionSwatch(desire.tone);
    final focus = puffCentroid(shape);
    return SizedBox(
      width: 140,
      height: 88,
      child: CustomPaint(
        painter: _CloudPainter(fill: swatch.fill, shape: shape),
        child: Align(
          alignment: Alignment(focus.dx * 2 - 1, focus.dy * 2 - 1),
          child: Text(
            desire.icon,
            style: const TextStyle(fontSize: 26, height: 1),
          ),
        ),
      ),
    );
  }
}

class _ThoughtLabel extends StatelessWidget {
  const _ThoughtLabel({required this.icon, required this.name});

  final String icon;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(icon, style: const TextStyle(fontSize: 16, height: 1)),
        const SizedBox(width: 6),
        Text(
          name,
          style: const TextStyle(
            color: Color(0xFF2A2A2A),
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}

class _CloudPainter extends CustomPainter {
  _CloudPainter({required this.fill, required this.shape});

  final Color fill;
  final DesireCloudShape shape;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = fill
      ..style = PaintingStyle.fill;
    void draw(CloudCircle circle) {
      canvas.drawCircle(
        Offset(circle.center.dx * size.width, circle.center.dy * size.height),
        circle.radius * size.width,
        paint,
      );
    }

    for (final puff in shape.puffs) {
      draw(puff);
    }
    for (final dot in shape.tail) {
      draw(dot);
    }
  }

  @override
  bool shouldRepaint(covariant _CloudPainter oldDelegate) =>
      fill != oldDelegate.fill || shape != oldDelegate.shape;
}

class _PercolatePainter extends CustomPainter {
  _PercolatePainter({required this.time, required this.color});

  final double time;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width * 0.5;
    final baseY = size.height - 4;
    for (var i = 0; i < 3; i++) {
      final t = (time * 0.65 + i * 0.33) % 1.0;
      final x = cx + math.sin((time + i) * 2.1) * 7;
      final y = baseY - t * (size.height - 8);
      final opacity = (1 - t) * 0.9;
      final r = 2.4 + (1 - t) * 2.8;
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = color.withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PercolatePainter oldDelegate) =>
      time != oldDelegate.time || color != oldDelegate.color;
}
