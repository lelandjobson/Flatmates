import 'dart:ui';

import '../asmr/asmr_desk_painter.dart' show kAsmrDeskColor;

/// The most selection groups a craft can have: A to E.
const int kMaxCraftGroups = 5;

/// Opacity of the crafting grid where it lies on the paper. The dots on the
/// bare desk are unchanged.
const double kPaperGridOpacity = 0.25;

/// How one selection group looks everywhere it shows: its chip and Save
/// button, the blueprint's lines and glow on the desk, and the tint on its
/// faces in 3D. The crafting background stays the plain desk. The null group
/// has a plain theme.
class CraftTheme {
  const CraftTheme({
    required this.accent,
    required this.desk,
    required this.dot,
    required this.majorDot,
    required this.line,
    required this.glow,
    required this.faceTint,
    required this.openFaceTint,
  });

  /// The group's own color: chip, Save button, Arrange outline.
  final Color accent;

  /// The crafting background. Cut lines are drawn in it too, so a cut reads
  /// as the background showing through. Every group uses the plain desk.
  final Color desk;

  /// Grid dots on the bare desk, and every fifth one.
  final Color dot;
  final Color majorDot;

  /// Blueprint edges, and the soft halo around the ones off the paper.
  final Color line;
  final Color glow;

  /// Over the group's faces on the model, and stronger while it is open.
  final Color faceTint;
  final Color openFaceTint;

  static CraftTheme lerp(CraftTheme a, CraftTheme b, double t) {
    if (t <= 0) return a;
    if (t >= 1) return b;
    return CraftTheme(
      accent: Color.lerp(a.accent, b.accent, t)!,
      desk: Color.lerp(a.desk, b.desk, t)!,
      dot: Color.lerp(a.dot, b.dot, t)!,
      majorDot: Color.lerp(a.majorDot, b.majorDot, t)!,
      line: Color.lerp(a.line, b.line, t)!,
      glow: Color.lerp(a.glow, b.glow, t)!,
      faceTint: Color.lerp(a.faceTint, b.faceTint, t)!,
      openFaceTint: Color.lerp(a.openFaceTint, b.openFaceTint, t)!,
    );
  }
}

/// The null group's theme: the plain desk.
const CraftTheme kCraftNoneTheme = CraftTheme(
  accent: Color(0xFFFFFFFF),
  desk: kAsmrDeskColor,
  dot: Color(0x33FFFFFF),
  majorDot: Color(0x66FFFFFF),
  line: Color(0xFFFFFFFF),
  glow: Color(0xFFFFFFFF),
  faceTint: Color(0x00000000),
  openFaceTint: Color(0x00000000),
);

/// Coral, amber, mint, sky, and violet: far apart in hue and all bright
/// enough to read over the dark desk and the white paper on the model.
const List<Color> kCraftGroupAccents = [
  Color(0xFFFF6B6B),
  Color(0xFFFFC145),
  Color(0xFF3DDC97),
  Color(0xFF4CC9F0),
  Color(0xFFB388FF),
];

/// The theme of group [letter], 0 for A through 4 for E.
CraftTheme craftGroupTheme(int letter) {
  final accent = kCraftGroupAccents[letter % kCraftGroupAccents.length];
  return CraftTheme(
    accent: accent,
    desk: kCraftNoneTheme.desk,
    dot: kCraftNoneTheme.dot,
    majorDot: kCraftNoneTheme.majorDot,
    line: accent,
    glow: Color.lerp(accent, const Color(0xFFFFFFFF), 0.35)!,
    faceTint: accent.withValues(alpha: 0.3),
    openFaceTint: accent.withValues(alpha: 0.5),
  );
}
