import 'package:flatmates/ui/fm_haptics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('place level grows with object size', () {
    expect(fmHapticPlaceLevel(1), FmHapticLevel.light);
    expect(fmHapticPlaceLevel(3), FmHapticLevel.medium);
    expect(fmHapticPlaceLevel(4), FmHapticLevel.heavy);
    expect(fmHapticPlaceLevel(12), FmHapticLevel.heavy);
  });

  test('delete level stays weak', () {
    expect(fmHapticDeleteLevel(1), FmHapticLevel.faint);
    expect(fmHapticDeleteLevel(4), FmHapticLevel.faint);
    expect(fmHapticDeleteLevel(8), FmHapticLevel.light);
    expect(
      fmHapticStyleForLevel(FmHapticLevel.faint),
      FmHapticStyle.selectionClick,
    );
    expect(
      fmHapticStyleForLevel(FmHapticLevel.light),
      FmHapticStyle.lightImpact,
    );
  });

  test('a selection crescendos up to a heavy thump', () {
    expect(fmSelectionTaps(0), isEmpty);
    expect(fmSelectionTaps(1), [FmHapticStyle.selectionClick]);
    expect(fmSelectionTaps(2), [
      FmHapticStyle.selectionClick,
      FmHapticStyle.lightImpact,
    ]);
    expect(fmSelectionTaps(3).last, FmHapticStyle.mediumImpact);
    expect(fmSelectionTaps(4), [
      FmHapticStyle.selectionClick,
      FmHapticStyle.lightImpact,
      FmHapticStyle.mediumImpact,
      FmHapticStyle.heavyImpact,
    ]);
    expect(fmSelectionTaps(20), fmSelectionTaps(kFmSelectionTapCap));
  });

  test('selected objects in one moment share a crescendo, then stop', () {
    final player = FmHapticPlayer();
    player.noteSelected(2, 0);
    player.noteSelected(3, 0.02);
    expect(player.take(0.04), isEmpty);

    expect(player.take(0.08), [FmHapticStyle.selectionClick]);
    expect(player.take(0.10), isEmpty);
    expect(player.take(0.08 + kFmSelectionTapGap), [FmHapticStyle.lightImpact]);
    expect(player.take(0.08 + kFmSelectionTapGap * 2), [
      FmHapticStyle.mediumImpact,
    ]);
    expect(player.take(0.08 + kFmSelectionTapGap * 3), [
      FmHapticStyle.heavyImpact,
    ]);
    expect(player.take(1), isEmpty);
  });

  test('the exacto buzzes only while it moves, and a snip pulses harder', () {
    final player = FmHapticPlayer();
    expect(player.take(0), isEmpty);
    expect(player.take(0.05, cutting: FmCutFeel.exacto), [
      FmHapticStyle.selectionClick,
    ]);
    expect(player.take(0.06, cutting: FmCutFeel.exacto), isEmpty);
    expect(player.take(0.05 + kFmExactoBuzzGap, cutting: FmCutFeel.exacto), [
      FmHapticStyle.selectionClick,
    ]);
    expect(player.take(1), isEmpty);

    final snip = FmHapticPlayer();
    expect(snip.take(0.05, cutting: FmCutFeel.pulse), [
      FmHapticStyle.lightImpact,
    ]);
    expect(
      snip.take(0.05 + kFmExactoBuzzGap, cutting: FmCutFeel.pulse),
      isEmpty,
    );
    expect(snip.take(0.05 + kFmCutPulseGap, cutting: FmCutFeel.pulse), [
      FmHapticStyle.lightImpact,
    ]);
  });
}
