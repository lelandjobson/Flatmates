import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// A full-screen view of the craft on the bench. Workviews overlap; only the
/// active one takes input, and it is drawn over the others.
enum Workview {
  /// The primary 3D workview: the model.
  model,

  /// The primary 2D workview: the desk.
  desk,
}

/// The longest gap between the two taps of a double-tap that switches the
/// active workview.
const Duration kWorkviewDoubleTap = Duration(milliseconds: 400);

/// How far apart the two taps of a switching double-tap may land, in
/// screen pixels.
const double kWorkviewDoubleTapSlop = 32;

/// How a workview is drawn: identity while active, the DevTools values
/// while inactive.
@immutable
class WorkviewLook {
  const WorkviewLook({
    this.opacity = 1,
    this.blur = 0,
    this.saturation = 1,
    this.brightness = 1,
  });

  static const WorkviewLook identity = WorkviewLook();

  /// 0 hides the workview, 1 draws it solid.
  final double opacity;

  /// Blur sigma in screen pixels.
  final double blur;

  /// 0 is grey, 1 as drawn, above 1 more vivid.
  final double saturation;

  /// Multiplies the color. 1 as drawn.
  final double brightness;

  static WorkviewLook lerp(WorkviewLook a, WorkviewLook b, double t) =>
      WorkviewLook(
        opacity: ui.lerpDouble(a.opacity, b.opacity, t)!,
        blur: ui.lerpDouble(a.blur, b.blur, t)!,
        saturation: ui.lerpDouble(a.saturation, b.saturation, t)!,
        brightness: ui.lerpDouble(a.brightness, b.brightness, t)!,
      );

  WorkviewLook withOpacity(double value) => WorkviewLook(
    opacity: value,
    blur: blur,
    saturation: saturation,
    brightness: brightness,
  );

  bool get _colored =>
      (saturation - 1).abs() > 1e-3 || (brightness - 1).abs() > 1e-3;

  bool get _blurred => blur > 1e-2;

  /// Saturation about Rec. 709 luminance, then brightness.
  List<double> get colorMatrix {
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final s = saturation;
    final k = brightness;
    final r = 1 - s;
    return <double>[
      (lr * r + s) * k, lg * r * k, lb * r * k, 0, 0, //
      lr * r * k, (lg * r + s) * k, lb * r * k, 0, 0, //
      lr * r * k, lg * r * k, (lb * r + s) * k, 0, 0, //
      0, 0, 0, 1, 0, //
    ];
  }

  ui.ImageFilter get _filter {
    final blurred = _blurred
        ? ui.ImageFilter.blur(
            sigmaX: blur,
            sigmaY: blur,
            tileMode: ui.TileMode.decal,
          )
        : null;
    final colored = _colored ? ui.ColorFilter.matrix(colorMatrix) : null;
    if (blurred != null && colored != null) {
      return ui.ImageFilter.compose(outer: blurred, inner: colored);
    }
    return blurred ?? colored ?? ui.ImageFilter.blur();
  }

  /// [child] drawn with this look. The tree keeps its shape whatever the
  /// values, so the child is not rebuilt when a filter turns on or off.
  Widget wrap(Widget child, {Key? key}) => Opacity(
    key: key,
    opacity: opacity.clamp(0.0, 1.0),
    child: ImageFiltered(
      enabled: _blurred || _colored,
      imageFilter: _filter,
      child: RepaintBoundary(child: child),
    ),
  );

  @override
  bool operator ==(Object other) =>
      other is WorkviewLook &&
      other.opacity == opacity &&
      other.blur == blur &&
      other.saturation == saturation &&
      other.brightness == brightness;

  @override
  int get hashCode => Object.hash(opacity, blur, saturation, brightness);
}

/// Spots the second of two quick taps on empty space close together.
class WorkviewDoubleTap {
  WorkviewDoubleTap({
    this.window = kWorkviewDoubleTap,
    this.slop = kWorkviewDoubleTapSlop,
  });

  final Duration window;
  final double slop;
  Offset? _at;
  double _time = 0;

  /// A tap on empty space at [at], [time] seconds on the view's clock.
  /// Returns true when it completes a double-tap, which is then used up.
  bool tap(Offset at, double time) {
    final last = _at;
    if (last != null &&
        time - _time <= window.inMicroseconds / 1e6 &&
        (at - last).distance <= slop) {
      _at = null;
      return true;
    }
    _at = at;
    _time = time;
    return false;
  }

  void reset() => _at = null;
}

/// DevTools values for how an inactive workview is drawn, saved as they
/// change and read back the next time the craft room opens.
class WorkviewSettings extends ChangeNotifier {
  WorkviewSettings({
    File? file,
    double opacity = 0.33,
    double blur = 3,
    double saturation = 1,
    double brightness = 1,
    double switchMs = 300,
  }) : _file = file ?? _defaultFile(),
       _values = {
         _opacity: _opacity.clamp(opacity),
         _blur: _blur.clamp(blur),
         _saturation: _saturation.clamp(saturation),
         _brightness: _brightness.clamp(brightness),
         _switchMs: _switchMs.clamp(switchMs),
       };

  static const _opacity = _Range('opacity', 0, 1);
  static const _blur = _Range('blur', 0, 20);
  static const _saturation = _Range('saturation', 0, 2);
  static const _brightness = _Range('brightness', 0, 2);
  static const _switchMs = _Range('switchMs', 0, 1000);

  /// `~/.flatmates/craft_room_workviews.json`, or a temp file under tests.
  static File _defaultFile() {
    if (Platform.environment['FLUTTER_TEST'] == 'true') {
      return File(
        '${Directory.systemTemp.path}/flatmates_craft_room_workviews_test.json',
      );
    }
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return File('$home/.flatmates/craft_room_workviews.json');
  }

  final File _file;
  final Map<_Range, double> _values;

  double get opacity => _values[_opacity]!;
  set opacity(double value) => _set(_opacity, value);

  double get blur => _values[_blur]!;
  set blur(double value) => _set(_blur, value);

  double get saturation => _values[_saturation]!;
  set saturation(double value) => _set(_saturation, value);

  double get brightness => _values[_brightness]!;
  set brightness(double value) => _set(_brightness, value);

  /// How long a workview takes to become active, or to step back.
  double get switchMs => _values[_switchMs]!;
  set switchMs(double value) => _set(_switchMs, value);

  Duration get switchDuration =>
      Duration(microseconds: math.max(1, (switchMs * 1000).round()));

  /// The look of a workview that is not active.
  WorkviewLook get inactive => WorkviewLook(
    opacity: opacity,
    blur: blur,
    saturation: saturation,
    brightness: brightness,
  );

  void _set(_Range range, double value) {
    final next = range.clamp(value);
    if ((next - _values[range]!).abs() < 1e-6) return;
    _values[range] = next;
    notifyListeners();
    _save();
  }

  /// Reads the saved file. Missing or unreadable files keep the defaults.
  Future<void> load() async {
    try {
      if (!await _file.exists()) return;
      final json = jsonDecode(await _file.readAsString());
      if (json is! Map) return;
      var changed = false;
      for (final range in _values.keys.toList()) {
        final raw = json[range.name];
        if (raw is! num) continue;
        final next = range.clamp(raw.toDouble());
        if ((next - _values[range]!).abs() < 1e-6) continue;
        _values[range] = next;
        changed = true;
      }
      if (changed) notifyListeners();
    } catch (_) {}
  }

  void _save() {
    try {
      _file.parent.createSync(recursive: true);
      _file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          for (final entry in _values.entries) entry.key.name: entry.value,
        }),
      );
    } catch (_) {}
  }
}

class _Range {
  const _Range(this.name, this.min, this.max);

  final String name;
  final double min;
  final double max;

  double clamp(double value) => value.clamp(min, max).toDouble();
}
