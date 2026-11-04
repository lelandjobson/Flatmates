import 'dart:math' as math;
import 'dart:ui';

class SurfaceAppearance {
  double brightness = 0, contrast = 1, saturation = 1, hue = 0;
  bool get neutral =>
      brightness == 0 && contrast == 1 && saturation == 1 && hue == 0;
  Map<String, dynamic> toJson() => {
    'brightness': brightness,
    'contrast': contrast,
    'saturation': saturation,
    'hue': hue,
  };
  static SurfaceAppearance fromJson(Object? raw) {
    final result = SurfaceAppearance();
    if (raw == null) return result;
    if (raw is! Map) throw const FormatException('Invalid appearance');
    double value(String key, double fallback, double low, double high) {
      final v = raw[key] ?? fallback;
      if (v is! num || !v.isFinite || v < low || v > high) {
        throw const FormatException('Invalid appearance');
      }
      return v.toDouble();
    }

    result.brightness = value('brightness', 0, -1, 1);
    result.contrast = value('contrast', 1, 0, 2);
    result.saturation = value('saturation', 1, 0, 2);
    result.hue = value('hue', 0, -180, 180);
    return result;
  }

  /// Hue and saturation, then contrast around mid-gray and additive brightness.
  /// Alpha is preserved, including transparent textures and camera cutaways.
  List<double> get matrix {
    final c = math.cos(hue * math.pi / 180),
        s = math.sin(hue * math.pi / 180),
        k = saturation;
    final h = [
      .213 + .787 * c - .213 * s,
      .715 - .715 * c - .715 * s,
      .072 - .072 * c + .928 * s,
      .213 - .213 * c + .143 * s,
      .715 + .285 * c + .140 * s,
      .072 - .072 * c - .283 * s,
      .213 - .213 * c - .787 * s,
      .715 - .715 * c + .715 * s,
      .072 + .928 * c + .072 * s,
    ];
    const l = [.213, .715, .072];
    final out = <double>[];
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 3; col++) {
        var v = 0.0;
        for (var j = 0; j < 3; j++) {
          v += ((row == j ? k : 0) + (1 - k) * l[j]) * h[j * 3 + col];
        }
        out.add(v * contrast);
      }
      out.addAll([0, 255 * (brightness + .5 * (1 - contrast))]);
    }
    out.addAll([0, 0, 0, 1, 0]);
    return out;
  }

  ColorFilter? get filter => neutral ? null : ColorFilter.matrix(matrix);
}
