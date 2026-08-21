import 'package:flutter/material.dart';

import '../../gameplay/tools/tool_3d.dart';
import '../../rendering/scene/camera.dart';

/// Invisible 2D frame around a [Tool3d] work area, with HUD at its corners.
class Tool3dWorkAreaLayer extends StatelessWidget {
  const Tool3dWorkAreaLayer({
    super.key,
    required this.camera,
    required this.viewport,
    required this.tool,
    this.pad = kTool3dWorkAreaPad,
    this.listenable,
    this.topLeft,
    this.topRight,
    this.bottomLeft,
    this.bottomRight,
  });

  final Camera camera;
  final Size viewport;
  final Tool3d tool;
  final EdgeInsets pad;
  final Listenable? listenable;
  final Widget? topLeft;
  final Widget? topRight;
  final Widget? bottomLeft;
  final Widget? bottomRight;

  @override
  Widget build(BuildContext context) {
    final listenable = this.listenable;
    if (listenable != null) {
      return ListenableBuilder(
        listenable: listenable,
        builder: (context, _) => _buildFrame(),
      );
    }
    return _buildFrame();
  }

  Widget _buildFrame() {
    final frame = Tool3dScreenFrame.project(
      camera: camera,
      viewport: viewport,
      worldPoints: tool.workAreaPoints,
      pad: pad,
    );
    if (frame == null) return const SizedBox.shrink();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (topLeft != null)
          _corner(frame, Tool3dCorner.topLeft, topLeft!),
        if (topRight != null)
          _corner(frame, Tool3dCorner.topRight, topRight!),
        if (bottomLeft != null)
          _corner(frame, Tool3dCorner.bottomLeft, bottomLeft!),
        if (bottomRight != null)
          _corner(frame, Tool3dCorner.bottomRight, bottomRight!),
      ],
    );
  }

  Widget _corner(Tool3dScreenFrame frame, Tool3dCorner corner, Widget child) {
    final p = frame.corner(corner);
    return Positioned(
      left: p.dx,
      top: p.dy,
      child: FractionalTranslation(
        translation: _anchor(corner),
        child: child,
      ),
    );
  }

  static Offset _anchor(Tool3dCorner corner) => switch (corner) {
        Tool3dCorner.topLeft => const Offset(0, 0),
        Tool3dCorner.topRight => const Offset(-1, 0),
        Tool3dCorner.bottomLeft => const Offset(0, -1),
        Tool3dCorner.bottomRight => const Offset(-1, -1),
      };
}
