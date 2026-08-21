import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../rendering/scene/camera.dart';

/// Places [child] in a [Stack] at the projected screen position of [world].
class ProjectedWorldAnchor extends StatelessWidget {
  const ProjectedWorldAnchor({
    super.key,
    required this.camera,
    required this.viewport,
    required this.world,
    required this.size,
    required this.child,
    this.rotation = 0,
  });

  final Camera camera;
  final Size viewport;
  final Vector3 world;
  final Size size;
  final Widget child;
  final double rotation;

  @override
  Widget build(BuildContext context) {
    final screen = camera.projectToScreen(world, viewport);
    if (screen == null) return const SizedBox.shrink();
    Widget content = child;
    if (rotation != 0) {
      content = Transform.rotate(angle: rotation, child: content);
    }
    return Positioned(
      left: screen.dx - size.width * 0.5,
      top: screen.dy - size.height * 0.5,
      width: size.width,
      height: size.height,
      child: content,
    );
  }
}
