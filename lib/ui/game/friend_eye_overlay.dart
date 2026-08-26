import 'package:flutter/material.dart';

import '../../gameplay/friends/friend_instance_store.dart';
import '../../gameplay/friends/friend_mesh_sync.dart';
import '../../gameplay/volumes/volume.dart';
import '../../rendering/scene/camera.dart';
import '../../rendering/scene/scene.dart';

/// White vector dots for friend eyes, projected from body-local 3D offsets.
class FriendEyeOverlay extends StatelessWidget {
  const FriendEyeOverlay({
    super.key,
    required this.friends,
    required this.camera,
    required this.viewport,
    required this.tileSize,
    this.subtilesPerTile = VolumeGrid.defaultSubtilesPerTile,
    this.listenable,
  });

  final FriendInstanceStore friends;
  final Camera camera;
  final Size viewport;
  final double tileSize;
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
    required this.subtilesPerTile,
  });

  final FriendInstanceStore friends;
  final Camera camera;
  final Size viewport;
  final double tileSize;
  final int subtilesPerTile;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final right = camera.right;

    for (final instance in friends.instances) {
      final expr = instance.friend.expression;
      if (expr == null) continue;
      final scaled = FriendMeshLayout.scaledExpression(
        expr,
        tileSize: tileSize,
        subtilesPerTile: subtilesPerTile,
      );
      for (final left in [true, false]) {
        final world = FriendMeshLayout.eyeWorld(
          instance: instance,
          left: left,
          tileSize: tileSize,
          subtilesPerTile: subtilesPerTile,
        );
        final center = camera.projectToScreen(world, viewport);
        if (center == null) continue;
        final edge = camera.projectToScreen(
          world + right * scaled.eyeRadiusX,
          viewport,
        );
        final radius = edge == null
            ? 2.0
            : (center - edge).distance.clamp(1.5, 18.0);
        canvas.drawCircle(center, radius, fill);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FriendEyePainter oldDelegate) => true;
}
