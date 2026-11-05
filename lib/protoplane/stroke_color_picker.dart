import 'package:flutter/material.dart';

/// Hue, saturation/value, and exact RGB entry; no fixed palette restriction.
Future<void> showStrokeColorPicker(
  BuildContext context,
  Color initial,
  ValueChanged<Color> changed, {
  String title = 'Line color',
}) => showDialog<void>(
  context: context,
  barrierColor: Colors.transparent,
  builder: (_) =>
      _StrokeColorDialog(initial: initial, changed: changed, title: title),
);

class _StrokeColorDialog extends StatefulWidget {
  const _StrokeColorDialog({
    required this.initial,
    required this.changed,
    required this.title,
  });
  final String title;
  final Color initial;
  final ValueChanged<Color> changed;
  @override
  State<_StrokeColorDialog> createState() => _StrokeColorDialogState();
}

class _StrokeColorDialogState extends State<_StrokeColorDialog> {
  late HSVColor hsv = HSVColor.fromColor(widget.initial);
  late final TextEditingController hex = TextEditingController(
    text: widget.initial
        .toARGB32()
        .toRadixString(16)
        .substring(2)
        .toUpperCase(),
  );
  @override
  void dispose() {
    hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    void set(HSVColor value) {
      setState(() {
        hsv = value;
        hex.text = hsv
            .toColor()
            .toARGB32()
            .toRadixString(16)
            .substring(2)
            .toUpperCase();
      });
      widget.changed(hsv.toColor());
    }

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 280,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                label: 'Saturation and brightness',
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    void pick(Offset p) => set(
                      hsv
                          .withSaturation(
                            (p.dx / constraints.maxWidth).clamp(0, 1),
                          )
                          .withValue((1 - p.dy / 150).clamp(0, 1)),
                    );
                    return GestureDetector(
                      onPanDown: (d) => pick(d.localPosition),
                      onPanUpdate: (d) => pick(d.localPosition),
                      child: SizedBox(
                        height: 150,
                        width: double.infinity,
                        child: CustomPaint(painter: _ColorField(hsv)),
                      ),
                    );
                  },
                ),
              ),
              Slider(
                value: hsv.hue,
                min: 0,
                max: 360,
                label: '${hsv.hue.round()}°',
                onChanged: (value) => set(hsv.withHue(value)),
              ),
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: hsv.toColor(),
                      border: Border.all(color: Colors.white54),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: hex,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: 'Hex',
                        prefixText: '#',
                        counterText: '',
                      ),
                      onChanged: (value) {
                        final rgb = RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(value)
                            ? int.tryParse(value, radix: 16)
                            : null;
                        if (rgb != null) {
                          final color = Color(0xff000000 | rgb);
                          setState(() => hsv = HSVColor.fromColor(color));
                          widget.changed(color);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _ColorField extends CustomPainter {
  _ColorField(this.hsv);
  final HSVColor hsv;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor()],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
    final point = Offset(
      hsv.saturation * size.width,
      (1 - hsv.value) * size.height,
    );
    canvas.drawCircle(
      point,
      6,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(
      point,
      6,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_ColorField old) => old.hsv != hsv;
}
