import 'package:flutter/material.dart';

import '../../gameplay/stuff/stuff_catalog.dart';

/// Scrollable list of stuff a program can possess.
class StuffPickerPanel extends StatelessWidget {
  const StuffPickerPanel({
    super.key,
    required this.items,
    required this.onSelect,
    this.title = 'Stuff',
  });

  final List<StuffSpec> items;
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
                for (final spec in items)
                  _StuffTile(
                    spec: spec,
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

class _StuffTile extends StatelessWidget {
  const _StuffTile({required this.spec, required this.onTap});

  final StuffSpec spec;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          child: Row(
            children: [
              Icon(spec.icon, size: 18, color: Colors.white),
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
              Text(
                '${spec.paperCost}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
