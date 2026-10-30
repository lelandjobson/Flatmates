import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// A faint repeating print on paper. [plain] prints nothing.
enum AsmrPattern {
  circleGrid,
  linesAndCircles,
  triangles,
  hexagons,
  octagons,
  plain,
}

/// A paper in the ASMR drawer: a color printed with a faint pattern.
class AsmrPaper {
  const AsmrPaper({
    required this.id,
    required this.name,
    required this.color,
    required this.pattern,
    this.bright,
  });

  final String id;
  final String name;
  final Color color;
  final AsmrPattern pattern;

  /// A continuous three-stop family of luminous neighbors of this paper.
  Color cutEdgeColor(double parameter) {
    final base = HSLColor.fromColor(Color.lerp(color, markingColor, 0.45)!);
    Color stop(double hue, double light) => base
        .withHue((base.hue + hue) % 360)
        .withSaturation(
          base.saturation < 0.05
              ? base.saturation
              : (base.saturation + 0.08).clamp(0.0, 0.65),
        )
        .withLightness((base.lightness + light).clamp(0.58, 0.88))
        .toColor();
    final stops = [stop(-18, 0.04), stop(0, 0.17), stop(18, 0.07)];
    final t = parameter.clamp(0.0, 1.0);
    return t <= 0.5
        ? Color.lerp(stops[0], stops[1], t * 2)!
        : Color.lerp(stops[1], stops[2], (t - 0.5) * 2)!;
  }

  /// A deliberately chosen luminous neighbor, rather than a white overlay.
  final Color? bright;
  Color get markingColor =>
      bright ?? Color.lerp(color, const Color(0xFFFFFFFF), 0.65)!;
}

const List<AsmrPaper> kAsmrPapers = [
  AsmrPaper(
    id: 'mint',
    name: 'Mint dots',
    color: Color(0xFFBFE8D4),
    pattern: AsmrPattern.circleGrid,
  ),
  AsmrPaper(
    id: 'sky',
    name: 'Sky grid',
    color: Color(0xFFBCD6F2),
    pattern: AsmrPattern.linesAndCircles,
  ),
  AsmrPaper(
    id: 'peach',
    name: 'Peach triangles',
    color: Color(0xFFF6CBB2),
    pattern: AsmrPattern.triangles,
  ),
  AsmrPaper(
    id: 'lavender',
    name: 'Lavender hexagons',
    color: Color(0xFFD7CAEF),
    pattern: AsmrPattern.hexagons,
  ),
  AsmrPaper(
    id: 'butter',
    name: 'Butter octagons',
    color: Color(0xFFF3E3A8),
    pattern: AsmrPattern.octagons,
  ),
];

/// The one plain sheet a whole ASMR craft is cut from.
const AsmrPaper kAsmrCraftPaper = AsmrPaper(
  id: 'white',
  name: 'Iris',
  color: Color(0xFF5A527D),
  bright: Color(0xFFE3C8FF),
  pattern: AsmrPattern.plain,
);

/// Muted grounds and luminous partners, drawn from the desk's violet theme
/// with warm and cool Albers-inspired color relationships.
const List<AsmrPaper> kAsmrCraftPalette = [
  kAsmrCraftPaper,
  AsmrPaper(
    id: 'craft-rose',
    name: 'Rose clay',
    color: Color(0xFF985D70),
    bright: Color(0xFFFFD29E),
    pattern: AsmrPattern.plain,
  ),
  AsmrPaper(
    id: 'craft-teal',
    name: 'Lagoon',
    color: Color(0xFF426F72),
    bright: Color(0xFFC7F2CD),
    pattern: AsmrPattern.plain,
  ),
  AsmrPaper(
    id: 'craft-ochre',
    name: 'Ochre',
    color: Color(0xFFA67943),
    bright: Color(0xFFFFE8A9),
    pattern: AsmrPattern.plain,
  ),
  AsmrPaper(
    id: 'craft-slate',
    name: 'Dusk blue',
    color: Color(0xFF506C91),
    bright: Color(0xFFCADCFF),
    pattern: AsmrPattern.plain,
  ),
];

AsmrPaper asmrPaletteForColor(Color color) {
  return kAsmrCraftPalette.reduce((a, b) {
    double distance(Color c) =>
        (c.r - color.r) * (c.r - color.r) +
        (c.g - color.g) * (c.g - color.g) +
        (c.b - color.b) * (c.b - color.b);
    return distance(a.color) <= distance(b.color) ? a : b;
  });
}

/// The drawer paper or craft paper with [id], or null.
AsmrPaper? asmrPaperById(String id) {
  if (id == kAsmrCraftPaper.id) return kAsmrCraftPaper;
  for (final paper in [...kAsmrCraftPalette, ...kAsmrPapers]) {
    if (paper.id == id) return paper;
  }
  return null;
}

/// Tile pixels per desk unit.
const double _kTileResolution = 12;

const Color _kPatternInk = Color(0xFF3A3550);
const double _kPatternInkMix = 0.5;
const double _kPatternInkAlpha = 0.32;

/// One repeat of [pattern], in desk units.
Offset patternPeriod(AsmrPattern pattern) => switch (pattern) {
  AsmrPattern.circleGrid => const Offset(10, 10),
  AsmrPattern.linesAndCircles => const Offset(12, 12),
  AsmrPattern.triangles => Offset(10, 10 * math.sqrt(3)),
  AsmrPattern.hexagons => Offset(6 * math.sqrt(3), 18),
  AsmrPattern.octagons => const Offset(12, 12),
  AsmrPattern.plain => const Offset(1, 1),
};

/// Each paper's tile, drawn once and repeated by an [ImageShader] wherever
/// the paper is drawn, flat on the desk or in perspective on the model.
class AsmrPaperTiles {
  final Map<String, ImageShader> _shaders = {};

  ImageShader shader(AsmrPaper paper) =>
      _shaders[paper.id] ??= _buildShader(paper);

  /// Paint for [paper] in paper-local coordinates. [shade] darkens it, as
  /// the light falls on a model face.
  Paint paint(AsmrPaper paper, {double shade = 1, double opacity = 1}) {
    final paint = Paint()
      ..shader = shader(paper)
      ..filterQuality = FilterQuality.medium
      ..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0));
    if (shade < 0.999) {
      final level = (shade.clamp(0.0, 1.0) * 255).round();
      paint.colorFilter = ColorFilter.mode(
        Color.fromARGB(255, level, level, level),
        BlendMode.modulate,
      );
    }
    return paint;
  }

  void dispose() {
    _shaders.clear();
  }
}

ImageShader _buildShader(AsmrPaper paper) {
  final period = patternPeriod(paper.pattern);
  final width = (period.dx * _kTileResolution).round();
  final height = (period.dy * _kTileResolution).round();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = paper.color,
  );
  canvas.scale(width / period.dx, height / period.dy);
  canvas.clipRect(Offset.zero & Size(period.dx, period.dy));
  final ink = Paint()
    ..color = Color.lerp(
      paper.color,
      _kPatternInk,
      _kPatternInkMix,
    )!.withValues(alpha: _kPatternInkAlpha)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.35
    ..isAntiAlias = true;
  _drawPattern(canvas, paper.pattern, period, ink);
  final image = recorder.endRecording().toImageSync(width, height);
  final matrix = Float64List(16)
    ..[0] = period.dx / width
    ..[5] = period.dy / height
    ..[10] = 1
    ..[15] = 1;
  return ImageShader(
    image,
    TileMode.repeated,
    TileMode.repeated,
    matrix,
    filterQuality: FilterQuality.medium,
  );
}

/// Draws one tile of [pattern]. Shapes that cross the tile edge are drawn
/// at every neighboring repeat too, so the tile wraps seamlessly.
void _drawPattern(Canvas canvas, AsmrPattern pattern, Offset p, Paint ink) {
  void everyRepeat(void Function(Offset at) draw) {
    for (var i = -1; i <= 1; i++) {
      for (var j = -1; j <= 1; j++) {
        draw(Offset(i * p.dx, j * p.dy));
      }
    }
  }

  switch (pattern) {
    case AsmrPattern.circleGrid:
      everyRepeat((at) {
        canvas.drawCircle(at + p / 2, 1.7, ink);
        canvas.drawCircle(at, 0.5, ink..style = PaintingStyle.fill);
        ink.style = PaintingStyle.stroke;
      });
    case AsmrPattern.linesAndCircles:
      everyRepeat((at) {
        canvas.drawLine(at, at + Offset(p.dx, 0), ink);
        canvas.drawLine(at, at + Offset(0, p.dy), ink);
        canvas.drawCircle(at + p / 2, 3, ink);
      });
    case AsmrPattern.triangles:
      final a = p.dx;
      final h = p.dy;
      everyRepeat((at) {
        canvas.drawLine(at, at + Offset(a, 0), ink);
        canvas.drawLine(at + Offset(0, h / 2), at + Offset(a, h / 2), ink);
        canvas.drawLine(at, at + Offset(a / 2, h / 2), ink);
        canvas.drawLine(at + Offset(a / 2, h / 2), at + Offset(a, h), ink);
        canvas.drawLine(at + Offset(a, 0), at + Offset(a / 2, h / 2), ink);
        canvas.drawLine(at + Offset(a / 2, h / 2), at + Offset(0, h), ink);
      });
    case AsmrPattern.hexagons:
      final side = p.dy / 3;
      void hexagon(Offset center) {
        final path = Path();
        for (var k = 0; k < 6; k++) {
          final angle = math.pi / 2 + k * math.pi / 3;
          final corner =
              center + Offset(math.cos(angle), math.sin(angle)) * side;
          if (k == 0) {
            path.moveTo(corner.dx, corner.dy);
          } else {
            path.lineTo(corner.dx, corner.dy);
          }
        }
        canvas.drawPath(path..close(), ink);
      }
      everyRepeat((at) {
        hexagon(at);
        hexagon(at + Offset(p.dx / 2, p.dy / 2));
      });
    case AsmrPattern.octagons:
      final half = p.dx / 2;
      final b = p.dx / (1 + math.sqrt2) / 2;
      everyRepeat((at) {
        final path = Path()
          ..moveTo(at.dx - b, at.dy - half)
          ..lineTo(at.dx + b, at.dy - half)
          ..lineTo(at.dx + half, at.dy - b)
          ..lineTo(at.dx + half, at.dy + b)
          ..lineTo(at.dx + b, at.dy + half)
          ..lineTo(at.dx - b, at.dy + half)
          ..lineTo(at.dx - half, at.dy + b)
          ..lineTo(at.dx - half, at.dy - b)
          ..close();
        canvas.drawPath(path, ink);
      });
    case AsmrPattern.plain:
      break;
  }
}
