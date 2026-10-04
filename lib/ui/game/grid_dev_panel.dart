import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../gridcraft/piece_glow.dart';
import '../../gridcraft/scrap.dart';

enum _GridDevSection { completedPiece, tapDebug, paperScore, camera }

/// Right-hand puzzle DevTools. The dropdown picks which settings to edit.
class GridDevPanel extends StatefulWidget {
  const GridDevPanel({
    super.key,
    required this.glow,
    required this.onGlowChanged,
    required this.onSave,
    required this.showTapDebug,
    required this.onShowTapDebugChanged,
    required this.tallyStyle,
    required this.onTallyStyleChanged,
    required this.cameraFollowsTool,
    required this.onCameraFollowsToolChanged,
    required this.cameraRotates,
    required this.onCameraRotatesChanged,
  });

  final PieceGlowSettings glow;
  final ValueChanged<PieceGlowSettings> onGlowChanged;
  final Future<void> Function() onSave;
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
  _GridDevSection _section = _GridDevSection.completedPiece;
  String _status = 'Save';

  Future<void> _save() async {
    try {
      await widget.onSave();
      if (!mounted) return;
      setState(() => _status = 'Saved');
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = 'Save failed');
    }
  }

  void _edit(PieceGlowSettings next) {
    setState(() => _status = 'Save');
    widget.onGlowChanged(next);
  }

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
                      value: _GridDevSection.completedPiece,
                      child: Text('Completed piece'),
                    ),
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
              if (_section == _GridDevSection.completedPiece)
                _CompletedPieceSettings(
                  glow: widget.glow,
                  status: _status,
                  onChanged: _edit,
                  onSave: _save,
                )
              else if (_section == _GridDevSection.paperScore)
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

class _CompletedPieceSettings extends StatelessWidget {
  const _CompletedPieceSettings({
    required this.glow,
    required this.status,
    required this.onChanged,
    required this.onSave,
  });

  final PieceGlowSettings glow;
  final String status;
  final ValueChanged<PieceGlowSettings> onChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'A finished blueprint piece blends into this color and glows.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 10,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Glow color',
          style: TextStyle(color: Colors.white70, fontSize: 11),
        ),
        const SizedBox(height: 6),
        _GlowColorPicker(
          color: glow.color,
          onChanged: (color) => onChanged(glow.copyWith(color: color)),
        ),
        const SizedBox(height: 10),
        Text(
          'Glow amount  ${(glow.amount * 100).round()}%',
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: Colors.white70,
            inactiveTrackColor: Colors.white24,
            thumbColor: Colors.white,
          ),
          child: Slider(
            key: const Key('grid-glow-amount'),
            min: 0,
            max: 1,
            value: glow.amount.clamp(0.0, 1.0),
            onChanged: (amount) => onChanged(glow.copyWith(amount: amount)),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('grid-glow-save'),
            onPressed: onSave,
            child: Text(status),
          ),
        ),
      ],
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

class _GlowColorPicker extends StatelessWidget {
  const _GlowColorPicker({required this.color, required this.onChanged});

  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    final hsv = HSVColor.fromColor(color);
    final hex = (color.toARGB32() & 0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0')
        .toUpperCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white24),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '#$hex',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _SvPad(hsv: hsv, onChanged: (next) => onChanged(next.toColor())),
        const SizedBox(height: 8),
        _HueBar(
          hue: hsv.hue,
          onChanged: (hue) => onChanged(hsv.withHue(hue).toColor()),
        ),
      ],
    );
  }
}

class _SvPad extends StatelessWidget {
  const _SvPad({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  void _pick(Offset local, Size size) {
    if (size.width < 1 || size.height < 1) return;
    final saturation = (local.dx / size.width).clamp(0.0, 1.0);
    final value = (1 - local.dy / size.height).clamp(0.0, 1.0);
    onChanged(hsv.withSaturation(saturation).withValue(value));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('grid-glow-pad'),
      height: 112,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanDown: (details) => _pick(details.localPosition, size),
            onPanUpdate: (details) => _pick(details.localPosition, size),
            child: CustomPaint(
              painter: _SvPadPainter(hsv: hsv),
              child: const SizedBox.expand(),
            ),
          );
        },
      ),
    );
  }
}

class _SvPadPainter extends CustomPainter {
  const _SvPadPainter({required this.hsv});

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hue = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor();
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()
        ..shader = ui.Gradient.linear(rect.topLeft, rect.topRight, [
          const Color(0xFFFFFFFF),
          hue,
        ]),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()
        ..shader = ui.Gradient.linear(rect.topLeft, rect.bottomLeft, [
          const Color(0x00000000),
          const Color(0xFF000000),
        ]),
    );
    final center = Offset(
      hsv.saturation * size.width,
      (1 - hsv.value) * size.height,
    );
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFFFFFFFF);
    canvas.drawCircle(center, 6, ring);
    canvas.drawCircle(
      center,
      6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFF000000),
    );
  }

  @override
  bool shouldRepaint(covariant _SvPadPainter oldDelegate) =>
      oldDelegate.hsv != hsv;
}

class _HueBar extends StatelessWidget {
  const _HueBar({required this.hue, required this.onChanged});

  final double hue;
  final ValueChanged<double> onChanged;

  void _pick(double dx, double width) {
    if (width < 1) return;
    onChanged((dx / width).clamp(0.0, 1.0) * 359.999);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 18,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => _pick(details.localPosition.dx, width),
            onHorizontalDragUpdate: (details) =>
                _pick(details.localPosition.dx, width),
            child: CustomPaint(
              painter: _HueBarPainter(hue: hue),
              child: const SizedBox.expand(),
            ),
          );
        },
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

class _HueBarPainter extends CustomPainter {
  const _HueBarPainter({required this.hue});

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(9)),
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topLeft,
          rect.topRight,
          [
            for (var stop = 0; stop <= 6; stop++)
              HSVColor.fromAHSV(1, stop * 60.0, 1, 1).toColor(),
          ],
          [for (var stop = 0; stop <= 6; stop++) stop / 6],
        ),
    );
    final x = (hue / 360) * size.width;
    final center = Offset(x.clamp(6, size.width - 6), size.height / 2);
    canvas.drawCircle(
      center,
      6,
      Paint()..color = HSVColor.fromAHSV(1, hue, 1, 1).toColor(),
    );
    canvas.drawCircle(
      center,
      6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFFFFFFF),
    );
  }

  @override
  bool shouldRepaint(covariant _HueBarPainter oldDelegate) =>
      oldDelegate.hue != hue;
}
