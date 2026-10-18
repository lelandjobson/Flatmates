import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Which page of the ASMR DevTools sheet is showing.
enum AsmrDevTab { curves, shadow }

/// Colors offered for the blueprint-edge shadow.
const List<Color> kAsmrShadowColors = [
  Color(0xFF000000),
  Color(0xFF1A1030),
  Color(0xFF3A2418),
  Color(0xFF10243A),
];

/// DevTools values for the ASMR view. They are written to [file] as they
/// change, and read back the next time the view opens.
class AsmrDevSettings extends ChangeNotifier {
  AsmrDevSettings({
    File? file,
    double curveSmoothing = 0,
    double shadowThrow = 10,
    double shadowSpread = 8,
    Color shadowColor = const Color(0xFF000000),
    double shadowOpacity = 0.45,
    double darkOverlay = 0.22,
  }) : _file = file ?? _defaultFile(),
       _curveSmoothing = curveSmoothing.clamp(0.0, 1.0),
       _shadowThrow = shadowThrow.clamp(0.0, 40.0),
       _shadowSpread = shadowSpread.clamp(0.0, 40.0),
       _shadowColor = shadowColor.withValues(alpha: 1),
       _shadowOpacity = shadowOpacity.clamp(0.0, 1.0),
       _darkOverlay = darkOverlay.clamp(0.0, 1.0);

  /// `~/.flatmates/asmr_devtools.json`, or a temp file under tests so a
  /// developer's saved slider does not change them.
  static File _defaultFile() {
    if (Platform.environment['FLUTTER_TEST'] == 'true') {
      return File(
        '${Directory.systemTemp.path}/flatmates_asmr_devtools_test.json',
      );
    }
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return File('$home/.flatmates/asmr_devtools.json');
  }

  final File _file;
  double _curveSmoothing;
  double _shadowThrow;
  double _shadowSpread;
  Color _shadowColor;
  double _shadowOpacity;
  double _darkOverlay;

  /// 0 leaves a tool curve as drawn. 1 smooths it as far as it goes.
  double get curveSmoothing => _curveSmoothing;

  set curveSmoothing(double value) {
    final next = value.clamp(0.0, 1.0);
    if ((next - _curveSmoothing).abs() < 1e-6) return;
    _curveSmoothing = next;
    notifyListeners();
    _save();
  }

  /// How far a blueprint-edge shadow is offset, in screen pixels.
  double get shadowThrow => _shadowThrow;

  set shadowThrow(double value) {
    final next = value.clamp(0.0, 40.0);
    if ((next - _shadowThrow).abs() < 1e-6) return;
    _shadowThrow = next;
    notifyListeners();
    _save();
  }

  /// How soft a blueprint-edge shadow is, in screen pixels.
  double get shadowSpread => _shadowSpread;

  set shadowSpread(double value) {
    final next = value.clamp(0.0, 40.0);
    if ((next - _shadowSpread).abs() < 1e-6) return;
    _shadowSpread = next;
    notifyListeners();
    _save();
  }

  /// The shadow color, opaque. [shadowOpacity] carries the alpha.
  Color get shadowColor => _shadowColor;

  set shadowColor(Color value) {
    final next = value.withValues(alpha: 1);
    if (next.toARGB32() == _shadowColor.toARGB32()) return;
    _shadowColor = next;
    notifyListeners();
    _save();
  }

  /// 0 hides the shadow. 1 paints [shadowColor] solid.
  double get shadowOpacity => _shadowOpacity;

  set shadowOpacity(double value) {
    final next = value.clamp(0.0, 1.0);
    if ((next - _shadowOpacity).abs() < 1e-6) return;
    _shadowOpacity = next;
    notifyListeners();
    _save();
  }

  /// [shadowColor] at [shadowOpacity], ready to paint.
  Color get shadowPaint => _shadowColor.withValues(alpha: _shadowOpacity);

  /// How dark a piece is when it is not touching a blueprint edge. 0 leaves
  /// it as printed.
  double get darkOverlay => _darkOverlay;

  set darkOverlay(double value) {
    final next = value.clamp(0.0, 1.0);
    if ((next - _darkOverlay).abs() < 1e-6) return;
    _darkOverlay = next;
    notifyListeners();
    _save();
  }

  /// Reads the saved file. Missing or unreadable files leave the defaults.
  Future<void> load() async {
    try {
      if (!await _file.exists()) return;
      final json = jsonDecode(await _file.readAsString());
      if (json is! Map) return;
      var changed = false;
      final smoothing = json['curveSmoothing'];
      if (smoothing is num) {
        final next = smoothing.toDouble().clamp(0.0, 1.0);
        if ((next - _curveSmoothing).abs() >= 1e-6) {
          _curveSmoothing = next;
          changed = true;
        }
      }
      final thrown = json['shadowThrow'];
      if (thrown is num) {
        final next = thrown.toDouble().clamp(0.0, 40.0);
        if ((next - _shadowThrow).abs() >= 1e-6) {
          _shadowThrow = next;
          changed = true;
        }
      }
      final spread = json['shadowSpread'];
      if (spread is num) {
        final next = spread.toDouble().clamp(0.0, 40.0);
        if ((next - _shadowSpread).abs() >= 1e-6) {
          _shadowSpread = next;
          changed = true;
        }
      }
      final color = json['shadowColor'];
      if (color is num) {
        final next = Color(color.toInt()).withValues(alpha: 1);
        if (next.toARGB32() != _shadowColor.toARGB32()) {
          _shadowColor = next;
          changed = true;
        }
      }
      final opacity = json['shadowOpacity'];
      if (opacity is num) {
        final next = opacity.toDouble().clamp(0.0, 1.0);
        if ((next - _shadowOpacity).abs() >= 1e-6) {
          _shadowOpacity = next;
          changed = true;
        }
      }
      final overlay = json['darkOverlay'];
      if (overlay is num) {
        final next = overlay.toDouble().clamp(0.0, 1.0);
        if ((next - _darkOverlay).abs() >= 1e-6) {
          _darkOverlay = next;
          changed = true;
        }
      }
      if (changed) notifyListeners();
    } catch (_) {}
  }

  void _save() {
    try {
      _file.parent.createSync(recursive: true);
      _file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'curveSmoothing': _curveSmoothing,
          'shadowThrow': _shadowThrow,
          'shadowSpread': _shadowSpread,
          'shadowColor': _shadowColor.toARGB32(),
          'shadowOpacity': _shadowOpacity,
          'darkOverlay': _darkOverlay,
        }),
      );
    } catch (_) {}
  }
}

/// The ASMR DevTools sheet.
class AsmrDevPanel extends StatefulWidget {
  const AsmrDevPanel({super.key, required this.settings});

  final AsmrDevSettings settings;

  @override
  State<AsmrDevPanel> createState() => _AsmrDevPanelState();
}

class _AsmrDevPanelState extends State<AsmrDevPanel> {
  AsmrDevTab _tab = AsmrDevTab.curves;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    final maxHeight = height.isFinite ? math.min(520.0, height * 0.82) : 520.0;
    final settings = widget.settings;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 272, maxHeight: maxHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xE61A1A1A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white24),
        ),
        child: Padding(
          key: const Key('asmr-dev-panel'),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
              Row(
                children: [
                  _Tab(
                    label: 'Curves',
                    tabKey: const Key('asmr-dev-tab-curves'),
                    selected: _tab == AsmrDevTab.curves,
                    onTap: () => setState(() => _tab = AsmrDevTab.curves),
                  ),
                  const SizedBox(width: 6),
                  _Tab(
                    label: 'Shadow',
                    tabKey: const Key('asmr-dev-tab-shadow'),
                    selected: _tab == AsmrDevTab.shadow,
                    onTap: () => setState(() => _tab = AsmrDevTab.shadow),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_tab == AsmrDevTab.curves)
                _CurvesPage(
                  amount: settings.curveSmoothing,
                  onChanged: (value) => settings.curveSmoothing = value,
                )
              else
                _ShadowPage(settings: settings),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.tabKey,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Key tabKey;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: tabKey,
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: selected ? Colors.white54 : Colors.white24),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white60,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _CurvesPage extends StatelessWidget {
  const _CurvesPage({required this.amount, required this.onChanged});

  final double amount;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How far a tool curve is smoothed. 0 keeps the stroke as drawn. 1 pulls it toward a smooth curve. The ends stay where the blade started and stopped.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 10,
            height: 1.3,
          ),
        ),
        _SliderRow(
          label: 'Curve smoothing',
          sliderKey: const Key('asmr-curve-smoothing'),
          value: amount.clamp(0.0, 1.0),
          max: 1,
          divisions: 20,
          readout: '${(amount * 100).round()}%',
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _ShadowPage extends StatelessWidget {
  const _ShadowPage({required this.settings});

  final AsmrDevSettings settings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pieces on the blueprint edge cast this shadow onto pieces that are not touching it. Throw is how far it is offset. Spread is how soft it gets. Dark overlay is how much those other pieces are darkened.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 10,
            height: 1.3,
          ),
        ),
        _SliderRow(
          label: 'Throw',
          sliderKey: const Key('asmr-shadow-throw'),
          value: settings.shadowThrow,
          max: 40,
          divisions: 40,
          readout: '${settings.shadowThrow.round()}',
          onChanged: (value) => settings.shadowThrow = value,
        ),
        _SliderRow(
          label: 'Spread',
          sliderKey: const Key('asmr-shadow-spread'),
          value: settings.shadowSpread,
          max: 40,
          divisions: 40,
          readout: '${settings.shadowSpread.round()}',
          onChanged: (value) => settings.shadowSpread = value,
        ),
        _SliderRow(
          label: 'Opacity',
          sliderKey: const Key('asmr-shadow-opacity'),
          value: settings.shadowOpacity,
          max: 1,
          divisions: 20,
          readout: '${(settings.shadowOpacity * 100).round()}%',
          onChanged: (value) => settings.shadowOpacity = value,
        ),
        _SliderRow(
          label: 'Overlay',
          sliderKey: const Key('asmr-dark-overlay'),
          value: settings.darkOverlay,
          max: 1,
          divisions: 20,
          readout: '${(settings.darkOverlay * 100).round()}%',
          onChanged: (value) => settings.darkOverlay = value,
        ),
        const SizedBox(height: 4),
        const Text(
          'Color',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < kAsmrShadowColors.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  key: Key('asmr-shadow-color-$i'),
                  onTap: () => settings.shadowColor = kAsmrShadowColors[i],
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: kAsmrShadowColors[i],
                      shape: BoxShape.circle,
                      border: Border.all(
                        color:
                            settings.shadowColor.toARGB32() ==
                                kAsmrShadowColors[i].toARGB32()
                            ? Colors.white
                            : Colors.white24,
                        width: 2,
                      ),
                    ),
                    child: const SizedBox(width: 22, height: 22),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.sliderKey,
    required this.value,
    required this.max,
    required this.divisions,
    required this.readout,
    required this.onChanged,
  });

  final String label;
  final Key sliderKey;
  final double value;
  final double max;
  final int divisions;
  final String readout;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 78,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        Expanded(
          child: Slider(
            key: sliderKey,
            value: value.clamp(0.0, max),
            max: max,
            divisions: divisions,
            activeColor: Colors.white70,
            inactiveColor: Colors.white24,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            readout,
            textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
