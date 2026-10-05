import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flatmates/geometry/polygon_union.dart';
import 'package:flatmates/gridcraft/blueprint.dart';
import 'package:flatmates/gridcraft/fold.dart';
import 'package:flatmates/gridcraft/rules.dart';
import 'package:flatmates/gridcraft/scissor.dart';
import 'package:flatmates/gridcraft/scrap.dart';
import 'package:flatmates/papercut/paper.dart';

/// One scissor use: where the blade enters, then one letter per stroke.
/// R, L, U, and D are +x, -x, +y, and -y in grid space.
class GridCut {
  const GridCut(this.x, this.y, this.moves) : via = const [];

  /// Strokes toward each point in [via] in turn until the blade reaches it.
  GridCut.via(Offset start, this.via) : x = start.dx, y = start.dy, moves = '';

  final double x;
  final double y;
  final String moves;
  final List<Offset> via;

  Offset get start => Offset(x, y);

  String get firstMove => via.isEmpty ? moves[0] : _toward(start, via.first);
}

String _toward(Offset from, Offset to) {
  final d = to - from;
  if (d.dx.abs() > 1e-6 && d.dy.abs() > 1e-6) {
    throw ArgumentError('$from to $to is not cardinal');
  }
  if (d.dx > 1e-6) return 'R';
  if (d.dx < -1e-6) return 'L';
  if (d.dy > 1e-6) return 'U';
  return 'D';
}

const _dir = {
  'R': Offset(1, 0),
  'L': Offset(-1, 0),
  'U': Offset(0, 1),
  'D': Offset(0, -1),
};

GridStep loadLevel(String collection, String slug) {
  final file = File('levels/$collection/$slug.json');
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return GridBlueprint.fromJson(json).steps.single;
}

GridRules _liveRules(GridStep step) {
  final cap = step.scissorLengthBudget;
  if (cap == step.rules.maxLength) return step.rules;
  if (cap == null) return step.rules.copyWith(clearLength: true);
  return step.rules.copyWith(maxLength: cap);
}

bool _onRing(Offset point, List<Offset> ring) {
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 < 1e-12) continue;
    var t = ((point - a).dx * ab.dx + (point - a).dy * ab.dy) / len2;
    t = t.clamp(0.0, 1.0);
    if ((a + ab * t - point).distance < 1e-6) return true;
  }
  return false;
}

/// Plays [cuts] on [step] the way the grid puzzle view commits them. Returns null on a
/// win, or the reason play stopped.
String? playGridCuts(GridStep step, List<GridCut> cuts) {
  final rules = _liveRules(step);
  final paper = step.paper;
  final perm = step.permutation;
  var sheet = PapercutSheet(
    pieces: [
      PapercutPiece(
        id: 'paper',
        color: const Color(0xFFFFF3B0),
        vertices: [
          paper.topLeft,
          paper.topRight,
          paper.bottomRight,
          paper.bottomLeft,
        ],
      ),
    ],
  );
  var progress = const CutProgress();
  final liberated = <int>{};
  bool skip(Offset a, Offset b) => penciledRidesPennedNeighbor(
    step.polygons,
    step.edgeStyles,
    a,
    b,
    closed: step.ringClosed,
  );

  PapercutSheet withMirrors(PapercutSheet sheet, List<Offset> path) {
    if (!perm.mirrorX && !perm.mirrorY) return sheet;
    var current = sheet;
    for (final image in mirroredPolylines(
      path,
      paper.center,
      mirrorX: perm.mirrorX,
      mirrorY: perm.mirrorY,
    )) {
      final next = cutThroughFolds(
        current,
        image,
        thickCut: step.attachment.thickCut,
        blueprintPieces: step.closedPolygons,
      );
      if (next != null) current = next;
    }
    return current;
  }

  String? mirrorTrouble(Offset from, Offset to) {
    if (!perm.mirrorX && !perm.mirrorY) return null;
    for (final image in mirroredPolylines(
      [from, to],
      paper.center,
      mirrorX: perm.mirrorX,
      mirrorY: perm.mirrorY,
    )) {
      final ruling = rules.consider(
        image.first,
        image.last,
        progress,
        paper: paper,
      );
      if (ruling.failed) return 'mirror image fails a rule';
      if (piercedBlueprint(step, image.first, image.last) != null) {
        return 'mirror image pierces a blueprint piece';
      }
      if (!ruling.allowed) return 'mirror image is refused';
    }
    return null;
  }

  for (var c = 0; c < cuts.length; c++) {
    final cut = cuts[c];
    PapercutPiece? piece;
    ScissorMarch? march;
    if (entryGemsRemain(rules, progress)) {
      final gem = rules.numbers.where(
        (mark) =>
            mark.number >= progress.nextNumber &&
            (mark.point - cut.start).distance < 1e-6,
      );
      if (gem.isEmpty) return 'cut $c does not start on a number gem';
      march = placeAtEntry(cut.start, paper);
    }
    final heading = _dir[cut.firstMove]!;
    for (final candidate in sheet.pieces) {
      final rings = [candidate.vertices, ...candidate.holes];
      if (!rings.any((ring) => _onRing(cut.start, ring))) continue;
      final ahead = cut.start + heading * 0.05;
      final into =
          isInsidePolygon(ahead, candidate.vertices) &&
          !candidate.holes.any((hole) => isInsidePolygon(ahead, hole));
      if (piece == null || into) piece = candidate;
      if (into) break;
    }
    if (march != null && piece == null) {
      for (final candidate in sheet.pieces) {
        if (isInsidePolygon(cut.start, candidate.vertices)) piece = candidate;
      }
    }
    if (piece == null) return 'cut $c starts off the paper edge';
    if (march == null) {
      march = placeOnRing(cut.start, piece.vertices);
      for (final hole in piece.holes) {
        march ??= placeOnRing(cut.start, hole);
      }
      march ??= placeScissor(cut.start, paper);
    }
    if (march == null) return 'cut $c cannot place the blade';
    final base = sheet;
    final bladeId = piece.id;
    var target = 0;
    for (var m = 0; ; m++) {
      final String move;
      if (cut.via.isEmpty) {
        if (m >= cut.moves.length) break;
        move = cut.moves[m];
      } else {
        while (target < cut.via.length &&
            (cut.via[target] - march!.position).distance < 1e-6) {
          target++;
        }
        if (target >= cut.via.length) break;
        if (m > 400) return 'cut $c never reaches ${cut.via[target]}';
        move = _toward(march!.position, cut.via[target]);
      }
      piece = sheet.pieces.where((p) => p.id == bladeId).firstOrNull ?? piece!;
      final closed = [...step.closedPolygons, piece.vertices, ...piece.holes];
      final where = 'cut $c stroke $m ($move) from ${march!.position}';
      final dir = _dir[move]!;
      if (m == 0 && (march.direction - dir).distance > 1e-6) {
        return '$where: first stroke heads ${march.direction}';
      }
      final end = march.previewEnd(
        step,
        base,
        direction: dir,
        closed: closed,
        skipCollinear: skip,
      );
      if (end == null) return '$where: no stop ahead';
      if (cutRidesBoundary(march.position, end, [
        piece.vertices,
        ...piece.holes,
      ])) {
        return '$where: rides the paper edge';
      }
      final ruling = rules.consider(
        march.position,
        end,
        progress,
        paper: paper,
      );
      if (!ruling.allowed) return '$where to $end: refused by a rule';
      if (ruling.failed) return '$where to $end: fails ${ruling.cause?.kind}';
      final pierced = piercedBlueprint(step, march.position, end);
      if (pierced != null) return '$where: pierces blueprint piece $pierced';
      final mirror = mirrorTrouble(march.position, end);
      if (mirror != null) return '$where: $mirror';
      final commit = commitScissor(
        march: march,
        step: step,
        base: base,
        direction: dir,
        closed: closed,
      );
      if (commit == null) return '$where: commit refused';
      final settled = withMirrors(commit.sheet, [...march.path, end]);
      progress = ruling.progress;
      if (Platform.environment['SHARP_DEBUG'] != null) {
        // ignore: avoid_print
        print('$where -> $end split=${commit.march == null}');
      }
      if (commit.march != null) {
        march = commit.march;
        sheet = settled;
        continue;
      }
      final last = cut.via.isEmpty
          ? m == cut.moves.length - 1
          : (end - cut.via.last).distance < 1e-6;
      if (!last) return '$where: split before the end at $end';
      final fresh = classifyFreshPieces(
        before: base,
        after: settled,
        closedRings: step.closedPolygons,
      );
      if (step.discardFailure && fresh.discardsBlueprint) {
        return '$where: discards a blueprint piece';
      }
      liberated.addAll(liberatedPieceIndexes(step, settled));
      if (Platform.environment['SHARP_DEBUG'] != null) {
        for (final p in settled.pieces) {
          // ignore: avoid_print
          print('${p.id}: ${p.vertices} holes ${p.holes}');
        }
      }
      final scraps = step.discardFailure
          ? {for (final scrap in fresh.scraps) scrap.id}
          : const <String>{};
      sheet = settled.copyWith(
        pieces: [
          for (final p in settled.pieces)
            if (!scraps.contains(p.id)) p,
        ],
      );
      march = null;
      break;
    }
    if (march != null) return 'cut $c never split the paper';
  }
  if (!piecesLiberated(step, liberated)) {
    return 'unfreed pieces: liberated $liberated';
  }
  final gems = step.rules.colors.isNotEmpty || step.rules.numbers.isNotEmpty;
  if (gems && !collectiblesCleared(step.rules, progress)) {
    return 'gems remain';
  }
  return null;
}
