import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../gridcraft/scrap.dart';

enum _GridDevSection { tapDebug, paperScore, camera, folding, input }

/// What a tap picks in 3D: by the pointer's own kind, or forced to the PC
/// cursor or the mobile reticle for any pointer.
enum GridAimMode { auto, cursor, reticle }

/// Right-hand puzzle DevTools. The dropdown picks which settings to edit.
class GridDevPanel extends StatefulWidget {
  const GridDevPanel({
    super.key,
    required this.showTapDebug,
    required this.onShowTapDebugChanged,
    required this.tallyStyle,
    required this.onTallyStyleChanged,
    required this.cameraFollowsTool,
    required this.onCameraFollowsToolChanged,
    required this.cameraRotates,
    required this.onCameraRotatesChanged,
    required this.cutFollow,
    required this.onCutFollowChanged,
    required this.foldOverlap,
    required this.onFoldOverlapChanged,
    required this.aimMode,
    required this.onAimModeChanged,
  });

  final bool showTapDebug;
  final ValueChanged<bool> onShowTapDebugChanged;
  final ScrapTallyStyle tallyStyle;
  final ValueChanged<ScrapTallyStyle> onTallyStyleChanged;
  final bool cameraFollowsTool;
  final ValueChanged<bool> onCameraFollowsToolChanged;
  final bool cameraRotates;
  final ValueChanged<bool> onCameraRotatesChanged;

  /// 0–1: how far a 3D pattern cut's camera turns from square to the
  /// blade's face toward the blade as seen from the model's middle.
  final double cutFollow;
  final ValueChanged<double> onCutFollowChanged;

  /// 0–1: how much of each fold the next one overlaps as a finished cut
  /// folds round the model.
  final double foldOverlap;
  final ValueChanged<double> onFoldOverlapChanged;
  final GridAimMode aimMode;
  final ValueChanged<GridAimMode> onAimModeChanged;

  @override
  State<GridDevPanel> createState() => _GridDevPanelState();
}

class _GridDevPanelState extends State<GridDevPanel> {
  _GridDevSection _section = _GridDevSection.tapDebug;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    final maxHeight = height.isFinite ? math.min(520.0, height * 0.72) : 520.0;
    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 272, maxHeight: maxHeight),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xE61A1A1A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white24),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: ListView(
              key: const Key('grid-dev-panel'),
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              children: [
                const Text(
                  'DevTools',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Settings',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
                DropdownButtonHideUnderline(
                  child: DropdownButton<_GridDevSection>(
                    key: const Key('grid-dev-section'),
                    isExpanded: true,
                    isDense: true,
                    dropdownColor: const Color(0xFF1A1A1A),
                    value: _section,
                    iconEnabledColor: Colors.white70,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    items: const [
                      DropdownMenuItem(
                        value: _GridDevSection.tapDebug,
                        child: Text('Tap debug'),
                      ),
                      DropdownMenuItem(
                        value: _GridDevSection.paperScore,
                        child: Text('Paper score'),
                      ),
                      DropdownMenuItem(
                        value: _GridDevSection.camera,
                        child: Text('Camera'),
                      ),
                      DropdownMenuItem(
                        value: _GridDevSection.folding,
                        child: Text('Folding'),
                      ),
                      DropdownMenuItem(
                        value: _GridDevSection.input,
                        child: Text('Input'),
                      ),
                    ],
                    onChanged: (section) {
                      if (section == null) return;
                      setState(() => _section = section);
                    },
                  ),
                ),
                const SizedBox(height: 8),
                if (_section == _GridDevSection.paperScore)
                  _PaperScoreSettings(
                    style: widget.tallyStyle,
                    onChanged: widget.onTallyStyleChanged,
                  )
                else if (_section == _GridDevSection.camera)
                  _CameraSettings(
                    followsTool: widget.cameraFollowsTool,
                    onFollowChanged: widget.onCameraFollowsToolChanged,
                    rotates: widget.cameraRotates,
                    onRotateChanged: widget.onCameraRotatesChanged,
                    cutFollow: widget.cutFollow,
                    onCutFollowChanged: widget.onCutFollowChanged,
                  )
                else if (_section == _GridDevSection.folding)
                  _FoldingSettings(
                    overlap: widget.foldOverlap,
                    onChanged: widget.onFoldOverlapChanged,
                  )
                else if (_section == _GridDevSection.input)
                  _InputSettings(
                    mode: widget.aimMode,
                    onChanged: widget.onAimModeChanged,
                  )
                else
                  _TapDebugSettings(
                    show: widget.showTapDebug,
                    onChanged: widget.onShowTapDebugChanged,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CameraSettings extends StatelessWidget {
  const _CameraSettings({
    required this.followsTool,
    required this.onFollowChanged,
    required this.rotates,
    required this.onRotateChanged,
    required this.cutFollow,
    required this.onCutFollowChanged,
  });

  final bool followsTool;
  final ValueChanged<bool> onFollowChanged;
  final bool rotates;
  final ValueChanged<bool> onRotateChanged;
  final double cutFollow;
  final ValueChanged<double> onCutFollowChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'The camera keeps the tool in the reticle. Rotate camera turns the sheet so each cut points up. With follow off, a cut zooms to fit and stays put, and further taps are measured from the tool.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 10,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 8),
        _CameraCheck(
          label: 'Follow tool',
          boxKey: const Key('grid-camera-follow'),
          value: followsTool,
          onChanged: onFollowChanged,
        ),
        _CameraCheck(
          label: 'Rotate camera',
          boxKey: const Key('grid-camera-rotate'),
          value: rotates,
          onChanged: onRotateChanged,
        ),
        const SizedBox(height: 12),
        Text(
          'In 3D, a pattern cut turns the camera square to the blade’s face. Blade pull turns it from there toward the blade, as seen from the model’s middle, to peek round the edge.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 10,
            height: 1.3,
          ),
        ),
        Row(
          children: [
            const Text(
              'Blade pull',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            Expanded(
              child: Slider(
                key: const Key('grid-cut-follow'),
                value: cutFollow.clamp(0.0, 1.0),
                divisions: 20,
                activeColor: Colors.white70,
                inactiveColor: Colors.white24,
                onChanged: onCutFollowChanged,
              ),
            ),
            SizedBox(
              width: 34,
              child: Text(
                '${(cutFollow * 100).round()}%',
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FoldingSettings extends StatelessWidget {
  const _FoldingSettings({required this.overlap, required this.onChanged});

  final double overlap;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'A finished cut folds round the model one fold after another, each over 250 ms. Overlap starts the next fold that much of a fold before the last one ends: 0% (the default) is one at a time, 100% all at once.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 10,
            height: 1.3,
          ),
        ),
        Row(
          children: [
            const Text(
              'Fold overlap',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            Expanded(
              child: Slider(
                key: const Key('grid-fold-overlap'),
                value: overlap.clamp(0.0, 1.0),
                divisions: 20,
                activeColor: Colors.white70,
                inactiveColor: Colors.white24,
                onChanged: onChanged,
              ),
            ),
            SizedBox(
              width: 34,
              child: Text(
                '${(overlap * 100).round()}%',
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CameraCheck extends StatelessWidget {
  const _CameraCheck({
    required this.label,
    required this.boxKey,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final Key boxKey;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          SizedBox(
            height: 24,
            width: 36,
            child: IgnorePointer(
              child: Checkbox(
                key: boxKey,
                value: value,
                onChanged: (_) {},
                side: const BorderSide(color: Colors.white54),
                fillColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return Colors.white24;
                  }
                  return Colors.transparent;
                }),
                checkColor: Colors.white,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TapDebugSettings extends StatelessWidget {
  const _TapDebugSettings({required this.show, required this.onChanged});

  final bool show;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Draws the crosshair tap and which side it chose.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 10,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(!show),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Show tap overlay',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
              SizedBox(
                height: 24,
                width: 36,
                child: IgnorePointer(
                  child: Checkbox(
                    key: const Key('grid-tap-debug'),
                    value: show,
                    onChanged: (_) {},
                    side: const BorderSide(color: Colors.white54),
                    fillColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return Colors.white24;
                      }
                      return Colors.transparent;
                    }),
                    checkColor: Colors.white,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InputSettings extends StatelessWidget {
  const _InputSettings({required this.mode, required this.onChanged});

  final GridAimMode mode;
  final ValueChanged<GridAimMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return RadioGroup<GridAimMode>(
      groupValue: mode,
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'What a tap picks in 3D. PC picks under the cursor, mobile under the reticle, whatever the pointer. The reticle always preselects the face.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 10,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          for (final option in GridAimMode.values)
            RadioListTile<GridAimMode>(
              key: Key('grid-aim-${option.name}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              activeColor: Colors.white,
              title: Text(switch (option) {
                GridAimMode.auto => 'Auto, by pointer',
                GridAimMode.cursor => 'PC: cursor',
                GridAimMode.reticle => 'Mobile: reticle',
              }, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              value: option,
            ),
        ],
      ),
    );
  }
}

class _PaperScoreSettings extends StatelessWidget {
  const _PaperScoreSettings({required this.style, required this.onChanged});

  final ScrapTallyStyle style;
  final ValueChanged<ScrapTallyStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    return RadioGroup<ScrapTallyStyle>(
      groupValue: style,
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'How leftover paper leaves at the end of a level. Each unit is one point.',
            style: TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 8),
          for (final option in ScrapTallyStyle.values)
            RadioListTile<ScrapTallyStyle>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              activeColor: Colors.white,
              title: Text(switch (option) {
                ScrapTallyStyle.shrink => 'Shrink',
                ScrapTallyStyle.shrinkThenFly => 'Shrink, then fly',
                ScrapTallyStyle.fly => 'Fly',
              }, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              value: option,
            ),
        ],
      ),
    );
  }
}
