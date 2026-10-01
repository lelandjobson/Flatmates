import 'dart:math' as math;

import 'package:flutter/animation.dart';

/// How a finished blueprint piece lights up.
///
/// The fill blends from the paper color into [color]. A halo of that color
/// blooms during the blend, then rests at [amount].
class PieceGlowSettings {
  const PieceGlowSettings({required this.color, required this.amount});

  /// Mint used by the old success fill. The halo is this color, lightened.
  static const standard = PieceGlowSettings(
    color: Color(0xFF69F0AE),
    amount: 0.65,
  );

  final Color color;

  /// 0 hides the halo. 1 is the widest, brightest rest state.
  final double amount;

  PieceGlowSettings copyWith({Color? color, double? amount}) {
    return PieceGlowSettings(
      color: color ?? this.color,
      amount: amount ?? this.amount,
    );
  }

  Map<String, Object> toJson() => {
    'color': '#${_hex(color)}',
    'amount': (amount * 1000).round() / 1000,
  };

  factory PieceGlowSettings.fromJson(Object? json) {
    if (json is! Map) return standard;
    return PieceGlowSettings(
      color: _parseColor(json['color']) ?? standard.color,
      amount: _parseAmount(json['amount']),
    );
  }
}

/// 0 at the start of the light-up, 1 when the fill has arrived at the glow.
double pieceGlowBlend(double t) {
  return Curves.easeInOutCubic.transform(t.clamp(0.0, 1.0));
}

/// Halo scale. Rests at 1, and blooms past 1 partway through the blend.
double pieceGlowHalo(double t) {
  final u = t.clamp(0.0, 1.0);
  return u + math.sin(u * math.pi) * 0.8;
}

Color pieceGlowFill({
  required Color paper,
  required Color glow,
  required double t,
}) {
  return Color.lerp(paper, glow, pieceGlowBlend(t))!;
}

/// The halo is the glow color lifted toward white so it reads as light.
Color pieceGlowLight(Color glow) {
  return Color.lerp(glow, const Color(0xFFFFFFFF), 0.28)!;
}

String _hex(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return rgb.toRadixString(16).padLeft(6, '0').toUpperCase();
}

Color? _parseColor(Object? raw) {
  if (raw is! String) return null;
  var hex = raw.trim();
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  final value = int.tryParse(hex, radix: 16);
  if (value == null) return null;
  return Color.fromARGB(
    (value >> 24) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 8) & 0xFF,
    value & 0xFF,
  );
}

double _parseAmount(Object? raw) {
  if (raw is! num) return PieceGlowSettings.standard.amount;
  return raw.toDouble().clamp(0.0, 1.0);
}
