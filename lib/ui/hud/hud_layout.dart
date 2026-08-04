import 'package:flutter/material.dart';
import '../../rendering/iso/iso_coordinate.dart';
import '../../rendering/iso/iso_camera.dart';

/// Base class for HUD overlays anchored to a world-space coordinate.
///
/// Subclasses implement [buildOverlay] to render content at the screen
/// position of [anchor]. The overlay repositions every frame as the
/// camera pans or zooms.
abstract class HudLayout extends StatelessWidget {
  const HudLayout({
    super.key,
    required this.anchor,
    required this.camera,
    required this.viewport,
  });

  final IsoCoordinate anchor;
  final IsoCamera camera;
  final Size viewport;

  /// Screen-space center of the anchor tile.
  Offset get screenCenter => anchor.toScreen(camera, viewport);

  /// Override to build the actual overlay content.
  Widget buildOverlay(BuildContext context, Offset center);

  @override
  Widget build(BuildContext context) {
    final center = screenCenter;
    return buildOverlay(context, center);
  }
}
