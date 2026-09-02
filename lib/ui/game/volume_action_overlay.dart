import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../gameplay/volumes/volume.dart';
import '../../gameplay/volumes/volume_store.dart';
import '../../rendering/scene/camera.dart';
import 'projected_world_anchor.dart';

const _kActionSize = 34.0;

/// Crafting-style corner orbs on the selected volume: delete, join, disconnect.
class VolumeActionOverlay extends StatelessWidget {
  const VolumeActionOverlay({
    super.key,
    required this.store,
    required this.camera,
    required this.viewport,
    required this.onDelete,
    required this.onJoin,
    required this.onDisconnect,
  });

  final VolumeStore store;
  final Camera camera;
  final Size viewport;
  final VoidCallback onDelete;
  final VoidCallback onJoin;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final volume = store.draftVolume;
    final cell = store.draftCell;
    if (volume == null || cell == null || !store.isEditing) {
      return const SizedBox.shrink();
    }

    final corners = cell.box.worldCorners(store.grid, cell.tx, cell.ty);
    final top = [corners[4], corners[5], corners[6], corners[7]];
    final canJoin = store.neighborsOf(volume).isNotEmpty;
    final canDisconnect = volume.cells.length > 1;

    final actions = <(Vector3, Widget)>[
      (
        top[0],
        _ActionOrb(
          icon: Icons.delete_outline,
          tooltip: 'Delete',
          tint: const Color(0xFF90A4AE),
          onTap: onDelete,
        ),
      ),
      if (canJoin)
        (
          top[1],
          _ActionOrb(
            icon: Icons.link,
            tooltip: 'Join',
            tint: const Color(0xFF42A5F5),
            onTap: onJoin,
          ),
        ),
      if (canDisconnect)
        (
          top[3],
          _ActionOrb(
            icon: Icons.link_off,
            tooltip: 'Disconnect',
            tint: const Color(0xFF66BB6A),
            onTap: onDisconnect,
          ),
        ),
    ];

    return Stack(
      fit: StackFit.expand,
      children: [
        for (final (world, child) in actions)
          ProjectedWorldAnchor(
            camera: camera,
            viewport: viewport,
            world: world,
            size: const Size(_kActionSize, _kActionSize),
            child: child,
          ),
      ],
    );
  }
}

class _ActionOrb extends StatelessWidget {
  const _ActionOrb({
    required this.icon,
    required this.tooltip,
    required this.tint,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Color.lerp(Colors.black, tint, 0.2)!.withValues(alpha: 0.85),
        shape: CircleBorder(
          side: BorderSide(color: tint.withValues(alpha: 0.45)),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: _kActionSize,
            height: _kActionSize,
            child: Icon(icon, color: Colors.white, size: 16),
          ),
        ),
      ),
    );
  }
}
