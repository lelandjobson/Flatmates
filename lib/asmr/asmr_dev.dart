import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// DevTools values for the ASMR view. They are written to [file] as they
/// change, and read back the next time the view opens.
class AsmrDevSettings extends ChangeNotifier {
  AsmrDevSettings({File? file, double curveSmoothing = 0})
    : _file = file ?? _defaultFile(),
      _curveSmoothing = curveSmoothing.clamp(0.0, 1.0);

  /// `~/.flatmates/asmr_devtools.json`, or a temp file under tests so a
  /// developer's saved slider does not change them.
  static File _defaultFile() {
    if (Platform.environment['FLUTTER_TEST'] == 'true') {
      return File('${Directory.systemTemp.path}/flatmates_asmr_devtools_test.json');
    }
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return File('$home/.flatmates/asmr_devtools.json');
  }

  final File _file;
  double _curveSmoothing;

  /// 0 leaves a tool curve as drawn. 1 smooths it as far as it goes.
  double get curveSmoothing => _curveSmoothing;

  set curveSmoothing(double value) {
    final next = value.clamp(0.0, 1.0);
    if ((next - _curveSmoothing).abs() < 1e-6) return;
    _curveSmoothing = next;
    notifyListeners();
    _save();
  }

  /// Reads the saved file. Missing or unreadable files leave the defaults.
  Future<void> load() async {
    try {
      if (!await _file.exists()) return;
      final json = jsonDecode(await _file.readAsString());
      if (json is! Map) return;
      final value = json['curveSmoothing'];
      if (value is! num) return;
      final next = value.toDouble().clamp(0.0, 1.0);
      if ((next - _curveSmoothing).abs() < 1e-6) return;
      _curveSmoothing = next;
      notifyListeners();
    } catch (_) {}
  }

  void _save() {
    try {
      _file.parent.createSync(recursive: true);
      _file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'curveSmoothing': _curveSmoothing,
        }),
      );
    } catch (_) {}
  }
}

/// The ASMR DevTools sheet.
class AsmrDevPanel extends StatelessWidget {
  const AsmrDevPanel({
    super.key,
    required this.curveSmoothing,
    required this.onCurveSmoothing,
  });

  final double curveSmoothing;
  final ValueChanged<double> onCurveSmoothing;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    final maxHeight = height.isFinite ? math.min(280.0, height * 0.4) : 280.0;
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
              Text(
                'How far a tool curve is smoothed. 0 keeps the stroke as drawn. 1 pulls it toward a smooth curve. The ends stay where the blade started and stopped.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 10,
                  height: 1.3,
                ),
              ),
              Row(
                children: [
                  const Text(
                    'Curve smoothing',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Expanded(
                    child: Slider(
                      key: const Key('asmr-curve-smoothing'),
                      value: curveSmoothing.clamp(0.0, 1.0),
                      divisions: 20,
                      activeColor: Colors.white70,
                      inactiveColor: Colors.white24,
                      onChanged: onCurveSmoothing,
                    ),
                  ),
                  SizedBox(
                    width: 34,
                    child: Text(
                      '${(curveSmoothing * 100).round()}%',
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
