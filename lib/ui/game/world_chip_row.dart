import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../gameplay/volumes/volume_program.dart';
import '../../rendering/scene/camera.dart';
import 'projected_world_anchor.dart';

const kWorldChipSize = 28.0;
const kWorldChipGap = 4.0;
const kWorldChipPad = 4.0;

const kAlertOutline = Color(0xFFE53935);

class WorldChip {
  const WorldChip({
    required this.icon,
    required this.color,
    this.tooltip,
    this.iconColor,
    this.alert = false,
  });

  final IconData icon;
  final Color color;
  final Color? iconColor;
  final String? tooltip;
  final bool alert;
}

Size worldChipRowSize(int count) {
  final n = count.clamp(0, kMaxProgramChips);
  if (n <= 0) return Size.zero;
  return Size(
    n * kWorldChipSize + (n - 1) * kWorldChipGap + kWorldChipPad * 2,
    kWorldChipSize + kWorldChipPad * 2,
  );
}

/// Horizontal row of circular icon chips (alerts or program possession).
class WorldChipRow extends StatelessWidget {
  const WorldChipRow({super.key, required this.chips});

  final List<WorldChip> chips;

  @override
  Widget build(BuildContext context) {
    final shown = chips.take(kMaxProgramChips).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const SizedBox(width: kWorldChipGap),
          _Chip(chip: shown[i]),
        ],
      ],
    );
  }
}

class WorldChipAnchor extends StatelessWidget {
  const WorldChipAnchor({
    super.key,
    required this.camera,
    required this.viewport,
    required this.world,
    required this.chips,
  });

  final Camera camera;
  final Size viewport;
  final Vector3 world;
  final List<WorldChip> chips;

  @override
  Widget build(BuildContext context) {
    final shown = chips.take(kMaxProgramChips).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    final size = worldChipRowSize(shown.length);
    return ProjectedWorldAnchor(
      camera: camera,
      viewport: viewport,
      world: world,
      size: size,
      child: WorldChipRow(chips: shown),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.chip});

  final WorldChip chip;

  @override
  Widget build(BuildContext context) {
    final circle = Container(
      width: kWorldChipSize,
      height: kWorldChipSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.62),
        border: Border.all(
          color: chip.alert ? kAlertOutline : chip.color,
          width: 2,
        ),
      ),
      child: Icon(
        chip.icon,
        size: 16,
        color: chip.iconColor ?? chip.color,
      ),
    );
    final tooltip = chip.tooltip;
    if (tooltip == null || tooltip.isEmpty) return circle;
    return Tooltip(message: tooltip, child: circle);
  }
}

const kUnprogrammedAlertChip = WorldChip(
  icon: Icons.priority_high,
  color: Color(0xFFFFC107),
  iconColor: Color(0xFFFFF8E1),
  tooltip: 'Unprogrammed',
  alert: true,
);

const kNoEntryAlertChip = WorldChip(
  icon: Icons.door_front_door_outlined,
  color: Color(0xFFFFC107),
  iconColor: Color(0xFFFFF8E1),
  tooltip: 'No entry',
  alert: true,
);

const kBedroomAccessAlertChip = WorldChip(
  icon: Icons.bed_outlined,
  color: Color(0xFFFFC107),
  iconColor: Color(0xFFFFF8E1),
  tooltip: 'Bedroom needs circulation or a door',
  alert: true,
);

const kUnprogrammedQuestionChip = WorldChip(
  icon: Icons.question_mark,
  color: Color(0xFFBDBDBD),
  iconColor: Color(0xFFFAFAFA),
  tooltip: 'Unprogrammed',
);

WorldChip programChip(ProgramSpec spec) => WorldChip(
      icon: spec.icon,
      color: spec.color,
      tooltip: spec.label,
    );
