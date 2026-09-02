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
    expect(fmHapticStyleForLevel(FmHapticLevel.faint), FmHapticStyle.selectionClick);
    expect(fmHapticStyleForLevel(FmHapticLevel.light), FmHapticStyle.lightImpact);
  });
}
