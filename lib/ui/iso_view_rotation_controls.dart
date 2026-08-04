import 'package:flutter/material.dart';

import '../rendering/iso/iso_camera.dart';

/// Reusable rotation controls for any 2.5D isometric view.
///
/// Rotates the camera through the 8 view directions (45° steps), keeping the
/// tile at the center of the screen fixed. Friend sprites and tiles update
/// automatically to match the new camera angle.
///
/// Use this in map view, benchmark view, or any other 2.5D screen. Placement
/// (e.g. bottom center) is up to the parent; this widget is just the button row.
class IsoViewRotationControls extends StatelessWidget {
  const IsoViewRotationControls({
    super.key,
    required this.camera,
    this.onRotate,
    this.heroTagPrefix = 'iso_rotate',
  });

  /// Camera to rotate. Must be the same [IsoCamera] used by the view's painter.
  final IsoCamera camera;

  /// Called after each rotation (clockwise or counter-clockwise).
  /// Use to run view-specific updates (e.g. refresh visible tiles/assets).
  final VoidCallback? onRotate;

  /// Prefix for [FloatingActionButton] hero tags to avoid conflicts when
  /// multiple 2.5D views exist in the app.
  final String heroTagPrefix;

  void _rotateClockwise() {
    camera.rotateClockwiseAroundCenter();
    onRotate?.call();
  }

  void _rotateCounterClockwise() {
    camera.rotateCounterClockwiseAroundCenter();
    onRotate?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton(
          mini: true,
          heroTag: '${heroTagPrefix}_left',
          onPressed: _rotateCounterClockwise,
          child: const Icon(Icons.rotate_left),
        ),
        const SizedBox(width: 16),
        FloatingActionButton(
          mini: true,
          heroTag: '${heroTagPrefix}_right',
          onPressed: _rotateClockwise,
          child: const Icon(Icons.rotate_right),
        ),
      ],
    );
  }
}
