import 'package:flutter/material.dart';

import 'snap_rules.dart';

const Map<SnapUser, String> _kUserLabels = {
  SnapUser.straightCut: 'Straight cut',
  SnapUser.scissors: 'Scissors',
  SnapUser.folder: 'Folder',
  SnapUser.straightEdge: 'Straight edge',
  SnapUser.exacto: 'Exacto',
  SnapUser.paperMove: 'Move paper',
  SnapUser.islandMove: 'Move island',
};

const Map<SnapTarget, String> _kTargetLabels = {
  SnapTarget.craftGrid: 'Grid',
  SnapTarget.paperVertex: 'Paper\ncorner',
  SnapTarget.paperEdge: 'Paper\nedge',
  SnapTarget.blueprintVertex: 'Net\ncorner',
  SnapTarget.blueprintEdge: 'Net\nedge',
};

const double _kLabelWidth = 68;
const double _kCell = 30;

/// The Snap page of the craft room's DevTools: one row per thing that snaps,
/// one box per thing it may snap to, and Free, which turns its snapping off.
class SnapRulesPage extends StatelessWidget {
  const SnapRulesPage({super.key, required this.settings});

  final SnapSettings settings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final rules = settings.rules;
        const header = TextStyle(
          color: Colors.white54,
          fontSize: 9,
          height: 1.1,
        );
        return Column(
          key: const Key('snap-rules'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'What each tool and move snaps to. Free leaves it where the pointer is.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 10,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const SizedBox(width: _kLabelWidth),
                for (final target in SnapTarget.values)
                  SizedBox(
                    width: _kCell,
                    child: Text(
                      _kTargetLabels[target]!,
                      textAlign: TextAlign.center,
                      style: header,
                    ),
                  ),
                const SizedBox(
                  width: _kCell,
                  child: Text(
                    'Free',
                    textAlign: TextAlign.center,
                    style: header,
                  ),
                ),
              ],
            ),
            for (final user in SnapUser.values)
              Row(
                children: [
                  SizedBox(
                    width: _kLabelWidth,
                    child: Text(
                      _kUserLabels[user]!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  for (final target in SnapTarget.values)
                    _Box(
                      boxKey: Key('snap-${user.name}-${target.name}'),
                      on: rules[user].targets.contains(target),
                      dim: rules[user].free,
                      onChanged: (on) => settings.toggle(user, target, on),
                    ),
                  _Box(
                    boxKey: Key('snap-${user.name}-free'),
                    on: rules[user].free,
                    onChanged: (on) => settings.setFree(user, on),
                  ),
                ],
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                const SizedBox(
                  width: 68,
                  child: Text(
                    'Paper grid',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
                Expanded(
                  child: Slider(
                    key: const Key('paper-grid-opacity'),
                    value: settings.paperGridOpacity,
                    divisions: 20,
                    activeColor: Colors.white70,
                    inactiveColor: Colors.white24,
                    onChanged: (value) => settings.paperGridOpacity = value,
                  ),
                ),
                SizedBox(
                  width: 32,
                  child: Text(
                    '${(settings.paperGridOpacity * 100).round()}%',
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            GestureDetector(
              key: const Key('snap-defaults'),
              onTap: () => settings.rules = const SnapRules(),
              child: const Text(
                'Restore defaults',
                style: TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({
    required this.boxKey,
    required this.on,
    required this.onChanged,
    this.dim = false,
  });

  final Key boxKey;
  final bool on;
  final bool dim;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final color = Colors.white.withValues(alpha: dim ? 0.3 : 0.8);
    return GestureDetector(
      key: boxKey,
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!on),
      child: SizedBox(
        width: _kCell,
        height: 26,
        child: Center(
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: on ? color : Colors.transparent,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: color, width: 1.4),
            ),
            child: on
                ? const Icon(Icons.check, size: 12, color: Color(0xFF1A1A1A))
                : null,
          ),
        ),
      ),
    );
  }
}
