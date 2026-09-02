import 'package:flutter/material.dart';

import '../volumes/volume.dart';
import '../volumes/volume_program.dart';
import 'selectable.dart';

enum SelectionActionId { isolate, program, delete, focusFace, focusFriend }

class SelectionActionSpec {
  const SelectionActionSpec({
    required this.id,
    required this.label,
    required this.icon,
  });

  final SelectionActionId id;
  final String label;
  final IconData icon;
}

/// Actions currently valid for [hit], inferred from stores — never isolate
/// just because a click happened.
List<SelectionActionSpec> inferSelectionActions({
  required SelectableHit hit,
  Volume? volume,
  VolumeProgramStore? programs,
}) {
  switch (hit.kind) {
    case SelectableKind.tile:
    case SelectableKind.region:
    case SelectableKind.path:
      return const [
        SelectionActionSpec(
          id: SelectionActionId.isolate,
          label: 'Isolate',
          icon: Icons.filter_center_focus,
        ),
      ];
    case SelectableKind.volume:
      return [
        const SelectionActionSpec(
          id: SelectionActionId.isolate,
          label: 'Isolate',
          icon: Icons.filter_center_focus,
        ),
        if (volume != null && (programs?.canAssignToVolume(volume) ?? false))
          const SelectionActionSpec(
            id: SelectionActionId.program,
            label: 'Program',
            icon: Icons.weekend_outlined,
          ),
        const SelectionActionSpec(
          id: SelectionActionId.delete,
          label: 'Delete',
          icon: Icons.delete_outline,
        ),
      ];
    case SelectableKind.volumeFace:
      return const [
        SelectionActionSpec(
          id: SelectionActionId.isolate,
          label: 'Isolate',
          icon: Icons.filter_center_focus,
        ),
        SelectionActionSpec(
          id: SelectionActionId.focusFace,
          label: 'Focus face',
          icon: Icons.crop_landscape,
        ),
      ];
    case SelectableKind.friend:
      return const [
        SelectionActionSpec(
          id: SelectionActionId.focusFriend,
          label: 'Focus',
          icon: Icons.center_focus_strong,
        ),
      ];
  }
}

/// Volume mass / face isolate opens the roof-off interior viewer, not crop isolate.
bool isolateOpensVolumeInterior(SelectableHit hit) => hit.volumeId != null;
