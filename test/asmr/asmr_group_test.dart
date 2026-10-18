import 'package:flatmates/asmr/asmr_group.dart';
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
    expect(groups.first.color, isNot(groups.last.color));
  });
}
