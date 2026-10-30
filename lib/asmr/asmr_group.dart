import 'dart:math' as math;
import 'dart:ui';

import 'asmr_net.dart';
import 'asmr_piece.dart';

/// How faint a group's hatch is on the cube.
const double kAsmrHatchOpacity = 0.3;

/// The lines a group's faces are hatched with on the cube, in the plane of
/// each face. Lengths are model units; a cube face is 5 across.
class AsmrHatch {
  const AsmrHatch({
    required this.color,
    required this.angle,
    required this.spacing,
    required this.width,
    this.cross = false,
  });

  /// Opaque. It is drawn at [kAsmrHatchOpacity].
  final Color color;

  /// Radians from the face's x axis.
  final double angle;
  final double spacing;
  final double width;

  /// A second set of lines across the first.
  final bool cross;
}

/// One hatch per group letter, in turn: each a different color, angle, and
/// density, so neighboring groups read apart.
const List<AsmrHatch> kAsmrHatches = [
  AsmrHatch(
    color: Color(0xFFFFB74D),
    angle: math.pi / 4,
    spacing: 0.5,
    width: 0.08,
  ),
  AsmrHatch(
    color: Color(0xFF4DD0E1),
    angle: -math.pi / 4,
    spacing: 0.32,
    width: 0.05,
  ),
  AsmrHatch(color: Color(0xFFF06292), angle: 0, spacing: 0.75, width: 0.14),
  AsmrHatch(
    color: Color(0xFFAED581),
    angle: math.pi / 2,
    spacing: 0.42,
    width: 0.07,
  ),
  AsmrHatch(
    color: Color(0xFFB39DDB),
    angle: math.pi / 4,
    spacing: 0.6,
    width: 0.06,
    cross: true,
  ),
  AsmrHatch(
    color: Color(0xFFFF8A65),
    angle: math.pi / 6,
    spacing: 0.28,
    width: 0.04,
  ),
  AsmrHatch(
    color: Color(0xFF81D4FA),
    angle: -math.pi / 3,
    spacing: 0.9,
    width: 0.18,
  ),
  AsmrHatch(
    color: Color(0xFFFFF176),
    angle: 0,
    spacing: 0.5,
    width: 0.06,
    cross: true,
  ),
];

AsmrHatch hatchOfGroup(int letter) =>
    kAsmrHatches[letter % kAsmrHatches.length];

/// The faces a stretch of the craft is cut for, and the paper already on
/// them.
///
/// A deal divides the object into 2, 3, or 4 of these. Two selections of the
/// same faces are the same group, whatever order the faces were taken in.
/// [picks] keeps the order the group
/// was made with, so its hologram unfolds the same way each time. Every
/// group cuts from the one shared desk; a piece cut close enough to the
/// group's blueprint leaves the desk and joins [bound], on the model. A
/// group stays until it is undone, with or without paper.
class AsmrGroup {
  AsmrGroup({
    required this.letter,
    required this.picks,
    required this.net,
    List<AsmrPiece>? bound,
    List<AsmrPiece>? draft,
    this.cutsUsed = 0,
    this.editing = false,
  }) : bound = bound ?? [],
       draft = draft ?? [];

  /// 0 for A, 1 for B, and on.
  final int letter;

  /// Successful scissors strokes spent on this group.
  int cutsUsed;

  /// Reopened submitted paper is held off the model until sent back.
  bool editing;
  final List<HologramPick> picks;
  final AsmrNet net;

  /// Paper on the group's faces, each piece bound to [net].
  final List<AsmrPiece> bound;

  /// Detached paper being edited, separate from the shared desk.
  final List<AsmrPiece> draft;

  late final Set<int> faces = {for (final pick in picks) pick.face};

  String get name => String.fromCharCode(0x41 + letter % 26);

  AsmrHatch get hatch => hatchOfGroup(letter);

  /// Whether any paper is on its faces.
  bool get anchored => bound.isNotEmpty;

  bool holds(Set<int> other) =>
      other.length == faces.length && faces.containsAll(other);

  /// A copy whose paper can change without touching this one.
  AsmrGroup copy() => AsmrGroup(
    letter: letter,
    picks: picks,
    net: net,
    bound: List.of(bound),
    draft: List.of(draft),
    cutsUsed: cutsUsed,
    editing: editing,
  );
}

/// The group of exactly [faces], if there is one.
AsmrGroup? groupOfFaces(Iterable<AsmrGroup> groups, Set<int> faces) {
  if (faces.isEmpty) return null;
  for (final group in groups) {
    if (group.holds(faces)) return group;
  }
  return null;
}

/// The lowest letter no group has.
int nextGroupLetter(Iterable<AsmrGroup> groups) {
  final used = {for (final group in groups) group.letter};
  var letter = 0;
  while (used.contains(letter)) {
    letter++;
  }
  return letter;
}
