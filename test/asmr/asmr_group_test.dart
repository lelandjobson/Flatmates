import 'dart:ui';

import 'package:flatmates/asmr/asmr_group.dart';
import 'package:flatmates/asmr/asmr_model_paper.dart';
import 'package:flatmates/asmr/asmr_net.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AsmrGroup group(int letter, List<HologramPick> picks) =>
      AsmrGroup(letter: letter, picks: picks, net: AsmrNet.empty);

  test('a group is its set of faces, whatever order they were taken in', () {
    final a = group(0, const [
      HologramPick(4),
      HologramPick(1, from: 4),
      HologramPick(2, from: 4),
    ]);
    expect(a.holds({2, 4, 1}), isTrue);
    expect(a.holds({1, 4}), isFalse);
    expect(a.holds({1, 2, 4, 5}), isFalse);
    expect(groupOfFaces([a], {1, 2, 4}), same(a));
    expect(groupOfFaces([a], {1, 2}), isNull);
    expect(groupOfFaces([a], {}), isNull);
  });

  test('a new group takes the lowest letter no group has', () {
    expect(nextGroupLetter(const []), 0);
    final groups = [
      group(0, const [HologramPick(0)]),
      group(2, const [HologramPick(2)]),
    ];
    expect(nextGroupLetter(groups), 1);
    expect(groups.first.name, 'A');
    expect(groups.last.name, 'C');
  });

  test('neighboring groups get different hatches, and paint without '
      'trouble', () async {
    final seen = {
      for (var i = 0; i < kAsmrHatches.length; i++) hatchOfGroup(i),
    };
    expect(seen, hasLength(kAsmrHatches.length));
    expect(hatchOfGroup(kAsmrHatches.length), same(hatchOfGroup(0)));
    expect(group(1, const [HologramPick(0)]).hatch, same(hatchOfGroup(1)));

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    for (final hatch in kAsmrHatches) {
      paintHatch(canvas, const [
        Offset(0, 0),
        Offset(5, 0),
        Offset(5, 5),
        Offset(0, 5),
      ], hatch);
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(8, 8);
    expect(image.width, 8);
    image.dispose();
    picture.dispose();
  });
}
