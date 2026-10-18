import 'dart:ui';

import 'asmr_net.dart';
import 'asmr_piece.dart';

/// Colors of selection groups A, B, C, and on, in letter order.
const List<Color> kAsmrGroupColors = [
  Color(0xFFFF7A59),
  Color(0xFF4FC3F7),
  Color(0xFFB388FF),
  Color(0xFF81C784),
  Color(0xFFFFD54F),
  Color(0xFFF06292),
  Color(0xFF4DB6AC),
  Color(0xFFFFB74D),
];

/// The faces paper was laid for, and that paper.
///
/// Opening the desk on a selection makes its group, or reopens the group of
/// the same faces. Two selections of the same faces are the same group,
/// whatever order the faces were taken in; [picks] keeps the order the group
/// was made with, so its hologram unfolds the same way each time and the
/// paper lines up with it. A group lasts only while some of its paper is
/// attached to its faces.
class AsmrGroup {
  AsmrGroup({
    required this.letter,
    required this.picks,
    required this.net,
    List<AsmrPiece>? pieces,
  }) : pieces = pieces ?? [];

  /// 0 for A, 1 for B, and on.
  final int letter;
  final List<HologramPick> picks;
  final AsmrNet net;

  /// The group's desk, attached or not.
  final List<AsmrPiece> pieces;

  late final Set<int> faces = {for (final pick in picks) pick.face};

  String get name => String.fromCharCode(0x41 + letter % 26);

  Color get color => kAsmrGroupColors[letter % kAsmrGroupColors.length];

  /// Whether any of its paper is attached to its faces.
  bool get anchored => pieces.any((piece) => piece.binding != null);

  bool holds(Set<int> other) =>
      other.length == faces.length && faces.containsAll(other);

  /// A copy whose desk can change without touching this one.
  AsmrGroup copy() => AsmrGroup(
    letter: letter,
    picks: picks,
    net: net,
    pieces: List.of(pieces),
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
