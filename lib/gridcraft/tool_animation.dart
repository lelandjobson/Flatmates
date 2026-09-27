import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tool_flight.dart';

/// Fill and outline shared by every tool glyph.
class ToolGlyphStyle {
  const ToolGlyphStyle({
    required this.fill,
    required this.stroke,
    required this.strokeWidth,
  });

  final Color fill;
  final Color stroke;
  final double strokeWidth;

  ToolGlyphStyle copyWith({Color? fill, Color? stroke, double? strokeWidth}) {
    return ToolGlyphStyle(
      fill: fill ?? this.fill,
      stroke: stroke ?? this.stroke,
      strokeWidth: strokeWidth ?? this.strokeWidth,
    );
  }

  Map<String, dynamic> toJson() => {
    'fill': fill.toARGB32(),
    'stroke': stroke.toARGB32(),
    'strokeWidth': strokeWidth,
  };
}

class ToolFeatureSpec {
  const ToolFeatureSpec(this.id, this.label, this.fallback, this.min, this.max);

  final String id;
  final String label;
  final double fallback;
  final double min;
  final double max;
}

class ToolFeature {
  const ToolFeature(this.spec, this.value);

  final ToolFeatureSpec spec;
  final double value;

  String get id => spec.id;
  String get label => spec.label;
  double get min => spec.min;
  double get max => spec.max;
}

/// A flat tool icon. Local space puts the tip at the origin and the work
/// axis along +X. Motion (roll, open, travel) stays on [ToolPose].
abstract class ToolAnimation {
  ToolAnimation({required this.style, Map<String, double>? values})
    : _values = values ?? const {};

  final ToolGlyphStyle style;
  final Map<String, double> _values;

  String get id;
  String get label;
  List<ToolFeatureSpec> get specs;

  List<ToolFeature> get features => [
    for (final spec in specs)
      ToolFeature(spec, feature(spec.id)),
  ];

  double feature(String id) {
    for (final spec in specs) {
      if (spec.id != id) continue;
      return (_values[id] ?? spec.fallback).clamp(spec.min, spec.max).toDouble();
    }
    return 0;
  }

  /// How far the pseudo-3D edge shifts at a full sine.
  double get edgeShift;

  /// Local X span of that edge, from the handle back to the tip.
  (double, double) get edgeSpan;

  void paintFace(Canvas canvas, ToolPose pose);

  ToolAnimation withStyle(ToolGlyphStyle style) =>
      copy(style: style, values: _values);

  ToolAnimation withFeature(String id, double value) {
    ToolFeatureSpec? spec;
    for (final item in specs) {
      if (item.id == id) spec = item;
    }
    if (spec == null) return this;
    return copy(
      style: style,
      values: {..._values, id: value.clamp(spec.min, spec.max).toDouble()},
    );
  }

  ToolAnimation applyJson(Map<String, dynamic> json) {
    var next = this;
    final styleJson = json['style'];
    if (styleJson is Map) {
      next = next.withStyle(
        ToolGlyphStyle(
          fill: colorFromArgb(styleJson['fill'], style.fill),
          stroke: colorFromArgb(styleJson['stroke'], style.stroke),
          strokeWidth: (styleJson['strokeWidth'] is num
                  ? (styleJson['strokeWidth'] as num).toDouble()
                  : style.strokeWidth)
              .clamp(0.2, 12)
              .toDouble(),
        ),
      );
    }
    final rawFeatures = json['features'];
    if (rawFeatures is Map) {
      for (final spec in specs) {
        final raw = rawFeatures[spec.id];
        if (raw is num) next = next.withFeature(spec.id, raw.toDouble());
      }
    }
    return next;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'style': style.toJson(),
    'features': {for (final item in features) item.id: item.value},
  };

  ToolAnimation copy({
    required ToolGlyphStyle style,
    required Map<String, double> values,
  });
}

/// Width scale of a rolled flat glyph. Zero would hide the face, so [roll]
/// stays inside the flight cap.
double rollFaceScale(double roll) => math.cos(roll.clamp(-kMaxRoll, kMaxRoll));

/// Extra heading, in radians, off the cut.
///
/// The cocked [ToolAnimation.feature] `startAngle` is the hover before a
/// cut. Once the view is cutting, the tool stays parallel to the line.
double toolYaw(ToolAnimation tool, ToolPose pose) {
  if (pose.cutting) return 0;
  return tool.feature('startAngle') * math.pi / 180;
}

/// Draws [tool] in local space, then rolls it around +X.
void paintRolledTool({
  required Canvas canvas,
  required ToolAnimation tool,
  required ToolPose pose,
  required double heading,
}) {
  final opacity = pose.visible.clamp(0.0, 1.0);
  if (opacity <= 0) return;
  final clamped = pose.roll.clamp(-kMaxRoll, kMaxRoll);
  canvas.save();
  canvas.rotate(heading);
  if (opacity < 1) {
    canvas.saveLayer(
      const Rect.fromLTRB(-220, -120, 40, 120),
      Paint()..color = Color.fromRGBO(255, 255, 255, opacity),
    );
  }
  canvas.save();
  canvas.scale(1, rollFaceScale(clamped));
  tool.paintFace(canvas, pose);
  canvas.restore();
  if (opacity < 1) canvas.restore();
  canvas.restore();
}

const kScissorStyle = ToolGlyphStyle(
  fill: Color(0xE6FFFFFF),
  stroke: Color(0xE6FFFFFF),
  strokeWidth: 1.2,
);

const kScissorSpecs = <ToolFeatureSpec>[
  ToolFeatureSpec('pivotX', 'Pivot', -36, -90, -8),
  ToolFeatureSpec('bladeWidth', 'Blade width', 2.15, 0.4, 8),
  ToolFeatureSpec('loopCenterX', 'Loop center', -74, -140, -20),
  ToolFeatureSpec('loopSpread', 'Loop spread', 15, 0, 40),
  ToolFeatureSpec('loopWidth', 'Loop width', 30, 8, 64),
  ToolFeatureSpec('loopHeight', 'Loop height', 36, 8, 72),
  ToolFeatureSpec('holeScale', 'Hole scale', 0.53, 0.2, 0.9),
  ToolFeatureSpec('edgeShift', 'Edge', 6.5, 0, 16),
  ToolFeatureSpec('startAngle', 'Start angle', 20, -60, 60),
];

class ScissorToolAnimation extends ToolAnimation {
  ScissorToolAnimation({super.style = kScissorStyle, super.values});

  @override
  String get id => 'scissors';

  @override
  String get label => 'Scissors';

  @override
  List<ToolFeatureSpec> get specs => kScissorSpecs;

  @override
  double get edgeShift => feature('edgeShift');

  @override
  (double, double) get edgeSpan => (
    feature('loopCenterX') - feature('loopWidth') / 2 - 4,
    2,
  );

  /// Center of the upper finger loop. [side] is -1 for the lower loop.
  Offset loopCenter({double side = 1}) =>
      Offset(feature('loopCenterX'), side * feature('loopSpread'));

  @override
  void paintFace(Canvas canvas, ToolPose pose) {
    final face = Paint()..color = style.fill;
    final ink = Paint()
      ..color = style.stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.strokeWidth
      ..strokeJoin = StrokeJoin.round;
    final pivot = Offset(feature('pivotX'), 0);
    for (final side in const [1.0, -1.0]) {
      final path = _rotated(_half(side), pivot, side * pose.open);
      canvas.drawPath(path, face);
      canvas.drawPath(path, ink);
    }
    canvas.drawCircle(pivot, 3.6, Paint()..color = style.fill);
  }

  Path _half(double side) {
    final pivot = feature('pivotX');
    final blade = feature('bladeWidth');
    final neck = blade * (0.9 / 2.15);
    final neckX = pivot * (12 / 36);
    final loopX = feature('loopCenterX');
    final spread = feature('loopSpread') * side;
    final loopW = feature('loopWidth');
    final loopH = feature('loopHeight');
    final hole = feature('holeScale');
    final path = Path()
      ..moveTo(pivot, blade)
      ..lineTo(neckX, neck)
      ..lineTo(0, 0)
      ..lineTo(neckX, -neck)
      ..lineTo(pivot, -blade)
      ..close()
      ..moveTo(pivot, side * 1.4)
      ..lineTo(loopX + 18, spread * 0.6)
      ..lineTo(loopX + 14, spread * 0.35)
      ..lineTo(pivot - 4, side * 0.2)
      ..close()
      ..addOval(
        Rect.fromCenter(
          center: Offset(loopX, spread),
          width: loopW,
          height: loopH,
        ),
      )
      ..addOval(
        Rect.fromCenter(
          center: Offset(loopX, spread),
          width: loopW * hole,
          height: loopH * hole,
        ),
      );
    path.fillType = PathFillType.evenOdd;
    return path;
  }

  @override
  ScissorToolAnimation copy({
    required ToolGlyphStyle style,
    required Map<String, double> values,
  }) {
    return ScissorToolAnimation(style: style, values: values);
  }
}

const kStraightEdgeStyle = ToolGlyphStyle(
  fill: Color(0xFF37474F),
  stroke: Color(0xFFFFD54F),
  strokeWidth: 1.4,
);

const kStraightEdgeSpecs = <ToolFeatureSpec>[
  ToolFeatureSpec('length', 'Length', 90, 40, 160),
  ToolFeatureSpec('thickness', 'Thickness', 10, 2, 28),
  ToolFeatureSpec('tickSpacing', 'Tick spacing', 12, 4, 32),
  ToolFeatureSpec('edgeShift', 'Edge', 4, 0, 16),
  ToolFeatureSpec('startAngle', 'Start angle', 20, -60, 60),
];

class StraightEdgeToolAnimation extends ToolAnimation {
  StraightEdgeToolAnimation({super.style = kStraightEdgeStyle, super.values});

  @override
  String get id => 'straight-edge';

  @override
  String get label => 'Straight edge';

  @override
  List<ToolFeatureSpec> get specs => kStraightEdgeSpecs;

  @override
  double get edgeShift => feature('edgeShift');

  @override
  (double, double) get edgeSpan => (-feature('length'), 2);

  @override
  void paintFace(Canvas canvas, ToolPose pose) {
    final length = feature('length');
    final thickness = feature('thickness');
    final ticks = feature('tickSpacing');
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTRB(-length, -thickness / 2, 0, thickness / 2),
      const Radius.circular(2),
    );
    canvas.drawRRect(rect, Paint()..color = style.fill);
    canvas.drawRRect(
      rect,
      Paint()
        ..color = style.stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = style.strokeWidth,
    );
    if (ticks <= 2) return;
    final tick = Paint()
      ..color = style.stroke
      ..strokeWidth = style.strokeWidth
      ..strokeCap = StrokeCap.round;
    for (var x = -ticks; x > -length + 2; x -= ticks) {
      canvas.drawLine(
        Offset(x, -thickness / 2),
        Offset(x, thickness / 2),
        tick,
      );
    }
  }

  @override
  StraightEdgeToolAnimation copy({
    required ToolGlyphStyle style,
    required Map<String, double> values,
  }) {
    return StraightEdgeToolAnimation(style: style, values: values);
  }
}

List<ToolAnimation> defaultToolAnimations() => [
  ScissorToolAnimation(),
  StraightEdgeToolAnimation(),
];

Color colorFromArgb(Object? raw, Color fallback) {
  if (raw is! num) return fallback;
  final argb = raw.toInt();
  return Color.fromARGB(
    (argb >> 24) & 0xFF,
    (argb >> 16) & 0xFF,
    (argb >> 8) & 0xFF,
    argb & 0xFF,
  );
}

Path _rotated(Path path, Offset pivot, double radians) {
  final matrix = Matrix4.identity()
    ..translateByDouble(pivot.dx, pivot.dy, 0, 1)
    ..rotateZ(radians)
    ..translateByDouble(-pivot.dx, -pivot.dy, 0, 1);
  return path.transform(matrix.storage);
}
