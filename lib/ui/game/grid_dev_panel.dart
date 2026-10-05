import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../gridcraft/scrap.dart';

enum _GridDevSection { tapDebug, paperScore, camera }

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
  });

  final bool showTapDebug;
  final ValueChanged<bool> onShowTapDebugChanged;
  final ScrapTallyStyle tallyStyle;
  final ValueChanged<ScrapTallyStyle> onTallyStyleChanged;
  final bool cameraFollowsTool;
  final ValueChanged<bool> onCameraFollowsToolChanged;
  final bool cameraRotates;
  final ValueChanged<bool> onCameraRotatesChanged;

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
    );
  }
}

class _CameraSettings extends StatelessWidget {
  const _CameraSettings({
    required this.followsTool,
    required this.onFollowChanged,
    required this.rotates,
    required this.onRotateChanged,
  });

  final bool followsTool;
  final ValueChanged<bool> onFollowChanged;
  final bool rotates;
  final ValueChanged<bool> onRotateChanged;

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
