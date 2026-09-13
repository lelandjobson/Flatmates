import 'package:flutter/material.dart';

import '../../gameplay/friends/friend_expression_pose.dart';
import '../../gameplay/friends/friend_instance.dart';
import '../../gameplay/friends/friend_instance_store.dart';
import '../../gameplay/friends/friend_mesh_sync.dart';
import '../../gameplay/friends/friend_overlay_visibility.dart';
import '../../gameplay/volumes/volume.dart';
import '../../gameplay/volumes/volume_store.dart';
import '../../rendering/scene/camera.dart';
import '../../rendering/scene/scene.dart';

/// Closed blob eyes on the friend's body-local front face. Hidden while walking.
class FriendEyeOverlay extends StatelessWidget {
  const FriendEyeOverlay({
    super.key,
    required this.friends,
    required this.camera,
    required this.viewport,
    required this.tileSize,
    this.volumes,
    this.interiorOpen,
    this.subtilesPerTile = VolumeGrid.defaultSubtilesPerTile,
    this.listenable,
  });

  final FriendInstanceStore friends;
  final Camera camera;
  final Size viewport;
  final double tileSize;
  final VolumeStore? volumes;
  final bool Function(int tx, int ty)? interiorOpen;
  final int subtilesPerTile;
  final Scene? listenable;

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
    return IgnorePointer(
      child: CustomPaint(
        size: viewport,
        painter: _FriendEyePainter(
          friends: friends,
          camera: camera,
          viewport: viewport,
          tileSize: tileSize,
          volumes: volumes,
          interiorOpen: interiorOpen,
          subtilesPerTile: subtilesPerTile,
        ),
      ),
    );
  }
}

class _FriendEyePainter extends CustomPainter {
  _FriendEyePainter({
    required this.friends,
    required this.camera,
    required this.viewport,
    required this.tileSize,
    this.volumes,
    this.interiorOpen,
    required this.subtilesPerTile,
  });

  final FriendInstanceStore friends;
  final Camera camera;
  final Size viewport;
  final double tileSize;
  final VolumeStore? volumes;
  final bool Function(int tx, int ty)? interiorOpen;
  final int subtilesPerTile;

  @override
  void paint(Canvas canvas, Size size) {
    for (final instance in friends.instances) {
      if (hideFriendOverlay(
        position: instance.position,
        volumes: volumes,
        interiorOpen: interiorOpen,
      )) {
        continue;
      }
      final opacity = instance.expression.opacity;
      if (opacity <= 0.01) continue;
      if (instance.friend.expression == null) continue;
      _drawFace(canvas, instance: instance, opacity: opacity);
    }
  }

  void _drawFace(
    Canvas canvas, {
    required FriendInstance instance,
    required double opacity,
  }) {
    final pose = instance.eyeProfile.apply(instance.expression.current);
    final fill = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;

    Offset? project(Offset face) {
      final world = FriendMeshLayout.faceWorld(
        instance: instance,
        face: face,
        tileSize: tileSize,
        subtilesPerTile: subtilesPerTile,
      );
      return camera.projectToScreen(world, viewport);
    }

    void drawEye(EyeBlob eye) {
      final screen = <Offset>[];
      for (final p in eye.ring) {
        final projected = project(p);
        if (projected == null) return;
        screen.add(projected);
      }
      canvas.drawPath(eyeBlobPath(screen), fill);
    }

    drawEye(pose.left);
    drawEye(pose.right);
  }

  @override
  bool shouldRepaint(covariant _FriendEyePainter oldDelegate) => true;
}
