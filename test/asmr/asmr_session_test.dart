import 'dart:io';

import 'package:flatmates/asmr/asmr_net.dart';
import 'package:flatmates/asmr/asmr_paper.dart';
import 'package:flatmates/asmr/asmr_piece.dart';
import 'package:flatmates/asmr/asmr_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a saved desk reads back with its paper and hologram', () {
    final file = File(
      '${Directory.systemTemp.path}/asmr_session_${DateTime.now().microsecondsSinceEpoch}.json',
    );
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
    final piece =
        AsmrPiece.sheet(
          id: 'mint-3',
          paper: kAsmrPapers.first,
          at: const Offset(12, -4),
        ).copyWith(
          edgeTone: 0.37,
          cutEdges: const [
            [Offset(-10, 0), Offset(10, 0)],
          ],
        );
    const picks = [HologramPick(2), HologramPick(1, from: 2)];
    AsmrSession(
      picks: picks,
      pieces: [piece],
      bindings: [picks],
      deskOrigin: const Offset(40, 50),
      deskScale: 2.5,
      in3d: false,
      azimuth: 0.4,
      elevation: 0.2,
      roll: 0.1,
      lookAt: const Offset(1, 2),
      lookAtZ: 3,
      halfHeight: 20,
      focal: 50,
      straightEdgeOn: true,
      straightEdgeAnchor: const Offset(8, 9),
      straightEdgeAngle: 1.2,
    ).write(file);

    final loaded = AsmrSession.read(file)!;
    expect(loaded.picks, picks);
    expect(loaded.pieces.single.id, 'mint-3');
    expect(loaded.pieces.single.edgeTone, 0.37);
    expect(loaded.pieces.single.cutEdges, piece.cutEdges);
    expect(loaded.pieces.single.position, const Offset(12, -4));
    expect(loaded.pieces.single.paper.id, kAsmrPapers.first.id);
    expect(loaded.bindings.single, picks);
    expect(loaded.deskScale, 2.5);
    expect(loaded.in3d, isFalse);
    expect(loaded.straightEdgeOn, isTrue);
    expect(loaded.straightEdgeAngle, 1.2);
    expect(loaded.azimuth, 0.4);
    expect(loaded.groups, isEmpty);
    expect(loaded.pieceGroups, [null]);
    expect(loaded.objectId, isNull);
  });

  test('selection groups and the group of each piece read back', () {
    final file = File(
      '${Directory.systemTemp.path}/asmr_groups_${DateTime.now().microsecondsSinceEpoch}.json',
    );
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
    AsmrPiece sheet(String id) =>
        AsmrPiece.sheet(id: id, paper: kAsmrPapers.first, at: Offset.zero);
    const a = [HologramPick(2)];
    const c = [HologramPick(4), HologramPick(1, from: 4)];
    AsmrSession(
      picks: c,
      pieces: [sheet('mint-0'), sheet('mint-1'), sheet('mint-2')],
      bindings: [a, const [], c],
      groups: {0: a, 2: c},
      groupCutsUsed: {0: 3, 2: 1},
      groupDrafts: {
        0: [sheet('draft-3')],
        2: [],
      },
      pieceGroups: [0, null, 2],
      deskOrigin: Offset.zero,
      deskScale: 1,
      in3d: true,
      azimuth: 0,
      elevation: 0,
      roll: 0,
      lookAt: Offset.zero,
      lookAtZ: 0,
      halfHeight: 10,
      focal: 50,
      objectId: 'box-stack',
    ).write(file);

    final loaded = AsmrSession.read(file)!;
    expect(loaded.objectId, 'box-stack');
    expect(loaded.groupCutsUsed, {0: 3, 2: 1});
    expect(loaded.groupDrafts[0]!.single.id, 'draft-3');
    expect(loaded.groupDrafts[0]!.single.binding, isNull);
    expect(loaded.groupDrafts.containsKey(2), isTrue);
    expect(loaded.groupDrafts[2], isEmpty);
    expect(loaded.groups.keys, [0, 2]);
    expect(loaded.groups[2], c);
    expect(loaded.pieceGroups, [0, null, 2]);
    expect(loaded.slots, isEmpty);
  });

  test('scrap slots read back, empty ones included', () {
    final file = File(
      '${Directory.systemTemp.path}/asmr_slots_${DateTime.now().microsecondsSinceEpoch}.json',
    );
    addTearDown(() {
      if (file.existsSync()) file.deleteSync();
    });
    final scrap = AsmrPiece.sheet(
      id: 'white-0.2',
      paper: kAsmrCraftPaper,
      at: const Offset(5, 6),
    ).affixedTo(2);
    AsmrSession(
      picks: const [],
      pieces: const [],
      bindings: const [],
      slots: [null, scrap, null],
      deskOrigin: Offset.zero,
      deskScale: 1,
      in3d: true,
      azimuth: 0,
      elevation: 0,
      roll: 0,
      lookAt: Offset.zero,
      lookAtZ: 0,
      halfHeight: 10,
      focal: 50,
    ).write(file);

    final loaded = AsmrSession.read(file)!;
    expect(loaded.slots, hasLength(3));
    expect(loaded.slots[0], isNull);
    expect(loaded.slots[1]!.id, 'white-0.2');
    expect(loaded.slots[1]!.paper.id, kAsmrCraftPaper.id);
    expect(loaded.slots[1]!.position, const Offset(5, 6));
    expect(loaded.slots[1]!.blueprints.single.group, 2);
    expect(loaded.slots[1]!.blueprints.single.origin, const Offset(-5, -6));
    expect(loaded.slots[2], isNull);
  });
}
