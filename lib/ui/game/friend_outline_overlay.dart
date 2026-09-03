import 'package:flutter/material.dart';

import '../../gameplay/friends/friend_instance_store.dart';
import '../../gameplay/outlines/friend_outline.dart';
import '../../gameplay/outlines/outline_paint.dart';
import '../../gameplay/volumes/volume.dart';
import '../../gameplay/volumes/volume_store.dart';
import '../../rendering/scene/camera.dart';
import '../../rendering/scene/scene.dart';

/// Outer body creases of placed friends, drawn on top of the 3D scene.
class FriendOutlineOverlay extends StatelessWidget {
  const FriendOutlineOverlay({
    super.key,
    required this.friends,
    required this.camera,
    required this.viewport,
    required this.tileSize,
    this.volumes,
    this.subtilesPerTile = VolumeGrid.defaultSubtilesPerTile,
    this.listenable,
    this.color = kWorldOutlineColor,
  });

  final FriendInstanceStore friends;
  final Camera camera;
  final Size viewport;
  final double tileSize;
  final VolumeStore? volumes;
  final int subtilesPerTile;
  final Scene? listenable;
  final Color color;

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
        painter: _FriendOutlinePainter(
          friends: friends,
          camera: camera,
          viewport: viewport,
          tileSize: tileSize,
          volumes: volumes,
          subtilesPerTile: subtilesPerTile,
          color: color,
        ),
      ),
    );
  }
}

class _FriendOutlinePainter extends CustomPainter {
  _FriendOutlinePainter({
    required this.friends,
    required this.camera,
    required this.viewport,
    required this.tileSize,
    this.volumes,
    required this.subtilesPerTile,
    required this.color,
  });

  final FriendInstanceStore friends;
  final Camera camera;
  final Size viewport;
  final double tileSize;
  final VolumeStore? volumes;
  final int subtilesPerTile;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (friends.instances.isEmpty) return;
    paintOutlineEdges(
      canvas: canvas,
      edges: buildFriendOutlines(
        friends: friends,
        tileSize: tileSize,
        subtilesPerTile: subtilesPerTile,
        volumes: volumes,
      ),
      camera: camera,
      viewport: viewport,
      color: color,
    );
  }

  @override
  bool shouldRepaint(covariant _FriendOutlinePainter oldDelegate) => true;
}
