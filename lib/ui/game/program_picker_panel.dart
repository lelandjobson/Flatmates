import 'package:flutter/material.dart';

import '../../gameplay/volumes/volume_program.dart';

/// Scrollable list of programs for the current indoor/outdoor surface.
class ProgramPickerPanel extends StatelessWidget {
  const ProgramPickerPanel({
    super.key,
    required this.programs,
    required this.onSelect,
    this.selectedId,
    this.title = 'Program',
  });

  final List<ProgramSpec> programs;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final spec in programs)
                  _ProgramTile(
                    spec: spec,
                    selected: spec.id == selectedId,
                    onTap: () => onSelect(spec.id),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgramTile extends StatelessWidget {
  const _ProgramTile({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  final ProgramSpec spec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: spec.color, width: 2),
                ),
                child: Icon(spec.icon, size: 14, color: spec.color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  spec.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
