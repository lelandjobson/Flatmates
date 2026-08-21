import 'package:flutter/painting.dart';
import 'package:vector_math/vector_math_64.dart';

import '../../rendering/scene/camera.dart';

/// A 3D editing tool that exposes its current work as world-space points.
///
/// Project [workAreaPoints] with [Tool3dScreenFrame.project] to get a 2D
/// bounding box, then anchor HUD at that box's corners.
abstract interface class Tool3d {
  /// World samples that span the tool's effective work (typically AABB corners).
  Iterable<Vector3> get workAreaPoints;
}

/// Corners of the projected 2D work-area box.
enum Tool3dCorner { topLeft, topRight, bottomLeft, bottomRight }

/// Screen-space AABB around a [Tool3d] work area, padded for HUD.
class Tool3dScreenFrame {
  const Tool3dScreenFrame(this.bounds);

  final Rect bounds;

  Offset corner(Tool3dCorner corner) => switch (corner) {
        Tool3dCorner.topLeft => bounds.topLeft,
        Tool3dCorner.topRight => bounds.topRight,
        Tool3dCorner.bottomLeft => bounds.bottomLeft,
        Tool3dCorner.bottomRight => bounds.bottomRight,
      };

  /// Project [worldPoints] to the viewport, take their 2D AABB, then inflate
  /// by [pad]. Returns null when nothing is in front of the camera.
  static Tool3dScreenFrame? project({
    required Camera camera,
    required Size viewport,
    required Iterable<Vector3> worldPoints,
    EdgeInsets pad = kTool3dWorkAreaPad,
    double screenMargin = 24,
  }) {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    var any = false;

    for (final world in worldPoints) {
      final screen = camera.projectToScreen(world, viewport);
      if (screen == null) continue;
      any = true;
      if (screen.dx < minX) minX = screen.dx;
      if (screen.dy < minY) minY = screen.dy;
      if (screen.dx > maxX) maxX = screen.dx;
      if (screen.dy > maxY) maxY = screen.dy;
    }
    if (!any) return null;

    var left = minX - pad.left;
    var top = minY - pad.top;
    var right = maxX + pad.right;
    var bottom = maxY + pad.bottom;

    final maxLeft = viewport.width - screenMargin;
    final maxTop = viewport.height - screenMargin;
    if (maxLeft < screenMargin || maxTop < screenMargin) {
      return Tool3dScreenFrame(Rect.fromLTRB(left, top, right, bottom));
    }

    left = left.clamp(screenMargin, maxLeft);
    top = top.clamp(screenMargin, maxTop);
    right = right.clamp(screenMargin, maxLeft);
    bottom = bottom.clamp(screenMargin, maxTop);
    if (right < left) {
      final mid = ((left + right) * 0.5).clamp(screenMargin, maxLeft);
      left = mid;
      right = mid;
    }
    if (bottom < top) {
      final mid = ((top + bottom) * 0.5).clamp(screenMargin, maxTop);
      top = mid;
      bottom = mid;
    }

    return Tool3dScreenFrame(Rect.fromLTRB(left, top, right, bottom));
  }
}

/// Padding applied after projecting a tool's 3D work area into 2D.
const kTool3dWorkAreaPad = EdgeInsets.all(52);
