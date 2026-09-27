import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../gridcraft/tool_animation.dart';
import '../gridcraft/tool_animation_io.dart';
import '../gridcraft/tool_flight.dart';
import '../papercut/models.dart';
import '../ui/fm_dev_back_button.dart';
import '../ui/fm_screen.dart';

const _kPreviewHold = Duration(milliseconds: 400);

/// Where the tool is presented on the editor stage, toward the bottom.
Offset toolStageAnchor(Size size) => Offset(size.width / 2, size.height * 0.72);

/// Scrub of arrive, a short hold, a cut, and leave. [t] is 0 to 1.
ToolPose toolPreviewPose(double t) {
  const arrive = 320.0;
  const hold = 400.0;
  const cut = 360.0;
  const leave = 220.0;
  final total = arrive + hold + cut + leave;
  var ms = t.clamp(0.0, 1.0) * total;
  const cue = ToolCue(
    anchor: Offset.zero,
    direction: Offset(1, 0),
    aim: Offset.zero,
    reach: 1,
  );
  const distance = 160.0;
  if (ms < arrive) {
    return sampleArrive(t: ms / arrive, cue: cue, distance: distance, sign: 1);
  }
  ms -= arrive;
  if (ms < hold) return sampleHold(cue: cue, sign: 1);
  ms -= hold;
  if (ms < cut) {
    return sampleCut(
      t: ms / cut,
      from: Offset.zero,
      to: const Offset(72, 0),
      direction: Offset(1, 0),
      fromRoll: kRestRoll,
      fromLateral: 0,
      fromOpen: kBladeOpen,
      sign: 1,
      present: true,
    );
  }
  ms -= cut;
  return sampleLeave(
    t: (ms / leave).clamp(0.0, 1.0),
    from: const ToolPose(
      tip: Offset(72, 0),
      direction: Offset(1, 0),
      roll: kRestRoll,
      open: kBladeClosed,
      lateral: 0,
      visible: 1,
      cutting: true,
    ),
    distance: distance,
    sign: 1,
  );
}

/// Dev editor for tool icon vectors and their flight preview.
class ToolAnimationView extends StatefulWidget {
  const ToolAnimationView({super.key, this.store});

  final ToolAnimationStore? store;

  @override
  State<ToolAnimationView> createState() => _ToolAnimationViewState();
}

class _ToolAnimationViewState extends State<ToolAnimationView>
    with SingleTickerProviderStateMixin {
  late final ToolAnimationStore _store = widget.store ?? ToolAnimationStore();
  late final AnimationController _play;
  List<ToolAnimation> _tools = defaultToolAnimations();
  String _selected = 'scissors';
  bool _saved = false;

  ToolAnimation get _tool => _tools.firstWhere((tool) => tool.id == _selected);

  @override
  void initState() {
    super.initState();
    final total = kArriveDuration + _kPreviewHold + kCutDuration + kLeaveDuration;
    _play = AnimationController(vsync: this, duration: total)..repeat();
    _load();
  }

  @override
  void dispose() {
    _play.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final tools = await _store.load();
    if (!mounted || tools.isEmpty) return;
    setState(() {
      _tools = tools;
      if (!tools.any((tool) => tool.id == _selected)) {
        _selected = tools.first.id;
      }
    });
  }

  Future<void> _save() async {
    await _store.save(_tools);
    if (!mounted) return;
    setState(() => _saved = true);
  }

  void _replace(ToolAnimation next) {
    setState(() {
      _saved = false;
      _tools = [
        for (final tool in _tools)
          if (tool.id == next.id) next else tool,
      ];
    });
  }

  void _dragStart(Offset local, Size size) {
    final delta = local - toolStageAnchor(size);
    if (delta.distance < 10) return;
    final aim = math.atan2(delta.dy, delta.dx);
    var degrees = (aim - (-math.pi / 2)) * 180 / math.pi;
    degrees = (degrees + 180) % 360 - 180;
    _replace(_tool.withFeature('startAngle', degrees));
  }

  void _scrub(double value) {
    _play.stop();
    _play.value = value;
  }

  void _togglePlay() {
    if (_play.isAnimating) {
      _play.stop();
    } else {
      _play.repeat();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return FmScreen(
      backgroundColor: kPapercutBackground,
      overlays: const [FmDevBackButton()],
      content: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 720;
          final stage = _stage();
          final controls = _controls();
          if (stacked) {
            return Column(
              children: [
                SizedBox(height: 280, child: stage),
                Expanded(child: controls),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: stage),
              SizedBox(width: 320, child: controls),
            ],
          );
        },
      ),
    );
  }

  Widget _stage() {
    return AnimatedBuilder(
      animation: _play,
      builder: (context, _) {
        return Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(constraints.maxWidth, constraints.maxHeight);
                  return GestureDetector(
                    onPanUpdate: (details) => _dragStart(details.localPosition, size),
                    child: CustomPaint(
                      painter: _ToolStagePainter(tool: _tool, t: _play.value),
                      child: const SizedBox.expand(),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: _play.isAnimating ? 'Pause' : 'Play',
                    onPressed: _togglePlay,
                    icon: Icon(
                      _play.isAnimating ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: _play.value.clamp(0.0, 1.0),
                      onChanged: _scrub,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _controls() {
    final tool = _tool;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 24),
      children: [
        const Text(
          'Tool animations',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        const SizedBox(height: 12),
        DropdownButton<String>(
          isExpanded: true,
          dropdownColor: const Color(0xFF1A1A1A),
          value: tool.id,
          items: [
            for (final item in _tools)
              DropdownMenuItem(
                value: item.id,
                child: Text(item.label, style: const TextStyle(color: Colors.white70)),
              ),
          ],
          onChanged: (id) {
            if (id == null) return;
            setState(() => _selected = id);
          },
        ),
        const SizedBox(height: 12),
        _ColorControls(
          label: 'Fill',
          color: tool.style.fill,
          onChanged: (color) => _replace(tool.withStyle(tool.style.copyWith(fill: color))),
        ),
        _ColorControls(
          label: 'Stroke',
          color: tool.style.stroke,
          onChanged: (color) => _replace(tool.withStyle(tool.style.copyWith(stroke: color))),
        ),
        _slider(
          'Stroke width',
          tool.style.strokeWidth,
          0.4,
          8,
          (value) => _replace(tool.withStyle(tool.style.copyWith(strokeWidth: value))),
        ),
        for (final feature in tool.features)
          _slider(
            feature.label,
            feature.value,
            feature.min,
            feature.max,
            (value) => _replace(tool.withFeature(feature.id, value)),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _save,
            child: Text(_saved ? 'Saved' : 'Save'),
          ),
        ),
      ],
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _ColorControls extends StatelessWidget {
  const _ColorControls({
    required this.label,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  Widget build(BuildContext context) {
    final hsv = HSVColor.fromColor(color);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        _channel('Hue', hsv.hue, 360, (value) {
          onChanged(hsv.withHue(value).toColor());
        }),
        _channel('Saturation', hsv.saturation, 1, (value) {
          onChanged(hsv.withSaturation(value).toColor());
        }),
        _channel('Value', hsv.value, 1, (value) {
          onChanged(hsv.withValue(value).toColor());
        }),
      ],
    );
  }

  Widget _channel(
    String label,
    double value,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(0.0, max),
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _ToolStagePainter extends CustomPainter {
  _ToolStagePainter({required this.tool, required this.t});

  final ToolAnimation tool;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final anchor = toolStageAnchor(size);
    final pose = toolPreviewPose(t);
    if (pose.visible <= 0) {
      _paintStartVector(canvas, anchor, tool);
      return;
    }
    const cutHeading = -math.pi / 2;
    final dir = Offset(math.cos(cutHeading), math.sin(cutHeading));
    final tip = anchor + dir * pose.tip.dx + Offset(-dir.dy, dir.dx) * pose.tip.dy;
    final perp = Offset(-dir.dy, dir.dx);
    canvas.save();
    canvas.translate((tip + perp * pose.lateral).dx, (tip + perp * pose.lateral).dy);
    paintRolledTool(
      canvas: canvas,
      tool: tool,
      pose: pose,
      heading: cutHeading + toolYaw(tool, pose),
    );
    canvas.restore();
    _paintStartVector(canvas, anchor, tool);
  }

  void _paintStartVector(Canvas canvas, Offset anchor, ToolAnimation tool) {
    const cutHeading = -math.pi / 2;
    final cut = Offset(math.cos(cutHeading), math.sin(cutHeading));
    canvas.drawLine(
      anchor,
      anchor + cut * 88,
      Paint()
        ..color = const Color(0x33FFFFFF)
        ..strokeWidth = 1.5,
    );
    final aim = cutHeading + tool.feature('startAngle') * math.pi / 180;
    final dir = Offset(math.cos(aim), math.sin(aim));
    final end = anchor + dir * 64;
    final ink = Paint()
      ..color = const Color(0xFFFFD54F)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(anchor, end, ink);
    final side = Offset(-dir.dy, dir.dx);
    canvas.drawLine(end, end - dir * 10 + side * 5, ink);
    canvas.drawLine(end, end - dir * 10 - side * 5, ink);
    canvas.drawCircle(anchor, 4.5, Paint()..color = const Color(0xFFFFFFFF));
  }

  @override
  bool shouldRepaint(covariant _ToolStagePainter oldDelegate) => true;
}
